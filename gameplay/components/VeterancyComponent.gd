extends RefCounted
class_name VeterancyComponent
## VeterancyComponent — XP + rank, resolved from a rank table (§5.9). Server/sim authoritative.
## XP is awarded on damage contribution, kill, repair/capture support. Ranks apply damage
## and health modifiers from a shared table (not per-unit hardcode).

# Shared rank table: { rank_index -> { xp_needed (cumulative), label, damage_mult, health_mult } }
const RANK_TABLE: Array = [
	{ "xp": 0,    "label": "Regular",   "damage_mult": 1.0, "health_mult": 1.0 },
	{ "xp": 150,  "label": "Veteran",   "damage_mult": 1.10, "health_mult": 1.10 },
	{ "xp": 500,  "label": "Elite",     "damage_mult": 1.25, "health_mult": 1.20 },
	{ "xp": 1200, "label": "Heroic",    "damage_mult": 1.40, "health_mult": 1.35 },
]

var xp: float = 0.0
var rank: int = 0   # index into RANK_TABLE

var owner: Entity = null

func setup(_def: Dictionary, owner_: Entity) -> void:
	owner = owner_

func add_xp(amount: float) -> void:
	if amount <= 0.0:
		return
	xp += amount
	rank = _rank_for_xp(xp)

func _rank_for_xp(xp_val: float) -> int:
	var r: int = 0
	for i in range(RANK_TABLE.size()):
		if xp_val >= RANK_TABLE[i]["xp"]:
			r = i
	return r

func rank_label() -> String:
	return RANK_TABLE[rank]["label"]

func damage_mult() -> float:
	return RANK_TABLE[rank]["damage_mult"]

func health_mult() -> float:
	return RANK_TABLE[rank]["health_mult"]
