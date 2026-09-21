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
    "TS": (
        "Game sprite of a single building for a 2D real-time strategy game, three-quarter top-down "
        "view from slightly above (about 40 degree camera tilt, like Command & Conquer Red Alert). "
        "Faction style: premium corporate war machine — sleek white and graphite composite panels, "
        "brushed titanium trim, tinted glass, seamless modular architecture, holographic teal signage "
        "and teal status light strips as the faction accent colour, drone landing pads, immaculate, "
        "like a defense contractor's flagship campus. "
    ),
    "SG": (
        "Game sprite of a single building for a 2D real-time strategy game, three-quarter top-down "
        "view from slightly above (about 40 degree camera tilt, like Command & Conquer Red Alert). "
        "Faction style: an assimilation intelligence built from stolen technology — buildings are "
        "asymmetric agglomerations of captured machinery fused together and overgrown with black "
        "crystalline shards, veins and seams of glowing orange-red light as the faction accent "
        "colour, antenna spines, slightly alive and unsettling, no faces, no organic flesh. "
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
    # ---- Federal Command ----
    "FC-B01": "the Continuity HQ: a wide two-story concrete command building with a flat roof bristling with radar dishes and antenna masts, a flag pole, sandbagged entrance, amber floodlights.",
    "FC-B02": "the Logistics Depot: a big warehouse with a loading dock, stacked shipping containers and pallets, a forklift, a truck unloading bay with hazard stripes.",
    "FC-B03": "the Field Generator: a fenced compound with two large diesel generator trailers, a transformer with insulators, fuel tanks, exhaust stacks.",
    "FC-B04": "the Barracks: a long prefab military barracks block with a covered porch, rows of windows, a parade square out front, sandbags, an amber-lit doorway.",
    "FC-B05": "the Motor Pool: a wide vehicle hangar with three roll-up bay doors, a humvee parked outside, oil drums, tire racks, hazard-striped bay floors.",
    "FC-B06": "the Armor Depot: a heavy reinforced hangar with a huge single bay door for tanks, a gantry crane, ammunition bunker beside it, tank tracks on the concrete.",
    "FC-B07": "the Artillery Battery: an open emplacement with a self-propelled howitzer under a camo net, shell racks, a range-finder radar mast, sandbag walls.",
    "FC-B08": "the Air Operations Center: a control tower with a glass-topped cab beside a helipad with painted markings, a radar dome, a fuel truck.",
    "FC-B09": "the Command Post: a compact armored comms bunker with a big satellite dish, antenna array and a floodlight mast, small and dense.",
    "FC-B10": "the Joint Operations Center: an imposing three-story command block with a huge radar dish, multiple antenna masts, tinted windows, a helipad on the roof.",
    "FC-B11": "the Repair Depot: an open-sided maintenance shed with a vehicle hoist, a crane arm, spare parts crates, a welding station, hazard stripes.",
    "FC-B12": "the Forward Operating Base: a fortified compound of stacked HESCO barriers around prefab huts, a watchtower, a small medic tent with a cross, an antenna.",
    "FC-D01": "the Sandbag Wall: a short segment of stacked sandbags with a steel picket, very small and low.",
    "FC-D02": "the Guard Tower: a tall steel watchtower on four legs with an enclosed cab, a searchlight and a mounted machine gun, small footprint.",
    "FC-D03": "the Machine Gun Nest: a low sandbagged pit with a heavy machine gun on a tripod and ammo cans, very compact.",
    "FC-D04": "the AT Emplacement: a concrete revetment with a heavy anti-tank missile launcher on a mount, spare missile tubes, small.",
    "FC-D05": "the Bunker: a squat reinforced concrete bunker with narrow firing slits on all sides, a steel door, sandbags, sturdy and heavy.",
    "FC-D06": "the SAM Site: a mobile launcher with four surface-to-air missile tubes raised on a hydraulic mount, a tracking radar dish beside it.",
    "FC-D07": "the Counter-UAS Station: a small trailer with a rotary anti-drone gun turret and a jammer antenna array, compact.",
    "FC-D08": "the Patriot Battery: a large boxy missile launcher tilted skyward with eight interceptor canisters, a phased-array radar panel, generator trailer.",
    # ---- Titan Systems ----
    "TS-B01": "the Titan Campus Core headquarters: a sleek low-slung glass-and-white-composite office block with a cantilevered upper floor, a rooftop drone pad, a holographic teal corporate logo, manicured entrance plaza.",
    "TS-B02": "the Supply Terminal: an automated logistics hub with robotic conveyor arms, a row of white cargo pods, an autonomous hauler docking bay, teal guide lights on the floor.",
    "TS-B03": "the Fusion Cell: a compact white cylindrical reactor housing with a teal-glowing torus window, cooling fins, thick shielded conduits, a small control kiosk.",
    "TS-B04": "the Security Academy: a modern training facility with a glass atrium, a rooftop shooting range canopy, a parade court with teal floor markings, corporate security banners.",
    "TS-B05": "the Vehicle Assembly: a clean white robotic assembly hall with a glass front showing robot arms building an SUV, a vehicle exit ramp, teal light strips.",
    "TS-B06": "the Heavy Fabricator: a large windowless white fabrication block with a giant sliding door, an overhead gantry crane, a tank chassis on a rail cart, teal warning lights.",
    "TS-B07": "the Precision Strike Battery: a rotating white missile pod on an armored turntable with a phased-array radar mast and a targeting laser, very clean lines.",
    "TS-B08": "the Drone Hangar: a wide flat building with a retractable roof half open revealing drone racks, a landing deck with teal landing lights, a control tower nub.",
    "TS-B09": "the Network Uplink: a tall slender white tower with a dish array and a glowing teal data spire on top, a small server annex at the base, compact.",
    "TS-B10": "the Executive Command Suite: a prestigious glass tower with a helipad, a panoramic boardroom floor, holographic teal displays visible through the glass, the tallest building.",
    "TS-B11": "the Service Bay: a glossy white automated maintenance bay with robotic arms on rails, a vehicle lift, a diagnostic screen wall, teal accents.",
    "TS-B12": "the Satellite Office: a compact modular white office pod on stilts with a satellite dish and a small drone pad, a teal signage panel, meant to deploy remotely.",
    "TS-D01": "the Composite Barrier: a short segment of sleek white composite wall with a teal light strip along the top, very small and low.",
    "TS-D02": "the Sentry Pylon: a slim white pylon with a rotating sensor head and a teal eye, a small gun pod, minimal footprint.",
    "TS-D03": "the Suppression Turret: a low white dome turret with a twin minigun and a sensor bar, teal status lights, compact.",
    "TS-D04": "the Rail Turret: a white angular turret with a long slender electromagnetic rail barrel and capacitor rings glowing teal, small base.",
    "TS-D05": "the Security Bunker: a smooth white armored bunker with slit windows of tinted glass, a teal-lit sliding door, rounded corners, heavy.",
    "TS-D06": "the Interceptor Pad: a small white launch pad with a rack of interceptor drones ready to lift off, a sensor mast, teal pad lights.",
    "TS-D07": "the Drone Denial Node: a small white dome with a ring of phased antenna panels and a jammer spike, teal light ring.",
    "TS-D08": "the Skyshield Array: a large white multi-panel radar array with four missile pods and a central command node, teal glow, the biggest defense.",
    # ---- The Signal ----
    "SG-B01": "the Signal Core headquarters: a towering asymmetric hub of fused captured machinery — tank hulls, server racks, satellite dishes — bound together by black crystal shards, orange-red light seams pulsing, antenna spines.",
    "SG-B02": "the Matter Reclaimer: a gaping maw-like intake structure where captured vehicles are dragged in on conveyor teeth, crystal-shard crushers, orange light glowing from within.",
    "SG-B03": "the Energy Siphon: a spiky cluster of black crystal spires around a stolen reactor core, arcs of orange-red energy between the tips, cables burrowing into the ground.",
    "SG-B04": "the Replication Pit: a sunken pit ringed with shard pillars where humanoid replicant frames stand in rows, orange-red light from below, machinery fused into the rim.",
    "SG-B05": "the Assembly Womb: a bulbous chamber built from fused vehicle parts and shards with a split opening where a half-built walker emerges, orange veins.",
    "SG-B06": "the Shard Forge: a heavy jagged foundry of black crystal with molten orange seams, a huge crystal growth chamber, captured tank parts embedded in it.",
    "SG-B07": "the Resonance Battery: an array of crystalline tuning-fork spires on a fused-machinery base, orange energy humming between them, a resonance dish.",
    "SG-B08": "the Spore Aerie: a shard-encrusted tower with pod-like openings where drone spores hang, orange glow inside each pod, antenna spines.",
    "SG-B09": "the Uplink Spire: a tall thin twisted spire of black crystal with a stolen satellite dish fused near the top and orange-red light running up its seams, small base.",
    "SG-B10": "the Overmind Node: a massive faceted black crystal core suspended in a cage of captured machinery, blazing orange-red light from within, the most alien structure.",
    "SG-B11": "the Reconstitution Pool: a shallow basin of glowing orange liquid-light ringed by shard pillars, damaged machines half submerged in it being rebuilt.",
    "SG-B12": "the Seed Node: a compact crystal seed pod half buried in the ground with a few shards sprouting and a single orange-red eye light, small.",
    "SG-D01": "the Shard Wall: a short row of jagged black crystal shards with orange light seams, very small and low.",
    "SG-D02": "the Watch Spire: a thin twisted crystal spike with a glowing orange sensor eye at the tip, minimal footprint.",
    "SG-D03": "the Flechette Node: a low bulbous shard cluster bristling with needle launchers, orange glow between the plates, compact.",
    "SG-D04": "the Lance Emplacement: a long crystal lance on a fused-machinery mount, orange energy charging along its length, small base.",
    "SG-D05": "the Husk Bunker: a captured armored vehicle hull half swallowed by black crystal and turned into a bunker with orange-lit firing slits.",
    "SG-D06": "the Sky Thorn: a tall thorn-like crystal spire with orange energy rings that fires upward at aircraft, slim.",
    "SG-D07": "the Static Bloom: a flower-like cluster of crystal petals around a stolen jammer dish, orange static arcing between petals, small.",
    "SG-D08": "the Reclaimer Cannon: a huge crystal-encrusted artillery cannon grown from a captured howitzer, orange-red seams, the biggest defense.",
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
        role = d.get("function") or ""
        prompt = PREFIX[a.faction] + DESC[sid] + (" Role: " + role + ". " if role else " ") + SUFFIX
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
