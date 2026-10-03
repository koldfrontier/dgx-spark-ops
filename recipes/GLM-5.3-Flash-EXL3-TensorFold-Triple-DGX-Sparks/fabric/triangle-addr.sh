#!/usr/bin/env bash
# Put ONE node's four CX7 netdevs on the triangle's addresses, at runtime, and keep NetworkManager off them.
#
# usage (on the node):  sudo -v; ./triangle-addr.sh <port0 CIDR> <port0 twin CIDR> <port1 CIDR> <port1 twin CIDR>
#   port0 = enp1s0f0np0, its PCIe twin enP2p1s0f0np0; port1 = enp1s0f1np1, twin enP2p1s0f1np1.
#   One /24 per twin per cable, both ends in it. The example triangle (head H, workers W1, W2;
#   each node's port 0 cabled to the next node's port 1):
#     H   10.100.61.1/24 10.100.62.1/24 10.100.65.2/24 10.100.66.2/24
#     W1  10.100.63.1/24 10.100.64.1/24 10.100.61.2/24 10.100.62.2/24
#     W2  10.100.65.1/24 10.100.66.1/24 10.100.63.2/24 10.100.64.2/24
#
# Why "unmanaged": on DGX OS the CX7 ports are NetworkManager profiles (netplan-generated). Any carrier
# change - a peer rebooting, a re-plug - makes NM re-apply the saved profile over runtime `ip addr`
# changes, on BOTH ends, with its static routes; a profile with ipv4.method=link-local also keeps
# re-adding a 169.254 address that NCCL's TP2 bootstrap then picks. Unmanaged is runtime only:
# a reboot, or `nmcli device set <dev> managed yes` + `netplan apply`, returns the ports to their profiles.
# For a permanent triangle, write it into netplan instead and skip this script.
set -euo pipefail
(( $# == 4 )) || { sed -n '2,9p' "$0"; exit 2; }
devs=(enp1s0f0np0 enP2p1s0f0np0 enp1s0f1np1 enP2p1s0f1np1)
want=("$@")
for d in "${devs[@]}"; do sudo -n nmcli device set "$d" managed no; done
sleep 2
for k in 0 1 2 3; do
  d=${devs[$k]}
  for a in $(ip -4 -o addr show dev "$d" | awk '{print $4}'); do
    [[ "$a" == "${want[$k]}" ]] || sudo -n ip addr del "$a" dev "$d"
  done
  ip -4 -o addr show dev "$d" | grep -q " ${want[$k]} " || sudo -n ip addr add "${want[$k]}" dev "$d"
  sudo -n ip link set "$d" mtu 6000
done
for d in "${devs[@]}"; do printf '%s %s mtu %s\n' "$d" "$(ip -4 -o addr show dev "$d" | awk '{print $4}' | tr '\n' ' ')" "$(cat /sys/class/net/$d/mtu)"; done
