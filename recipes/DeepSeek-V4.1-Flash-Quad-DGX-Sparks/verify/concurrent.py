#!/usr/bin/env python3
"""concurrent.py BASE OUT [--chars N] [--delay S] [--model NAME]

Fairness probe. Sends one cold long prompt (repetitive filler with a needle in
the middle), then DELAY seconds later a short streaming request, and reports
the long request's time to first token and the short stream's inter-chunk gaps.
Without --long-prefill-token-threshold the short stream gets one chunk per full
8192-token prefill step; with it, one per capped step. Also fires a six-image
prompt at the end to check --limit-mm-per-prompt.

  python3 concurrent.py http://<head>:8000/v1 out.json --chars 1000000 --delay 15
"""
import sys, json, time, threading, urllib.request, base64, zlib, struct
BASE = sys.argv[1]; OUT = sys.argv[2]
CHARS = int(sys.argv[sys.argv.index("--chars")+1]) if "--chars" in sys.argv else 1_000_000
DELAY = float(sys.argv[sys.argv.index("--delay")+1]) if "--delay" in sys.argv else 15.0
MODEL = sys.argv[sys.argv.index("--model")+1] if "--model" in sys.argv else "deepseek-v4.1-flash"
NEEDLE = "The secret passphrase for the archive is 'cobalt-heron-417'."
filler = ("The river valley holds a small town whose market opens at dawn and closes when the bells ring at noon. "
          "Traders bring grain, cloth and pottery, and the ledger keeper records each sale in a bound book. ")
n = CHARS // len(filler); half = n // 2
prompt = filler * half + NEEDLE + " " + filler * (n - half) + "\n\nQuestion: what is the secret passphrase for the archive? Answer with the passphrase only."

def stream(body, tag):
    req = urllib.request.Request(BASE + "/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
    t0 = time.time(); stamps = []; text = ""
    with urllib.request.urlopen(req, timeout=3600) as r:
        for line in r:
            if not line.startswith(b"data: ") or line.strip() == b"data: [DONE]": continue
            d = json.loads(line[6:]); ch = d["choices"][0]["delta"].get("content") or ""
            if ch: stamps.append(time.time()); text += ch
    return {"tag": tag, "t_first": (stamps[0]-t0) if stamps else None, "t_total": time.time()-t0,
            "chunks": len(stamps), "gaps": [round(b-a,3) for a,b in zip(stamps, stamps[1:])], "text": text[:200]}

res = {}
def long_req():
    res["long"] = stream({"model": MODEL, "stream": True, "max_tokens": 32, "temperature": 0,
                          "messages": [{"role": "user", "content": prompt}]}, "long")
th = threading.Thread(target=long_req); th.start()
time.sleep(DELAY)
res["short"] = stream({"model": MODEL, "stream": True, "max_tokens": 200, "temperature": 0,
                       "messages": [{"role": "user", "content": "Count from 1 to 60, comma separated, nothing else."}]}, "short")
th.join()
g = res["short"]["gaps"]
res["short_summary"] = {"chunks": res["short"]["chunks"], "t_first": round(res["short"]["t_first"] or -1, 2),
                        "t_total": round(res["short"]["t_total"], 2), "gap_max": max(g) if g else None,
                        "gap_mean": round(sum(g)/len(g), 3) if g else None, "gaps_over_1s": sum(1 for x in g if x > 1.0)}
res["long_summary"] = {"prompt_chars": len(prompt), "t_first": round(res["long"]["t_first"] or -1, 1),
                       "t_total": round(res["long"]["t_total"], 1), "needle_found": "cobalt-heron-417" in res["long"]["text"]}
# six tiny images against the new --limit-mm-per-prompt
def png(rgb):
    raw = b"".join(b"\x00" + bytes(rgb)*2 for _ in range(2))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t+d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
imgs = [{"type": "image_url", "image_url": {"url": "data:image/png;base64," + base64.b64encode(png(c)).decode()}}
        for c in [(255,0,0),(0,255,0),(0,0,255),(255,255,0),(0,255,255),(255,0,255)]]
body = {"model": MODEL, "max_tokens": 20, "temperature": 0,
        "messages": [{"role": "user", "content": [{"type": "text", "text": "How many images did I send? Reply with the number only."}] + imgs}]}
try:
    req = urllib.request.Request(BASE + "/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
    d = json.load(urllib.request.urlopen(req, timeout=600)); res["six_images"] = {"status": 200, "text": d["choices"][0]["message"]["content"][:80]}
except urllib.error.HTTPError as e:
    res["six_images"] = {"status": e.code, "text": e.read()[:200].decode(errors="replace")}
json.dump(res, open(OUT, "w"), indent=1)
print(json.dumps({"short": res["short_summary"], "long": res["long_summary"], "six_images": res["six_images"]}, indent=1))
