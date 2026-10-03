#!/usr/bin/env python3
"""Compare tfbench2 runs against a baseline mean, flagging moves beyond the measured noise.
usage: analyze.py <baseline label prefix> <log> [<log> ...]   (driver logs with '] result {...}' lines)"""
import json, re, statistics as st, sys
KEYS = [("prefill_8k", 3.0), ("prefill_32k", 1.5), ("prefill_128k", 1.5), ("prose_x1", 2.5), ("code_rep_x1", 2.5),
        ("code_nat_x1", 5.0), ("prose_x4_agg", 5.0), ("prose_x8_agg", 5.0), ("code_x4_agg", 5.0), ("code_x8_agg", 5.0)]
base_prefix, logs = sys.argv[1], sys.argv[2:]
rows = []
for lg in logs:
    for line in open(lg, encoding="utf-8", errors="replace"):
        m = re.search(r"\] result (\{.*\})\s*$", line)
        if m:
            try: rows.append(json.loads(m.group(1)))
            except ValueError: pass
base = [r for r in rows if r["label"].startswith(base_prefix)]
mean = {k: st.mean(r[k] for r in base) for k, _ in KEYS}
hdr = "run".ljust(22) + "".join(k.replace("prefill_", "pf").replace("_agg", "").replace("_x1", "")[:9].rjust(10) for k, _ in KEYS)
print(hdr); print("base mean (n=%d)" % len(base) + " " * (22 - 15 - len(str(len(base)))) + "".join(("%.1f" % mean[k]).rjust(10) for k, _ in KEYS))
for r in rows:
    if r in base: continue
    cells = []
    for k, thr in KEYS:
        d = 100 * (r[k] - mean[k]) / mean[k]
        cells.append(("%+.1f%s" % (d, "*" if abs(d) > thr else " ")).rjust(10))
    print(r["label"][:22].ljust(22) + "".join(cells))
print("\n* = beyond the noise threshold for that metric (%s)" % ", ".join("%s %.1f%%" % (k, t) for k, t in KEYS))
