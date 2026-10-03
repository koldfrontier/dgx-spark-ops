#!/usr/bin/env bash
# Fabric health on ONE DGX Spark / ASUS Ascent GX10. Run it on every node after any re-cable or reboot,
# before you benchmark or trust a tensor-parallel boot.
#
#   1. The PCIe root ports' LTR bit (DevCtl2 bit 10). Reads 0x0420 on a healthy GB10; 0x0020 on a node
#      whose ConnectX-7 was re-added by cx7-pcie-hotplug (both QSFP cages were empty at some point).
#      That node runs every RDMA read of host memory at ~1/8 speed until it is rebooted.
#   2. Each RoCE device: state, rate, MTU, IPv4 (and a warning when a netdev holds more than one IPv4 -
#      NCCL's bootstrap socket takes the first, which may be a 169.254 link-local).
#   3. A 3 s loopback RDMA write per addressed device (never leaves the node): ~105-110 Gb/s healthy,
#      ~14 Gb/s in the hotplug state. Normal small-message latency does not rule the problem out.
#
# Needs perftest (ib_write_bw; DGX OS ships it) and passwordless sudo for the setpci *read*.
# Exit status 1 if anything looks wrong. WARN_GBPS (default 50) sets the loopback threshold.
set -u
WARN_GBPS=${WARN_GBPS:-50}
bad=0
echo "== $(hostname)"
for rp in 0000:00:00.0 0002:00:00.0; do
  if ! v=$(sudo -n setpci -s "$rp" CAP_EXP+28.w 2>/dev/null); then echo "root port $rp: DevCtl2 unreadable (sudo -n?)"; continue; fi
  if (( 0x$v & 0x0400 )); then echo "root port $rp: DevCtl2=$v LTR on  OK"
  else echo "root port $rp: DevCtl2=$v LTR OFF  <- CX7 re-added by hotplug? reboot this node"; bad=1; fi
done
gid_of() {   # <dev> <ipv4> -> the RoCE v2 GID index whose GID is ::ffff:<ipv4>
  local dev=$1 hex i g t
  hex=$(printf '%02x%02x:%02x%02x' ${2//./ })
  for i in $(seq 0 15); do
    g=$(cat /sys/class/infiniband/$dev/ports/1/gids/$i 2>/dev/null) || continue
    t=$(cat /sys/class/infiniband/$dev/ports/1/gid_attrs/types/$i 2>/dev/null)
    [[ "$g" == *":ffff:$hex" && "$t" == "RoCE v2" ]] && { echo "$i"; return; }
  done
}
for d in /sys/class/infiniband/*; do
  dev=$(basename "$d"); nd=$(ls "$d/device/net" 2>/dev/null | head -1)
  state=$(awk '{print $2}' "$d/ports/1/state"); rate=$(awk '{print $1}' "$d/ports/1/rate")
  ips=$(ip -4 -o addr show dev "$nd" 2>/dev/null | awk '{print $4}')
  ip=$(echo "$ips" | grep -v '^169\.254\.' | head -1 | cut -d/ -f1)
  line="$dev ($nd) $state ${rate}G mtu $(cat /sys/class/net/$nd/mtu) ipv4 ${ip:--}"
  (( $(echo "$ips" | grep -c .) > 1 )) && line+=" [several IPv4s: $(echo $ips | tr ' ' ',') - NCCL's socket takes the first]"
  if [[ "$state" != ACTIVE || -z "$ip" ]]; then echo "$line  (no test)"; continue; fi
  g=$(gid_of "$dev" "$ip")
  if [[ -z "$g" ]]; then echo "$line  no RoCE v2 GID for $ip"; bad=1; continue; fi
  (timeout 15 ib_write_bw -d "$dev" -x "$g" -F -s 1048576 -D 3 --report_gbits >/dev/null 2>&1 &)
  sleep 1.5
  bw=$(timeout 15 ib_write_bw -d "$dev" -x "$g" -F -s 1048576 -D 3 --report_gbits "$ip" 2>/dev/null | awk '$1 == 1048576 {print $4}')
  sleep 0.5
  if [[ -z "$bw" ]]; then echo "$line gid $g  loopback FAILED"; bad=1
  elif awk -v b="$bw" -v w="$WARN_GBPS" 'BEGIN { exit !(b < w) }'; then echo "$line gid $g  loopback $bw Gb/s  <- LOW"; bad=1
  else echo "$line gid $g  loopback $bw Gb/s  OK"; fi
done
exit $bad
