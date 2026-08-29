#!/usr/bin/env bash
set -euo pipefail
#
# Launcher for Jiunsong/SuperDeepseek-V4-Flash-abliterated-MQ-2xDGX on a
# 2-node DGX Spark / ASUS Ascent GX10 pair, adapted from the checkpoint's own
# repro/scripts/serve_superdeepseek_v4_dual.sh. Deviations from upstream, and
# why:
#
#  1. Hostname seal retargeted to this pair's own hostnames (edit
#     EXPECTED_HOSTNAME_A/B below). Kept, not removed - it is a real guard
#     against launching the wrong rank on the wrong box. Some GB10 units ship
#     with a duplicate machine-id / SSH host key out of the box, so hostname
#     is one of the few reliable identity signals available at boot.
#  2. Fabric/NIC/GID genericized below - upstream's values describe the
#     author's cluster, not yours. Fill in your own fabric IPs, NIC names,
#     and GID index; NEVER copy GID_INDEX from this or any other recipe -
#     confirm yours with `show_gids` on each node first (see "Finding your
#     own values" below).
#  3. The pinned-parent base_dir mount and its verification-report gate are
#     removed. Upstream refuses to start without a local
#     deepseek-ai/DeepSeek-V4-Flash-0731 checkout and a verification report
#     generated on the author's own hosts. Most readers will not have
#     either. This drops an upstream provenance check - it is NOT a claim
#     that a checkpoint obtained any other way is independently verified.
#     Serving itself only needs /model, whose config.json is self-contained.
#  4. The API binds a private/tailnet address, never 0.0.0.0. This container
#     runs with --network host; binding 0.0.0.0 would publish an uncensored,
#     unauthenticated model on every interface on the box, including Wi-Fi.
#     Bind a VPN/tailnet address (Tailscale, WireGuard, etc.) or a private
#     LAN address behind your own firewall - never a public route.
#  5. PERFORMANCE_MODE env var, default "interactivity" (upstream's hardcoded
#     value) so behavior is unchanged unless you opt in. WARNING: PERFORMANCE_MODE=throughput
#     was tested once on the reference deployment this recipe is drawn from and crashed the
#     engine after ~10 minutes of otherwise-normal serving (clean exit code 1,
#     not OOM, cause unconfirmed - logs were lost to --rm). If you try it,
#     start `docker logs -f <container> > file 2>&1 &` immediately after
#     launch so a repeat failure is diagnosable.
#  6. OVERRIDE_GENERATION_CONFIG env var, empty by default - passes through
#     to --override-generation-config only when set.
#  7. SPEC_TOKENS/SPEC_SAMPLE_METHOD env vars, default 1/greedy (upstream's
#     exact tested speculative-decoding value). See "Speculative decoding"
#     below before changing these.
#  8. ENABLE_SPIN_WAIT_HOTFIX/ENABLE_ISSUE22_HOTFIX env vars, both default 0
#     (off). Optional community hotfixes from MiaAI-Lab's DSpark recipe - see
#     "Optional hotfixes" below.
#
# Everything else - the runtime env block, cache mounts, and the in-container
# vLLM argument set - is upstream's own measured serving profile, kept
# deliberately unchanged.

if [[ $# -ne 1 ]]; then
  echo "usage: $0 NODE_RANK   (0 = head/API node, 1 = worker node)" >&2
  exit 2
fi
node_rank=$1
if [[ "$node_rank" != "0" && "$node_rank" != "1" ]]; then
  echo "NODE_RANK must be 0 or 1" >&2
  exit 2
fi

# --- Fill in for your own cluster --------------------------------------
expected_hostname_a="node-a"          # hostname -s on your head/API node
expected_hostname_b="node-b"          # hostname -s on your worker node
master_addr="10.10.10.1"              # head node's fabric IP
worker_fabric_addr="10.10.10.2"       # worker node's fabric IP
netdev="enp1s0f1np1"                  # fabric NIC name - verify with `ip -br link` on YOUR hardware
rdma_device="rocep1s0f1"              # RDMA device name - verify with `ibv_devices` on YOUR hardware
gid_index=3                           # NEVER copy this - run `show_gids` on your own node and pick the RoCEv2/IPv4 entry
api_bind_addr="100.64.0.1"            # head node's tailnet/VPN address - never 0.0.0.0 or a public IP
model_dir="/srv/models/staging/superdeepseek-v4-abliterated-mq"
work_dir="/srv/superdeepseek-work"
# -------------------------------------------------------------------------

expected_hostname=$expected_hostname_a
if [[ "$node_rank" == "1" ]]; then expected_hostname=$expected_hostname_b; fi
actual_hostname=$(hostname -s)
if [[ "$actual_hostname" != "$expected_hostname" ]]; then
  echo "node rank $node_rank is sealed to $expected_hostname, got $actual_hostname" >&2
  echo "edit expected_hostname_a/b in this script for your own two hostnames" >&2
  exit 2
fi

image=ghcr.io/anemll/dspark-vllm-gx10:0.1.1
container=superdeepseek-v4-rank${node_rank}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

master_port=25001
graph_profile=regular
breakable=0
served_name=SuperDeepseek-V4-Flash-abliterated-MQ-2xDGX

if [[ "$node_rank" == "0" ]]; then
  host_ip=$master_addr
  api_host=$api_bind_addr
  headless=0
else
  host_ip=$worker_fabric_addr
  api_host=$worker_fabric_addr
  headless=1
fi

if [[ ! -f "$model_dir/model.safetensors.index.json" ]]; then
  echo "model index not found under $model_dir" >&2
  exit 2
fi
if [[ ! -f "$model_dir/encoding/encoding_dsv4.py" ]]; then
  echo "custom encoding module not found under $model_dir/encoding" >&2
  exit 2
fi

mkdir -p "$work_dir/cache/vllm-serve" "$work_dir/cache/flashinfer-serve" "$work_dir/cache/tmp-serve"
docker rm -f "$container" >/dev/null 2>&1 || true

exec docker run --rm -d \
  --name "$container" \
  --privileged \
  --gpus all \
  --network host \
  --ipc host \
  --shm-size 64g \
  --ulimit memlock=-1:-1 \
  --ulimit stack=67108864:67108864 \
  -e HF_HUB_OFFLINE=1 \
  -e TRANSFORMERS_OFFLINE=1 \
  -e HF_HUB_DISABLE_XET=1 \
  -e NODE_RANK="$node_rank" \
  -e MASTER_ADDR="$master_addr" \
  -e MASTER_PORT="$master_port" \
  -e HEADLESS="$headless" \
  -e GRAPH_PROFILE="$graph_profile" \
  -e SERVED_NAME="$served_name" \
  -e API_HOST="$api_host" \
  -e DEFAULT_THINKING="${DEFAULT_THINKING:-low}" \
  -e PERFORMANCE_MODE="${PERFORMANCE_MODE:-interactivity}" \
  -e OVERRIDE_GENERATION_CONFIG="${OVERRIDE_GENERATION_CONFIG:-}" \
  -e SPEC_TOKENS="${SPEC_TOKENS:-1}" \
  -e SPEC_SAMPLE_METHOD="${SPEC_SAMPLE_METHOD:-greedy}" \
  -e ENABLE_SPIN_WAIT_HOTFIX="${ENABLE_SPIN_WAIT_HOTFIX:-0}" \
  -e ENABLE_ISSUE22_HOTFIX="${ENABLE_ISSUE22_HOTFIX:-0}" \
  -e PATCHES_DIR=/opt/dspark-patches \
  -e VLLM_HOST_IP="$host_ip" \
  -e NCCL_NET=IB \
  -e NCCL_IB_DISABLE=0 \
  -e NCCL_IB_HCA="$rdma_device" \
  -e NCCL_IB_GID_INDEX="$gid_index" \
  -e NCCL_SOCKET_IFNAME="$netdev" \
  -e GLOO_SOCKET_IFNAME="$netdev" \
  -e TP_SOCKET_IFNAME="$netdev" \
  -e NCCL_IB_ADDR_FAMILY=AF_INET \
  -e NCCL_IB_ROCE_VERSION_NUM=2 \
  -e NCCL_CROSS_NIC=1 \
  -e NCCL_CUMEM_ENABLE=0 \
  -e NCCL_IGNORE_CPU_AFFINITY=1 \
  -e NCCL_NVLS_ENABLE=0 \
  -e NCCL_DEBUG=WARN \
  -e VLLM_ALLOW_LONG_MAX_MODEL_LEN=1 \
  -e VLLM_SPARSE_INDEXER_MAX_LOGITS_MB=256 \
  -e VLLM_MEMORY_PROFILER_ESTIMATE_CUDAGRAPHS=0 \
  -e VLLM_USE_BREAKABLE_CUDAGRAPH="$breakable" \
  -e VLLM_USE_B12X_MOE=1 \
  -e VLLM_USE_FLASHINFER_SAMPLER=1 \
  -e VLLM_B12X_W4A16_FORCE_BLOCKS_PER_SM=0 \
  -e VLLM_B12X_W4A16_FORCE_BLOCKS_MAX_M=16 \
  -e TORCH_CUDA_ARCH_LIST=12.1a \
  -e FLASHINFER_CUDA_ARCH_LIST=12.1a \
  -e CUTE_DSL_ARCH=sm_121a \
  -e FLASHINFER_DISABLE_VERSION_CHECK=1 \
  -e FLASHINFER_WORKSPACE_BASE=/cache/flashinfer \
  -e TILELANG_CLEANUP_TEMP_FILES=1 \
  -e DG_JIT_USE_NVRTC=0 \
  -e DG_JIT_NVCC_COMPILER=/usr/local/cuda/bin/nvcc \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  -v "$model_dir:/model:ro" \
  -v "$work_dir/cache/vllm-serve:/root/.cache/vllm" \
  -v "$work_dir/cache/flashinfer-serve:/cache/flashinfer" \
  -v "$work_dir/cache/tmp-serve:/tmp" \
  -v "$script_dir:/bundle-scripts:ro" \
  -v "$script_dir/patches:/opt/dspark-patches:ro" \
  --entrypoint /bin/bash \
  "$image" \
  /bundle-scripts/run-vllm-inner.sh
