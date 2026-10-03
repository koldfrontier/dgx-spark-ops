#!/usr/bin/env python3
"""TensorFold GLM-5.3-Flash tuning harness v2: one JSON line per run.
usage: tfbench2.py <label> [base=http://127.0.0.1:8888/v1] [model=GLM-5.3-Flash-EXL3]
v2 adds a ~128K prefill, a natural code prompt next to the copy-friendly one, code at
4 streams, prose and code at 8 streams, and inter-token gap percentiles (meaningful with STREAM_SMOOTH=0;
with smoothing on, gaps follow the playout pacing)."""
import json, random, statistics, sys, threading, time, urllib.request
LABEL = sys.argv[1]; BASE = sys.argv[2] if len(sys.argv) > 2 else "http://127.0.0.1:8888/v1"
MODEL = sys.argv[3] if len(sys.argv) > 3 else "GLM-5.3-Flash-EXL3"
NOTHINK = {"enable_thinking": False}
PROSE = ("Explain how a hash map handles collisions. Cover separate chaining and open addressing, "
         "their trade-offs, and when each is preferred. Write in flowing prose.")
CODE_REP = ("Write 50 small Python functions named clamp_00 through clamp_49. Each takes (x, lo, hi) and "
            "returns x clamped to [lo, hi]. Change only the function name suffix (00, 01, ... 49). "
            "One blank line between functions. No other text.")
CODE_NAT = ("Write a Python module implementing an LRU cache class with O(1) get and put, a configurable "
            "capacity, optional per-entry time-to-live, and hit/miss statistics. Include type hints, "
            "docstrings, and a set of pytest unit tests at the end. Output only the code.")

def post(body, timeout=1800):
    return urllib.request.urlopen(urllib.request.Request(BASE + "/chat/completions", json.dumps(body).encode(),
                                  {"Content-Type": "application/json"}), timeout=timeout)

def decode(prompt, tag, n=256):
    body = {"model": MODEL, "messages": [{"role": "user", "content": prompt + " (%s)" % tag}], "max_tokens": n,
            "temperature": 0, "top_p": 1, "stream": True, "stream_options": {"include_usage": True},
            "chat_template_kwargs": NOTHINK}
    t0 = time.time(); first = last = None; toks = 0; ev = []
    with post(body) as r:
        for line in r:
            line = line.decode().strip()
            if not line.startswith("data:") or line.endswith("[DONE]"): continue
            d = json.loads(line[5:])
            ch = d.get("choices") or []
            if ch and ch[0].get("delta", {}).get("content"):
                now = time.time(); first = first or now; last = now; ev.append(now)
            if d.get("usage"): toks = d["usage"]["completion_tokens"]
    gaps = [b - a for a, b in zip(ev, ev[1:])]
    return {"ttft": (first - t0) if first else None, "tps": (toks - 1) / (last - first) if first and last > first else 0,
            "toks": toks, "gaps": gaps}

def prefill(words):
    rnd = random.Random(time.time_ns()); a = "abcdefghijklmnopqrstuvwxyz"
    txt = " ".join("".join(rnd.choice(a) for _ in range(rnd.randint(3, 9))) for _ in range(words))
    body = {"model": MODEL, "messages": [{"role": "user", "content": "%d %s\nReply OK." % (rnd.randint(0, 10**12), txt)}],
            "max_tokens": 1, "chat_template_kwargs": NOTHINK}
    t = time.time(); r = json.load(post(body)); dt = time.time() - t
    return {"tokens": r["usage"]["prompt_tokens"], "tps": r["usage"]["prompt_tokens"] / dt}

def pct(xs, q):
    xs = sorted(xs); return xs[min(len(xs) - 1, int(q * len(xs)))] if xs else 0

def concurrent(prompt, k):
    out = [None] * k
    def w(i): out[i] = decode(prompt, "stream %d/%d" % (i + 1, k))
    ts = [threading.Thread(target=w, args=(i,)) for i in range(k)]; t0 = time.time()
    [t.start() for t in ts]; [t.join() for t in ts]
    gaps = [g for o in out for g in o["gaps"]]
    return {"agg": sum(o["toks"] for o in out) / (time.time() - t0), "per": statistics.median(o["tps"] for o in out),
            "ttft": statistics.median(o["ttft"] for o in out), "p50": pct(gaps, 0.5), "p99": pct(gaps, 0.99)}

res = {"label": LABEL, "v": 2, "started": time.strftime("%H:%M:%S", time.gmtime())}
decode(PROSE, "warm a"); decode(CODE_REP, "warm b"); decode(CODE_NAT, "warm c")       # warm-up, discarded
concurrent(PROSE, 4); concurrent(PROSE, 8)
for key, words, n in (("8k", 2300, 2), ("32k", 9300, 2), ("128k", 37300, 1)):
    p = [prefill(words) for _ in range(n)]
    res["prefill_" + key] = round(statistics.median(x["tps"] for x in p)); res["prefill_%s_tokens" % key] = p[0]["tokens"]
pr = [decode(PROSE, "p%d" % i) for i in range(3)]
res["prose_x1"] = round(statistics.median(x["tps"] for x in pr), 1); res["prose_ttft_ms"] = round(1000 * statistics.median(x["ttft"] for x in pr))
res["code_rep_x1"] = round(statistics.median(decode(CODE_REP, "c%d" % i)["tps"] for i in range(2)), 1)
res["code_nat_x1"] = round(statistics.median(decode(CODE_NAT, "n%d" % i)["tps"] for i in range(2)), 1)
for name, prompt in (("prose", PROSE), ("code", CODE_NAT)):
    for k in (4, 8):
        c = concurrent(prompt, k)
        res["%s_x%d_agg" % (name, k)] = round(c["agg"], 1); res["%s_x%d_per" % (name, k)] = round(c["per"], 1)
        if name == "prose":
            res["prose_x%d_ttft_ms" % k] = round(1000 * c["ttft"])
            res["prose_x%d_gap_p50_ms" % k] = round(1000 * c["p50"], 1); res["prose_x%d_gap_p99_ms" % k] = round(1000 * c["p99"], 1)
res["finished"] = time.strftime("%H:%M:%S", time.gmtime())
print(json.dumps(res), flush=True)
