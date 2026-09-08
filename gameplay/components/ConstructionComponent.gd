extends RefCounted
class_name ConstructionComponent
## ConstructionComponent — powers a structure's build-site lifecycle (Blueprint §5.2).
## A structure spawns as a build site (not yet built) when created by the BUILD command,
## ticks its progress, and activates (enabling production/power/weapons) when complete.
## Map/script pre-placed structures spawn already built (start_built=true).

var total: float = 0.0
var progress: float = 0.0
var built: bool = false

func setup(def: Dictionary, start_built: bool) -> void:
	total = def.get("buildTimeSec", 10.0)
	built = start_built
	progress = total if start_built else 0.0

func is_built() -> bool:
	return built

## Advance construction. Returns true this tick if it just finished building.
func tick(dt: float) -> bool:
	if built:
		return false
	progress += dt
	if progress >= total:
		progress = total
		built = true
		return true
	return false

func fraction() -> float:
	if total <= 0.0:
		return 1.0 if built else 0.0
	return clampf(progress / total, 0.0, 1.0)
