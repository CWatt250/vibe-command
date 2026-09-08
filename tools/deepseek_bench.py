#!/usr/bin/env python3
"""Side-by-side: DeepSeek V4.1 Flash (beta) vs V4 Flash Vision Exp on agent/coding/vision tasks."""
import os, json, time, re, sys

BASE = os.environ.get("DEEPSEEK_BASE", "https://api.deepseek.com/v1")

KEY = None
for p in [os.path.expanduser("~/.hermes/profiles/scout/.env"),
          os.path.expanduser("~/.hermes/profiles/forge/.env")]:
    try:
        for line in open(p):
            if line.startswith("DEEPSEEK_API_KEY="):
                KEY = line.split("=", 1)[1].strip().strip('"').strip("'")
                break
    except FileNotFoundError:
        continue
    if KEY:
        break
if not KEY:
    print("NO DEEPSEEK_API_KEY found"); sys.exit(2)

MODELS = {
    "v4-flash-vision": "deepseek-v4-flash-vision-exp",
    "v4.1-flash-beta": "deepseek-v4.1-flash-expires-on-0910",
}

def chat(model, messages, max_tokens=1500, temperature=0.3):
    body = {"model": model, "messages": messages, "max_tokens": max_tokens, "temperature": temperature, "stream": False}
    import urllib.request
    req = urllib.request.Request(BASE + "/chat/completions",
        data=json.dumps(body).encode(), method="POST",
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + KEY})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=180) as r:
        data = json.loads(r.read().decode())
    el = time.time() - t0
    u = data.get("usage", {})
    return {
        "text": data["choices"][0]["message"]["content"],
        "latency_s": round(el, 2),
        "prompt_tokens": u.get("prompt_tokens", 0),
        "completion_tokens": u.get("completion_tokens", 0),
        "total_tokens": u.get("total_tokens", 0),
        "tok_per_s": round(u.get("completion_tokens", 0) / max(el, 0.001)),
    }

def run(model, tasks):
    print(f"\n===== {model} =====")
    for name, (usr, sys_, want) in tasks.items():
        msgs = ([{"role":"system","content":sys_}] if sys_ else []) + [{"role":"user","content":usr}]
        res = chat(model, msgs, max_tokens=want)
        print(f"\n--- {name} ---")
        print(f"latency={res['latency_s']}s tok/s={res['tok_per_s']} ctin={res['completion_tokens']} pto={res['prompt_tokens']}")
        print(res["text"][:1600])
        res["name"] = name
        res["model"] = model
        all_res.append(res)

all_res = []
PY = """Write a Python function `levenshtein(a, b)` returning the Levenshtein edit distance, iterative DP O(len(a)*len(b)), correct and clean, no comments. Then a self-test in a `if __name__` block."""
AGENT = """You are a systems agent. A Godot 4 game needs harvesters that gather from depletable resource fields. Give the minimal `HarvestComponent` state machine as GDScript: states IDLE/TRAVEL_FIELD/HARVEST/TRAVEL_DROPOFF/DEPOSIT, fields capacity, cargo, harvest_rate, harvest_radius, target ids, and a `tick(sim)` skeleton. Keep it tight."""
CODE_REV = """Explain in 3 sentences what a production build gate (dequeued on queue, blocks elite output when command capacity is exhausted) does. Then give the one-line invariant it enforces."""
TASKS = {
    "coding": (PY, "You are an expert Python engineer.", 900),
    "agent-design": (AGENT, "You are a game systems engineer. GDScript (Godot 4).", 1400),
    "reasoning": (CODE_REV, "You are a senior RTS engineer.", 500),
}

for tag, m in MODELS.items():
    try:
        run(m, TASKS)
    except Exception as e:
        print(f"\n===== {m} FAILED: {e} =====")

print("\n\n########## SUMMARY ##########")
from collections import defaultdict
byname = defaultdict(list)
for r in all_res:
    byname[r["name"]].append((r["model"], r["latency_s"], r["tok_per_s"], r["completion_tokens"]))
for name, lst in byname.items():
    print(f"[{name}]")
    for m, la, ts, ct in lst:
        print(f"  {m:22s} latency={la:>6}s  tok/s={ts:>5}  ctin={ct}")
