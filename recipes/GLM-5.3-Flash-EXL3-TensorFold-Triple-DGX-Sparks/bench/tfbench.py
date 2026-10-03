#!/usr/bin/env python3
"""Tuning harness for TensorFold GLM-5.3-Flash servers: one JSON line per run.
usage: tfbench.py <label> [base=http://127.0.0.1:8888/v1] [model=GLM-5.3-Flash-EXL3]"""
import json, random, statistics, sys, threading, time, urllib.request
LABEL = sys.argv[1]; BASE = sys.argv[2] if len(sys.argv) > 2 else "http://127.0.0.1:8888/v1"
MODEL = sys.argv[3] if len(sys.argv) > 3 else "GLM-5.3-Flash-EXL3"
NOTHINK = {"enable_thinking": False}
PROSE = ("Explain how a hash map handles collisions. Cover separate chaining and open addressing, "
         "their trade-offs, and when each is preferred. Write in flowing prose.")
CODE = ("Write 50 small Python functions named clamp_00 through clamp_49. Each takes (x, lo, hi) and "
        "returns x clamped to [lo, hi]. Change only the function name suffix (00, 01, ... 49). "
        "One blank line between functions. No other text.")

def post(body, timeout=900):
    return urllib.request.urlopen(urllib.request.Request(BASE + "/chat/completions", json.dumps(body).encode(),
                                  {"Content-Type": "application/json"}), timeout=timeout)

def decode(prompt, tag, n=256):
    body = {"model": MODEL, "messages": [{"role": "user", "content": prompt + " (%s)" % tag}], "max_tokens": n,
            "temperature": 0, "top_p": 1, "stream": True, "stream_options": {"include_usage": True},
            "chat_template_kwargs": NOTHINK}
    t0 = time.time(); first = last = None; toks = 0
    with post(body) as r:
        for line in r:
            line = line.decode().strip()
            if not line.startswith("data:") or line.endswith("[DONE]"): continue
            d = json.loads(line[5:])
            ch = d.get("choices") or []
            if ch and ch[0].get("delta", {}).get("content"):
                now = time.time(); first = first or now; last = now
            if d.get("usage"): toks = d["usage"]["completion_tokens"]
    return {"ttft": (first - t0) if first else None, "tps": (toks - 1) / (last - first) if first and last > first else 0, "toks": toks}

def prefill(words):
    rnd = random.Random(time.time_ns()); a = "abcdefghijklmnopqrstuvwxyz"
    txt = " ".join("".join(rnd.choice(a) for _ in range(rnd.randint(3, 9))) for _ in range(words))
    body = {"model": MODEL, "messages": [{"role": "user", "content": "%d %s\nReply OK." % (rnd.randint(0, 10**12), txt)}],
            "max_tokens": 1, "chat_template_kwargs": NOTHINK}
    t = time.time(); r = json.load(post(body)); dt = time.time() - t
    return {"tokens": r["usage"]["prompt_tokens"], "tps": r["usage"]["prompt_tokens"] / dt}

def concurrent(prompt, k):
    out = [None] * k
    def w(i): out[i] = decode(prompt, "stream %d/%d" % (i + 1, k))
    ts = [threading.Thread(target=w, args=(i,)) for i in range(k)]; t0 = time.time()
    [t.start() for t in ts]; [t.join() for t in ts]
    return {"agg": sum(o["toks"] for o in out) / (time.time() - t0), "per": statistics.median(o["tps"] for o in out)}

res = {"label": LABEL, "started": time.strftime("%H:%M:%S", time.gmtime())}
decode(PROSE, "warm a"); decode(CODE, "warm b"); concurrent(PROSE, 4)            # warm-up wave, discarded
p8 = [prefill(2300) for _ in range(2)]; p32 = [prefill(9300) for _ in range(2)]
res["prefill_8k"] = round(statistics.median(x["tps"] for x in p8)); res["prefill_8k_tokens"] = p8[0]["tokens"]
res["prefill_32k"] = round(statistics.median(x["tps"] for x in p32)); res["prefill_32k_tokens"] = p32[0]["tokens"]
pr = [decode(PROSE, "p%d" % i) for i in range(3)]; co = [decode(CODE, "c%d" % i) for i in range(2)]
res["prose_x1"] = round(statistics.median(x["tps"] for x in pr), 1); res["prose_ttft_ms"] = round(1000 * statistics.median(x["ttft"] for x in pr))
res["code_x1"] = round(statistics.median(x["tps"] for x in co), 1)
c4 = concurrent(PROSE, 4); res["prose_x4_agg"] = round(c4["agg"], 1); res["prose_x4_per"] = round(c4["per"], 1)
res["finished"] = time.strftime("%H:%M:%S", time.gmtime())
print(json.dumps(res), flush=True)
