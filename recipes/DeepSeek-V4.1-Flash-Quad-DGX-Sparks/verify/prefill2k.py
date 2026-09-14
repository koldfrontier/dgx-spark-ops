#!/usr/bin/env python3
"""prefill2k.py BASE N  - short-prompt cold-prefill rate, in isolation.

N prompts of ~2.2K and ~1.1K tokens, each with a unique random prefix so
nothing hits the prefix cache, reporting TTFT and prompt tokens per call. Use
it to tell a real regression from a benchmark cell that collided with live
traffic or with a first-use JIT compile.

  python3 prefill2k.py http://<head>:8000/v1 4
"""
import sys, json, time, random, urllib.request
BASE, N = sys.argv[1], int(sys.argv[2])
words = "valley market ledger grain cloth pottery bells river dawn trader bound book noon".split()
def run(nwords, tag):
    out = []
    for i in range(N):
        rnd = random.Random(time.time_ns())
        body_txt = f"[{rnd.randrange(10**9)}] " + " ".join(rnd.choice(words) for _ in range(nwords)) + "\n\nReply with the single word: done."
        body = {"model": "deepseek-v4.1-flash", "stream": True, "max_tokens": 8, "temperature": 0, "messages": [{"role": "user", "content": body_txt}]}
        req = urllib.request.Request(BASE + "/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
        t0 = time.time(); ttft = None; usage = None
        with urllib.request.urlopen(req, timeout=600) as r:
            for line in r:
                if not line.startswith(b"data: ") or line.strip() == b"data: [DONE]": continue
                d = json.loads(line[6:])
                if ttft is None and d["choices"] and (d["choices"][0]["delta"].get("content") or ""): ttft = time.time() - t0
                if d.get("usage"): usage = d["usage"]
        # prompt tokens via a non-stream echo is overkill; estimate from a second call with stream=False
        body["stream"] = False
        d = json.load(urllib.request.urlopen(urllib.request.Request(BASE + "/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"}), timeout=600))
        pt = d["usage"]["prompt_tokens"]
        out.append({"tag": tag, "prompt_tokens": pt, "ttft_s": round(ttft, 3), "prefill_tok_s": round(pt / ttft, 1)})
        print(json.dumps(out[-1]), flush=True)
        time.sleep(2)
    return out
res = run(2200, "~3K") + run(1100, "~1.5K")
json.dump(res, open("prefill2k.json", "w"), indent=1)
