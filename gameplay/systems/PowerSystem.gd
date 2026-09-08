extends RefCounted
class_name PowerSystem
## PowerSystem — per-faction power economy (Blueprint §6 / §5.5).
## Sums powerProduced (generators) and powerDrawn (consumers) across a faction's
## BUILT structures and derives a ratio. Ratio maps to a production speed_scale
## and a powered flag; brownout tiers slow (and critical brownout pauses) production.
## Sim is engine-agnostic; this is pure logic, no Node.

## Compute power ratio for a faction. Returns {ratio, produced, drawn, powered}.
func _compute(entities: Dictionary, faction: String) -> Dictionary:
	var produced: float = 0.0
	var drawn: float = 0.0
	for id in entities:
		var e = entities[id]
		if e.faction_id != faction:
			continue
		if e.kind != "structure":
			continue
		# Only built structures supply/draw power; build sites aren't wired yet.
		if e.construction != null and not e.construction.is_built():
			continue
		var def: Dictionary = e.def_data
		produced += def.get("powerProduced", 0.0)
		drawn += def.get("powerDrawn", 0.0)
	var ratio: float = 1.0
	if drawn > 0.0:
		ratio = produced / drawn
	elif produced <= 0.0 and drawn <= 0.0:
		ratio = 1.0
	return {
		"ratio": ratio,
		"produced": produced,
		"drawn": drawn,
		"powered": ratio >= 1.0
	}

## Map ratio -> production speed_scale (Blueprint brownout tiers).
func _speed_scale(ratio: float) -> float:
	if ratio >= 1.0:
		return 1.0
	if ratio >= 0.5:
		return 0.5     # brownout — halves production
	return 0.0         # critical brownout — no power, production paused
