#!/usr/bin/env bash
# ring-cluster.sh preflight|start|stop|status|gates
# Drives all four ranks over SSH from one node. Run it as the ordinary user that
# owns the SSH keys, never under sudo (root has no keys to the other machines).
#
#   preflight  head's share is exported and the checkpoint is there; every
#              worker has the share mounted (mounts it if fstab says nofail)
#   start      preflight, stop, then launch ranks 3, 2, 1 and finally 0
#   stop       remove the container everywhere, HEAD FIRST
#   status     container state + last log line per node
#   gates      the boot gate lines from every node's log
#
# Order matters. A worker that joins a still-listening old head hangs the boot,
# so the head is stopped first; and the head is started last so that the workers
# are already waiting at the rendezvous.
set -u
SELF_RANK="${SELF_RANK:-1}"            # the rank this script runs on ("local")
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
J="ssh -n -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -i $SSH_KEY"
# user@address for the other three ranks, over whichever network is always up
# (the fabric here; a VPN address works too and is one less dependency).
R0="${R0:?set R0=user@rank0-address}"
R2="${R2:?set R2=user@rank2-address}"
R3="${R3:?set R3=user@rank3-address}"
LAUNCH="${LAUNCH:-$HOME/ring-launch.sh}"
ENVF="${ENVF:-$HOME/boot.env}"
SHARE="${SHARE:-/mnt/head-models}"
MODEL_DIR="${MODEL_DIR:-DeepSeek-V4.1-Flash}"
NAME="${CONTAINER_NAME:-vllm_dsv41}"

r() { # host cmd   ("local" runs here)
  if [ "$1" = local ]; then bash -c "$2"; else $J "$1" "$2"; fi
}
stop_all() {
  for h in "$R0" local "$R2" "$R3"; do
    echo "== stop on $h"
    r "$h" "docker rm -f $NAME >/dev/null 2>&1; sleep 2; n=\$(nvidia-smi --query-compute-apps=pid --format=csv,noheader | grep -c .); echo \"\$(hostname): $NAME removed, gpu compute apps=\$n\""
  done
}
preflight() {
  r "$R0" "systemctl is-active --quiet nfs-server && [ -f /srv/models/$MODEL_DIR/config.json ] && echo \"\$(hostname): share active, checkpoint present\" || { echo \"\$(hostname): share inactive or checkpoint missing\"; exit 4; }" || exit 4
  for h in local "$R2" "$R3"; do
    r "$h" "mountpoint -q $SHARE || sudo -n mount $SHARE; [ -f $SHARE/$MODEL_DIR/config.json ] && echo \"\$(hostname): $SHARE mounted\" || { echo \"\$(hostname): $SHARE not mounted\"; exit 4; }" || exit 4
  done
}
start_all() {
  [ -f "$ENVF" ] || { echo "missing $ENVF"; exit 3; }
  B=$(base64 -w0 "$ENVF")
  preflight
  stop_all
  for pair in "$R3 3" "$R2 2" "local 1"; do
    # shellcheck disable=SC2086
    set -- $pair
    echo "== rank $2 on $1"
    r "$1" "echo $B | base64 -d > /tmp/boot.env; . /tmp/boot.env; bash $LAUNCH $2" || { echo "rank $2 launch FAILED"; exit 1; }
  done
  sleep 5
  echo "== rank 0 on $R0 (head)"
  r "$R0" "echo $B | base64 -d > /tmp/boot.env; . /tmp/boot.env; bash $LAUNCH 0" || { echo "rank 0 launch FAILED"; exit 1; }
  echo "all four launched $(date -u +%FT%TZ)"
}
status_all() {
  for h in "$R0" local "$R2" "$R3"; do
    r "$h" "echo \"\$(hostname): \$(docker ps --format '{{.Names}} {{.Status}}' | grep $NAME || echo NOT-RUNNING) | \$(docker logs --tail 1 $NAME 2>&1 | cut -c1-150)\""
  done
}
gates_all() {
  for h in "$R0" local "$R2" "$R3"; do
    r "$h" "echo \"### \$(hostname)\"; docker logs $NAME 2>&1 | grep -E 'Model loading took|Engram DISK mode|GPU KV cache size|Maximum concurrency|Channel 00/04|Tree transport setup disabled|NET/IB : Using|Duplicate NCCL|No device found|Traceback|ERROR|OOM|Killed|Application startup complete' | tail -14 | cut -c1-200"
  done
}
case "${1:-}" in
  stop) stop_all;; start) start_all;; status) status_all;; gates) gates_all;; preflight) preflight;;
  *) echo "usage: $0 preflight|start|stop|status|gates"; exit 2;;
esac
