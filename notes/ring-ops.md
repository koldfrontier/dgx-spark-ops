# Running four DGX Sparks as a switchless ring

Operational notes from a four-node GB10 cluster wired as a cycle — each unit's
two QSFP ports cabled to its two neighbours, no switch — serving one
tensor-parallel vLLM workload. Everything below is measured on that hardware
unless it says otherwise, with the method included so you can judge whether it
transfers.

Companion to [`../recipes/DeepSeek-V4.1-Flash-Quad-DGX-Sparks`](../recipes/DeepSeek-V4.1-Flash-Quad-DGX-Sparks),
which is the serving config these notes came out of.

---

## 1. Verify the transport by counters, not by config

The single most useful habit on this hardware. NCCL will silently fall back to
TCP over your management network and everything still works — just slowly, in a
way that looks like a GPU or a model problem for hours.

```bash
# before and after one real generation, on every node
for d in /sys/class/infiniband/roce*; do
  echo "$(basename $d) xmit=$(cat $d/ports/1/counters/port_xmit_data)"
done
cat /sys/class/net/<fabric-if>/statistics/tx_bytes
```

IB counters are in units of 4 bytes. If `port_xmit_data` does not move across a
generation, **NCCL is not using RDMA**, whatever the config says. On this
cluster that fallback survived a full four-node reboot, cable swaps, checkpoint
byte-verification and image-immutability checks, because none of those touch
container device access. Fixing it took an 8-stream benchmark from 48.57 to
85.66 tok/s.

Two things make the failure loud instead of silent:

- `NCCL_NET=IB` — the fallback becomes `NET/IB : No device found` at startup.
- Give the container `--cap-add IPC_LOCK --device /dev/infiniband:/dev/infiniband`
  and `--ulimit memlock=-1:-1`. (`--privileged` also works and is what we used
  first; the narrower pair is enough.)

Healthy startup lines look like `NET/IB : Using [0]<hca>:1/RoCE` and
`Channel 00/04` … with `Tree transport setup disabled` on a ring-only build.

## 2. The RoCEv2 GID index is per machine. Derive it, never copy it

Identical units, same model, same day, gave GID index **3** on two nodes and
**5** on the other two. The index you want is the one that is both an IPv4
RoCEv2 entry *and* carries that node's fabric address:

```bash
for i in $(seq 0 15); do
  g=$(cat /sys/class/infiniband/<hca>/ports/1/gids/$i)
  t=$(cat /sys/class/infiniband/<hca>/ports/1/gid_attrs/types/$i 2>/dev/null)
  echo "$i $g $t"
done | grep -i 'ffff.*RoCE v2'
```

Wire it into a preflight that refuses the boot rather than a comment in a
runbook — a wrong GID index does not fail cleanly, it produces connection
attempts that hang or fall back.

## 3. Cabling: prove the cycle before you configure it

Cable labels lie and ports are easy to swap. Confirm the neighbour on each
port with LLDP (`lldpctl`, or `tcpdump -i <if> -s0 ether proto 0x88cc`) and
write the cycle down. Everything downstream — the rank map, which HCA faces
which neighbour, the routes — is derived from that one fact, and a transposed
pair produces a fabric that links, passes `ping`, and then performs oddly under
collectives.

## 4. Routing on a cycle: two nodes forward, two do not

On a ring, non-adjacent nodes have no direct link. NCCL does not need one (see
§6), but everything else does — the NFS share, the rendezvous, your own SSH.
The arrangement that works:

- One /24 per link, both endpoints addressed in it.
- Two opposite nodes enable `ip_forward` (and an `ACCEPT` rule in Docker's
  `DOCKER-USER` chain, or Docker's default `FORWARD` drop silently breaks
  transit traffic *only* — which is a confusing way to find out).
- Static routes on every node for the two subnets it cannot reach directly.
- `nofail,_netdev` on the share's fstab entry, or a worker that boots before
  the head simply has no checkpoint and the launcher's preflight has to mount
  it.

**Keep a second, always-up control plane** (a VPN/tailnet address per node).
Being able to boot the cluster with `CTRL=private` before the fabric routes
exist — and to fix the routes remotely when they do not — is worth the extra
interface. Our launcher takes `CTRL=private|fabric` for exactly this.

## 5. What the ring topology actually costs

Measured with the DSv4.1-Flash TP4 workload described in the recipe.

**Decode: the fabric is latency, not bandwidth.**

| | |
|---|---:|
| all-reduce p50, 8 KB | 41.7 µs |
| all-reduce p50, 60 KB | 59.0 µs |
| all-reduce p50, 1 MB | 175.9 µs |
| 88 all-reduces back-to-back (one decode step's worth) | 4.64 ms |
| decode step time | 62–67 ms |

So the whole fabric is **~7% of a decode step**, and most of those 42 µs is
NCCL software (proxy thread, protocol, launch), not wire time — an 8 KB
all-reduce is under 4 µs of wire at 100 Gb/s. No topology change can give back
more than that 7%, and a faster link gives back almost none of it.

**Prefill: bandwidth matters, bounded.** Reading the head's HCA counters around
one cold 130,258-token prompt (88.4 s to first token):

- 181.5 GB transmitted = **1.39 MB of fabric traffic per prompt token**
- = 2.85 GB per 2,048-token scheduler step
- = 228 ms of wire time in a 1,390 ms step at ~100 Gb/s → **16% of prefill**
- and the link averaged only 16 Gb/s over the prompt: it is bursty between
  compute phases, not saturated.

**Steady state.** Over a 20-minute 8-stream soak each ring link carried 531.1 GB
in its forward direction (and 4.7 GB back — see §7), all four links within
0.1 GB of each other. That equality is a useful balance check: a link that moved
materially less is a link that is not carrying its share of the ring.

**Pinned shared memory.** Under the ring-only patch with 4 channels and no
buffer tuning, NCCL's pinned `Shmem` footprint is 0.35–0.37 GiB per node. For
comparison, MiaAI-Lab measured NCCL's default connection buffers at 4.7 GiB per
node on GB10 before tuning. Two peers per rank and no Tree appears to avoid
that bloat structurally, which matters when 128 GB is shared between host and
GPU.

## 6. Why a ring is not slower than a switch here (and when it would be)

The common objection: on a switch every rank has a full-rate path to every
other rank; on a ring each rank talks only to two neighbours at half the
aggregate injection bandwidth. True, and it mostly does not matter for
tensor-parallel serving:

- **TP does all-reduce and all-gather only.** NCCL's ring algorithm sends every
  byte one hop to a neighbour; rank 0 never needs to reach rank 2. The missing
  direct links carry no traffic even when they exist.
- **Decode is latency-bound** (§5). A switch lets stock NCCL use Tree/PAT
  instead of Ring, which for four ranks is a latency trick worth a fraction of
  4.64 ms in a 63 ms step.
- **Prefill is the only place a wider pipe shows up**, and it is 16% of the
  step, so the ceiling is single digits end to end.

Where a switch does win: **more than four nodes** (a ring's hop count grows,
a star's does not), any-to-any collectives (expert parallel, all-to-all),
pipeline-parallel layouts, resilience (one dead cable takes down a ring, not a
star), and running stock NCCL instead of a patched build. Those are the reasons
to buy one — mostly not tok/s.

The one concrete tok/s exception so far: tonyd2wild's speed run measured a
**one-shot RoCE all-reduce** (local-inference-lab's b12x, replacing NCCL for
small collectives) at code +11% / prose +16% single-stream on a switched
four-Spark fleet. It is an all-to-all RDMA write on one HCA, so a ring cannot
run it. If you are choosing between the topologies for a TP4 decode workload,
that ~10% is the number to weigh against the ring's simplicity.

**Channel count.** `NCCL_MAX_NCHANNELS=8` (from the same speed run, +10.7% C6
on a switch) measured neutral on the cycle as its own boot: C6 +1.4%, decode
step and prefill inside run-to-run noise, NCCL's pinned `Shmem` on the head
0.48 -> 0.62 GiB. The ring-only build's 4 channels stay.

If you do move to a switch, RoCE on a small managed switch wants **lossy mode
with QoS off**, not the lossless-PFC setup datacenter documentation assumes;
several DGX Spark deployments have collapsed to single-digit Gb/s with clean
links and zero loss until PFC was disabled on both switch and hosts.

## 7. A ring runs one direction (an open question)

On our four-rank cycle, **every channel uses the same orientation**: each rank
transmits on one HCA and receives on the other, and the reverse direction
carries only control traffic. IB counter deltas over a 1,289 s eight-stream
soak:

| rank | HCA A xmit / rcv (GB) | HCA B xmit / rcv (GB) |
|---|---:|---:|
| 0 | 531.1 / 4.7 | 4.7 / 531.1 |
| 1 | 4.7 / 531.1 | 531.2 / 4.7 |
| 2 | 531.1 / 4.6 | 4.7 / 531.2 |
| 3 | 4.6 / 531.1 | 531.1 / 4.7 |

Stock NCCL duplicates channels with the two NICs' roles swapped, which on a
cycle is the reverse orientation. If channels could alternate, the same bytes
would leave over both ports, halving the 16% prefill wire share — an upper
bound of ~8% on cold long prompts, nothing on decode, with the cables you
already have. Whether that is deliberate (peer/GID advertisement, deadlock
avoidance) or an artefact of how the cycle builder duplicates channel 0 is
asked upstream in
[sparkring#273](https://github.com/FujitsuPolycom/sparkring/issues/273).

## 8. Failure modes that do not announce themselves

These cost us the most time; all four look like a healthy `docker ps`.

**A patch set built against the wrong commit.** Whole-file Python patches over
a tree that moved: loads fine, boots fine, every generation is garbage. The
patched file was consistent with the file *next to* it in the old tree, and an
upstream commit changed that neighbour. Pin the commit by sha, and verify by
hashing an **unpatched** file that the patch set depends on — the neighbour,
not the patch — inside the built image. A *newer* file
over an older tree usually crashes (loud, fine); an *older* file over a newer
tree boots and is wrong (silent, expensive).

**A CUDA-graph capture list that never matches.** With speculation on, a decode
step's batch is `k` or `k+1` tokens per sequence, so the capture list must be
the multiples of those up to your max sequences (at k=5, 8 seqs:
`5,6,10,12,15,18,20,24,25,30,35,36,40,42,48`). A hand-written list like `[8]`
forces the engine to pad into an uncaptured shape and yields silent NaN, not an
error. Derive the list in the launcher; never type it.

**Orphaned engine workers.** `pkill -f 'vllm serve'` kills the launcher, not
the `EngineCore` / `Worker_TP*` children — vLLM renames those process titles.
They keep the GPU and the port and contend with the next boot. Kill by PID and
confirm `nvidia-smi` shows no compute process before relaunching.

**Launch order.** Start the headless workers first and the head (rank 0) last;
stop in the opposite order, head first. Launching rank 0 first "works" and then
produces a reproducible ~40% throughput regression that survives a reboot and
looks like a hardware mystery. A worker joining a still-listening old head
hangs the boot outright.

## 9. Benchmarks that mislead on this stack

- **A single prompt's tok/s means little without its acceptance length.** Our
  per-category C1 spread in one run is 30.6 (narrative) to 90.5 (counting) —
  3× on one engine — and it tracks speculative acceptance. Compare like with
  like, or compare `ms/step` and `tokens/step` separately.
- **The KV pool is a lottery, not a setting.** Four boots of an identical
  config gave 1,109,543 / 1,140,181 / 1,287,900 / 1,350,412 tokens, because the
  pool is computed from free memory at init and that depends on host state. One
  boot per arm cannot attribute a pool difference to a flag. Tune for headroom;
  gate on step time.
- **`expandable_segments:True` vs `False`.** Another fleet reported a large KV
  gain from `False`; A/B'd here it cost **19–37% decode throughput**, and its
  apparent KV gain did not survive a third boot. Measure allocator flags on
  step time, not on the pool.
- **Prefix caching makes prefill cells lie.** Two bench runs in the same
  process with the same seeds will hit the cache on the second; a cold-prefill
  cell that suddenly reads 3× faster (or, once, 2× slower on a first-use JIT
  compile) is an artefact. Use unique random prefixes.
- **`hangcheck`-style log watchers false-positive on long prefills.** vLLM adds
  prompt tokens to its throughput log only when the first output token appears,
  so a cold 300K prefill logs `prompt throughput 0.0 / generation ~0 tok/s` for
  minutes with every GPU busy. Watch `vllm:kv_cache_usage_perc` creeping up
  instead.

## 10. Housekeeping that turned out to matter

- **Caches off `/tmp`.** `/tmp` and `/var/tmp` are wiped on reboot on a stock
  DGX Spark; a wiped Triton/FlashInfer cache costs minutes of JIT on the first
  request after every boot. Put `VLLM_CACHE_ROOT`, `TRITON_CACHE_DIR` and
  friends under the user's home and bind-mount them.
- **Drop the page cache before a big load** (`sync; echo 3 > drop_caches`) and
  refuse to boot below a `MemAvailable` floor. On unified memory, the page
  cache is competing with the model.
- **Check `/proc/buddyinfo` after long uptime** — memory fragmentation makes a
  large contiguous allocation fail in ways that read as an OOM.
- **`--restart no`, always.** A four-node TP workload cannot self-heal one
  rank; an automatic restart produces a rank that boots into a dead rendezvous
  and holds the GPU.
- **`--oom-score-adj 500` on the engine** so the kernel kills it before it
  kills sshd — and then never build an image on a node that is serving.

---

*Measured on four GB10 units (DGX Spark / ASUS Ascent GX10) on a switchless
RoCE cycle, 2026-09. Numbers are from the workload in the companion recipe; the
method is given so you can re-run them rather than take them on faith.*
