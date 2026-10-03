# A re-cabled DGX Spark can lose 7/8 of its RDMA bandwidth until reboot

Found while re-cabling three GB10 units (ASUS Ascent GX10, DGX OS kernel `6.17.0-1032-nvidia`, CX7
firmware `28.45.4028`) from a four-node ring into a three-node triangle, 2026-10-03. Measured, with the
method below; the mechanism is inferred, and the note says where.

## Symptom

A tensor-parallel model prefilled 35-45% below its published numbers on two and on three nodes, while
decode was only ~10% low. Every usual check passed: links up at 200 Gb/s, PCIe Gen5 x4, MTU 6000 /
`active_mtu` 4096, RDMA counters moving on both rails of every cable, nothing on the LAN.

## What perftest showed

`ib_write_bw` (1 MiB, 4 s) and `ib_write_lat` (8 B), model stopped:

| | bandwidth a rail | latency |
|---|---:|---:|
| cable between two re-plugged nodes, either direction | 13.1-13.3 Gb/s | 1.4 us |
| cable from a node that kept a cable in throughout | 109.3 Gb/s | 1.4 us |
| **loopback on one device of a re-plugged node** (never leaves it) | **14.2 Gb/s** | |
| loopback on the node that kept a cable in | 106.7 Gb/s | |
| every cable and loopback after rebooting the re-plugged nodes | 106.4-109.3 Gb/s | 1.4 us |

The loopback result puts it on the host side, not the cable: every RDMA transfer that **reads host
memory** on the affected node runs at ~1/8 speed. Latency is untouched - which is why decode (small,
latency-bound all-gathers) barely shows it and prefill (bulk all-gathers) does.

## What differs on an affected node

GB10 hot-removes the ConnectX-7 from PCIe when **both** QSFP cages are empty (`cx7-pcie-hotplug ...
Cable removal` in `dmesg`) and re-adds it on the next plug-in (`Cable plugin`). Diffing `lspci -vvv` of
the CX7 functions and their root ports against an unaffected node, the one functional difference:

| node | hotplug events during the re-cable | root ports' `DevCtl2` | loopback |
|---|---|---|---:|
| kept a cable in throughout | none | `0x0420` (LTR Mechanism Enable on) | 107 Gb/s |
| cables removed, CX7 still absent | `Cable removal` only | `0x0420` | - |
| cables removed and re-plugged (x2 nodes) | `Cable removal` + `Cable plugin` | **`0x0020` (LTR off)** | 14 Gb/s |

Everything else matched: PCIe link (Gen5 x4), MaxPayload / MaxReadReq 512, relaxed ordering, IOMMU mode
(`DMA-FQ`), pause settings, firmware, kernel. (The surprise removal also leaves sticky `SDES+` /
`FatalErr+` status bits, which change nothing.)

**Proven:** a reboot restores both the LTR bit and full bandwidth (two nodes, before/after above).
**Not proven:** that LTR is the mechanism. We could not set the bit alone: kernel lockdown under Secure
Boot refuses `setpci` writes ("Operation not permitted"). Treat LTR-off as the reliable *marker* of the
bad state.

## Check and avoid

```bash
# on each node: 0420 is healthy, 0020 means "reboot me"
sudo setpci -s 0000:00:00.0 CAP_EXP+28.w; sudo setpci -s 0002:00:00.0 CAP_EXP+28.w
dmesg | grep cx7-pcie-hotplug        # "Cable plugin" since boot = suspect
```

or run [`../recipes/GLM-5.3-Flash-EXL3-TensorFold-Triple-DGX-Sparks/fabric/check-fabric.sh`](../recipes/GLM-5.3-Flash-EXL3-TensorFold-Triple-DGX-Sparks/fabric/check-fabric.sh),
which also does a 3 s loopback `ib_write_bw` on every addressed device.

- **Re-cable one cable at a time**, so no node ever has both cages empty; or
- **reboot every node that logged `Cable plugin`** before you measure or serve.

## A second trap when you re-address after a re-cable

On DGX OS the CX7 ports are NetworkManager profiles generated from netplan. If you re-address them at
runtime (`ip addr`), **any carrier change - a peer rebooting, a re-plug - makes NetworkManager re-apply
the saved profile**, addresses and static routes, on both ends of the cable. A profile with
`ipv4.method=link-local` also re-adds a `169.254.x.x` address whenever it is removed; NCCL's bootstrap
takes the first IPv4 of `NCCL_SOCKET_IFNAME`, so a two-node start then fails with `connect to
169.254.x.x ... Network is unreachable` -> `NCCL error 2: unhandled system error`. Either write the new
topology into netplan, or set the ports `unmanaged` for the session (`nmcli device set <dev> managed no`;
a reboot undoes it).

## What it cost, for scale

GLM-5.3-Flash (EXL3 4 bpw, TensorFold), same recipe and checkpoint, before and after the reboots:

| | affected | after reboot |
|---|---:|---:|
| three nodes: prefill ~8K / ~32K tok/s | 1,181 / 1,188 | 2,205 / 2,231 |
| three nodes: one-stream prose / code tok/s | 57.6 / 87.2 | 62.8 / 99.3 |
| two nodes: prefill ~8K / ~32K tok/s | 1,375 / 1,406 | 1,921 / 1,966 |
