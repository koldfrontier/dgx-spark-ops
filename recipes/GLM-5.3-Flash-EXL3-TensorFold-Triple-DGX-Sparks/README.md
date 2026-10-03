# GLM-5.3-Flash EXL3 · three DGX Sparks, TensorFold, no switch

Serves [`Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold`](https://huggingface.co/Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold)
as one OpenAI-compatible endpoint, tensor-parallel across **three** DGX Spark / ASUS Ascent GX10 units
cabled as a **triangle** (one direct QSFP cable per pair, no switch), using
[MiaAI-Lab's TensorFold recipe](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold)
and its experimental three-Spark engine (patches 0066-0068).

This directory is not a fork of that recipe. It is what we add on top to run it on three nodes: the
fabric setup and the checks that catch a silently degraded fabric, the start settings we measured, the
harness, and the numbers.

| | |
|---|---|
| Shape | TP3 across 3 x GB10, rank 0 serves the API on `:8888` |
| Engine | TensorFold v0.6.0 + recipe v1.4 (`cf28cc4`, 68 patches), image `v0.6.0-5e01f1bb74d8` |
| Checkpoint | `078455ff`, 164 GiB, one copy on the head, read by the workers over NFS |
| Rank 0 memory | startup estimate 68.74 GiB; shared KV pool 4,997,120 tokens (`KV_POOL_GIB=27`) |
| Serving | 1,048,576-token window, 4 streams, FP8 KV, DFlash2 + copy drafts, vision on |
| Decode, one stream | prose **66.9** tok/s, code **101.9**; TTFT 152 ms |
| Decode, 4 streams | prose **123.1** tok/s aggregate |
| Cold prefill | **2,226 / 2,260** tok/s at ~8K / ~32K tokens (random-word prompts) |
| Vision + tool calling | 7/7 on a real-image / real-tool-call suite |
| Start to serving | 165-190 s |
| Last verified | 2026-10-03, on the hardware below |

Against two Sparks with the same checkpoint and recipe, same harness: prefill +13-15%, one-stream prose
+23%, code +28%, 4 streams +31%.

> **Status: tuning in progress.** The figures above are measured on a healthy fabric. Our first round of
> knob measurements was made on a fabric we later found degraded (see [the hotplug note](../../notes/gb10-cx7-hotplug-ltr.md))
> and has been discarded; a full re-run on the healthy fabric is under way and this file will be updated
> with it.

## What this adds to the upstream recipe

- **A fabric check that catches what nothing else does.** Re-cabling a GB10 so that both QSFP cages are
  empty at once leaves its ConnectX-7 at ~1/8 RDMA bandwidth until reboot, with every link, PCIe and MTU
  check still green. It cost us 45% of prefill. [`fabric/check-fabric.sh`](fabric/check-fabric.sh) reads
  the marker and runs a loopback bandwidth test per device. Details: [`../../notes/gb10-cx7-hotplug-ltr.md`](../../notes/gb10-cx7-hotplug-ltr.md).
- **Triangle addressing that survives a peer's reboot** ([`fabric/triangle-addr.sh`](fabric/triangle-addr.sh)),
  and why DGX OS's NetworkManager profiles undo runtime addressing otherwise.
- **Measured start settings for three nodes**: `COMM=roce` and `NCCL_CHANNELS=8` ([`config/local.sh.example`](config/local.sh.example)).
- **A small, repeatable harness** ([`bench/tfbench.py`](bench/tfbench.py)) and every result behind the numbers
  ([`bench/results-2026-10-03.jsonl`](bench/results-2026-10-03.jsonl)).

## ---------- AGENT.md ATTENTION ----------

If you are an AI agent setting this up on new hardware, in order, confirming each with the operator:

1. **Run `fabric/check-fabric.sh` on every node before the first benchmark**, and again after any
   re-cable or reboot. A node reporting `LTR OFF` or a loopback under ~50 Gb/s gives you wrong numbers
   for everything; reboot it. Do not tune on top of an unchecked fabric - we did, and threw the results away.
2. **Cable a directed triangle**: each node's port 0 to the next node's port 1. Confirm with LLDP or link
   state, not by trusting labels. A mirrored triangle leaves one pair NCCL cannot connect.
3. **Address each PCIe twin on its own /24 per cable**, both ends; both twins carry traffic only when both
   are addressed. Keep NetworkManager off those ports while you run (see `triangle-addr.sh`).
4. **Check the rendezvous**: `getent hosts $(hostname)` on the head. A loopback answer means you must set
   `MASTER_ADDR` to an address every worker reaches.
5. **Give `COMM` on the command line** (`COMM=roce ./start-tp3.sh`); `start-tp3.sh` ignores it in
   `scripts/local.sh`.
6. **Warm the server before measuring** (a few decode requests and one concurrent wave). TensorFold's first
   requests after start run slow.

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
git checkout cf28cc4          # what was measured; newer releases exist
cp <this dir>/config/local.sh.example scripts/local.sh   # then fill in
```

1. **Fabric** - on each node, `fabric/triangle-addr.sh <four CIDRs>` (examples in its header), then
   `fabric/check-fabric.sh`. Ping every twin pair from both ends.
2. **NFS** - export the head's HF cache read-only to every worker link address (both twins of both
   cables), e.g. `/home/<you>/.cache/huggingface <w1-a>(ro,no_subtree_check,all_squash,anonuid=1000,anongid=1000) ...`.
3. **ssh** - the head must reach each worker *at its link address* with your key (`~/.ssh/config` `Host`
   block if your key is selected per host).
4. **Prepare** - `TP=3 scripts/prepare.sh` downloads on the head, copies the image to each worker over the
   link and checks the workers' NFS view file by file.

### Finding your own values

| Value | How to find it | Why not to copy ours |
|---|---|---|
| Link CIDRs | One /24 per twin per cable, yours | Ours only need to be unique on your fabric |
| `WORKER`, `WORKER2` | The worker's address on the cable to the head | They must route over the cable, not the LAN |
| `MASTER_ADDR` | An address of the head every worker reaches; only needed when the hostname resolves to loopback | LAN layouts differ |
| Which port is "port 0" | `ip -br link` + LLDP; our TOP / BOTTOM cable labels meant port 0 on two units and port 1 on the other two | Mounting orientation flips it |

## Run

```bash
COMM=roce ./start-tp3.sh            # NCCL_CHANNELS=8 comes from scripts/local.sh
./stop.sh                           # stops all three ranks
```

Expect, in rank 0's log: `rank 0 of 3`; `all-gathers up to 512 KiB over RoCE (rank 1 over <two
devices>; rank 2 over <the other two> ...)`; `prompt chunks' hyper-connections: rows split between the
ranks, exchanges by send/receive ...`; then `serving ... rank 0 of 3` after ~2.5-3 minutes.

## Measured (healthy fabric, 2026-10-03)

Harness: [`bench/tfbench.py`](bench/tfbench.py) from a fourth machine over the LAN. Warm-up first; cold
random-word prompts of ~7.9K and ~31.9K tokens (`max_tokens` 1, tok/s = prompt tokens / wall, median of 2);
one-stream decode of a prose and a code prompt (256 tokens, temperature 0, thinking off; median of 3 and 2);
prose at 4 concurrent streams. Random words prefill ~4-8% slower than sparkDash's filler text on this
model (two comparisons), so compare our prefill to other tables with that in mind. Each run is a fresh start; every run's
settings were read back from the running container.

| TP3 | prefill ~8K | ~32K | prose x1 | code x1 | prose x4 |
|---|---:|---:|---:|---:|---:|
| recipe defaults (`COMM=nccl`, 4 channels) | 2,205 | 2,231 | 62.8 | 99.3 | 118.8 |
| `COMM=roce` (2 starts, mean) | 2,177 | 2,228 | 67.0 | 102.2 | 122.8 |
| **`COMM=roce NCCL_CHANNELS=8`** (2 starts, mean) | **2,245** | **2,259** | **67.1** | **102.0** | **122.3** |
| `COMM=roce TF_GLM_HC_EXCHANGE=gather` | 1,782 | 1,780 | 66.2 | 102.1 | 123.5 |
| `COMM=roce SPLIT=0` | 1,675 | 1,675 | 66.2 | 102.6 | 122.2 |
| *TP2 (two of the nodes), recipe defaults* | *1,921* | *1,966* | *54.4* | *80.0* | *93.4* |

Single starts unless marked; we have not yet measured the start-to-start spread properly, so read
differences under ~2% as noise. That is what the re-run is for.

## Pitfalls we hit

- **The hotplug bandwidth trap** - above and in [the note](../../notes/gb10-cx7-hotplug-ltr.md).
- **NetworkManager undoing runtime addresses** on a peer's reboot, and re-adding a `169.254` address that
  NCCL's two-node bootstrap then dials (`NCCL error 2: unhandled system error`).
- **`TF_GLM_PROFILE=1` reports only the start-up warm-up chunk with `PARALLEL` > 1** - the multi-stream
  engine's prompt path never arms it. Profile with `PARALLEL=1`.
- **When a worker dies during start**, `start.sh` reports it but leaves rank 0's container running;
  `./stop.sh` clears it.

## Security posture

The API binds `0.0.0.0:8888` by default (upstream `HOST`). Keep it on a private network or VPN, or set
`HOST` to a private address. NFS exports go to link addresses only, read-only, squashed.

## Trust notes

- The engine image is the upstream recipe's prebuilt GHCR image, pinned by digest
  (`sha256:14f15591...` for `v0.6.0-5e01f1bb74d8`); `prepare.sh` streams it to the workers over the link.
- **DFlash2 (`incoai/GLM-5.3-Flash-DFlash2`) is CC BY-NC-ND 4.0, non-commercial.** For commercial use set
  `DRAFTER=mtp` before the first start (one request at a time, ~5-10% slower decode).
- Read the checkpoint's model card for its license and attribution terms before you serve it.

## Credits

[MiaAI-Lab](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold) (Apache-2.0) for the
recipe, the checkpoint and the three-Spark engine; [ashhart/TensorFold](https://github.com/ashhart/TensorFold)
for the engine; incoai for DFlash2; b12x for the RoCEnante transport the recipe uses for small all-gathers.
Bugs in *this* directory are ours.
