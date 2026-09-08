#!/usr/bin/env python3
"""Import the Titan Systems (TS) and The Signal (SG) unit rosters from the
Faction/Unit/Structure Bible into content JSON.

Source of truth:
  Vibe_Command_Faction_Unit_Structure_Bible.docx  (CONTENT-002, Draft 0.1)

Scope: UNITS ONLY. Structures/defenses for TS and SG are not in this pass --
the bible structure tables carry a free-text class column that does not parse
mechanically, and they are not needed for the VC vs FC vertical slice.

What the bible pins (used verbatim): id, displayName, techTier, type, cost,
build time, armor class, and the abilities cell.
What the bible does NOT pin (health, vision, detection, move profile,
population, weapon slots) is derived from the shipped content scale per
Blueprint section 12 and recorded in BANDS below.

Idempotent: existing IDs are skipped.
"""
import json
import os
import re
import sys

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "content", "data")
BIBLE = "/tmp/bible.txt"

# Derived stat bands, keyed by armor class. Mirrors the shipped VC/FC scale
# (see tools/import_bible_content.py DERIVED_NOTES).
BANDS = {
    "Infantry":      dict(hp=130, vis=210, det=105, prof="prof_infantry",       pop=1, sel=3, wpn=["wpn_small_arms"],  flags=["Infantry", "Garrisonable"]),
    "HeavyInfantry": dict(hp=600, vis=280, det=140, prof="prof_infantry",       pop=3, sel=6, wpn=["wpn_autocannon"],  flags=["Infantry"]),
    "Light":         dict(hp=240, vis=255, det=128, prof="prof_vehicle_fast",   pop=2, sel=4, wpn=["wpn_small_arms"],  flags=["Vehicle"]),
    "Medium":        dict(hp=350, vis=270, det=135, prof="prof_vehicle",        pop=2, sel=5, wpn=["wpn_autocannon"],  flags=["Vehicle"]),
    "Heavy":         dict(hp=590, vis=280, det=140, prof="prof_vehicle_heavy",  pop=3, sel=6, wpn=["wpn_anti_armor"],  flags=["Vehicle"]),
    "AirLight":      dict(hp=65,  vis=275, det=140, prof="prof_air_fast",       pop=0, sel=3, wpn=["wpn_small_arms"],  flags=["Aircraft"]),
    "AirHeavy":      dict(hp=420, vis=320, det=160, prof="prof_air",            pop=3, sel=6, wpn=["wpn_anti_armor"],  flags=["Aircraft"]),
}
HARVESTER = dict(hp=330, vis=220, det=110, prof="prof_vehicle", pop=2, sel=2,
                 wpn=[], flags=["Harvester"])
EPIC_WEAPONS = ["wpn_energy_beam", "wpn_explosive"]

ARMOR_MAP = {"Heavy Infantry": "HeavyInfantry", "Air-Light": "AirLight",
             "Air-Heavy": "AirHeavy", "Light": "Light", "Medium": "Medium",
             "Heavy": "Heavy", "Infantry": "Infantry"}

# The bible's armor column, longest-first so "Heavy Infantry" beats "Infantry".
ARMOR_TOKENS = ["Heavy Infantry", "Air-Heavy", "Air-Light", "Infantry",
                "Light", "Medium", "Heavy"]

UNIT_RE = re.compile(
    r'((?:VC|FC|TS|SG)-U\d\d)\s+(.+?)\s+T(\d)\s+(.+?)\s+(\d+)\s+(\d+)\s+(.+?)\s+('
    + "|".join(re.escape(a) for a in ARMOR_TOKENS) + r')(?=\s|$)')


def _ability_id(text):
    s = re.sub(r'[^a-z0-9]+', '_', text.strip().lower()).strip('_')
    return "ability_" + s if s else ""


def parse_units(text, prefix):
    """Return the bible's unit rows for one faction prefix (TS or SG)."""
    out = []
    for m in UNIT_RE.finditer(text):
        uid, name, tier, typ, cost, time, mid, armor = m.groups()
        if not uid.startswith(prefix + "-"):
            continue
        # The bible's cell is "role sentence(s). Ability; Ability". The ability
        # list starts after the last sentence period.
        cut = mid.rfind(". ")
        if cut == -1:
            role, abil_text = mid.strip(), ""
        else:
            role, abil_text = mid[:cut + 1].strip(), mid[cut + 2:].strip()
        abilities = [_ability_id(a) for a in abil_text.split(";") if a.strip()]
        out.append(dict(id=uid, name=name.strip(), tier=int(tier), type=typ.strip(),
                        cost=int(cost), buildTime=float(time), armor=armor,
                        role=role, abilities=abilities))
    return out


def derive(row):
    """Fill the fields the bible does not pin, from the shipped scale."""
    armor = ARMOR_MAP[row["armor"]]
    is_harv = row["type"].lower() in ("economy",) or "harvester" in row["name"].lower()
    band = HARVESTER if is_harv else BANDS[armor]
    wpn = list(band["wpn"])
    if row["type"].lower() in ("scout", "drone") and "sensor" in row["role"].lower():
        # bible: "no serious weapon" / sensor platform only
        wpn = []
    elif row["type"].lower() == "epic":
        wpn = list(EPIC_WEAPONS)
    elif row["type"].lower() in ("siege", "tank destroyer"):
        wpn = ["wpn_anti_armor"] if row["type"].lower() == "tank destroyer" else ["wpn_explosive"]
    elif row["type"].lower() in ("air", "aircraft", "air support", "drone") and armor.startswith("Air"):
        wpn = ["wpn_anti_armor"] if armor == "AirHeavy" else ["wpn_small_arms"]
    out = {
        "id": row["id"], "displayName": row["name"],
        "factionId": row["id"][:2], "techTier": row["tier"],
        "costCredits": row["cost"], "buildTimeSec": row["buildTime"],
        "reserveCapacity": 4 if row["type"].lower() == "epic" else (2 if "Vehicle" in band["flags"] else 0),
        "maxHealth": 1100 if row["type"].lower() == "epic" else band["hp"],
        "armorClass": armor, "moveProfileId": band["prof"],
        "visionRadius": band["vis"], "detectionRadius": band["det"],
        "weaponSlots": wpn, "abilityIds": row["abilities"],
        "componentFlags": list(band["flags"]),
        "populationWeight": 5 if row["type"].lower() == "epic" else band["pop"],
        "wreckDefinitionId": None,
        "selectionPriority": 8 if row["type"].lower() == "epic" else band["sel"],
        "bibleRole": "T%d %s" % (row["tier"], row["type"]),
        "bibleText": row["role"],
    }
    if is_harv:
        out["harvest"] = True
        out["harvestCapacity"] = 500.0
        out["harvestRatePerSec"] = 60.0
        out["harvestRadius"] = 45.0
        out["depositRadius"] = 70.0
    return out


FACTION_DEFS = {
    "TS": dict(displayName="Titan Systems", color="2fa8a0",
               resourceIds=["credits", "power", "network"], startCredits=1500,
               harvesterUnitId=None, builderUnitId="TS-U02",
               defenseTag="corporate", techTiers=3,
               desc="Premium corporate war machine. Network Licenses gate elite production."),
    "SG": dict(displayName="The Signal", color="d6532e",
               resourceIds=["credits", "energy", "assimilation"], startCredits=1500,
               harvesterUnitId="SG-U03", builderUnitId="SG-U10",
               defenseTag="assimilated", techTiers=3,
               desc="Assimilation Intelligence built from stolen technology. Matter and Energy in place of credits and power."),
}


def main():
    if not os.path.exists(BIBLE):
        sys.exit("missing %s -- extract the bible docx first" % BIBLE)
    text = open(BIBLE).read()

    up = os.path.join(BASE, "units.json")
    fp = os.path.join(BASE, "factions.json")
    units_doc = json.load(open(up))
    factions_doc = json.load(open(fp))
    units = units_doc["units"]
    factions = factions_doc["factions"]
    have = {u["id"] for u in units}

    added, refreshed = [], []
    refresh = os.environ.get("REFRESH") == "1"
    for prefix in ("TS", "SG"):
        rows = parse_units(text, prefix)
        if len(rows) != 14:
            sys.exit("expected 14 %s units in the bible, parsed %d" % (prefix, len(rows)))
        for row in rows:
            new = derive(row)
            if row["id"] in have:
                if refresh:
                    for i, u in enumerate(units):
                        if u["id"] == row["id"]:
                            units[i] = new
                            refreshed.append(row["id"])
                            break
                continue
            units.append(new)
            added.append(row["id"])

    have_f = {f["id"] for f in factions}
    for fid, defn in FACTION_DEFS.items():
        if fid not in have_f:
            entry = {"id": fid}
            entry.update(defn)
            factions.append(entry)

    units.sort(key=lambda x: (x["factionId"], x["id"]))
    factions.sort(key=lambda x: x["id"])
    json.dump(units_doc, open(up, "w"), indent=2)
    open(up, "a").write("\n")
    json.dump(factions_doc, open(fp, "w"), indent=2)
    open(fp, "a").write("\n")

    print("units added (%d): %s" % (len(added), added))
    print("units refreshed (%d): %s" % (len(refreshed), refreshed))
    print("factions: %s" % [f["id"] for f in factions])
    print("totals: units=%d" % len(units))


if __name__ == "__main__":
    main()
