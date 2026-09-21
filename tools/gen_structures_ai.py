#!/usr/bin/env python3
"""Pipeline B batch: every structure of a faction through Qwen-Image-2.1 -> game sprite.

    ~/AI_Agent/venv/bin/python tools/gen_structures_ai.py VC [--only VC-B03,VC-D02] [--seed-bump N]

Assumes ComfyUI is up on 127.0.0.1:8188 (run ~/Dev/ComfyUI/launch.sh first); leaves it up.
Per structure: PREFIX[faction] + DESC[id] + SUFFIX -> raw PNG in docs/concepts/<faction>/,
keyed sprite in assets/sprites/<id>_ai.png (tools/ai_sprite_prep.py), manifest entry
{"file", "scale", "tint": 0}. Seed = stable hash of id (+ --seed-bump) so one structure can be
re-rolled without moving the others. Skips ids that already have a raw render unless --force.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.expanduser("~/AI_Agent"))
from tools import comfy_qwen as cq  # noqa: E402

SPRITES = os.path.join(ROOT, "assets", "sprites")
MANIFEST = os.path.join(SPRITES, "manifest.json")
STRUCTURES = os.path.join(ROOT, "content", "data", "structures.json")

PREFIX = {
    "VC": (
        "Game sprite of a single building for a 2D real-time strategy game, three-quarter top-down "
        "view from slightly above (about 40 degree camera tilt, like Command & Conquer Red Alert). "
        "Faction style: scrappy garage-tech built by hobbyist engineers — plywood and OSB panels, "
        "corrugated sheet metal, duct tape patches, zip-tied cable bundles, exposed consumer battery "
        "packs, PVC pipe masts, laptops and monitors, cyan LED strips as the faction accent colour. "
    ),
    "FC": (
        "Game sprite of a single building for a 2D real-time strategy game, three-quarter top-down "
        "view from slightly above (about 40 degree camera tilt, like Command & Conquer Red Alert). "
        "Faction style: clean federal military-industrial — matte grey angular concrete and steel "
        "panels, riveted plating, chevron hazard stripes, floodlights, amber warning lights as the "
        "faction accent colour, tidy and imposing. "
    ),
}
SUFFIX = (
    "Exaggerated chunky proportions, big readable silhouette, hand-painted stylized look like "
    "Warcraft 3, hard sunlight from the upper left with a strong dark contact shadow on the ground to "
    "the lower right. The object is centered and fills the frame, isolated on a flat solid bright "
    "magenta background, no ground texture, no scenery, no people, no text, no watermark."
)

# What each building IS, in the faction's visual language. The def's `function` is appended.
DESC = {
    "VC-B01": "the Garage Core headquarters: a chunky two-story workshop with one big roll-up garage door open showing a workbench with glowing monitors inside, satellite dish and solar panels on the roof, tall antenna mast with a bright cyan LED.",
    "VC-B02": "the Fabrication Yard: an open-sided shed over a scrap-sorting yard, conveyor belt, stacked pallets and crates, a small crane arm, an unloading ramp for harvester trucks at the front.",
    "VC-B03": "the Generator Bank: a low wooden rack holding a row of portable gas generators and car batteries wired together, exhaust pipes puffing, extension cords everywhere, a fuel drum beside it.",
    "VC-B04": "the Cooling Plant: a plywood hut with several big box fans and a rooftop swamp cooler, water tanks, radiator coils, hoses, frost on the vents.",
    "VC-B05": "the Server Rack Hall: a long shed packed with open server racks visible through the front, blinking cyan LEDs, tangled ethernet cables, a ceiling of box fans, a small chiller unit outside.",
    "VC-B06": "the AI Cluster: a taller two-story compute building of stacked server containers with liquid cooling pipes, heavy power cables, a glowing cyan status tower on top, more industrial than the rest.",
    "VC-B07": "the Maker Space: a workshop where infantry are trained — open front showing 3D printers, a drill press and a whiteboard, a canvas awning, tool racks, a small drone on the roof.",
    "VC-B08": "the Robot Shop: a vehicle garage with two wide bay doors, a vehicle lift, welding sparks, a half-built wheeled robot on the lift, tires stacked outside.",
    "VC-B09": "the Drone Farm: a flat roof helipad with painted landing circles and a few quadcopter drones parked on it, a control shack with antennas, charging cables running to the pads.",
    "VC-B10": "the Autonomy Lab: a research trailer with a glass front, a rooftop sensor array with lidar domes and cameras, whiteboards visible inside, a cyan-lit test rig out front.",
    "VC-B11": "the Repair Bay: an open canopy over a vehicle pit with a hoist, toolboxes, spare parts shelves, an air compressor, oil stains.",
    "VC-B12": "the Expansion Node: a compact outpost box — a shipping container with a small generator on top, a folding antenna, solar panel, a cyan beacon, meant to be dropped far from base.",
    "VC-D01": "the Camera Pole: a single tall PVC pole on a sandbag base with a security camera cluster and a floodlight on top, small and thin.",
    "VC-D02": "the Auto Turret: a small sandbagged pedestal with a homemade machine-gun turret, a webcam sight bolted to the gun, ammo boxes, cyan LED.",
    "VC-D03": "the Drone Nest: a squat honeycomb rack of drone launch tubes with a few drones peeking out, a small control box with an antenna, compact.",
    "VC-D04": "the Smart Mine Node: a small buried sensor post — a low hub with a blinking cyan light and a few disc-shaped mines half-buried around it, very small.",
    "VC-D05": "the AT Launcher: a small emplacement with a shoulder-fired rocket launcher mounted on a tripod behind sandbags and a plywood blast shield, spare rockets in a crate.",
    "VC-D06": "the Counter-Drone Mast: a tall lattice mast with a jammer dish and antenna arrays on top, guy wires, a control box at the base, small footprint.",
    "VC-D07": "the Predictive Turret: a medium turret on a concrete plinth with a twin autocannon, a radar dome and a bank of cameras, cables to a computer cabinet.",
    "VC-D08": "the Rail Emplacement: a heavy emplacement with a long railgun barrel on a rotating mount, huge capacitor banks and cooling fins, thick power cables, the biggest defense.",
}


def seed_for(sid: str, bump: int) -> int:
    return int(hashlib.md5(f"{sid}:{bump}".encode()).hexdigest()[:7], 16)


def scale_for(fp) -> float:
    w = int(fp[0]) if fp else 1
    return {1: 1.7, 2: 1.4}.get(w, 1.3)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("faction")
    ap.add_argument("--only", default="")
    ap.add_argument("--seed-bump", type=int, default=0)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--steps", type=int, default=22)
    a = ap.parse_args()

    defs = [d for d in json.load(open(STRUCTURES))["structures"] if d["factionId"] == a.faction]
    only = {s.strip() for s in a.only.split(",") if s.strip()}
    raw_dir = os.path.join(ROOT, "docs", "concepts", a.faction.lower())
    os.makedirs(raw_dir, exist_ok=True)

    deadline = time.time() + 240
    while not cq._up() and time.time() < deadline:
        time.sleep(3)
    if not cq._up():
        sys.exit("COMFY_NOT_UP")

    manifest = json.load(open(MANIFEST))
    done = 0
    for d in defs:
        sid = d["id"]
        if only and sid not in only:
            continue
        if sid not in DESC:
            print("SKIP no description:", sid, flush=True)
            continue
        raw = os.path.join(raw_dir, f"{sid}.png")
        if os.path.exists(raw) and not a.force:
            print("SKIP exists:", sid, flush=True)
            continue
        prompt = PREFIX[a.faction] + DESC[sid] + " Role: " + d.get("function", "") + ". " + SUFFIX
        r = cq.generate(prompt, steps=a.steps, seed=seed_for(sid, a.seed_bump),
                        width=1024, height=1024, filename=f"struct_{sid}")
        print(sid, json.dumps({k: r[k] for k in ("ok", "seconds", "seed", "error")}), flush=True)
        if not r["ok"]:
            continue
        os.replace(r["path"], raw)
        sprite = os.path.join(SPRITES, f"{sid}_ai.png")
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "ai_sprite_prep.py"),
                        raw, sprite, "--width", "256"], check=True)
        manifest[sid] = {"file": f"{sid}_ai.png", "scale": scale_for(d.get("footprint")), "tint": 0.0}
        json.dump(manifest, open(MANIFEST, "w"), indent=1, sort_keys=True)
        done += 1
    print("DONE", done, "structures", flush=True)


if __name__ == "__main__":
    main()
