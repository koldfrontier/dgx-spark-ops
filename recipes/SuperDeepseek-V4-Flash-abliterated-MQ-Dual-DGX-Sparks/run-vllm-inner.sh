#!/usr/bin/env bash
set -euo pipefail
#
# In-container launcher, adapted from the model repository's
# repro/scripts/run_superdeepseek_v4_vllm.sh.
#
# Deviation 1 from upstream: --host binds ${API_HOST} (a private/tailnet
# address) instead of upstream's hardcoded 0.0.0.0. With --network host,
# 0.0.0.0 would publish an uncensored, unauthenticated model on every
# interface on the box, including Wi-Fi. Do not revert this.
#
# Deviation 2: --performance-mode is read from $PERFORMANCE_MODE, defaulting
# to upstream's hardcoded "interactivity" so behavior is unchanged unless a
# caller opts in.
#
# WARNING - tested and rejected on the reference deployment this recipe is
# drawn from: PERFORMANCE_MODE=throughput was launched once (GRAPH_PROFILE=
# regular, i.e. this branch, backend eager, cudagraph_capture_sizes
# otherwise unset). vLLM logged "Performance mode set to 'throughput'" and
# resolved cudagraph_mode to FULL_AND_PIECEWISE with capture sizes
# [1,2,4,8,16,24,32] (vs. FULL-only, every size 1..32, under interactivity).
# The container ran for ~620s then exited with code 1 (not OOM, not
# SIGKILL - docker events showed a clean die, dmesg had no OOM-killer entry)
# and was destroyed by --rm before its logs could be captured, so the exact
# cause is UNCONFIRMED. Do not re-enable this without capturing
# `docker logs -f > file &` immediately after launch so a repeat failure is
# diagnosable. --speculative-config stays upstream's exact tested value
# regardless of this setting.
#
# Deviation 3: --max-num-seqs raised from upstream's 6 to 12
# (--max-num-batched-tokens left at upstream's 8192, unchanged). Unlike
# deviation 2, upstream's own script never tested a different --max-num-seqs
# value for this checkpoint, so this is open territory, not a rejection of
# vendor testing. On the reference 2-node GB10 pair this recipe is drawn
# from, raising the ceiling to 12 measured a genuine, replicated throughput
# gain with zero preemptions and KV cache usage comfortably inside budget
# (peaked ~9% of the reserved pool at concurrency 12) - see "Benchmarked
# results" below. Your hardware and traffic mix may differ; watch
# `vllm:num_requests_waiting` and `vllm:kv_cache_usage_perc` on /metrics
# before trusting this value blindly on a different setup.
#
# Deviation 4: --override-generation-config is appended, sourced from
# $OVERRIDE_GENERATION_CONFIG, only when that variable is non-empty.
# Upstream's --generation-config vllm is unchanged (still no model
# generation_config.json merge); the override applies on top of it
# regardless, since vLLM's get_diff_sampling_param() always calls
# self.override_generation_config last, independent of the base source.
#
# Deviation 5: --speculative-config's num_speculative_tokens and
# draft_sample_method are read from $SPEC_TOKENS/$SPEC_SAMPLE_METHOD,
# defaulting to upstream's tested 1/greedy so behavior is unchanged unless a
# caller opts in. See "Speculative decoding" in the README before setting
# SPEC_SAMPLE_METHOD=probabilistic with SPEC_TOKENS>1 for mixed-length
# concurrent traffic - MiaAI-Lab's own DSpark-recipe issue tracker documents
# an EngineCore crash for that combination on their recipe, and most
# real-world traffic (chat UI + agents + benchmarks together) is
# mixed-length by construction.
#
# Deviation 6: two of MiaAI-Lab's DSpark-recipe boot-time hotfixes can be
# optionally applied from a mounted patches directory ($PATCHES_DIR, unset
# by default = skip both, no directory needed):
#   ENABLE_SPIN_WAIT_HOTFIX=1  -> hotfix-gb10-spin-wait.sh
#     (IPC busy_loop_s 1->0.002, pure timing constant, no numerical/output
#     effect - reduces CPU contention under TP=2)
#   ENABLE_ISSUE22_HOTFIX=1    -> hotfix-nvfp4-ds-mla-issue22.sh
#     (routes nvfp4_ds_mla KV-cache reads to the fast FP8 kernel dispatch
#     path instead of the slow bf16 one - single-line dispatch condition,
#     same KV-cache dtype this deployment already uses)
# Get both from github.com/MiaAI-Lab/DeepSeek-v4-Flash-DSpark-2x-DGX-Spark
# (their `patches/` directory) and mount/symlink them at ./patches next to
# this script - see the README. Neither touches scheduling, batching, or
# spec-decode logic (what deviation 5 already changes); both are simple,
# single-target dispatch/timing patches.
#
# Everything else is upstream's measured serving profile, unchanged.

export PATH="/usr/local/cuda/bin:/usr/local/bin:${PATH:-}"
export CUDA_HOME=/usr/local/cuda
export CUDA_PATH="$CUDA_HOME"
export CUDAToolkit_ROOT="$CUDA_HOME"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

# The DeepSeek V4 custom encoding module ships with the checkpoint, not with
# vLLM. --tokenizer-mode deepseek_v4 cannot resolve without this copy.
cp /model/encoding/encoding_dsv4.py \
  /usr/local/lib/python3.12/dist-packages/vllm/tokenizers/deepseek_v4_encoding.py

python3 - <<'PY'
from pathlib import Path

path = Path("/usr/local/lib/python3.12/dist-packages/vllm/tokenizers/deepseek_v4.py")
source = path.read_text()
old = """elif reasoning_effort in ("max", "xhigh"):
                reasoning_effort = "max"
            else:
                reasoning_effort = "high"""
new = """elif reasoning_effort in ("max", "xhigh"):
                reasoning_effort = "max"
            elif reasoning_effort == "high":
                reasoning_effort = "high"
            else:
                reasoning_effort = "low"""
if new not in source:
    if source.count(old) != 1:
        raise RuntimeError("DeepSeek V4 reasoning-effort patch target changed")
    path.write_text(source.replace(old, new))
PY

# Deviation 6 opt-in patches (see header comment). Off unless explicitly
# enabled; $PATCHES_DIR must point at a mounted copy of MiaAI-Lab's
# patches/ directory when either is set to 1.
if [[ "${ENABLE_SPIN_WAIT_HOTFIX:-0}" == "1" ]]; then
  bash "${PATCHES_DIR:?PATCHES_DIR must be set when ENABLE_SPIN_WAIT_HOTFIX=1}/hotfix-gb10-spin-wait.sh"
fi
if [[ "${ENABLE_ISSUE22_HOTFIX:-0}" == "1" ]]; then
  bash "${PATCHES_DIR:?PATCHES_DIR must be set when ENABLE_ISSUE22_HOTFIX=1}/hotfix-nvfp4-ds-mla-issue22.sh"
fi

case "${DEFAULT_THINKING:-low}" in
  off) default_chat_template_kwargs='{"thinking":false}' ;;
  low) default_chat_template_kwargs='{"thinking":true,"reasoning_effort":"low"}' ;;
  high) default_chat_template_kwargs='{"thinking":true,"reasoning_effort":"high"}' ;;
  max) default_chat_template_kwargs='{"thinking":true,"reasoning_effort":"max"}' ;;
  *) echo "DEFAULT_THINKING must be off, low, high, or max" >&2; exit 2 ;;
esac

speculative_config=$(printf \
  '{"method":"dspark","num_speculative_tokens":%s,"draft_sample_method":"%s"}' \
  "${SPEC_TOKENS:-1}" "${SPEC_SAMPLE_METHOD:-greedy}")

args=(
  /model
  --served-model-name "$SERVED_NAME"
  --host "${API_HOST:-127.0.0.1}"
  --port 8888
  --trust-remote-code
  --tensor-parallel-size 2
  --pipeline-parallel-size 1
  --kv-cache-dtype nvfp4_ds_mla
  --block-size 256
  --max-model-len 1048576
  --max-num-seqs 12
  --max-num-batched-tokens 8192
  --gpu-memory-utilization 0.80
  --enable-prefix-caching
  --enable-prompt-tokens-details
  --cudagraph-metrics
  --async-scheduling
  --enable-chunked-prefill
  --speculative-config "$speculative_config"
  --tokenizer-mode deepseek_v4
  --distributed-executor-backend mp
  --moe-backend flashinfer_b12x
  --tool-call-parser deepseek_v4
  --enable-auto-tool-choice
  --reasoning-parser deepseek_v4
  --reasoning-config '{"reasoning_parser":"deepseek_v4","reasoning_start_str":"<think>","reasoning_end_str":"</think>"}'
  --default-chat-template-kwargs "$default_chat_template_kwargs"
  --generation-config vllm
  --enable-flashinfer-autotune
  --nnodes 2
  --node-rank "$NODE_RANK"
  --master-addr "$MASTER_ADDR"
  --master-port "$MASTER_PORT"
)

if [[ "$GRAPH_PROFILE" == regular ]]; then
  args+=(
    --max-cudagraph-capture-size 32
    --performance-mode "${PERFORMANCE_MODE:-interactivity}"
    --compilation-config '{"backend":"eager"}'
  )
else
  args+=(
    --max-cudagraph-capture-size 32
    --compilation-config '{"cudagraph_mode":"PIECEWISE"}'
  )
fi
if [[ "$GRAPH_PROFILE" == eager ]]; then args+=(--enforce-eager); fi
if [[ "$HEADLESS" == 1 ]]; then args+=(--headless); fi
if [[ -n "${OVERRIDE_GENERATION_CONFIG:-}" ]]; then
  args+=(--override-generation-config "$OVERRIDE_GENERATION_CONFIG")
fi
exec /usr/local/bin/vllm serve "${args[@]}"
