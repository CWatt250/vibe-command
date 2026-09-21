#!/usr/bin/env python3
"""Scaffold Titan Systems (TS) and The Signal (SG) structures.

The TS/SG Bible import (tools/import_ts_sg.py) was units only; structures.json has
no TS/SG buildings, so nothing can be built, trained or drawn for them. This mirrors
the 20 Federal Command slots 1:1 — same cost, build time, HP, footprint, class,
flags — with faction names and trainsUnits remapped to the faction's real units.
Every scaffolded def carries "draft": true; re-running the Bible importer (when the
docx turns up) should overwrite them. Idempotent: existing TS/SG ids are replaced.

    python3 tools/scaffold_ts_sg_structures.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "content", "data", "structures.json")

# slot -> (TS name, SG name). Slots are the FC ids' suffixes.
NAMES = {
    "B01": ("Titan Campus Core", "Signal Core"),
    "B02": ("Supply Terminal", "Matter Reclaimer"),
    "B03": ("Fusion Cell", "Energy Siphon"),
    "B04": ("Security Academy", "Replication Pit"),
    "B05": ("Vehicle Assembly", "Assembly Womb"),
    "B06": ("Heavy Fabricator", "Shard Forge"),
    "B07": ("Precision Strike Battery", "Resonance Battery"),
    "B08": ("Drone Hangar", "Spore Aerie"),
    "B09": ("Network Uplink", "Uplink Spire"),
    "B10": ("Executive Command Suite", "Overmind Node"),
    "B11": ("Service Bay", "Reconstitution Pool"),
    "B12": ("Satellite Office", "Seed Node"),
    "D01": ("Composite Barrier", "Shard Wall"),
    "D02": ("Sentry Pylon", "Watch Spire"),
    "D03": ("Suppression Turret", "Flechette Node"),
    "D04": ("Rail Turret", "Lance Emplacement"),
    "D05": ("Security Bunker", "Husk Bunker"),
    "D06": ("Interceptor Pad", "Sky Thorn"),
    "D07": ("Drone Denial Node", "Static Bloom"),
    "D08": ("Skyshield Array", "Reclaimer Cannon"),
}

# Which real units each production slot trains (FC's lists point at FC units).
TRAINS = {
    "TS": {"B04": ["TS-U01", "TS-U02", "TS-U06", "TS-U12"],
           "B05": ["TS-U04", "TS-U05", "TS-U08", "TS-U09"],
           "B06": ["TS-U07", "TS-U13"],
           "B07": [],
           "B08": ["TS-U03", "TS-U10", "TS-U11", "TS-U14"]},
    "SG": {"B04": ["SG-U04", "SG-U14"],
           "B05": ["SG-U01", "SG-U02", "SG-U05", "SG-U06", "SG-U07", "SG-U10"],
           "B06": ["SG-U08", "SG-U11", "SG-U12", "SG-U13"],
           "B07": [],
           "B08": ["SG-U09"]},
}
# Faction wording for the FC-specific function text.
REWORD = {
    "TS": [("Command Capacity", "Network Licenses"), ("truck", "hauler")],
    "SG": [("Command Capacity", "Signal Reach"), ("Harvester dropoff and truck production.", "Matter intake and Harvester assembly.")],
}


def main() -> None:
    data = json.load(open(PATH))
    structs = data["structures"]
    fc = {d["id"].split("-")[1]: d for d in structs if d["factionId"] == "FC"}
    kept = [d for d in structs if d["factionId"] not in ("TS", "SG")]
    added = []
    for fac, idx in (("TS", 0), ("SG", 1)):
        for slot, names in NAMES.items():
            src = fc[slot]
            d = json.loads(json.dumps(src))
            d["id"] = f"{fac}-{slot}"
            d["factionId"] = fac
            d["displayName"] = names[idx]
            fn = d.get("function") or ""
            for a, b in REWORD[fac]:
                fn = fn.replace(a, b)
            d["function"] = fn or None
            if "trainsUnits" in d:
                d["trainsUnits"] = TRAINS[fac].get(slot, [])
            d["draft"] = True
            d["draftNote"] = f"scaffolded from {src['id']} stats 2026-09-20; replace from the Bible"
            added.append(d)
    data["structures"] = kept + added
    json.dump(data, open(PATH, "w"), indent=2)
    print(f"structures: {len(kept)} kept + {len(added)} scaffolded = {len(data['structures'])}")


if __name__ == "__main__":
    main()
