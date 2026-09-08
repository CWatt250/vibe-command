extends RefCounted
## HealthComponent — max/current health, armor class, damage intake, death handling (Blueprint §4.1).

var max_health: float = 100.0
var current: float = 100.0
var armor_class: String = "Infantry"
var wreck_id: String = ""

func setup(def: Dictionary, _owner) -> void:
	max_health = def.get("maxHealth", 100.0)
	current = max_health
	armor_class = def.get("armorClass", "Infantry")
	wreck_id = str(def.get("wreckDefinitionId", ""))

func is_alive() -> bool:
	return current > 0.0

func ratio() -> float:
	return current / max_health if max_health > 0 else 0.0

## Apply raw damage (already armor-resolved by CombatSystem). Returns true if now dead.
func apply_damage(amount: float) -> bool:
	if not is_alive():
		return false
	current = maxf(0.0, current - amount)
	return current <= 0.0

func heal(amount: float) -> void:
	current = minf(max_health, current + amount)
