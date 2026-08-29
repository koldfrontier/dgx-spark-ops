# Qwen3.8-Flash-Next-FP8 · Dual DGX Spark

Serves [`Qwen/Qwen3.8-Flash-Next-FP8`](https://huggingface.co/Qwen/Qwen3.8-Flash-Next-FP8)
(native FP8, `qwen4_exp` "Next" MoE architecture with MTP speculative
decoding, 262,144-token native context, vision-capable) as one
OpenAI-compatible vLLM endpoint split tensor-parallel across two **NVIDIA
DGX Spark / ASUS Ascent GX10** units.

| | |
|---|---|
| Image | `skfine24/qwen38-flash-next-vllm:20260827` (third-party, see **Trust notes**) |
| Toolkit | [`eugr/spark-vllm-docker`](https://github.com/eugr/spark-vllm-docker) |
| Checkpoint | ~173 GB, native FP8, full copy needed on **both** nodes |
| Context | 262,144 tokens native |
| Speculative decoding | MTP, 3 draft tokens — measured 44% acceptance |
| Vision | working (confirmed with a real image, not just config) |
| Concurrency | `--max-num-seqs 4` (deliberately chosen, not the image's own default — see **Concurrency tuning**) |
| Measured peak throughput | ~80 tok/s aggregate (8-way concurrency, reproduced across 3 independent runs) |

There is **no official vLLM support for this checkpoint yet** — the
architecture ships in two unmerged upstream PRs
([#53896](https://github.com/vllm-project/vllm/pull/53896),
[#53899](https://github.com/vllm-project/vllm/pull/53899)), and neither
lists DGX Spark / GB10 as a validated platform. This recipe uses a
pre-built third-party image instead, after a self-built attempt from the
unmerged PR hit a genuine, unconditional upstream bug — see **Alternative:
building from the upstream PR** below before trying that path yourself.

## ---------- AGENT.md ATTENTION ----------

If you are an AI agent deploying this recipe on new hardware: do not run
`launch.sh` as-is. Work through these in order and confirm each before
moving on.

1. **On each node**, run `ip -br link` and identify the fabric NIC (the
   interface carrying the direct QSFP link between the two nodes) and
   `ibv_devices` for the RDMA device name. Set `ETH_IF`/`IB_IF` in `.env`
   (copied from `.env.example`) to what you actually find - the example
   values are illustrative, not defaults.
2. Determine both nodes' fabric IPs (however the operator addressed the
   direct link, head node first) and set `CLUSTER_NODES` accordingly.
3. Confirm with the operator where the checkpoint should live on **both**
   nodes (identical path on each - it is not pre-sharded, every node reads
   the full copy), download it there
   (`hf download Qwen/Qwen3.8-Flash-Next-FP8 --local-dir <path>`), and pass
   that path as `CHECKPOINT_DIR` when running `launch.sh`.
4. **Before running anything**, re-check the trust facts in "Trust notes"
   yourself rather than trusting this README's snapshot blindly - it is
   dated, and pull counts/stars/tags on a single-author image can change.
   Run `docker history --no-trunc <image>` and skim it; if anything looks
   different from what's documented here, stop and tell the operator
   before proceeding, don't silently continue.
5. **Do not decide the `--host 0.0.0.0` question yourself.** `launch.sh`
   binds every interface on the box by default (see "Security posture") -
   ask the operator whether that's acceptable for their network, or
   whether to bind a private/tailnet address instead, and edit `launch.sh`
   accordingly. This is a real security tradeoff, not a cosmetic flag.
6. Verify before declaring success: `curl <host>:8888/health` returns 200,
   `/v1/models` shows `qwen` with `max_model_len: 262144`, and one real
   chat completion returns coherent content. If the operator specifically
   asked for vision or MTP, verify those with real requests and real
   `/metrics` counters per "Verifying MTP and vision are actually
   working" below - a successful boot log is not proof either is actually
   working.
7. If asked to raise `--max-num-seqs` above `4`, read "Concurrency tuning"
   below first: `5` measured no better than `4`, and `6`'s apparently
   higher peak did not reproduce and came with real (if non-fatal) memory
   pressure. Don't chase a higher number without re-running the same
   before/after `journalctl -k` check this recipe used - a clean HTTP
   response is not sufficient evidence that raising concurrency was safe.

## Prerequisites

- Two DGX Spark / ASUS Ascent GX10 units (or equivalent GB10-class
  hardware), networked over their direct QSFP fabric port, each reachable
  over a private/VPN network for the API.
- ~200 GB free per node for the checkpoint plus working space.
- Docker with GPU support.

## Setup

1. Clone the orchestration toolkit and read its own runbook first — it has
   an explicit `docs/AGENT_RUNBOOK.md` and general docs worth understanding
   before your first launch:

   ```bash
   git clone https://github.com/eugr/spark-vllm-docker.git
   cd spark-vllm-docker
   ```

2. Copy `.env.example` from this recipe into the toolkit directory as
   `.env`, and fill in your own fabric IPs / NIC names (never copy the
   example values — see **Finding your own values** below).

3. Download the checkpoint to **identical paths on both nodes** — vLLM
   shards it in-process at load time, it is not pre-split on disk:

   ```bash
   hf download Qwen/Qwen3.8-Flash-Next-FP8 --local-dir /path/to/models/Qwen3.8-Flash-Next-FP8
   ```

4. Copy `launch.sh` from this recipe into the toolkit directory, and run
   it from there:

   ```bash
   CHECKPOINT_DIR=/path/to/models/Qwen3.8-Flash-Next-FP8 ./launch.sh
   ```

5. Verify:

   ```bash
   curl http://<your-head-node>:8888/health
   curl http://<your-head-node>:8888/v1/models
   ```

## Finding your own values

`.env.example`'s `CLUSTER_NODES`/`ETH_IF`/`IB_IF` describe **this
recipe author's example cluster, not yours** — see the SuperDeepseek
recipe's "Finding your own values" section in this same repository for how
to determine your own fabric IPs, NIC names, and why copying them blindly
is the wrong move. The short version: `ip -br link` for interface names,
`ibv_devices`/`show_gids` for RDMA identity, never assumed from any recipe
including this one.

## Trust notes

Both the toolkit and the image were checked before use, not just adopted on
reputation. As of 2026-08-28:

- **`eugr/spark-vllm-docker`**: created 2025-11-25, 2,197 GitHub stars,
  author active on GitHub since 2012 with 287 followers and a companion
  benchmarking tool (`llama-benchy`). Substantially higher-trust than most
  single-purpose recipe repos.
- **`skfine24/qwen38-flash-next-vllm:20260827`**: materially thinner —
  single image tag, 141 Docker Hub pulls, 0 stars, created one day before
  this recipe was written, single author with no other public repositories
  found. Its layer history was checked directly (`docker history
  --no-trunc`) and confirms real, substantive build steps (an
  `instanttensor` package install and a genuine patch to
  `transformers/modeling_rope_utils.py`), not a fabricated or malicious
  image as far as this inspection could tell. **Decide your own risk
  tolerance** — this is exactly the kind of single-author, day-old image
  that deserves scrutiny, and this recipe's own trust bar for it is lower
  than for the toolkit.
- The image's **own documented recipe recommends `--distributed-executor-backend ray`,
  but Ray is not installed in the image** — a real inconsistency between the
  image and its own instructions, found by direct verification
  (`python3 -c "import ray"` failed). `launch.sh` omits `--ray` and uses the
  toolkit's default multiprocessing backend instead, which works.

## Alternative: building from the upstream PR

The originally-attempted path was building vLLM from source with PR #53899
applied via the toolkit's own `--apply-vllm-pr` mechanism, to get an image
built from auditable, in-review upstream code instead of a third-party
binary. The build itself succeeded cleanly. **Launching against this
checkpoint's FP8 PLE (n-gram embedding) tensor consistently failed** with:

```
ValueError: FP8 PLE checkpoint is missing its global scale
```

This reproduced identically regardless of context length, and regardless of
whether MTP speculative decoding was enabled at all — ruling out an
MTP-specific cause. It is a genuine, unconditional gap in that PR's
checkpoint-loading code for this specific checkpoint's PLE tensor layout,
not something fixable by any serving flag. If you want to try this path
anyway (e.g. because the PR has since been fixed or merged), one non-obvious
gotcha: the PR's true git merge-base must be computed with
`git merge-base <upstream-branch> <pr-branch>` — the GitHub API's `base.sha`
field reflects the *current* tip of the target branch at query time, not
the actual merge-base, and using it produces spurious patch conflicts.

## Concurrency tuning

`--max-num-seqs` was swept from 2 through 6 on the reference hardware, with
a fixed benchmark (concurrency levels 1/2/4/6/8 at a ~2000-token prompt,
256-token fixed-length generations, plus a small/medium/large/extralarge
context ladder) repeated at each setting:

| `--max-num-seqs` | Peak aggregate tok/s | At level | Notes |
|---:|---:|---|---|
| 2 | 56.67 | C4 | |
| 4 | 80.01 / **80.12** (reproduced) | C8 | still climbing at C8, no ceiling found |
| 5 | 80.12 | C8 | matches 4 almost exactly, not a midpoint toward 6 |
| 6 | **89.03** | C6 | but dipped to 84.77 at C8 — the only run to show a ceiling |

The **seqs=6 peak looks like a measurement-alignment artifact**, not a real
advantage: it lands exactly on the one test level where sent concurrency
(6) exactly saturates the cap with zero requests queued — the only
config/level combination in the whole sweep where that happens. Three
independent measurements (the original seqs=4 run, seqs=5, and a seqs=4
retest) all land within 0.14% of each other at ~80 tok/s / C8, a genuinely
reproducible plateau that seqs=6 does not fit.

Kernel-level memory pressure (real NVRM `Out of memory
[NV_ERR_NO_MEMORY]` retry messages, checked via `journalctl -k` before and
after each run, not just HTTP-level error counts) told a clearer story:
**seqs=4 generated roughly a third the retry churn of seqs=5 or seqs=6**
(34 combined events vs. 90 and 98) for the same measured throughput ceiling
as seqs=5. None of these produced an actual application error or container
restart at any setting tested — this is about retry overhead and margin,
not correctness.

**This recipe settles on `--max-num-seqs 4`**: same peak throughput as 5,
meaningfully less memory pressure than 5 or 6, and no unreproduced spike or
regression to chase. If your hardware has more memory headroom than the
reference pair did at test time (both nodes were independently observed
around 90%+ system memory utilization from other concurrent activity), your
own results may differ — this is a starting point, not a universal
constant. `MAX_NUM_SEQS=<n> ./launch.sh` overrides it.

## Verifying MTP and vision are actually working

Boot-log confirmation alone isn't proof a feature is doing anything —
verify with real traffic and real metrics:

**MTP**: issue a longer generation (a few hundred tokens is enough to
accumulate meaningful counters), then read `/metrics` directly:

```
vllm:spec_decode_num_drafts_total
vllm:spec_decode_num_draft_tokens_total
vllm:spec_decode_num_accepted_tokens_total
vllm:spec_decode_num_accepted_tokens_per_pos_total{position=N}
```

On the reference deployment, a 400-token generation produced 184 drafts,
552 draft tokens (184 × 3, matching `num_speculative_tokens=3` exactly),
and 243 accepted tokens — a genuine 44% acceptance rate, not just a
successfully-parsed config flag. One documented, non-fatal limitation: the
boot log notes the draft model "does not support external multimodal
embeddings," so MTP's draft model doesn't see image embeddings during
vision requests — plausibly reducing acceptance specifically for
vision-heavy generations (not separately measured).

**Vision**: send a real, properly-sized test image (not a degenerate 1–2
pixel PNG — that produced a wrong answer on the reference deployment purely
from being too small for the vision encoder's patch size, not from a real
defect) and check the answer content directly, not just the HTTP status.

## Security posture

- This recipe's `launch.sh` binds `--host 0.0.0.0` inside a container
  launched with host networking (the toolkit's default) — **that
  publishes the API on every interface on the box**, not just your private
  network. This matches the image's own published default recipe but is
  weaker than this repository's general recommendation (see the
  SuperDeepseek recipe): change `--host` to your own tailnet/private
  address before exposing this beyond a fully trusted LAN.
- No application-level authentication. Whatever network the API is
  reachable on is the entire access boundary.
- The `skfine24` image is single-author and one day old at time of writing
  — see **Trust notes**. This recipe found no evidence of anything
  malicious, but "no evidence found" is not the same bar as a reviewed,
  reproducible-from-source image.

## Files

```
launch.sh       genericized launch command (toolkit + image + vLLM args)
.env.example    template for the toolkit's own .env — fill in your own network values
```

## Status

Running in production on the reference two-node pair at `--max-num-seqs 4`.
The two open items worth knowing about: the `skfine24` image's thin
single-author trust profile (see **Trust notes**), and the `--host 0.0.0.0`
default (see **Security posture**) — neither is silently glossed over here,
both are yours to decide on for your own deployment.

## License

Scripts in this directory: **Apache-2.0**, per the repository root. The
toolkit, the image, and the model checkpoint are each licensed separately
by their own authors.
