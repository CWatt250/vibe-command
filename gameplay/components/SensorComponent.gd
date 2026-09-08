extends RefCounted
## SensorComponent — vision + detection radii, used for fog-of-war and stealth detection (Blueprint §4.1).

var vision_radius: float = 200.0
var detection_radius: float = 100.0
var reveal_stealth: bool = false

func setup(def: Dictionary, _owner) -> void:
	vision_radius = def.get("visionRadius", 200.0)
	detection_radius = def.get("detectionRadius", 100.0)
