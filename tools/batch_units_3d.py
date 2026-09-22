#!/usr/bin/env python3
"""Roster batch: portrait -> Hunyuan3D-2 mesh -> painted 16-facing sprite -> manifest.

    ~/AI_Agent/venv/bin/python tools/batch_units_3d.py VC [--only VC-U04,VC-U05] [--steps 40] [--octree 320] [--force]

Per unit: tools/image_to_3d.py (skipped if the GLB exists), then the Blender rig
(tools/render_sprites.py, generic kit_generated), then tools/pack_facings.py.
Assumes ComfyUI is up on 8188. Run in chunks — each unit is ~2.5 min mesh + ~40 s render.
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
FRAMES = os.path.expanduser("~/Dev/assets/generated3d/frames")
UNITS = os.path.join(ROOT, "content", "data", "units.json")
PY = sys.executable


def run(cmd, timeout):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.returncode, (r.stdout + r.stderr)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("faction")
    ap.add_argument("--only", default="")
    ap.add_argument("--steps", type=int, default=40)
    ap.add_argument("--octree", type=int, default=320)
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()

    # Infantry render from Kenney humanoids in the Blender rig (kit_infantry), not from
    # a generated mesh — Hunyuan3D can't do a readable human from one view.
    defs = [d for d in json.load(open(UNITS))["units"] if d["factionId"] == a.faction]
    ids = [d["id"] for d in defs if d.get("armorClass") not in ("Infantry", "HeavyInfantry")]
    only = {s.strip() for s in a.only.split(",") if s.strip()}
    os.makedirs(FRAMES, exist_ok=True)
    done = 0
    for uid in ids:
        if only and uid not in only:
            continue
        t0 = time.time()
        glb = os.path.join(GENERATED, f"{uid}.glb")
        if a.force or not os.path.exists(glb):
            if a.force and os.path.exists(glb):
                os.remove(glb)
            rc, out = run([PY, os.path.join(ROOT, "tools", "image_to_3d.py"), uid,
                           "--steps", str(a.steps), "--octree", str(a.octree)], timeout=900)
            if rc != 0:
                print(uid, "MESH_FAILED", out.strip().splitlines()[-1:] , flush=True)
                continue
        t1 = time.time()
        fdir = os.path.join(FRAMES, uid)
        subprocess.run(["rm", "-rf", fdir])
        rc, out = run([BLENDER, "-b", "-P", os.path.join(ROOT, "tools", "render_sprites.py"), "--",
                       uid, fdir, "--facings", "16", "--px", "256"], timeout=600)
        if rc != 0 or "RENDERED" not in out:
            print(uid, "RENDER_FAILED", [l for l in out.splitlines() if "Error" in l or "Traceback" in l][:2], flush=True)
            continue
        rc, out = run([PY, os.path.join(ROOT, "tools", "pack_facings.py"), uid, fdir, "--downscale", "2"], timeout=120)
        if rc != 0:
            print(uid, "PACK_FAILED", out.strip().splitlines()[-1:], flush=True)
            continue
        print(f"{uid} OK mesh {t1 - t0:.0f}s render+pack {time.time() - t1:.0f}s", flush=True)
        done += 1
    print("DONE", done, "units", flush=True)


if __name__ == "__main__":
    main()
