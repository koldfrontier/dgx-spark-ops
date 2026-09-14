#!/usr/bin/env bash
# ring-launch.sh <rank>  - DeepSeek-V4.1-Flash TP4 on a four-node switchless ring
# (rank 0 - 1 - 2 - 3 - 0). Run on each node with its own rank, workers first,
# head last. Every knob is an env var; the per-machine values live in ring.conf.
#
# Adapted from tonyd2wild/DeepSeek-V4.1-Flash-vLLM-DGX-Spark (MIT),
# launch/dsv41-tp4.sh @ 592540c, whose knob names this keeps. Differences, all
# deliberate and all explained in ../README.md:
#   1. Rank map is a config file keyed by hostname, and the script refuses to
#      start a rank on the wrong machine.
#   2. Transport is FujitsuPolycom/sparkring's patched NCCL 2.30.7 (Apache-2.0),
#      LD_PRELOAD + VLLM_NCCL_SO_PATH, with the four-rank switchless cycle env:
#      two HCAs per rank, subnet-aware routing, Ring only, Tree/PAT skipped.
#      Upstream's single-HCA switched-fabric block is replaced, not appended to.
#   3. Per-rank NCCL_IB_GID_INDEX with a preflight that refuses a wrong one.
#   4. Control plane selectable: CTRL=private (VPN/tailnet addresses, works
#      before the fabric routes exist) or CTRL=fabric.
#   5. API binds to a private address, never 0.0.0.0.
#   6. Head reads the checkpoint locally, workers over the share.
#   7. --load-format safetensors, and a PYTORCH_CUDA_ALLOC_CONF knob
#      (upstream hardcodes expandable_segments:True; see the README's A/B).
set -euo pipefail
NODE_RANK="${1:?usage: ring-launch.sh <0|1|2|3>}"
CONF="${RING_CONF:-$(cd "$(dirname "$0")" && pwd)/ring.conf}"
[ -f "$CONF" ] || { echo "missing $CONF (copy ring.conf.example and fill it in)" >&2; exit 2; }
# shellcheck disable=SC1090
. "$CONF"

IMAGE="${IMAGE:?set IMAGE to the overlay image you built}"
EXP_NAME="${EXP_NAME:-boot1}"
GMU="${GMU:-0.80}"
MAXLEN="${MAXLEN:-131072}"
SEQS="${SEQS:-8}"
MAX_BATCHED="${MAX_BATCHED:-8192}"
EAGER="${EAGER:-1}"
CUDAGRAPH_MODE="${CUDAGRAPH_MODE:-FULL_AND_PIECEWISE}"
CG_SIZES="${CG_SIZES:-}"
SPEC="${SPEC:-none}"
ENGRAM_DISK="${ENGRAM_DISK:-1}"
TEXT_ONLY="${TEXT_ONLY:-1}"
THINKING="${THINKING:-false}"
PARSERS="${PARSERS:-0}"
RUST_FE="${RUST_FE:-0}"
VLLM_EXTRA="${VLLM_EXTRA:-}"
NCCL_EXTRA="${NCCL_EXTRA:-}"
CTRL="${CTRL:-private}"
ALLOC_CONF="${ALLOC_CONF:-expandable_segments:True}"
NCCL_DEBUG_LEVEL="${NCCL_DEBUG:-WARN}"
SERVED_NAME="${SERVED_NAME:-deepseek-v4.1-flash}"

NAME="${CONTAINER_NAME:-vllm_dsv41}"
SITE="/usr/local/lib/python3.12/dist-packages/vllm"
MPORT="${MPORT:-29541}"; PORT="${PORT:-8000}"

# ---- rank map from ring.conf ----
HN=$(hostname)
eval "WANT=\${RANK${NODE_RANK}_HOST:-}"
eval "HCA=\${RANK${NODE_RANK}_HCA:-}"
eval "GID=\${RANK${NODE_RANK}_GID:-}"
eval "FAB_IP=\${RANK${NODE_RANK}_FAB_IP:-}"
eval "FAB_IF=\${RANK${NODE_RANK}_FAB_IF:-}"
eval "PRIV_IP=\${RANK${NODE_RANK}_PRIV_IP:-}"
[ -n "$WANT" ] && [ -n "$HCA" ] && [ -n "$GID" ] || { echo "ring.conf has no complete entry for rank $NODE_RANK" >&2; exit 2; }
[ "$HN" = "$WANT" ] || { echo "REFUSING: rank $NODE_RANK belongs to $WANT, this is $HN" >&2; exit 2; }
case "$NODE_RANK" in
  0) HEADLESS=""; MODEL_HOST="$MODEL_HOST_RANK0/$MODEL_DIR" ;;
  1|2|3) HEADLESS="--headless"; MODEL_HOST="$MODEL_HOST_WORKERS/$MODEL_DIR" ;;
  *) echo "rank must be 0-3" >&2; exit 2 ;;
esac
case "$CTRL" in
  private) HOST_IP=$PRIV_IP; HEAD_IP=$RANK0_PRIV_IP; CTRL_IF=$PRIV_IF ;;
  fabric)  HOST_IP=$FAB_IP;  HEAD_IP=$RANK0_FAB_IP;  CTRL_IF=$FAB_IF ;;
  *) echo "CTRL must be private|fabric" >&2; exit 2 ;;
esac
API_HOST=$RANK0_API_IP

# ---- preflight: checkpoint, patched NCCL, link state, GID identity ----
test -f "$MODEL_HOST/config.json" || { echo "MODEL MISSING at $MODEL_HOST" >&2; exit 3; }
test -f "$NCCL_SO_HOST" || { echo "PATCHED NCCL MISSING at $NCCL_SO_HOST" >&2; exit 3; }
if [ -n "${NCCL_SO_SHA256:-}" ]; then
  echo "$NCCL_SO_SHA256  $NCCL_SO_HOST" | sha256sum --check --quiet || { echo "PATCHED NCCL sha256 MISMATCH" >&2; exit 3; }
else
  echo "WARNING: NCCL_SO_SHA256 empty in ring.conf - the transport binary is unverified" >&2
fi
for d in ${HCA//,/ }; do
  st=$(cat /sys/class/infiniband/"$d"/ports/1/state 2>/dev/null || echo none)
  case "$st" in *ACTIVE*) ;; *) echo "HCA $d not ACTIVE ($st)" >&2; exit 3;; esac
  t=$(cat /sys/class/infiniband/"$d"/ports/1/gid_attrs/types/"$GID" 2>/dev/null || echo none)
  g=$(cat /sys/class/infiniband/"$d"/ports/1/gids/"$GID" 2>/dev/null || echo none)
  case "$g:$t" in 0000:0000:0000:0000:0000:ffff:*"RoCE v2") ;; *) echo "GID $GID on $d is not an IPv4 RoCEv2 entry ($g $t) - re-derive" >&2; exit 3;; esac
done

# ---- patch set: whole files bind-mounted over the image's vllm ----
PATCH_DIR="${PATCH_DIR:-$PATCH_ROOT/${PATCH_NAME:?set PATCH_NAME to the patch directory name}}"
PATCH_MOUNTS=""
if [ -f "$PATCH_DIR/mounts.txt" ]; then
  while read -r f rel; do
    [ -z "$f" ] && continue
    if [ "$ENGRAM_DISK" != "1" ] && { [ "$f" = "engram.py" ] || [ "$f" = "weight_utils.py" ] || [ "$f" = "model_state.py" ]; }; then continue; fi
    test -f "$PATCH_DIR/$f" || { echo "PATCH FILE MISSING: $PATCH_DIR/$f" >&2; exit 3; }
    PATCH_MOUNTS="$PATCH_MOUNTS -v $PATCH_DIR/$f:$SITE/$rel:ro"
  done < "$PATCH_DIR/mounts.txt"
else
  echo "no mounts.txt in $PATCH_DIR" >&2; exit 3
fi

if [ "$ENGRAM_DISK" = "1" ]; then
  ENGRAM_ENV="-e DSV41_ENGRAM_DISK=1 -e DSV41_ENGRAM_DISK_THREADS=${ENGRAM_THREADS:-32} -e DSV41_ENGRAM_DISK_CHUNK=${ENGRAM_CHUNK:-16}"
else
  ENGRAM_ENV="-e DSV41_ENGRAM_DISK=0"
fi
ENGRAM_LOCAL_HOST="${ENGRAM_LOCAL_HOST:-$ENGRAM_LOCAL_ROOT/$MODEL_DIR}"
ENGRAM_LOCAL_MOUNT=""
if [ "$ENGRAM_DISK" = "1" ] && [ "${ENGRAM_LOCAL:-0}" = "1" ] && [ -f "$ENGRAM_LOCAL_HOST/engram-local.json" ]; then
  ENGRAM_LOCAL_MOUNT="-v $ENGRAM_LOCAL_HOST:/engram-local:ro"
  ENGRAM_ENV="$ENGRAM_ENV -e DSV41_ENGRAM_DIR=/engram-local"
fi

mkdir -p "$CACHE_HOST_PATH"
docker rm -f "$NAME" 2>/dev/null || true
sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null
AVAIL_GB=$(( $(grep MemAvailable /proc/meminfo | awk '{print $2}') / 1048576 ))
[ "$AVAIL_GB" -ge "${MIN_AVAIL_GB:-100}" ] || { echo "MemAvailable ${AVAIL_GB} GiB < ${MIN_AVAIL_GB:-100} GiB, refusing to boot" >&2; exit 4; }

# ---- CUDA graphs: capture sizes must MATCH the batch shapes you will run ----
# With speculation on, a step's batch is (k or k+1) tokens per sequence, so the
# capture list is the multiples of k and k+1 up to SEQS sequences. A list that
# never matches makes the engine pad into an uncaptured shape, which on this
# stack yields silent NaN, not an error. Derived, never hand-written.
GRAPH_ENV=""
if [ "$EAGER" = "1" ]; then
  GRAPH_ARGS=(--enforce-eager)
else
  if [ "$ENGRAM_DISK" = "1" ] && ! grep -q '^model_state.py ' "$PATCH_DIR/mounts.txt"; then
    echo "EAGER=0 + ENGRAM_DISK=1 needs the Engram prestage patch (model_state.py in mounts.txt)" >&2; exit 3
  fi
  if [ -z "$CG_SIZES" ]; then
    if [ "$SPEC" = "dspark" ]; then
      K="${SPEC_K:-5}"
      CG_SIZES=$( { seq "$K" "$K" $((K * SEQS)); seq $((K + 1)) $((K + 1)) $(((K + 1) * SEQS)); } | sort -n -u | paste -sd, - )
    else
      CG_SIZES=$(seq 1 "$SEQS" | paste -sd, -)
    fi
  fi
  GRAPH_ARGS=(--compilation-config "{\"cudagraph_mode\":\"$CUDAGRAPH_MODE\",\"cudagraph_capture_sizes\":[$CG_SIZES]}")
  GRAPH_ENV="-e VLLM_USE_BREAKABLE_CUDAGRAPH=1"
fi
if [ "$EAGER" = "1" ]; then SPEC_ADAPT=false; else SPEC_ADAPT="${SPEC_ADAPT:-false}"; fi
if [ "$SPEC" = "dspark" ]; then
  SPEC_ARGS="--speculative-config {\"method\":\"dspark\",\"num_speculative_tokens\":${SPEC_K:-5},\"draft_sample_method\":\"probabilistic\",\"rejection_sample_method\":\"block\",\"enable_adaptive_verification\":${SPEC_ADAPT}}"
else SPEC_ARGS=""; fi
if [ "$TEXT_ONLY" = "1" ]; then TEXT_ARGS="--language-model-only"; else TEXT_ARGS=""; fi
if [ "$PARSERS" = "1" ]; then PARSER_ARGS="--tool-call-parser deepseek_v41 --enable-auto-tool-choice --reasoning-parser deepseek_v41"; else PARSER_ARGS=""; fi

# shellcheck disable=SC2086
docker run --gpus all -d --name "$NAME" --restart no \
  --network host --ipc host --shm-size 32g --memory 112g --memory-swap 112g \
  --ulimit memlock=-1:-1 --cap-add IPC_LOCK --device /dev/infiniband:/dev/infiniband \
  --oom-score-adj 500 \
  -v "$MODEL_HOST:/models/$MODEL_DIR:ro" \
  -v "$CACHE_HOST_PATH:/cache" \
  -v "$NCCL_SO_HOST:/opt/sparkring/nccl/libnccl.so.2:ro" \
  $PATCH_MOUNTS $ENGRAM_LOCAL_MOUNT \
  -e VLLM_HOST_IP=$HOST_IP -e HF_HOME=/cache/huggingface -e HF_HUB_OFFLINE=1 -e TRANSFORMERS_OFFLINE=1 \
  -e VLLM_CACHE_ROOT="/cache/vllm-$EXP_NAME" \
  -e VLLM_ENGINE_READY_TIMEOUT_S=3600 -e PYTORCH_CUDA_ALLOC_CONF="$ALLOC_CONF" \
  -e VLLM_USE_RUST_FRONTEND=$RUST_FE -e VLLM_HAS_FLASHINFER_CUBIN=1 \
  $ENGRAM_ENV $GRAPH_ENV \
  -e TORCH_CUDA_ARCH_LIST=12.1a -e FLASHINFER_CUDA_ARCH_LIST=12.1a -e FLASHINFER_DISABLE_VERSION_CHECK=1 \
  -e LD_PRELOAD=/opt/sparkring/nccl/libnccl.so.2 -e VLLM_NCCL_SO_PATH=/opt/sparkring/nccl/libnccl.so.2 \
  -e NCCL_NET=IB -e NCCL_IB_DISABLE=0 -e NCCL_IB_HCA=$HCA -e NCCL_IB_GID_INDEX=$GID \
  -e NCCL_IB_ROCE_VERSION_NUM=2 -e NCCL_IB_ADDR_FAMILY=AF_INET \
  -e NCCL_IB_SUBNET_AWARE_ROUTING=1 -e NCCL_IB_SUBNET_PREFIX_LEN=24 -e NCCL_IB_MERGE_NICS=0 -e NCCL_CROSS_NIC=1 \
  -e NCCL_ALGO=Ring -e NCCL_PROTO=LL,LL128,Simple -e NCCL_MIN_NCHANNELS=4 -e NCCL_MAX_NCHANNELS=4 \
  -e NCCL_SWITCHLESS_RING_ONLY=1 -e NCCL_SKIP_TREE_CONNECT=1 -e NCCL_P2P_LEVEL=SYS \
  -e NCCL_SOCKET_IFNAME=$CTRL_IF -e GLOO_SOCKET_IFNAME=$CTRL_IF -e TP_SOCKET_IFNAME=$CTRL_IF -e MN_IF_NAME=$CTRL_IF \
  -e NCCL_NVLS_ENABLE=0 -e NCCL_CUMEM_ENABLE=0 \
  -e NCCL_IGNORE_CPU_AFFINITY=1 -e NCCL_DEBUG=$NCCL_DEBUG_LEVEL -e TORCH_NCCL_ASYNC_ERROR_HANDLING=1 \
  $NCCL_EXTRA \
  "$IMAGE" \
    "/models/$MODEL_DIR" \
    --served-model-name "$SERVED_NAME" --host "$API_HOST" --port "$PORT" \
    --load-format safetensors \
    --tensor-parallel-size 4 --gpu-memory-utilization "$GMU" --max-model-len "$MAXLEN" \
    --max-num-seqs "$SEQS" --max-num-batched-tokens "$MAX_BATCHED" \
    --engram-config '{"cpu_offload": false}' \
    --default-chat-template-kwargs "{\"thinking\": $THINKING}" \
    $TEXT_ARGS $PARSER_ARGS $SPEC_ARGS "${GRAPH_ARGS[@]}" \
    --distributed-executor-backend mp --nnodes 4 --node-rank "$NODE_RANK" \
    --master-addr "$HEAD_IP" --master-port "$MPORT" $HEADLESS $VLLM_EXTRA

echo "launched $NAME host=$HN rank=$NODE_RANK ctrl=$CTRL($HOST_IP) hca=$HCA gid=$GID exp=$EXP_NAME image=$IMAGE patches=$PATCH_DIR gmu=$GMU maxlen=$MAXLEN seqs=$SEQS eager=$EAGER cg=${CUDAGRAPH_MODE}[${CG_SIZES}] spec=$SPEC adapt=$SPEC_ADAPT engram_disk=$ENGRAM_DISK engram_local=${ENGRAM_LOCAL_MOUNT:+yes} text_only=$TEXT_ONLY alloc=$ALLOC_CONF avail=${AVAIL_GB}GiB"
sleep 3
docker ps --format '{{.Names}} {{.Status}}' | grep "$NAME" || { echo "$NAME exited" >&2; docker logs --tail 40 "$NAME" >&2; exit 1; }
