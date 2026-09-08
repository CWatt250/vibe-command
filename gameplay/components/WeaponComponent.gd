extends RefCounted
## WeaponComponent — one weapon: range, cooldown, targeting, and a resolve/attack hook.
## CombatSystem drives acquisition (which target) using this weapon's stats; this component
## owns per-weapon cooldown timers and fires (calls back into CombatSystem for damage).

var weapon_id: String = ""
var range: float = 120.0
var min_range: float = 0.0
var reload_sec: float = 1.0
var burst_count: int = 1
var burst_interval: float = 0.0
var base_damage: float = 10.0
var damage_type: String = "SmallArms"
var target_tags: Array = []
var preferred_tags: Array = []
var projectile_id: String = ""
var splash_radius: float = 0.0
var requires_los: bool = true
var aim_time: float = 0.2
var turn_rate_mod: float = 3.0

# runtime
var cooldown_left: float = 0.0
var burst_left: int = 0
var burst_timer: float = 0.0
var current_target_id: int = -1
var acquire_radius: float = 220.0   # acquisition > weapon range (Blueprint §3.5)
var reaction_scale: float = 1.0     # compute-deficit penalty: >1.0 = slower cooldown

func setup(def: Dictionary, _owner) -> void:
	weapon_id = def.get("id", "")
	range = def.get("range", 120.0)
	min_range = def.get("minRange", 0.0)
	reload_sec = def.get("reloadSec", 1.0)
	burst_count = def.get("burstCount", 1)
	burst_interval = def.get("burstInterval", 0.0)
	base_damage = def.get("baseDamage", 10.0)
	damage_type = def.get("damageType", "SmallArms")
	target_tags = def.get("targetTags", [])
	preferred_tags = def.get("preferredTags", [])
	projectile_id = str(def.get("projectileId", ""))
	splash_radius = def.get("splashRadius", 0.0)
	requires_los = def.get("requiresLineOfSight", true)
	aim_time = def.get("aimTime", 0.2)
	turn_rate_mod = def.get("turnRateModifier", 3.0)
	# acquire radius = max(range, default acquisition)
	acquire_radius = maxf(range, 220.0)

func tick_cool(dt: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left -= dt
	if burst_left > 0:
		burst_timer -= dt
		if burst_timer <= 0.0:
			burst_left -= 1
			burst_timer = burst_interval

func can_fire() -> bool:
	return cooldown_left <= 0.0 and burst_left <= 0

func target_in_range(target_pos: Vector2, self_pos: Vector2) -> bool:
	var d := self_pos.distance_to(target_pos)
	return d >= min_range and d <= range

func begin_cooldown() -> void:
	if burst_count > 1:
		burst_left = burst_count - 1
		burst_timer = burst_interval
	cooldown_left = reload_sec * reaction_scale

func set_reaction_scale(scale: float) -> void:
	reaction_scale = scale
