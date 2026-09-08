extends RefCounted
class_name ComputeSystem
## ComputeSystem — per-faction Vibe Compute economy (Blueprint §6.1).
## Compute is produced by Compute structures (VC-B05 Server Rack Hall / VC-B06 AI Cluster),
## reduced by brownout (power ratio) and by cooling failure (coolingNeed vs coolingProvided).
## Advanced autonomous units RESERVE compute (reserveCapacity on a Bot/unit def). If usable
## compute falls below reserved, the faction enters Compute Deficit, which applies a
## deterministic global reaction/cooldown/accuracy penalty (Blueprint §6.1 MVP — NOT random
## shutdown of individual units).
## Pure logic, no Node — the sim owns an instance and calls into it each tick.

const DEFICIT_PENALTY: float = 1.15  # deterministic reaction/cooldown penalty under deficit

## Compute usable/required for a faction.
## Returns {produced, reserved, usable, cooling, cooling_ratio, deficit}.
func _compute(entities: Dictionary, faction: String, power_ratio: float) -> Dictionary:
	var produced: float = 0.0
	var cooling_provided: float = 0.0
	var cooling_needed: float = 0.0
	for id in entities:
		var e = entities[id]
		if e.faction_id != faction:
			continue
		if e.kind != "structure":
			continue
		# Compute buildings must be BUILT to produce; build sites aren't wired yet.
		if e.construction != null and not e.construction.is_built():
			continue
		var def: Dictionary = e.def_data
		produced += def.get("computeProduced", 0.0)
		cooling_provided += def.get("coolingProvided", 0.0)
		cooling_needed += def.get("coolingNeed", 0.0)
	# Cooling ratio: how much of the compute's cooling need is satisfied. If there are no
	# compute buildings or no cooling need, treat as satisfied (ratio 1).
	var cooling_ratio: float = 1.0
	if cooling_needed > 0.0:
		cooling_ratio = 1.0 if cooling_provided >= cooling_needed else (cooling_provided / cooling_needed)
	# Usable compute = produced, reduced by power brownout AND cooling shortfall.
	var usable: float = produced * minf(power_ratio, 1.0) * clampf(cooling_ratio, 0.0, 1.0)
	# Reserved = sum of reserveCapacity across a faction's living autonomous units.
	var reserved: float = 0.0
	for id in entities:
		var e = entities[id]
		if e.faction_id != faction:
			continue
		if e.kind != "unit":
			continue
		var def: Dictionary = e.def_data
		# Autonomous units are marked with the Bot flag; they draw reserve capacity.
		if def.get("componentFlags", []).has("Bot"):
			reserved += def.get("reserveCapacity", 0.0)
	var deficit: bool = usable < reserved
	return {
		"produced": produced,
		"reserved": reserved,
		"usable": usable,
		"cooling": cooling_provided,
		"cooling_ratio": cooling_ratio,
		"deficit": deficit
	}

## Apply the global compute deficit penalty to a running speed/reaction scalar for a faction.
## Returns a cooldown/multiplier modifier; 1.0 = no deficit, DEFICIT_PENALTY = under deficit.
func reaction_scale(deficit: bool) -> float:
	return DEFICIT_PENALTY if deficit else 1.0
