#!/usr/bin/env bash
# rdma-snap.sh <label>  - port_xmit_data / port_rcv_data for every RoCE HCA on
# this node (IB counters are in units of 4 bytes). Snapshot before and after a
# real generation on every node: if the RDMA counters do not move, NCCL is not
# using RDMA no matter what the config says.
L=${1:-snap}
for d in /sys/class/infiniband/roce*; do
  [ -e "$d" ] || continue
  echo "$L $(hostname) $(basename "$d") xmit=$(cat "$d"/ports/1/counters/port_xmit_data) rcv=$(cat "$d"/ports/1/counters/port_rcv_data) $(date +%s)"
done
