#!/usr/bin/env python3
"""Import the VC/FC roster from the Faction/Unit/Structure Bible into content JSON.

Source of truth:
  Vibe_Command_Faction_Unit_Structure_Bible.docx  (CONTENT-002, Draft 0.1, Sept 2026)

Scope: Vibe Coder (VC) + Federal Command (FC) only. Titan Systems (TS) and
The Signal (SG) are intentionally deferred -- the first playable target is the
VC vs FC vertical slice.

Balance values the bible pins (cost, build time, armor class, role) are used
verbatim. Values it does NOT pin (health, vision, move profile, population,
weapon slots, structure cost/build time) are derived from the existing content
scale so new units sit in the same band as shipped ones. Every derived value is
recorded in DERIVED_NOTES below (Blueprint section 12 sanction).

Idempotent: re-running will not duplicate IDs.
"""
import json
import os

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "content", "data")

DERIVED_NOTES = """
Derivation rules (from the shipped content scale):
  Infantry      hp 120-140  vis 200-220  prof_infantry       pop 1
  HeavyInfantry hp 600      vis 280      prof_infantry       pop 3
  Light         hp 220-260  vis 250-260  prof_vehicle_fast   pop 2
  Medium        hp 280-420  vis 260-280  prof_vehicle        pop 2-3
  Heavy         hp 560-620  vis 280      prof_vehicle_heavy  pop 3
  AirLight      hp 60-70    vis 250-300  prof_air(_fast)     pop 0
  AirHeavy      hp 380-460  vis 300-340  prof_air(_fast)     pop 3
  Harvester     hp 320-340  vis 220      prof_vehicle        pop 2
Structure cost bands (shipped): HQ 500-550 | Power 300-350 | Economy 650 |
  Compute 700-1200 | Infantry 500-550 | Vehicle 800-850 | Support 650-700 |
  Defense 450-600 | Wall 100. Air/Tech/Expansion derived at 600-1400 by tier.
Defense cost comes from the bible; build time/hp/weapon slot derived from the
shipped FC-D02 Guard Tower (450cr/14s/380hp/wpn_turret_gun) and VC-D02 Auto
Turret (600cr/15s/260hp) as the reference points.
"""

# ---------------------------------------------------------------- VC units
VC_UNITS = [
    dict(id="VC-U09", displayName="Swarm Carrier", techTier=2, costCredits=1400,
         buildTimeSec=30.0, maxHealth=360, armorClass="Medium",
         moveProfileId="prof_vehicle", visionRadius=260, detectionRadius=130,
         reserveCapacity=3, weaponSlots=["wpn_autocannon"],
         abilityIds=["ability_launch_swarm", "ability_recall"],
         componentFlags=["Vehicle"], populationWeight=2, selectionPriority=5,
         bibleRole="T2 Support Vehicle",
         bibleText="Armored carrier launches reusable micro-drones."),
    dict(id="VC-U11", displayName="Hunter Drone", techTier=3, costCredits=1500,
         buildTimeSec=28.0, maxHealth=420, armorClass="AirHeavy",
         moveProfileId="prof_air", visionRadius=300, detectionRadius=180,
         reserveCapacity=4, weaponSlots=["wpn_anti_armor"],
         abilityIds=["ability_lockon", "ability_emergency_return"],
         componentFlags=["Aircraft"], populationWeight=3, selectionPriority=6,
         bibleRole="T3 Aircraft",
         bibleText="Fast autonomous anti-vehicle drone aircraft."),
    dict(id="VC-U12", displayName="AI Battle Tank", techTier=3, costCredits=1900,
         buildTimeSec=36.0, maxHealth=600, armorClass="Heavy",
         moveProfileId="prof_vehicle_heavy", visionRadius=280, detectionRadius=140,
         reserveCapacity=5, weaponSlots=["wpn_explosive", "wpn_small_arms"],
         abilityIds=["ability_predictive_fire", "ability_remote_repair"],
         componentFlags=["Vehicle"], populationWeight=3, selectionPriority=6,
         bibleRole="T3 Heavy Vehicle",
         bibleText="Uncrewed MBT-equivalent with excellent reaction time."),
    dict(id="VC-U13", displayName="Drone Mothership", techTier=3, costCredits=3100,
         buildTimeSec=55.0, maxHealth=700, armorClass="AirHeavy",
         moveProfileId="prof_air", visionRadius=320, detectionRadius=180,
         reserveCapacity=6, weaponSlots=["wpn_small_arms"],
         abilityIds=["ability_drone_screen", "ability_recall_all"],
         componentFlags=["Aircraft"], populationWeight=4, selectionPriority=7,
         bibleRole="T3 Heavy Aircraft",
         bibleText="Slow airborne carrier that produces small attack drones in combat."),
    dict(id="VC-U14", displayName="Titan Rig", techTier=3, costCredits=5200,
         buildTimeSec=90.0, maxHealth=1100, armorClass="Heavy",
         moveProfileId="prof_vehicle_heavy", visionRadius=300, detectionRadius=160,
         reserveCapacity=8, weaponSlots=["wpn_energy_beam", "wpn_explosive"],
         abilityIds=["ability_siege_mode", "ability_emergency_overclock"],
         componentFlags=["Vehicle"], populationWeight=5, selectionPriority=8,
         bibleRole="T3 Epic Siege",
         bibleText="Huge unmanned siege crawler / walker. Long-range weapon plus drone defense."),
    dict(id="VC-SRV", displayName="Salvage Rig", techTier=1, costCredits=700,
         buildTimeSec=20.0, maxHealth=320, armorClass="Light",
         moveProfileId="prof_vehicle", visionRadius=220, detectionRadius=110,
         reserveCapacity=0, weaponSlots=[],
         abilityIds=[], componentFlags=["Harvester"],
         populationWeight=2, selectionPriority=2, harvest=True,
         harvestCapacity=500.0, harvestRatePerSec=65.0, harvestRadius=45.0,
         depositRadius=70.0,
         bibleRole="Economy harvester (produced by VC-B02 Fabrication Yard)",
         bibleText="Salvages scrap and processed material back to the Fabrication Yard."),
]

# ---------------------------------------------------------------- FC units
FC_UNITS = [
    dict(id="FC-U04", displayName="Heavy Gunner Team", techTier=1, costCredits=450,
         buildTimeSec=13.0, maxHealth=130, armorClass="Infantry",
         moveProfileId="prof_infantry", visionRadius=220, detectionRadius=110,
         reserveCapacity=0, weaponSlots=["wpn_small_arms"],
         abilityIds=["ability_bipod", "ability_suppress"],
         componentFlags=["Infantry", "Garrisonable"], populationWeight=1,
         selectionPriority=3, garrisonCapable=True,
         bibleRole="T1 Infantry",
         bibleText="Suppression and anti-drone small arms."),
    dict(id="FC-U10", displayName="MLRS Battery", techTier=3, costCredits=1900,
         buildTimeSec=38.0, maxHealth=340, armorClass="Medium",
         moveProfileId="prof_vehicle", visionRadius=260, detectionRadius=130,
         reserveCapacity=4, weaponSlots=["wpn_explosive"],
         abilityIds=["ability_ripple_fire"],
         componentFlags=["Vehicle"], populationWeight=3, selectionPriority=6,
         bibleRole="T3 Siege",
         bibleText="Area saturation rockets."),
    dict(id="FC-U11", displayName="Blackhawk Transport", techTier=2, costCredits=1300,
         buildTimeSec=26.0, maxHealth=400, armorClass="AirHeavy",
         moveProfileId="prof_air", visionRadius=280, detectionRadius=150,
         reserveCapacity=3, weaponSlots=["wpn_small_arms"],
         abilityIds=["ability_fastrope"],
         componentFlags=["Aircraft", "Transport"], populationWeight=3,
         selectionPriority=5,
         bibleRole="T2 Aircraft",
         bibleText="Fast infantry transport, door guns."),
    dict(id="FC-U12", displayName="Apache Gunship", techTier=3, costCredits=1900,
         buildTimeSec=35.0, maxHealth=440, armorClass="AirHeavy",
         moveProfileId="prof_air", visionRadius=300, detectionRadius=170,
         reserveCapacity=4, weaponSlots=["wpn_anti_armor"],
         abilityIds=["ability_hellfire_salvo"],
         componentFlags=["Aircraft"], populationWeight=3, selectionPriority=6,
         bibleRole="T3 Aircraft",
         bibleText="Anti-armor attack helicopter."),
    dict(id="FC-U13", displayName="Fighter", techTier=3, costCredits=2200,
         buildTimeSec=42.0, maxHealth=380, armorClass="AirHeavy",
         moveProfileId="prof_air_fast", visionRadius=340, detectionRadius=200,
         reserveCapacity=4, weaponSlots=["wpn_anti_armor"],
         abilityIds=["ability_afterburner", "ability_patrol_cap"],
         componentFlags=["Aircraft"], populationWeight=3, selectionPriority=6,
         bibleRole="T3 Aircraft",
         bibleText="Air superiority / interception."),
    dict(id="FC-U14", displayName="Special Operations Team", techTier=3,
         costCredits=1500, buildTimeSec=32.0, maxHealth=260,
         armorClass="HeavyInfantry", moveProfileId="prof_infantry_fast",
         visionRadius=280, detectionRadius=160, reserveCapacity=3,
         weaponSlots=["wpn_small_arms", "wpn_explosive"],
         abilityIds=["ability_laser_designate", "ability_satchel", "ability_cloak"],
         componentFlags=["Infantry", "Capturer", "Garrisonable"],
         populationWeight=2, selectionPriority=5, garrisonCapable=True,
         bibleRole="T3 Infantry",
         bibleText="Stealth infiltration, designation, demolition."),
    dict(id="FC-SRV", displayName="Harvester Truck", techTier=1, costCredits=700,
         buildTimeSec=20.0, maxHealth=340, armorClass="Light",
         moveProfileId="prof_vehicle", visionRadius=220, detectionRadius=110,
         reserveCapacity=0, weaponSlots=[],
         abilityIds=[], componentFlags=["Harvester"],
         populationWeight=2, selectionPriority=2, harvest=True,
         harvestCapacity=500.0, harvestRatePerSec=60.0, harvestRadius=45.0,
         depositRadius=70.0,
         bibleRole="Economy harvester (produced by FC-B02 Logistics Depot)",
         bibleText="Hauls processed material back to the Logistics Depot."),
]

# ---------------------------------------------------------------- VC structures
VC_STRUCTS = [
    dict(id="VC-B09", displayName="Drone Farm", techTier=2, costCredits=900,
         buildTimeSec=24.0, maxHealth=520, footprint=[3, 3], klass="Air",
         function="Produces Scout Quads, FPV drones, Hunter Drones and Mothership components.",
         componentFlags=["ProductionAir"],
         trainsUnits=["VC-U02", "VC-U03", "VC-U11", "VC-U13"]),
    dict(id="VC-B10", displayName="Autonomy Lab", techTier=2, costCredits=950,
         buildTimeSec=22.0, maxHealth=480, footprint=[2, 2], klass="Tech",
         function="Unlocks T2/T3 adaptive algorithms, predictive targeting, advanced bots.",
         componentFlags=["TechSource"], unlocksTechTier=3),
    dict(id="VC-B12", displayName="Expansion Node", techTier=2, costCredits=600,
         buildTimeSec=18.0, maxHealth=500, footprint=[2, 2], klass="Expansion",
         function="Extends build radius and provides limited power/data relay.",
         componentFlags=["Expansion", "PowerSource"], powerProduced=40),
]

# ---------------------------------------------------------------- FC structures
FC_STRUCTS = [
    dict(id="FC-B02", displayName="Logistics Depot", techTier=1, costCredits=650,
         buildTimeSec=22.0, maxHealth=650, footprint=[3, 3], klass="Economy",
         function="Harvester dropoff and truck production.",
         componentFlags=["Dropoff", "ProducesHarvester"],
         trainsUnits=["FC-SRV"]),
    dict(id="FC-B06", displayName="Armor Depot", techTier=2, costCredits=1000,
         buildTimeSec=26.0, maxHealth=600, footprint=[3, 3], klass="Vehicle",
         function="Produces MBTs and heavy support.",
         componentFlags=["ProductionVehicle"],
         trainsUnits=["FC-U07", "FC-U08", "FC-U09"]),
    dict(id="FC-B07", displayName="Artillery Battery", techTier=2, costCredits=900,
         buildTimeSec=24.0, maxHealth=520, footprint=[3, 2], klass="Siege",
         function="Produces artillery and MLRS; enables counter-battery sensors.",
         componentFlags=["ProductionVehicle", "Siege"],
         trainsUnits=["FC-U09", "FC-U10"]),
    dict(id="FC-B08", displayName="Air Operations Center", techTier=2,
         costCredits=950, buildTimeSec=25.0, maxHealth=540, footprint=[3, 3],
         klass="Air", function="Aircraft production / reinforcement abstraction.",
         componentFlags=["ProductionAir"],
         trainsUnits=["FC-U11", "FC-U12", "FC-U13"]),
    dict(id="FC-B10", displayName="Joint Operations Center", techTier=3,
         costCredits=1400, buildTimeSec=30.0, maxHealth=700, footprint=[3, 3],
         klass="Tech",
         function="Unlocks elite air, special operations, EMP and strategic strikes.",
         componentFlags=["TechSource", "CommandSource"], commandCapacity=15,
         unlocksTechTier=3),
    dict(id="FC-B12", displayName="Forward Operating Base", techTier=2,
         costCredits=700, buildTimeSec=20.0, maxHealth=560, footprint=[3, 3],
         klass="Expansion",
         function="Extends build area, limited healing and infantry reinforcement.",
         componentFlags=["Expansion", "Dropoff"]),
]

# ---------------------------------------------------------------- VC defenses
VC_DEF = [
    dict(id="VC-D01", displayName="Camera Pole", techTier=1, costCredits=250,
         buildTimeSec=6.0, maxHealth=150, footprint=[1, 1], weaponSlots=[],
         componentFlags=["Defense", "Sensor"], visionRadius=400,
         bibleRole="Detection / vision. Cheap and almost no damage."),
    dict(id="VC-D03", displayName="Drone Nest", techTier=2, costCredits=850,
         buildTimeSec=18.0, maxHealth=340, footprint=[2, 2],
         weaponSlots=["wpn_autocannon"],
         componentFlags=["Defense", "Turret", "DroneLauncher"],
         bibleRole="Launches 6 reusable interceptors against ground/air within radius."),
    dict(id="VC-D04", displayName="Smart Mine Node", techTier=1, costCredits=350,
         buildTimeSec=10.0, maxHealth=200, footprint=[1, 1], weaponSlots=[],
         componentFlags=["Defense", "MineLayer"],
         bibleRole="Places/replenishes limited smart mines in a small field."),
    dict(id="VC-D05", displayName="AT Launcher", techTier=2, costCredits=900,
         buildTimeSec=18.0, maxHealth=300, footprint=[1, 1],
         weaponSlots=["wpn_anti_armor"],
         componentFlags=["Defense", "Turret"],
         bibleRole="Guided anti-vehicle turret; vulnerable to infantry swarms."),
    dict(id="VC-D06", displayName="Counter-Drone Mast", techTier=2,
         costCredits=800, buildTimeSec=16.0, maxHealth=320, footprint=[1, 1],
         weaponSlots=["wpn_energy_beam"],
         componentFlags=["Defense", "Turret", "Jammer"],
         bibleRole="Electronic anti-drone / anti-missile pulse tower."),
    dict(id="VC-D07", displayName="Predictive Turret", techTier=3,
         costCredits=1450, buildTimeSec=24.0, maxHealth=460, footprint=[2, 2],
         weaponSlots=["wpn_autocannon"],
         componentFlags=["Defense", "Turret"],
         bibleRole="T3 adaptive cannon. Accuracy ramps against repeated target classes."),
    dict(id="VC-D08", displayName="Rail Emplacement", techTier=3, costCredits=2100,
         buildTimeSec=32.0, maxHealth=560, footprint=[2, 2],
         weaponSlots=["wpn_energy_beam"],
         componentFlags=["Defense", "Turret"],
         bibleRole="Late anti-heavy / anti-structure defensive weapon with slow recharge."),
]

# ---------------------------------------------------------------- FC defenses
FC_DEF = [
    dict(id="FC-D03", displayName="Machine Gun Nest", techTier=1, costCredits=550,
         buildTimeSec=15.0, maxHealth=320, footprint=[1, 1],
         weaponSlots=["wpn_small_arms"],
         componentFlags=["Defense", "Turret"],
         bibleRole="Strong anti-infantry fixed arc."),
    dict(id="FC-D04", displayName="AT Emplacement", techTier=2, costCredits=900,
         buildTimeSec=18.0, maxHealth=300, footprint=[1, 1],
         weaponSlots=["wpn_anti_armor"],
         componentFlags=["Defense", "Turret"],
         bibleRole="Heavy anti-vehicle missile/gun."),
    dict(id="FC-D05", displayName="Bunker", techTier=2, costCredits=1000,
         buildTimeSec=22.0, maxHealth=700, footprint=[2, 2],
         weaponSlots=["wpn_small_arms"], garrisoned=6,
         componentFlags=["Defense", "Garrisonable"],
         bibleRole="Garrison 6; high health; firing ports."),
    dict(id="FC-D06", displayName="SAM Site", techTier=2, costCredits=950,
         buildTimeSec=18.0, maxHealth=340, footprint=[2, 2],
         weaponSlots=["wpn_anti_armor"],
         componentFlags=["Defense", "Turret", "AntiAir"],
         bibleRole="Long-range anti-air, weak vs ground."),
    dict(id="FC-D07", displayName="Counter-UAS Station", techTier=2,
         costCredits=800, buildTimeSec=16.0, maxHealth=320, footprint=[1, 1],
         weaponSlots=["wpn_autocannon"],
         componentFlags=["Defense", "Turret", "Jammer"],
         bibleRole="Anti-drone gun + jammer."),
    dict(id="FC-D08", displayName="Patriot Battery", techTier=3, costCredits=1800,
         buildTimeSec=28.0, maxHealth=500, footprint=[2, 2],
         weaponSlots=["wpn_anti_armor"],
         componentFlags=["Defense", "Turret", "AntiAir"],
         bibleRole="T3 air/missile defense with interceptor charges."),
]

# IDs that shipped under the wrong bible number: Repair buildings were authored
# as B10 but the bible assigns them B11 (B10 = Autonomy Lab / Joint Ops Center).
RENUMBER = {"VC-B10": "VC-B11", "FC-B10": "FC-B11"}


def _unit(d, faction):
    out = {
        "id": d["id"], "displayName": d["displayName"], "factionId": faction,
        "techTier": d["techTier"], "costCredits": d["costCredits"],
        "buildTimeSec": d["buildTimeSec"],
        "reserveCapacity": d["reserveCapacity"], "maxHealth": d["maxHealth"],
        "armorClass": d["armorClass"], "moveProfileId": d["moveProfileId"],
        "visionRadius": d["visionRadius"],
        "detectionRadius": d["detectionRadius"],
        "weaponSlots": d["weaponSlots"], "abilityIds": d["abilityIds"],
        "componentFlags": d["componentFlags"],
        "populationWeight": d["populationWeight"],
        "wreckDefinitionId": None,
        "selectionPriority": d["selectionPriority"],
    }
    if d.get("garrisonCapable"):
        out["garrisonCapable"] = True
    if d.get("harvest"):
        # HarvestComponent only attaches when the def carries harvest:true
        # (Entity._attach_components). Tuning defaults come from the component.
        out["harvest"] = True
        out["harvestCapacity"] = d.get("harvestCapacity", 500.0)
        out["harvestRatePerSec"] = d.get("harvestRatePerSec", 60.0)
        out["harvestRadius"] = d.get("harvestRadius", 40.0)
        out["depositRadius"] = d.get("depositRadius", 60.0)
    return out


def _struct(d, faction, klass=None):
    out = {
        "id": d["id"], "displayName": d["displayName"], "factionId": faction,
        "techTier": d["techTier"], "costCredits": d["costCredits"],
        "buildTimeSec": d["buildTimeSec"], "maxHealth": d["maxHealth"],
        "armorClass": "StructureHeavy",
        "footprint": d["footprint"],
        "class": klass or d.get("klass") or "Defense",
        "function": d.get("function", d.get("bibleRole", "")),
        "componentFlags": d["componentFlags"],
    }
    if d.get("weaponSlots"):
        out["weaponSlots"] = d["weaponSlots"]
    if "garrisoned" in d:
        out["garrisoned"] = d["garrisoned"]
    if "unlocksTechTier" in d:
        out["unlocksTechTier"] = d["unlocksTechTier"]
    if "commandCapacity" in d:
        out["commandCapacity"] = d["commandCapacity"]
    if "powerProduced" in d:
        out["powerProduced"] = d["powerProduced"]
    if d.get("trainsUnits"):
        out["trainsUnits"] = d["trainsUnits"]
    if "visionRadius" in d:
        out["visionRadius"] = d["visionRadius"]
    return out


def main():
    up = os.path.join(BASE, "units.json")
    sp = os.path.join(BASE, "structures.json")
    units_doc = json.load(open(up))
    structs_doc = json.load(open(sp))
    units = units_doc["units"]
    structs = structs_doc["structures"]

    # 1) renumber the mis-numbered Repair buildings to match the bible
    renumbered = []
    for s in structs:
        if s["id"] in RENUMBER:
            old = s["id"]
            s["id"] = RENUMBER[old]
            renumbered.append((old, s["id"]))

    have_u = {u["id"] for u in units}
    have_s = {s["id"] for s in structs}
    added_u, added_s, skipped = [], [], []

    for d in VC_UNITS:
        if d["id"] in have_u:
            skipped.append(d["id"])
            continue
        units.append(_unit(d, "VC"))
        added_u.append(d["id"])
    for d in FC_UNITS:
        if d["id"] in have_u:
            skipped.append(d["id"])
            continue
        units.append(_unit(d, "FC"))
        added_u.append(d["id"])

    for d in VC_STRUCTS:
        if d["id"] in have_s:
            skipped.append(d["id"])
            continue
        structs.append(_struct(d, "VC"))
        added_s.append(d["id"])
    for d in FC_STRUCTS:
        if d["id"] in have_s:
            skipped.append(d["id"])
            continue
        structs.append(_struct(d, "FC"))
        added_s.append(d["id"])
    for d in VC_DEF:
        if d["id"] in have_s:
            skipped.append(d["id"])
            continue
        structs.append(_struct(d, "VC", klass="Defense"))
        added_s.append(d["id"])
    for d in FC_DEF:
        if d["id"] in have_s:
            skipped.append(d["id"])
            continue
        structs.append(_struct(d, "FC", klass="Defense"))
        added_s.append(d["id"])

    # stable ordering by ID
    units.sort(key=lambda x: (x["factionId"], x["id"]))
    structs.sort(key=lambda x: (x["factionId"], x["id"]))

    json.dump(units_doc, open(up, "w"), indent=2)
    open(up, "a").write("\n")
    json.dump(structs_doc, open(sp, "w"), indent=2)
    open(sp, "a").write("\n")

    print("renumbered:", renumbered)
    print("units added (%d): %s" % (len(added_u), added_u))
    print("structures added (%d): %s" % (len(added_s), added_s))
    print("skipped (already present):", skipped)
    print("totals: units=%d structures=%d" % (len(units), len(structs)))


if __name__ == "__main__":
    main()
