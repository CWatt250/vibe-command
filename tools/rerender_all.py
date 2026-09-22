#!/usr/bin/env python3
"""Re-render every unit sprite from cached meshes with the current rig settings.

    ~/AI_Agent/venv/bin/python tools/rerender_all.py [--only VC-U04,FC-U07] [--facings 16]

No GPU/ComfyUI needed: infantry build from the Kenney kit and vehicles reuse the GLBs
already in ~/Dev/assets/generated3d/. Use this after ANY change to lighting, projection,
outline or scale so the whole roster stays consistent — a roster rendered under two
different rigs reads as two different games.
"""
import argparse
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLENDER = os.path.expanduser("~/Dev/tools/blender-4.5.13-linux-x64/blender")
GENERATED = os.path.expanduser("~/Dev/assets/generated3d")
FRAMES = os.path.join(GENERATED, "frames")
UNITS = os.path.join(ROOT, "content", "data", "units.json")
INFANTRY = ("Infantry", "HeavyInfantry")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--facings", type=int, default=16)
    ap.add_argument("--px", type=int, default=256)
    a = ap.parse_args()
    only = {s.strip() for s in a.only.split(",") if s.strip()}

    defs = json.load(open(UNITS))["units"]
    todo = []
    for d in defs:
        uid = d["id"]
        if only and uid not in only:
            continue
        if d.get("armorClass") in INFANTRY or os.path.exists(os.path.join(GENERATED, f"{uid}.glb")):
            todo.append(uid)

    ok = 0
    for uid in todo:
        t0 = time.time()
        fdir = os.path.join(FRAMES, uid)
        subprocess.run(["rm", "-rf", fdir])
        r = subprocess.run([BLENDER, "-b", "-P", os.path.join(ROOT, "tools", "render_sprites.py"), "--",
                            uid, fdir, "--facings", str(a.facings), "--px", str(a.px)],
                           capture_output=True, text=True, timeout=900)
        if "RENDERED" not in (r.stdout + r.stderr):
            print(uid, "RENDER_FAILED", flush=True)
            continue
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "pack_facings.py"),
                            uid, fdir, "--downscale", "2"], capture_output=True, text=True, timeout=180)
        if r.returncode != 0:
            print(uid, "PACK_FAILED", r.stderr.strip().splitlines()[-1:], flush=True)
            continue
        ok += 1
        print(f"{uid} ok {time.time() - t0:.0f}s", flush=True)
    print("RERENDER_DONE", ok, "of", len(todo), flush=True)


if __name__ == "__main__":
    main()
