#!/usr/bin/env python3
"""Turn a Strata run config that setup wrote (strata-<model>.json) into this recipe's V100 serving form.

Only these change; everything else setup wrote is kept:
  env       + PR #3411's 13 Volta switches (opt-in in Strata 0.1.52; byte-identical output in our runs)
  args      + --kv-resident 32768 when missing (setup writes it itself from 64K context up when RAM allows; a config
              whose context was raised by hand does not have it) and --vram-reserve-mib N when missing
  parallel  = --slots (1: fastest per request and in total on this card; 2: a second request starts at once, but both
              share one decode)

usage: apply-v100-stack.py SETUP_CONFIG OUT_CONFIG [--slots 1|2] [--reserve-mib 768]
Standard library only. Read the printed summary, then point the server at OUT_CONFIG."""
import argparse, copy, json, sys

V100_ENV = {"STRATA_SIDE_MIXER": "2", **{f"STRATA_{k}": "1" for k in (
    "GR_UP75 B6_MMVQ_ROWS GU_SWIGLU QSA_ROWS ATTN_DAILY SM70_TABLE GR_NORM_FAST ARGMAX_ROWS_SM70 QIL EXPDEC "
    "GR_DOWN_TG DEQUANT_WIDE").split()}}

ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("dst")
ap.add_argument("--slots", type=int, choices=(1, 2), default=1)
ap.add_argument("--reserve-mib", type=int, default=768)
a = ap.parse_args()

c = json.load(open(a.src))
out = copy.deepcopy(c)
args = list(c["args"])
notes = []
ctx = int(args[args.index("--max-context") + 1]) if "--max-context" in args else 0
if ctx < 65536:
    notes.append(f"context {ctx}: KV streaming only pays from 64K up; --kv-resident not added")
elif "--kv-resident" not in args:
    args += ["--kv-resident", "32768"]; notes.append("added --kv-resident 32768 (the KV cache beyond 32K cells per QSA layer lives in pinned RAM)")
if "--vram-reserve-mib" not in args:
    args += ["--vram-reserve-mib", str(a.reserve_mib)]; notes.append(f"added --vram-reserve-mib {a.reserve_mib}")
out["args"] = args
out["args_written"] = list(args)
env = dict(c.get("env") or {})
kept = {k: v for k, v in env.items() if k in V100_ENV and v != V100_ENV[k]}
out["env"] = {**V100_ENV, **env}                     # a value you already set wins
if kept:
    notes.append(f"kept your own values for {sorted(kept)}")
out["parallel"] = a.slots
json.dump(out, open(a.dst, "w"), indent=2)
print(f"{a.dst}: parallel {a.slots}, {len(out['env'])} env entries")
for n in notes:
    print(" -", n)
if c.get("parallel") != a.slots:
    print(f" - slots {c.get('parallel')} -> {a.slots}")
sys.exit(0)
