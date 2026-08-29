#!/usr/bin/env bash
set -euo pipefail
#
# Launches Qwen/Qwen3.8-Flash-Next-FP8 as one vLLM TP=2 endpoint across a
# 2-node DGX Spark / ASUS Ascent GX10 pair, using eugr/spark-vllm-docker's
# cluster orchestration toolkit (github.com/eugr/spark-vllm-docker) and a
# third-party pre-built image. Run from the toolkit's own directory (see
# README "Setup").
#
# Trust note on the image (skfine24/qwen38-flash-next-vllm): thin - single
# tag, single author, no other public repos found, created the day before
# this recipe was written. Verified independently before use (see README
# "Trust notes"), not just taken on faith. If that bar is too low for you,
# build your own image instead - see README "Alternative: build your own
# image" for the path this recipe originally tried and why it was
# abandoned.
#
# Why not --ray: this image's own bundled documentation recommends
# --distributed-executor-backend ray, but Ray is not actually installed in
# the image (verified: `python3 -c "import ray"` -> ModuleNotFoundError).
# Omitting --ray falls back to the toolkit's default multiprocessing
# backend, which works. Re-check this if the image is ever updated - it may
# get fixed upstream.

image="skfine24/qwen38-flash-next-vllm:20260827"
checkpoint_dir="${CHECKPOINT_DIR:?set CHECKPOINT_DIR to your local Qwen3.8-Flash-Next-FP8 checkpoint path, present on both nodes}"
max_num_seqs="${MAX_NUM_SEQS:-4}"

./launch-cluster.sh \
  -t "$image" \
  -v "${checkpoint_dir}:/models/Qwen3.8-Flash-Next-FP8" \
  -e VLLM_ALLOW_LONG_MAX_MODEL_LEN=1 \
  -e FLASHINFER_DISABLE_VERSION_CHECK=1 \
  exec vllm serve /models/Qwen3.8-Flash-Next-FP8 \
    --served-model-name qwen \
    --host 0.0.0.0 \
    --port 8888 \
    --trust-remote-code \
    --tensor-parallel-size 2 \
    --gpu-memory-utilization 0.85 \
    --max-model-len 262144 \
    --max-num-seqs "$max_num_seqs" \
    --max-num-batched-tokens 8192 \
    --load-format instanttensor \
    --enable-prefix-caching \
    --enable-chunked-prefill \
    --enforce-eager \
    --moe-backend triton \
    --attention-backend flashinfer \
    --no-enable-flashinfer-autotune \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    --reasoning-parser qwen3 \
    --default-chat-template-kwargs '{"enable_thinking":true,"preserve_thinking":true,"reasoning_effort":"xhigh"}' \
    --override-generation-config '{"temperature":1.0,"top_p":0.95,"top_k":20,"min_p":0.0,"presence_penalty":0.0}' \
    --speculative-config '{"method":"mtp","num_speculative_tokens":3}'
