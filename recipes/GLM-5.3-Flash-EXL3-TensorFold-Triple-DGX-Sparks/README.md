# GLM-5.3-Flash EXL3 · three DGX Sparks, TensorFold, no switch

Serves [`Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold`](https://huggingface.co/Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold)
as one OpenAI-compatible endpoint, tensor-parallel across **three** DGX Spark / ASUS Ascent GX10 units
cabled as a **triangle** (one direct QSFP cable per pair, no switch), using
[MiaAI-Lab's TensorFold recipe](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold)
v1.5 and its experimental three-Spark engine.

This directory is not a fork of that recipe. It is what we add on top to run it well on three nodes: the
fabric setup and a check that catches a silently degraded fabric, three start settings measured to help,
a measured map of the settings that do not, a per-rank profile of where the time goes, two optional engine
patches, the harness and every result.

| | |
|---|---|
| Shape | TP3 across 3 x GB10, rank 0 serves the API on `:8888`, 8 requests at once |
| Engine | TensorFold v0.6.0 + recipe v1.5 (`1576746`, 70 patches), image `v0.6.0-9f73cca659a1` |
| Checkpoint | `078455ff`, 164 GiB, one copy on the head, read by the workers over NFS |
| Start line | `COMM=roce ./start-tp3.sh` with `NCCL_CHANNELS=8` and `TF_GLM_PREFILL_ROWS=4096` ([`config/local.sh.example`](config/local.sh.example)) |
| Rank 0 memory | startup estimate 71.1 GiB; shared KV pool ~4.6M tokens |
| Decode, sparkDash prose | 75.0 tok/s one request · 133.1 at 4 · **186.0 at 8** (aggregate) |
| Cold prefill, sparkDash | 2,361 / **2,469** / 2,396 / **2,232** tok/s at 16K / 32K / 65K / 131K |
| Long context | needle at 131K tokens found (2,170 tok/s) |
| Vision + tool calling | 7/7 on a real-image / real-tool-call suite |
| Start to serving | ~3 minutes |
| Last verified | 2026-10-03, on the hardware below |

**Against the upstream v1.5 three-Spark defaults on the same three Sparks** (harness below): prefill **+7% / +6%**
at 32K / 128K, one-stream decode **+5-7%**, 4 requests +3%, 8 requests the same. For context only (different
hardware, clocks capped at 2,200 MHz there): against the upstream README / changelog sparkDash figures, prose at
4 / 8 requests +9% / +12%, prefill +18-20%, one request 75.0 vs 77.6; our two-Spark runs already measured 7-8%
above those tables before any tuning. Upstream's code figures use a different prompt and are not compared.

## What this adds to the upstream recipe

- **A fabric check that catches what nothing else does.** Re-cabling a GB10 so that both QSFP cages are
  empty at once leaves its ConnectX-7 at ~1/8 RDMA bandwidth until reboot, with every link, PCIe and MTU
  check still green. It cost us 45% of prefill before we found it. [`fabric/check-fabric.sh`](fabric/check-fabric.sh)
  reads the marker and runs a loopback bandwidth test per device. Details: [`../../notes/gb10-cx7-hotplug-ltr.md`](../../notes/gb10-cx7-hotplug-ltr.md).
- **Triangle addressing that survives a peer's reboot** ([`fabric/triangle-addr.sh`](fabric/triangle-addr.sh)).
- **Three settings that help at three ranks**, each beyond the measured start-to-start noise (below).
- **A measured map of what does not help**, so you do not spend restarts on it.
- **A per-rank prefill profile** and two optional engine patches ([`engine/`](engine/)).
- **The harness** ([`bench/tfbench2.py`](bench/tfbench2.py)), the noise-aware comparison
  ([`bench/analyze.py`](bench/analyze.py)) and **all 34 v1.5 runs** ([`bench/results-v15-2026-10-03.jsonl`](bench/results-v15-2026-10-03.jsonl));
  the earlier v1.4 runs with the first harness are in `bench/results-2026-10-03.jsonl` / `bench/tfbench.py`.

## ---------- AGENT.md ATTENTION ----------

If you are an AI agent setting this up on new hardware, in order, confirming each with the operator:

1. **Run `fabric/check-fabric.sh` on every node before the first benchmark**, and again after any
   re-cable or reboot. A node reporting `LTR OFF` or a loopback under ~50 Gb/s gives you wrong numbers
   for everything; reboot it. Do not tune on top of an unchecked fabric - we did once, and threw the results away.
2. **Cable a directed triangle**: each node's port 0 to the next node's port 1. Confirm with LLDP or link
   state, not by trusting labels.
3. **Address each PCIe twin on its own /24 per cable**, both ends; both twins carry traffic only when both
   are addressed. Keep NetworkManager off those ports while you run (see `triangle-addr.sh`).
4. **Check the rendezvous**: `getent hosts $(hostname)` on the head. A loopback answer means you must set
   `MASTER_ADDR` to an address every worker reaches.
5. **Give `COMM` on the command line** (`COMM=roce ./start-tp3.sh`); `start-tp3.sh` ignores it in
   `scripts/local.sh`. **`export`** `TF_GLM_*` settings in `local.sh`, or they never reach the ranks.
6. **Measure noise before you tune.** Three fresh starts of one configuration gave spreads of 0.5% (long
   prefill), ~1% (one-stream decode) and 3-4% (multi-stream aggregates) here. Anything inside that is not a finding.

## Hardware and prerequisites

- Three GB10 systems with 128 GB unified memory, nothing else large on their GPUs (each needs ~110 GiB
  free at start).
- Three QSFP cables, one per pair. Each port appears as two PCIe "twins" (`enp1s0f0np0` / `enP2p1s0f0np0`,
  RoCE `rocep1s0f0` / `roceP2p1s0f0`); one twin is one PCIe Gen5 x4, ~112 Gb/s of the port's 200.
- `arp_ignore=1`, `arp_announce=2` on the fabric netdevs (two twins share one L2 segment).
- The upstream recipe's own prerequisites: Docker with the NVIDIA runtime, key-based ssh from the head to
  each worker's link address, `rsync`, perftest.
- Disk on the head: ~205 GB (checkpoint, DFlash2, image). Workers need only the image (~25 GB) with
  `WORKER_WEIGHTS=nfs`.

## Set up

```bash
# head
git clone https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold && cd GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold
git checkout 1576746          # v1.5, what was measured
cp <this dir>/config/local.sh.example scripts/local.sh   # then fill in
```

1. **Fabric** - on each node, `fabric/triangle-addr.sh <four CIDRs>` (examples in its header), then
   `fabric/check-fabric.sh`. Ping every twin pair from both ends.
2. **NFS** - export the head's HF cache read-only to every worker link address (both twins of both
   cables), e.g. `/home/<you>/.cache/huggingface <w1-a>(ro,no_subtree_check,all_squash,anonuid=1000,anongid=1000) ...`.
3. **ssh** - the head must reach each worker *at its link address* with your key.
4. **Prepare** - `TP=3 scripts/prepare.sh` downloads on the head, copies the image to each worker and checks
   the workers' NFS view file by file. (If you would rather the workers did not pull the image from GHCR
   themselves, kill their `docker pull` and prepare falls back to streaming it from the head over the link.)

### Finding your own values

| Value | How to find it | Why not to copy ours |
|---|---|---|
| Link CIDRs | One /24 per twin per cable, yours | Ours only need to be unique on your fabric |
| `WORKER`, `WORKER2` | The worker's address on the cable to the head | They must route over the cable, not the LAN |
| `MASTER_ADDR` | An address of the head every worker reaches; only needed when the hostname resolves to loopback | LAN layouts differ |
| Which port is "port 0" | `ip -br link` + LLDP; our TOP / BOTTOM cable labels meant port 0 on two units and port 1 on the other two | Mounting orientation flips it |

## Run

```bash
COMM=roce ./start-tp3.sh            # NCCL_CHANNELS and TF_GLM_PREFILL_ROWS come from scripts/local.sh
./stop.sh                           # stops all three ranks
```

Expect, in rank 0's log: `rank 0 of 3`; `all-gathers up to 1024 KiB over RoCE (rank 1 over <two devices>;
rank 2 over <the other two> ...)`; `prompt chunks' hyper-connections: rows split between the ranks ...`;
`--parallel 8`; then `serving ... rank 0 of 3`.

## What moves speed at three ranks (measured)

Method: [`bench/tfbench2.py`](bench/tfbench2.py) from a fourth machine over the LAN, warm-up first, then cold
random-word prefills of ~8K / ~32K / ~128K tokens, one-stream decode of a prose prompt, a copy-friendly code
prompt (fifty near-identical functions) and a natural code task, and prose and natural code at 4 and 8
requests at once. One variable per fresh start; every value read back from the running container. Base: v1.5
with `COMM=roce` and 8 channels, three starts (spread: prefill 32K / 128K 0.6% / 0.5%, prose x1 0.9%, the
4- and 8-stream aggregates 2.5-4.3%). `*` = beyond that metric's noise. Random words prefill 4-8% slower than
sparkDash's filler on this model.

**Helps:**

| setting | prefill 8K / 32K / 128K | one-stream decode | 4 / 8 streams | starts |
|---|---|---|---|---:|
| `TF_GLM_PREFILL_ROWS=4096` (default 2048) | +3.7% / **+6.2%*** / **+5.0%*** | same | same | 3 |
| `COMM=roce` (TP3 default `nccl`) | same (32K / 128K) | **prose +7.3%*, code +5-7%*** | +4% / +2% | 3 v 1 |
| `NCCL_CHANNELS=8` (default 4) | **+10% / +2.6% / +1.9%** (vs 4) | same | same | 3 v 1 |
| v1.5 itself (vs v1.4) | same | same | same / **prose +40%, code +35%** | 3 v 1 |

**Defaults that are right at three ranks:** split prefill (`SPLIT=0`: prefill -25%, measured on v1.4), the `p2p`
split exchange (`gather`: -20%, v1.4), 2 overlap pieces (1: -6%, 4: -3%), L2 prefetch on (off: one-stream decode -2%), draft
policy `fnc7:0.3` (0.2: same or slightly worse).

**No measurable effect** (each within noise): `TF_ROCE_MAX_KB` 512 / 2048 (auto 1024 at 8 streams),
`TF_GLM_MULTI_WINDOW=48` (auto 64), `NCCL_CHANNELS=16`, `NCCL_NCHANNELS_PER_NET_PEER=4`,
`NCCL_P2P_NET_CHUNKSIZE=524288`, `NCCL_BUFFSIZE=8388608`, `vm.compaction_proactiveness=0` (round-gap p99 unchanged
with smoothing off), `TF_GLM_OVERLAP_PRIORITY=-1` (prefill +1.5% at 32K, decode -1.4 to -2.2% at 4 / 8 streams:
not worth it), prompt chunks past 4096 (6144: below 4096 at 32K; 8192: +1-1.5% more for 3 GiB more; 4224's
zero pad rows buy nothing).

**Trade to know about:** 8 requests at once (v1.5's three-Spark default) is throughput, not latency - each
request runs at ~22 tok/s with 8 in flight against ~33 with 4. One request alone is unaffected.

## Where the time goes (per-rank profile)

One 128K-token prompt, `TF_GLM_PROFILE=1` with [`engine/0072-glm-profile-parallel.patch`](engine/0072-glm-profile-parallel.patch)
(the profiler reports nothing under `--parallel` without it), 75.8 s timed on every rank (the profiler's syncs
slow prefill ~22%; the fractions are what to read):

| block | rank 0 | rank 1 | rank 2 |
|---|---:|---:|---:|
| MoE total | 35.0 s | 35.1 | 34.9 |
| routed experts (EXL3) | **18.7** | 16.1 | 16.1 |
| DSA attention total (token selection 7.9, sparse attention 5.6) | 17.6 | 17.6 | 17.6 |
| KDA linear attention | 11.9 | 11.9 | 11.8 |
| hyper-connection glue and its exchanges | 10.7 | 10.6 | 10.9 |

MoE 46%, attention 23%, KDA 16%, glue 14%. **Rank 0 is the routed-expert straggler**: the experts' 2,048
intermediate columns split in 128-column units, 6 / 5 / 5 over three ranks, so the 6-unit rank takes 16% longer
and the others wait ~2.6 s of every 128K prompt (~3.4%). Exchanges hide behind the overlap - which is why no
NCCL setting moved anything.

## Optional engine patches ([`engine/`](engine/))

Both apply on top of the upstream recipe's patch set (v1.5, 0001-0070) and change nothing unless enabled.

- **`0072-glm-profile-parallel.patch`** - `TF_GLM_PROFILE=1` under `--parallel` > 1: arms the prefill profiler
  around the multi-stream engine's whole-chunk fills and reports once per prompt on every rank, which is what
  produced the table above.
- **`0073-tp-remainder-placement.patch`** - `TENSORFOLD_TP_REMAINDER=last` gives a split's remainder units to the
  highest rank instead of rank 0 (MoE 640 / 640 / 768, heads 21 / 21 / 22). The straggler moves to rank 2 and
  prefill is unchanged (the 6-unit rank still sets the pace); one-stream decode ~2% lower and 4 streams ~3% higher
  in both starts (each at its noise line) - but **rank 0, the API host, holds 9.1 GiB less**, and the shared KV pool (the minimum spare across ranks) grew 0.4-0.7M tokens here.

To try one without rebuilding the image, bind-mount the patched file into every rank's container at the
package path (`/usr/local/lib/python3.12/dist-packages/tensorfold/...`) - the upstream `start.sh` has no hook
for extra `docker run` arguments, so that means a local edit of its `RUN_ARGS`.

**Not attempted, measured case for it:** balance the routed experts exactly by splitting the sixteenth
128-column unit by expert instead of by column (every rank keeps 5 units of every expert plus the 16th unit of
96 of the 288 experts). Worth ~2.7% of prefill at 128K from the profile above, likely some decode; it needs
ragged per-expert widths in the EXL3 MoE kernels.

## Pitfalls we hit

- **The hotplug bandwidth trap** - above and in [the note](../../notes/gb10-cx7-hotplug-ltr.md).
- **NetworkManager undoing runtime addresses** on a peer's reboot, and re-adding a `169.254` address that
  NCCL's two-node bootstrap then dials (`NCCL error 2: unhandled system error`).
- **`TF_GLM_*` set in `local.sh` without `export` never reach the ranks**; read the running container's env.
- **When a worker dies during start**, `start.sh` reports it but leaves rank 0's container running;
  `./stop.sh` clears it.

## Security posture

The API binds `0.0.0.0:8888` by default (upstream `HOST`). Keep it on a private network or VPN, or set
`HOST` to a private address. NFS exports go to link addresses only, read-only, squashed.

## Trust notes

- The engine image is the upstream recipe's prebuilt GHCR image, pinned by digest
  (`sha256:ef83797d...` for `v0.6.0-9f73cca659a1`).
- **DFlash2 (`incoai/GLM-5.3-Flash-DFlash2`) is CC BY-NC-ND 4.0, non-commercial.** For commercial use set
  `DRAFTER=mtp` before the first start (one request at a time on v1.5).
- Read the checkpoint's model card for its license and attribution terms before you serve it.

## Credits

[MiaAI-Lab](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold) (Apache-2.0) for the
recipe, the checkpoint and the three-Spark engine; [ashhart/TensorFold](https://github.com/ashhart/TensorFold)
for the engine; incoai for DFlash2; b12x for the RoCEnante transport the recipe uses for small all-gathers.
Bugs in *this* directory are ours.
