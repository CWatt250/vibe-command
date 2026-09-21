#!/usr/bin/env python3
"""Pipeline B: unit portraits for the HUD (selection card + build/queue cameos).

    ~/AI_Agent/venv/bin/python tools/gen_portraits_ai.py VC [--only VC-U04,VC-U07] [--seed-bump N] [--force]

Full 3/4-view renders of each unit, all facing the same way (toward the viewer's lower-left) so
the cameo row reads as one set — and so they double as the reference sheet for the Blender pass.
Assumes ComfyUI is up on 127.0.0.1:8188; leaves it up. Output: docs/concepts/units/<fac>/<id>.png
(raw), assets/portraits/<id>.png (keyed, 256 wide), assets/portraits/manifest.json {id: file}.
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

PORTRAITS = os.path.join(ROOT, "assets", "portraits")
MANIFEST = os.path.join(PORTRAITS, "manifest.json")
UNITS = os.path.join(ROOT, "content", "data", "units.json")

VIEW = (
    "Game unit portrait for a 2D real-time strategy game: the whole unit, three-quarter view from "
    "slightly above, facing toward the viewer's lower-left, "
)
PREFIX = {
    "VC": VIEW + (
        "faction style: scrappy garage-tech built by hobbyist engineers — plywood and OSB armor "
        "panels, duct tape, zip ties, exposed consumer battery packs, mismatched wheels, PVC "
        "antennas, strapped-on laptops, cyan LED accents as the faction colour. "
    ),
    "FC": VIEW + (
        "faction style: conventional modern federal military — desert-tan and grey camouflage, "
        "real-world military hardware, tidy and functional, amber marker lights as the faction "
        "colour. "
    ),
    "TS": VIEW + (
        "faction style: premium corporate war machine — sleek white and graphite composite armor, "
        "brushed titanium, tinted visors, seamless panels, holographic teal light strips as the "
        "faction colour, immaculate. "
    ),
    "SG": VIEW + (
        "faction style: an assimilation intelligence built from stolen technology — machines made of "
        "captured hardware fused together and overgrown with black crystalline shards, seams of "
        "glowing orange-red light as the faction colour, asymmetric, unsettling, no faces, no flesh. "
    ),
}
# Aircraft get a prefix without the ground/armor/visor cues — those pull the model toward
# mechs and pilots. Selected when the def's componentFlags contain Aircraft or Air.
AIR_VIEW = (
    "Game unit portrait for a 2D real-time strategy game: a single unmanned aircraft alone in the "
    "air, three-quarter view from above, nose toward the viewer's lower-left, no pilot, no robot, "
    "no mech, no vehicle, no ground, "
)
PREFIX_AIR = {
    "VC": AIR_VIEW + "faction style: scrappy garage-built drone — plywood, duct tape, zip-tied battery packs, exposed wiring, cyan LED accents as the faction colour. ",
    "FC": AIR_VIEW + "faction style: modern federal military aircraft — grey and tan camouflage, real-world hardware, amber marker lights as the faction colour. ",
    "TS": AIR_VIEW + "faction style: premium corporate aircraft — sleek white and graphite composite, seamless panels, holographic teal light strips as the faction colour. ",
    "SG": AIR_VIEW + "faction style: a flying machine of captured hardware fused with black crystal shards, orange-red light seams as the faction colour. ",
}
SUFFIX = (
    "Exaggerated chunky proportions, big readable silhouette, hand-painted stylized look like "
    "Warcraft 3, hard sunlight from the upper left. Centered and filling the frame, isolated on a "
    "flat solid bright magenta background, no ground, no scenery, no text, no watermark."
)

DESC = {
    # ---- Vibe Coder ----
    "VC-SRV": "the Salvage Rig: a beat-up flatbed truck with a scrap-grabbing crane claw and a magnet, piled with salvaged metal, plywood cab armor.",
    "VC-U01": "the Maker Crew: one hobbyist engineer in a hoodie and work apron with a tool belt, safety goggles on the forehead, carrying a cordless drill and a laptop bag, a small drone clipped to the backpack.",
    "VC-U02": "the Scout Quad: a consumer quadcopter drone with a GoPro-style camera, zip-tied battery pack, cyan LED arms, hovering.",
    "VC-U03": "the FPV Strike Drone: a racing FPV quadcopter with a taped-on explosive charge and a wire antenna, aggressive and fast, hovering.",
    "VC-U04": "the Technical: a pickup truck with plywood armor panels and a machine gun bolted to a welded frame in the bed, extra batteries, a laptop on the dash.",
    "VC-U05": "the Bot Dog: a quadruped robot dog with 3D-printed panels, a small gun mounted on its back, cyan eye sensor, cables visible.",
    "VC-U06": "the Sentry Bot: a squat tracked robot with a rotating turret, webcam sights, a stack of battery cells, plywood side skirts.",
    "VC-U07": "the Hack Van: a cargo van covered in antennas, satellite dishes and a rooftop server rack, cyan-lit windows, electronic warfare vehicle.",
    "VC-U08": "the Crawler: a low wide six-wheeled robot rover with a boxy plywood-armored body and a mortar tube, cameras on stalks.",
    "VC-U09": "the Swarm Carrier: a box truck with its roof open showing racks of small drones ready to launch, antennas, cyan lights.",
    "VC-U10": "the Atlas Bot: a bulky bipedal humanoid robot with exposed hydraulics, scavenged plate armor, a heavy rifle, a cyan visor.",
    "VC-U11": "the Hunter Drone: a large fixed-wing combat drone with a missile under each wing and a sensor ball, cyan running lights, flying.",
    "VC-U12": "the AI Battle Tank: a tracked tank built from a scrapped bulldozer chassis with a homemade turret, welded scrap armor, a sensor mast and a cyan status light.",
    "VC-U13": "the Drone Mothership: a large blimp-like airship with a gondola full of drone launch racks and antennas, cyan lights, flying.",
    "VC-U14": "the Titan Rig: a colossal mining truck converted into a rolling fortress with multiple turrets, scrap armor plates, a crane, an antenna forest.",
    # ---- Federal Command ----
    "FC-SRV": "the Harvester Truck: a military dump truck with a scoop conveyor arm, tan camouflage, amber marker lights.",
    "FC-U01": "the Rifle Squad: one modern infantry soldier in full tan combat gear, helmet with goggles, body armor, assault rifle, kneeling ready.",
    "FC-U02": "the Combat Engineer: a soldier in tan gear with a large tool backpack, a welding torch, a mine detector, and a hard hat over the helmet.",
    "FC-U03": "the Javelin Team: a soldier in tan gear shouldering a Javelin anti-tank missile launcher with its command unit, spare missile tube on the back.",
    "FC-U04": "the Heavy Gunner Team: a soldier in tan gear braced behind a bipod-mounted heavy machine gun with an ammo belt, sandbag.",
    "FC-U05": "the Humvee: a tan military Humvee with a roof-mounted machine gun turret and a whip antenna.",
    "FC-U06": "the IFV: a tan eight-wheeled infantry fighting vehicle with an autocannon turret and rear troop ramp.",
    "FC-U07": "the M1X Main Battle Tank: a tan modern main battle tank with reactive armor blocks, a long cannon, commander's machine gun.",
    "FC-U08": "the Mobile AA: a tan tracked anti-aircraft vehicle with twin rotary cannons and a rotating radar dish.",
    "FC-U09": "the Self-Propelled Artillery: a tan tracked howitzer with a long elevated barrel and a rear spade.",
    "FC-U10": "the MLRS Battery: a tan tracked multiple-launch rocket system with its rocket pod raised.",
    "FC-U11": "the Blackhawk Transport: a grey military transport helicopter with side doors open and a door gunner, flying.",
    "FC-U12": "the Apache Gunship: a grey attack helicopter with stub-wing missile pods and a chin cannon, flying.",
    "FC-U13": "the Fighter: a grey multirole jet fighter with missiles under the wings, banking, flying.",
    "FC-U14": "the Special Operations Team: an elite operator in dark tactical gear with night-vision goggles, suppressed carbine, comms headset.",
    # ---- Titan Systems ----
    "TS-U01": "the Corporate Security Team: a private security operator in a sleek white-and-graphite tactical uniform with a tinted visor helmet, compact carbine, teal shoulder light.",
    "TS-U02": "the Combat Technician: a technician in a white composite exo-vest with a diagnostic wrist screen, a repair drone hovering beside, a toolkit backpack, teal lights.",
    "TS-U03": "the Recon Drone: ONLY a small unmanned aircraft, nothing else in frame — a sleek white delta-wing surveillance drone with a teal sensor eye underneath, hovering in the air. No robot, no mech, no person, no ground vehicle.",
    "TS-U04": "the Security SUV: a white armored luxury SUV with graphite trim, a roof sensor bar and a discreet gun pod, teal light strip.",
    "TS-U05": "the Sentinel APC: a white six-wheeled armored personnel carrier with angular composite armor, an active-protection sensor ring, a remote turret, teal lights.",
    "TS-U06": "the Exosuit Trooper: a soldier in a full white powered exosuit with graphite joints, a heavy shotgun, a teal visor.",
    "TS-U07": "the Paladin Tank: a sleek white main battle tank with a low angular turret, a long cannon, seamless composite armor, teal status lights.",
    "TS-U08": "the Rail Hunter: a white wheeled tank destroyer with a long thin railgun barrel and teal capacitor rings.",
    "TS-U09": "the Aegis EW Vehicle: a white armored vehicle with a large phased-array radar panel and a dome of antennas, teal glow.",
    "TS-U10": "the Autonomous Gunship: a white pilotless gunship with tilt-rotor engines, a chin cannon and missile pods, teal lights, flying.",
    "TS-U11": "the Interceptor Drone Wing: ONLY three small unmanned white jet drones flying in a tight arrowhead formation, teal engine glow, seen from above. No robot, no mech, no person, no ground vehicle.",
    "TS-U12": "the Heavy Exoskeleton: a tall bipedal walking weapons frame with a pilot inside a white armored cage, twin cannons on the arms, teal lights.",
    "TS-U13": "the Prototype Mech: a large white bipedal combat mech with modular weapon pods on the shoulders and a glowing teal core.",
    "TS-U14": "the Skyhook Command Craft: ONLY a large unmanned aircraft — a white flying-wing command plane with a bulbous sensor dome on its back and teal light strips along the wings, in flight, seen from above. No robot, no mech, no person.",
    # ---- The Signal ----
    "SG-U01": "the Skitter: a tiny fast six-legged machine made of scrap and black crystal with an orange eye and blade forelimbs.",
    "SG-U02": "the Watcher: a small hovering sensor machine, a black crystal disc with a large orange lens eye and antenna spines.",
    "SG-U03": "the Harvester: a crawling machine with a wide crystal-toothed intake maw at the front and a cargo hull, orange seams.",
    "SG-U04": "the Replicant: a humanoid machine built from stolen exoskeleton parts overgrown with black crystal, an orange glowing chest core, a fused arm cannon, no face.",
    "SG-U05": "the Stalker: a sleek four-legged predator machine, low and fast, black crystal plating, an orange light seam along the spine.",
    "SG-U06": "the Assimilator: a tracked machine with a crystal drill arm and a captured-vehicle hull, orange energy at the drill tip.",
    "SG-U07": "the Walker: a four-legged combat platform with a captured turret fused on top and crystal-plated legs, orange seams.",
    "SG-U08": "the Shard Tank: a heavy tank hull swallowed by black crystal growths, its cannon replaced by a crystal lance, orange glow.",
    "SG-U09": "the Spore Drone: a floating black crystal pod with hanging spines trailing orange mist, flying.",
    "SG-U10": "the Seeder: a bulky tracked machine carrying a giant black crystal seed on its back, orange veins, construction unit.",
    "SG-U11": "the Reclaimer: a long heavy machine with a huge crystal dismantling beam emitter on its back, orange energy charging.",
    "SG-U12": "the Swarm Host: a large crawling hive machine with open pods on its back from which small skitter machines emerge, orange glow.",
    "SG-U13": "the Leviathan: a colossal walking machine made of many captured vehicles fused into a crystal-encrusted body, siege cannons, orange light seams, the biggest unit.",
    "SG-U14": "the Echo: a humanoid machine of shifting black crystal facets that mimic other units, a single orange light where a face would be.",
}


def seed_for(uid: str, bump: int) -> int:
    return int(hashlib.md5(f"portrait:{uid}:{bump}".encode()).hexdigest()[:7], 16)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("faction")
    ap.add_argument("--only", default="")
    ap.add_argument("--seed-bump", type=int, default=0)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--steps", type=int, default=22)
    a = ap.parse_args()

    defs = [d for d in json.load(open(UNITS))["units"] if d["factionId"] == a.faction]
    only = {s.strip() for s in a.only.split(",") if s.strip()}
    raw_dir = os.path.join(ROOT, "docs", "concepts", "units", a.faction.lower())
    os.makedirs(raw_dir, exist_ok=True)
    os.makedirs(PORTRAITS, exist_ok=True)

    deadline = time.time() + 240
    while not cq._up() and time.time() < deadline:
        time.sleep(3)
    if not cq._up():
        sys.exit("COMFY_NOT_UP")

    manifest = json.load(open(MANIFEST)) if os.path.exists(MANIFEST) else {}
    done = 0
    for d in defs:
        uid = d["id"]
        if only and uid not in only:
            continue
        if uid not in DESC:
            print("SKIP no description:", uid, flush=True)
            continue
        raw = os.path.join(raw_dir, f"{uid}.png")
        if os.path.exists(raw) and not a.force:
            print("SKIP exists:", uid, flush=True)
            continue
        flags = d.get("componentFlags", [])
        is_air = "Aircraft" in flags or "Air" in flags
        prompt = (PREFIX_AIR if is_air else PREFIX)[a.faction] + DESC[uid] + " " + SUFFIX
        r = cq.generate(prompt, steps=a.steps, seed=seed_for(uid, a.seed_bump),
                        width=1024, height=1024, filename=f"portrait_{uid}")
        print(uid, json.dumps({k: r[k] for k in ("ok", "seconds", "seed", "error")}), flush=True)
        if not r["ok"]:
            continue
        os.replace(r["path"], raw)
        out = os.path.join(PORTRAITS, f"{uid}.png")
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "ai_sprite_prep.py"),
                        raw, out, "--width", "256"], check=True)
        manifest[uid] = f"{uid}.png"
        json.dump(manifest, open(MANIFEST, "w"), indent=1, sort_keys=True)
        done += 1
    print("DONE", done, "portraits", flush=True)


if __name__ == "__main__":
    main()
