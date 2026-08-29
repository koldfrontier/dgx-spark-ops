# SuperDeepseek-V4-Flash-abliterated-MQ · Dual DGX Spark

Serves [`Jiunsong/SuperDeepseek-V4-Flash-abliterated-MQ-2xDGX`](https://huggingface.co/Jiunsong/SuperDeepseek-V4-Flash-abliterated-MQ-2xDGX)
(304B-class MoE, mixed FP4/FP8/BF16, 1M-token configured context) as one
OpenAI-compatible vLLM endpoint split tensor-parallel across two **NVIDIA DGX
Spark / ASUS Ascent GX10** units joined by their direct QSFP fabric port.

| | |
|---|---|
| Runtime image | `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` |
| vLLM | `v0.25.2.dev0+g752a3a504.d20260714` (checkpoint author's fork) |
| Nodes | 2 × DGX Spark / ASUS Ascent GX10, tensor-parallel |
| Context | 1,048,576 tokens configured |
| Concurrency | `--max-num-seqs 12` (raised from upstream's tested `6` - see below) |
| Measured throughput | up to 171.9 tok/s aggregate (end-to-end, concurrency 12) |

This recipe **adapts** the checkpoint's own `repro/scripts/` launchers to run
on a generic two-node pair instead of the author's specific hosts. Every
deviation from upstream is called out, with the reasoning, in the script
headers and below - read those before changing anything.

## ---------- AGENT.md ATTENTION ----------

If you are an AI agent deploying this recipe on new hardware: do not run
either script as-is. Both have a block of placeholder values at the top of
`serve-superdeepseek-dual.sh` that **must** be replaced with values you
discover on the actual target machines, not copied from this file or
inferred from context. In order:

1. **On each node**, run `hostname -s` and set `expected_hostname_a`
   (head/API node) / `expected_hostname_b` (worker node) to the real
   results. Do not skip this seal - some GB10 units ship with duplicate
   machine-ids, so hostname is a real safety check, not decoration.
2. **On each node**, run `ip -br link` and identify the fabric NIC (the
   interface carrying the direct QSFP link between the two nodes, *not*
   the tailnet/management interface). Set `netdev` and the two fabric IPs
   (`master_addr` for the head node, `worker_fabric_addr` for the worker)
   to what you actually find - `enp1s0f1np1` and `10.10.10.x` here are
   this recipe's example values, not defaults to assume.
3. **On each node**, run `ibv_devices` for the RDMA device name
   (`rdma_device`), then `show_gids` for the GID index (`gid_index`) -
   pick the RoCEv2/IPv4 entry. **Never reuse the index from this or any
   other recipe**; it is driver/hardware-specific and a wrong value
   typically fails closed rather than silently degrading, but confirm
   rather than assume either way.
4. Determine the operator's actual private/VPN address for the head node
   (Tailscale, WireGuard, or private LAN) and set `api_bind_addr` to that.
   **Never** set it to `0.0.0.0` or a public IP - ask the operator which
   private network to bind if it isn't obvious, do not guess or default to
   the broadest option.
5. Set `model_dir`/`work_dir` to wherever the operator wants the checkpoint
   and cache to live on both nodes - these are directory-convention
   choices, not fixed requirements.
6. Launch the **worker** node first, confirm `world_size=2 rank=1` in its
   logs, *then* launch the head node - launching out of order is a
   documented failure mode, not just a suggestion.
7. Verify before declaring success: `curl <api_bind_addr>:8888/health`
   returns 200, `/v1/models` shows the expected served name, and one real
   chat completion returns coherent, non-empty `content` (see "The
   `reasoning` field consumes `max_tokens`" below - a small `max_tokens`
   budget will look like a broken deployment when it is actually just an
   exhausted reasoning budget).
8. If the operator asks you to raise `--max-num-seqs` beyond `12` or
   change `--speculative-config`, read "Speculative decoding" and
   "Benchmarked results" below first - both document real, hardware-tested
   tradeoffs, not arbitrary defaults you're free to tune away from without
   re-measuring.

## Prerequisites

- Two DGX Spark / ASUS Ascent GX10 units (or equivalent GB10-class hardware),
  networked together over their direct QSFP port and each reachable over a
  private/VPN network (Tailscale, WireGuard, or your own LAN behind a
  firewall) for the API itself.
- The checkpoint downloaded to identical paths on **both** nodes (it does not
  need to be pre-sharded; each node's vLLM process reads the full copy and
  splits work at load time). Roughly 200–300 GB free per node depending on
  the exact shard set you pull.
- Docker with GPU support, `--privileged` and `--network host` capability.
- This checkpoint **cannot** run on a stock/upstream vLLM build. It needs
  `--kv-cache-dtype nvfp4_ds_mla`, `--moe-backend flashinfer_b12x`, and
  `--speculative-config method=dspark`, which exist only in the model
  author's forked runtime image above.

## Finding your own values

Both scripts have a block of cluster-specific values at the top -
**do not copy these from any recipe, including this one**:

- **Hostnames** (`expected_hostname_a`/`_b` in `serve-superdeepseek-dual.sh`) -
  your own `hostname -s` output on each node. This seal exists because some
  early GB10 units ship with a duplicate machine-id/SSH host key out of the
  box, so hostname is one of the few reliable "am I node A or node B"
  signals available at boot.
- **Fabric IPs, NIC name** (`master_addr`, `worker_fabric_addr`, `netdev`) -
  whatever addressing you assigned to the direct QSFP link, and the NIC name
  from `ip -br link` on each node.
- **RDMA device, GID index** (`rdma_device`, `gid_index`) - the RDMA device
  from `ibv_devices`, and the GID index from `show_gids` **on each node** -
  pick the RoCEv2/IPv4 entry. This is genuinely hardware- and
  driver-version-specific; a wrong index typically fails closed (no
  connection) rather than silently degrading, but always verify rather than
  assume.
- **API bind address** (`api_bind_addr`) - your head node's private/tailnet
  address. **Never** set this to `0.0.0.0` or a public IP: this container
  runs `--network host`, so `0.0.0.0` publishes an uncensored,
  unauthenticated model on every interface on the box, Wi-Fi included.

## Start and stop

Worker first, always. The script self-guards by hostname, so launching the
wrong rank on the wrong box fails safely instead of corrupting the
rendezvous.

On the worker node:

```bash
./serve-superdeepseek-dual.sh 1
```

Wait for `world_size=2 rank=1` in `docker logs superdeepseek-v4-rank1`, then
on the head node:

```bash
./serve-superdeepseek-dual.sh 0
```

Stop (on either node, for its own rank):

```bash
docker rm -f superdeepseek-v4-rank0   # or -rank1 on the worker
```

Weight load plus CUDA-graph capture takes roughly 6–7 minutes per the
checkpoint author's own figures; the first start on a fresh cache directory
can take longer (~10 minutes measured) because `--enable-flashinfer-autotune`
compiles fused kernels and autotunes against empty caches. Later starts reuse
that cache. Do not treat a slow first start as a hang - the
`shm_broadcast "No available shared memory broadcast block found in 60
seconds"` line during this phase is INFO-level and self-attributed to
compilation, not an error.

## Optional hotfixes

Two of MiaAI-Lab's [DeepSeek-v4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark)
recipe's boot-time patches can be layered on top of this launcher. They are
**not** bundled here - grab them from that repository's own `patches/`
directory and place (or symlink) them at `./patches` next to this script,
then:

```bash
ENABLE_SPIN_WAIT_HOTFIX=1 ENABLE_ISSUE22_HOTFIX=1 ./serve-superdeepseek-dual.sh <0|1>
```

- `hotfix-gb10-spin-wait.sh` - an IPC busy-wait timing constant
  (`busy_loop_s` 1 → 0.002), reduces CPU contention under TP=2. No
  numerical/output effect.
- `hotfix-nvfp4-ds-mla-issue22.sh` - routes `nvfp4_ds_mla` KV-cache reads to
  the fast FP8 kernel dispatch path instead of the slow bf16 fallback.
  Single-line dispatch condition; this recipe already uses that KV-cache
  dtype.

On the reference hardware this recipe was developed on, both were kept after
isolated testing: no measurable throughput change at short/medium context on
their own, no reproduction of a documented long-context regression up to
~461K tokens tested, zero errors. Neither touches scheduling, batching, or
speculative-decoding logic. Your mileage may vary - test before trusting
blindly on different hardware.

## Speculative decoding

Upstream's own tested-and-shipped value is `SPEC_TOKENS=1
SPEC_SAMPLE_METHOD=greedy` (this script's default). MiaAI-Lab's DSpark
recipe instead uses `5`/`probabilistic`, which measurably raises
low-concurrency throughput - but **their own issue tracker documents an
EngineCore crash for that combination under mixed-length concurrent
traffic**, which is what most real workloads (chat UI + agents + benchmarks
together) look like. If you enable it, understand that risk first.

If you hit an EngineCore crash, the immediate rollback is
`SPEC_TOKENS=1 SPEC_SAMPLE_METHOD=greedy` (or just unset both).

## The `PERFORMANCE_MODE` knob - do not set it to `throughput`

`run-vllm-inner.sh` reads `--performance-mode` from `$PERFORMANCE_MODE`
(default `interactivity`, matching upstream). `throughput` was tested once
on the reference deployment: the engine logged "Performance mode set to
'throughput'", resolved `cudagraph_mode` to a coarser capture-size set, ran
for ~620 seconds, then exited with code 1 (not OOM, not a signal - a
clean-ish application exit) and was destroyed by `--rm` before its logs
could be captured. Root cause is **unconfirmed**. If you want to try it,
arm `docker logs -f <container> > relaunch-$(date +%s).log 2>&1 &` right
after launch, or a repeat failure will be just as undiagnosable.

## The `reasoning` field consumes `max_tokens`

This checkpoint returns its chain-of-thought in a separate `reasoning`
message field, and those tokens are billed against `max_tokens`. Measured on
the reference deployment:

| `max_tokens` | `finish_reason` | `content` | `reasoning` |
|---:|---|---|---|
| 200 | `length` | **empty** | consumed the whole budget |
| 1200 | `stop` | 296 chars, correct | 2,693 chars |

A client that reads only `content` will see blank answers at small budgets.
Budget at least ~800 tokens even for one-sentence answers if reasoning is
enabled, and expect benchmark tokens/sec figures to include reasoning
tokens unless you disable thinking per-request
(`chat_template_kwargs: {"thinking": false}`).

## Verifying the fabric is actually used

This image does not set `NCCL_DEBUG=INFO`, so there is no `NET/IB` or
`NET/Socket` line in the logs to confirm RoCE is in play. Read the device
counters around a request instead (adjust the device path to yours):

```bash
C=/sys/class/infiniband/<your-rdma-device>/ports/1/counters
cat $C/port_xmit_data $C/port_rcv_data   # before, on both nodes
# ...issue one completion...
cat $C/port_xmit_data $C/port_rcv_data   # after
```

On a healthy TP=2 request the deltas are large and mirrored between nodes
(measured on the reference deployment: ~450 MB each way per node for a
single 667-token completion; values are in 4-byte lanes). A socket fallback
cannot produce numbers like that.

## Benchmarked results (reference deployment)

Concurrency raised from upstream's `--max-num-seqs 6` to `12`
(`--max-num-batched-tokens` left at upstream's `8192`):

| Level | Aggregate tok/s (end-to-end) |
|---|---:|
| c6 | 115.5 |
| c8 | 131.4 |
| c12 | 171.9 |

`num_requests_running` hit exactly the configured ceiling in every
corresponding burst (the raised ceiling was genuinely used, not just
configured); KV cache usage peaked at 8.85% of the reserved pool at c12; zero
preemptions. At c12, end-to-end aggregate throughput (171.9 tok/s plain
text) already exceeds the model card's own headline claim of "123.3
aggregate tok/s on structured tool generation," in the same end-to-end
metric.

Separately: a fabric MTU increase from 1500 to 6000 (standard jumbo-frame
tuning, moving the RoCE path MTU from 1024 to 4096) measured a real gain at
concurrency 6 on the reference hardware - plain-text steady-state ~104.7 →
~116.2 tok/s aggregate. This is a network-layer change independent of any
vLLM flag; if your OS/NIC/switch path supports jumbo frames, it is worth
testing.

## Security posture

- Runs `--privileged`, `--network host`, `--ipc host` from a third-party
  image that is not reproducible from a reviewed Dockerfile in this repo.
- This checkpoint is **abliterated** (refusal training removed) - the model
  card documents worst-mode refusal dropping from 97.92% to 4.17%. There is
  no built-in moderation. Decide your own access-control and content-policy
  posture before exposing this to anyone beyond yourself.
- No application-level authentication. Whatever network you bind the API to
  **is** the entire access boundary - a VPN/tailnet is strongly recommended
  over a bare LAN bind.
- Verify your own checkpoint download against the Hub's published hashes;
  this recipe does not do that for you.

## Files

```
serve-superdeepseek-dual.sh   outer launcher - hostname seal, docker run, env wiring
run-vllm-inner.sh             in-container launcher - vLLM argument set, opt-in hotfixes
patches/                      (not included) - optional MiaAI-Lab hotfixes, see "Optional hotfixes"
```

## Status

Running in production on the reference two-node pair. The provenance caveat
in "Prerequisites" (dropped upstream verification gate) and the untested
`PERFORMANCE_MODE=throughput` crash are the two open items worth knowing
about before you rely on this. If you hit something different on your own
hardware, please open an issue.

## License

Scripts in this directory: **Apache-2.0**, per the repository root. The
runtime image, the model checkpoint, and the optional MiaAI-Lab patches are
each licensed separately by their own authors - check their sources before
redistributing.
