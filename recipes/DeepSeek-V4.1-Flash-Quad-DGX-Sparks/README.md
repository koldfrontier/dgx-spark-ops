# DeepSeek-V4.1-Flash · four DGX Sparks, no switch

Serves [`deepseek-ai/DeepSeek-V4.1-Flash`](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash)
(552B-backbone MoE, 769B with the Engram tables, 16B active, MXFP4 experts,
1M native context) as **one** OpenAI-compatible vLLM endpoint, tensor-parallel
across **four** DGX Spark / ASUS Ascent GX10 units wired as a **switchless
ring** — each unit's two QSFP ports cabled to its two neighbours, no switch
bought, no switch needed.

| | |
|---|---|
| Shape | TP4 across 4 × GB10, rank 0 serves the API |
| Checkpoint | 475 GiB, one copy on the head, read by the others over NFS |
| Per-rank weights | 81.58 GiB resident |
| Context | 300,000 (boot 2/4) or **1,048,576** (boot 5) |
| Speculative decoding | DSpark k=5, measured acceptance 3.55 over a 20-minute mixed soak |
| Vision + tool calling | both on, 7/7 on a real-image / real-tool-call suite |
| Decode | **62–63 ms/step**, 92.8 tok/s counting, C1 55–57 per-stream, C6 144–152 aggregate |
| Long context | needle exact at **298K / 596K / 993K** tokens |
| Transport | [FujitsuPolycom/sparkring](https://github.com/FujitsuPolycom/sparkring) patched NCCL 2.30.7, four-rank switchless cycle |
| Fabric cost | 4.64 ms of a 63 ms decode step; 531.1 GB per ring link over a 20-min soak |
| Last verified | 2026-09-14 on the hardware described below |

It does **not** fit at TP2 in any layout, so this is a four-node workload or
nothing: while it serves, everything else on those four machines is down.

## What this recipe adds

Three other people have published DGX Spark recipes for this checkpoint, and
this one stands on all of them — [tonyd2wild](https://github.com/tonyd2wild/DeepSeek-V4.1-Flash-vLLM-DGX-Spark)
(the patch set and the launcher this one is adapted from, MIT),
[ZackO2o](https://github.com/ZackO2o/DeepSeek-V4.1-Flash-4x-GB10-1M-Full-Recipe)
(the 1M-context work, MIT), and [MiaAI-Lab](https://github.com/MiaAI-Lab/DeepSeek-v4.1-Flash-DGX-Sparks).
What is here and not there:

- **A switchless four-node ring**, rather than a switch. The transport, the
  routing, the failure modes and the measured cost of the topology are in
  [`../../notes/ring-ops.md`](../../notes/ring-ops.md).
- **Boot profiles as files**, not flags in your shell history: a gate profile,
  a 300K serving profile, a fair-prefill profile, a 1M profile. Changing the
  serving shape is `cp profiles/<x>.env ~/boot.env && ring-cluster.sh start`,
  and a rollback is the same command with the old file.
- **Fairness under mixed load.** `--long-prefill-token-threshold` measured from
  both sides: what it buys a co-scheduled stream, and what it costs the long
  request.
- **Verification that would catch a silent failure**, not just a clean boot:
  RDMA counters, per-category decode, needle retrieval, a soak, and the
  specific things on this stack that fail *quietly* (a wrong CUDA-graph
  capture list, a patch set built against the wrong commit).

## ---------- AGENT.md ATTENTION ----------

If you are an AI agent deploying this on new hardware, work through these in
order and confirm each with the operator before moving on.

1. **Pin the vLLM commit, and verify what you actually built.** The patch set
   is seven *whole-file* replacements. Against a different tree they still
   load, the engine still boots, and every generation is garbage — that is
   [tonyd2wild#2](https://github.com/tonyd2wild/DeepSeek-V4.1-Flash-vLLM-DGX-Spark/issues/2),
   caused by the branch being force-pushed under a recipe that named a branch
   rather than a commit. Build against
   `e47aa780bccf59f59dfa2cbb18e17a10b4fe69ba` and fetch it **by sha**. Then
   check what you actually built, before any config: `sha256sum` the unpatched
   `vllm/v1/attention/backends/mla/indexer.py` inside the image. `392d93da110e…`
   is the right tree; `416677cea31c…` is the commit after it, and no launcher
   flag will save you there (verified on our own image; the table is in
   [tonyd2wild#2](https://github.com/tonyd2wild/DeepSeek-V4.1-Flash-vLLM-DGX-Spark/issues/2)).
2. **Cable the ring, then prove the cabling.** Do not trust the labels on the
   cables. `lldpctl` (or `ip -d link` plus the switch-less neighbour's MAC) on
   every node, and write the cycle down before configuring anything.
3. **Derive every node's RoCEv2 GID index on that node.** Identical hardware
   enumerates it differently. The launcher refuses a wrong one — that check
   exists because copying a neighbour's value is the obvious mistake.
4. **Never `--host 0.0.0.0`.** `ring.conf` takes a private/VPN address for the
   API. Ask the operator before widening it; the endpoint has no auth.
5. **First boot is `profiles/boot1-eager.env`.** Eager, text-only, 131K,
   no speculation. If it serves and answers coherently, the ring, the
   checkpoint, the patch set and RDMA are all good, and everything after that
   is tuning. Do not start at the serving profile.
6. **Verify with `verify/` and the gate lines, not with "the container is up".**
   A boot that garbles, a boot whose NCCL fell back to TCP, and a healthy boot
   all look identical in `docker ps`.
7. **Do not raise `--max-num-seqs` or hand-write `cudagraph_capture_sizes`.**
   The launcher derives the capture list from `SEQS` and `SPEC_K`; a list that
   never matches a real batch shape produces silent NaN on this stack, not an
   error (see `notes/ring-ops.md`).

## Hardware and prerequisites

- **Four** DGX Spark / ASUS Ascent GX10 (GB10, 128 GB unified memory each).
- Four QSFP cables, wired as a cycle: `0↔1`, `1↔2`, `2↔3`, `3↔0`. Each node
  uses both of its ports, one per neighbour. No switch.
- One /24 per link, and routes so any node can reach any other (two of the
  nodes forward; see `notes/ring-ops.md`). A VPN/tailnet address per node as
  the always-up control plane is strongly recommended — it lets you boot the
  cluster before the fabric routes exist, and to fix them if they break.
- ~500 GB free on the head for the checkpoint, exported read-only to the
  other three (NFS here), plus ~50 GB per worker for node-local Engram rows.
- Docker with GPU support, and `sudo -n` for `drop_caches` and the share mount.
- Patience: a first build is ~2 h, a cold boot is 11–13 min.

## Build

The image is not published anywhere — build it yourself. Follow
[tonyd2wild's build](https://github.com/tonyd2wild/DeepSeek-V4.1-Flash-vLLM-DGX-Spark)
(`build/`), which layers, on `vllm/vllm-openai:nightly`:

1. vLLM `dsv41-feat` **at `e47aa780bccf59f59dfa2cbb18e17a10b4fe69ba`**, fetched
   by sha (`git fetch origin <sha>`), not by branch name.
2. `_C_stable_libtorch` compiled for `sm_121a`.
3. FlashInfer `v0.7.0rc1`, plus the prebuilt `mxfp8_gemm_cutlass_sm120` and
   `sparse_mla_sm120` kernels so the first request does not JIT them.

Build on **one** node and copy the image to the others
(`docker save | ssh | docker load` over the fabric is fastest). Do not build
on a node that is serving: the build wants all the RAM, and vLLM runs with
`--oom-score-adj 500`.

The seven patch files come from tonyd2wild's `patch/` directory with its
`mounts.txt`; md5-verify them against that repo's `patch/README.md` after
copying to `$PATCH_ROOT/<name>/` on all four nodes.

## Configure

```bash
cp launch/ring.conf.example launch/ring.conf   # then fill in, per the comments
```

Every value in `ring.conf` is read off your own machines. The examples are
placeholders and will not work anywhere.

### Finding your own values

| Value | How to find it | Why not to copy it |
|---|---|---|
| `RANKn_HOST` | `hostname` on each node | The launcher refuses a rank on the wrong machine; that only works if these are right |
| `RANKn_HCA` | `ibv_devices`, then match to the ports you cabled | Port naming differs between machines of the same model |
| `RANKn_GID` | For each HCA: the index `i` where `/sys/class/infiniband/<hca>/ports/1/gids/<i>` is `::ffff:<your fabric IPv4>` **and** `gid_attrs/types/<i>` says `RoCE v2` | Differs per node. Ours were 3 on two nodes and 5 on the other two, same model, same day |
| `RANKn_FAB_IP/IF` | Your own addressing, one /24 per link | — |
| `RANKn_PRIV_IP`, `PRIV_IF` | Your VPN/tailnet address and interface | — |
| `NCCL_SO_SHA256` | `sha256sum` of the patched NCCL you downloaded | The launcher verifies the transport binary on every boot; an empty value only warns |

## Run

Workers first, head last, every time.

```bash
# on each node, or from one node with launch/ring-cluster.sh
. profiles/boot1-eager.env
IMAGE=<your image> bash launch/ring-launch.sh 3   # then 2, then 1, then 0
```

or, from any node that has SSH to the others:

```bash
cp profiles/boot2-serving-300k.env ~/boot.env
R0=user@rank0 R2=user@rank2 R3=user@rank3 bash launch/ring-cluster.sh start
bash launch/ring-cluster.sh gates
```

Stopping is `ring-cluster.sh stop` (head first — a worker that joins a
still-listening old head hangs the next boot). Never `pkill -f 'vllm serve'`:
vLLM renames its `EngineCore`/`Worker_TP*` children, so that pattern kills the
launcher and orphans the workers, which keep the GPU and the port.

### Gate lines to expect

```
Model loading took 81.58 GiB memory and ~295 seconds
Engram DISK mode: layer N rows [a, b) read from model-000NN-of-00048.safetensors
Graph capturing finished in 6 secs, took 1.78 GiB
GPU KV cache size: 1,992,707 tokens, Maximum concurrency for 1,048,576 tokens per request: 1.90x
Application startup complete.
```

`Model loading took 81.58 GiB` is the strongest single signal that you built
and patched the right thing: three independent fleets report the same number
to two decimals. A different number means a different tree.

## Measured

All on four GB10 units on the switchless ring, temperature 0, thinking off,
prompt set held constant across boots.

### Decode (boot 2 / boot 4, 300K window)

| concurrency | aggregate tok/s | per-stream tok/s | mean TTFT (s) |
|---|---:|---:|---:|
| C1 | 50.4 | 57.2 | 0.30 |
| C2 | 77.4 | 44.5 | 0.35 |
| C3 | 96.1 | 36.7 | 0.38 |
| C4 | 117.9 | 34.7 | 0.40 |
| C6 | 151.9 | 29.0 | 0.48 |

Per-stream C1 by category — the spread matters more than the headline, because
the mean of eight categories is not comparable to anyone's single prompt:

| counting | tables | code | math | reasoning | JSON | summary | prose | narrative |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 90.5 | 90.0 | 75.6 | 69.1 | 63.0 | 59.7 | 36.8 | 33.1 | 30.6 |

That is a 3× spread on one engine in one run, and it tracks DSpark acceptance
(counting and code accept near the k+1 maximum of 6; prose and narrative near
2). At a 63 ms step, 2.0 accepted tokens/step is 31.7 tok/s and 5.85 is 92.9 —
so a "slow" number on a prose prompt is not a broken fleet.

### Long context (boot 5, 1M window, gmu 0.83)

| prompt tokens | TTFT (s) | prefill tok/s | needle |
|---:|---:|---:|---|
| 298,172 | 222.6 | 1,340 | exact |
| 596,196 | 522.4 | 1,141 | exact |
| 993,435 | 1,032.7 | 962 | exact |

KV pool at 1M: **1,992,707 tokens = 1.90×** a full-window request. Decode is
unchanged from the 300K profile (62.4–63.6 ms/step, C1 55.2, C6 143.8), so on
this hardware the 1M window costs pool headroom, not speed. Note prefill rate
falls with length — a full 1M prompt is a 17-minute first token, and your
client's timeout, not the model, is what will break first.

### Soak (8 streams, 20 minutes, mixed categories)

829 requests, **0 errors, 0 hangs, 0 preemptions**, 104.7 tok/s aggregate,
TTFT p50 0.79 s, longest gap between two chunks of any stream 0.72 s, DSpark
acceptance 3.55. Every ring link moved 531.1 GB in that window, all four within
0.1 GB of each other.

### The long-prefill threshold, both directions

During a cold 210,041-token prefill (TTFT 114 s), a short stream started 15 s
in got its first token in 2.4 s and then a chunk **every 1.03 s** at
`--long-prefill-token-threshold 2048`. Without the cap that gap is one full
8192-token prefill step. The cost is on the long request: cold prefill drops
9–13% above the cap (1,544 tok/s at 40K vs 1,720 uncapped; 1,488 at 130K vs
1,635), and nothing below it — prompts under the threshold, and prefix-cached
turns that add fewer new tokens than the threshold, are unaffected. `4096`
halves both the benefit and the cost; `8192` is a no-op.

## Verifying a whole-file patch before you mount it

Whole-file patches belong to the tree they were cut from. Mounting an older
file over a newer tree *boots* and is wrong — that is the failure mode behind
the garbling issue, and it is worth 60 seconds to rule out. Before adding
anyone's file (for example ZackO2o's `gpu_worker.py` for the 1M profile):

```bash
# the file as YOUR image has it
docker run --rm --entrypoint cat <your image> \
  /usr/local/lib/python3.12/dist-packages/vllm/v1/worker/gpu_worker.py > ours.py
diff ours.py theirs.py
```

You want to see *only* the changes their README documents. Ours showed exactly
four hunks (an env gate on the graph-memory profiling pass, `warmup_kernels`
moved before capture, the matching removal after it, and a post-capture state
cleanup) and nothing else — so their base was our pinned commit and the file
was safe to mount. Anything else in that diff means re-derive, don't mount.

## Security posture

The API binds to `RANK0_API_IP` from `ring.conf` and has **no authentication**.
Put a private/VPN address there. `0.0.0.0` on a machine with a public interface
publishes an unauthenticated endpoint that can generate arbitrary text and read
whatever you have mounted into the container; that is your decision to make
deliberately, not a default this recipe will make for you.

The container runs `--cap-add IPC_LOCK --device /dev/infiniband` rather than
`--privileged`, which is the narrower grant that still lets NCCL use RDMA.

## Trust notes

- **The checkpoint** is DeepSeek's own (`deepseek-ai/DeepSeek-V4.1-Flash`).
  Pin `model_revision` and verify sizes after download; ours was
  `dba1be0a40aa45a94ad051997016db3960a90277`, 88 files, 510,313,353,565 B.
- **The patch set** (tonyd2wild, MIT) is seven whole-file Python replacements
  that run inside the engine. Read them, or at least md5-verify them against
  the repo's own `patch/README.md`, and pin the vLLM commit they were cut from.
  [im0xMagnus's PR #4](https://github.com/tonyd2wild/DeepSeek-V4.1-Flash-vLLM-DGX-Spark/pull/4)
  regenerates them as repo-relative diffs, which is easier to review — we
  verified those diffs apply at `e47aa780b` and reproduce the seven files
  byte-for-byte.
- **The patched NCCL** (sparkring, Apache-2.0) is a shared object you
  `LD_PRELOAD` into the engine. Pin its sha256 in `ring.conf`; the launcher
  checks it every boot.
- **ZackO2o's `gpu_worker.py`** (MIT), only if you use the 1M profile — verify
  it against your own image first, as above.
- Nothing here is vendor-validated. NVIDIA does not list this checkpoint, this
  topology, or this vLLM tree as supported on DGX Spark.

## Upgrading the engine: read this before you try

vLLM `main` has since gained DSv4.1-specific work worth wanting (fused
per-step metadata preparation, a hardened top-k gather, a `DeepSelect` top-k
path). Rebasing the patch set onto it, as of 2026-09-14, is **not** a rebase:

- The SM12x top-k fix became a flag — `--sparse-indexer-topk-backend per_row`
  — because the dispatch it patched moved into a new module.
- The indexer backend was renamed and moved, so the 64-state page subclass
  needs re-pointing.
- The Engram work is structural: upstream now implements `cpu_offload` as
  pinned host memory over UVA, which on GB10 comes out of the same 128 GB the
  GPU uses. The disk-backed table + node-local rows that make four Sparks work
  at all have to be re-derived as a third storage backend behind upstream's new
  hooks. There are no reference numbers for that on this hardware yet.

We measured that surface and stayed on the pinned commit. If you are reading
this later, check whether upstream has rebased before spending the two hours.

## Credits

[tonyd2wild](https://github.com/tonyd2wild/DeepSeek-V4.1-Flash-vLLM-DGX-Spark)
(MIT) for the patch set, the build and the launcher this one adapts;
[FujitsuPolycom/sparkring](https://github.com/FujitsuPolycom/sparkring)
(Apache-2.0) for the switchless-ring NCCL and the four-rank cycle environment;
[ZackO2o](https://github.com/ZackO2o/DeepSeek-V4.1-Flash-4x-GB10-1M-Full-Recipe)
(MIT) for the 1M-context patch and the gmu→KV-pool curve;
[im0xMagnus](https://github.com/im0xMagnus) for the repo-relative diffs;
[MiaAI-Lab](https://github.com/MiaAI-Lab/DeepSeek-v4.1-Flash-DGX-Sparks) for
the GB10 profiling work. Bugs in *this* recipe are ours.
