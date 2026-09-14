# Notes

Operational findings from running these machines, separate from any one
model's recipe. Measurements are from our own hardware with the method
included; where something is inferred rather than measured, it says so.

| Note | What it covers |
|---|---|
| [`ring-ops.md`](ring-ops.md) | Four DGX Sparks as a switchless RoCE ring: verifying the transport by counters, per-node GID derivation, cabling and routing on a cycle, what the topology costs (4.64 ms of a 63 ms decode step; 16% of prefill), ring vs switch, and the failure modes that look like a healthy container |
