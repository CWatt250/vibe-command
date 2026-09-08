extends RefCounted
class_name Entity
## Entity — runtime object composed of components per Blueprint §3.2 / §2 (component-based).
## Owns no presentation; holds def_id + stable runtime id, faction, position, and components.

const HealthComponent := preload("res://gameplay/components/HealthComponent.gd")
const MovementComponent := preload("res://gameplay/components/MovementComponent.gd")
const WeaponComponent := preload("res://gameplay/components/WeaponComponent.gd")
const SensorComponent := preload("res://gameplay/components/SensorComponent.gd")
const ProductionComponent := preload("res://gameplay/components/ProductionComponent.gd")
const ConstructionComponent := preload("res://gameplay/components/ConstructionComponent.gd")

## Runtime refs — bound by Simulation at spawn.
var grid: NavGrid = null
var spatial: SpatialIndex = null
var registry: ContentRegistry = null

var id: int = -1
var def_id: String = ""
var faction_id: String = ""
var kind: String = "unit"            # "unit" | "structure" | "projectile"
var position: Vector2 = Vector2.ZERO
var is_airborne: bool = false
var alive: bool = true

# --- components (Blueprint §2 / §4) ---
var health: HealthComponent = null
var movement: MovementComponent = null
var weapon: WeaponComponent = null
var sensor: SensorComponent = null
var production: ProductionComponent = null
var construction: ConstructionComponent = null
var def_data: Dictionary = {}

func _init(def: Dictionary, owner: String, entity_id: int) -> void:
	def_id = def.get("id", "")
	faction_id = owner
	id = entity_id
	kind = "unit"
	def_data = def

func is_owned_by(faction: String) -> bool:
	return faction_id == faction

## Attach components based on definition + content (Blueprint §2 component-based).
func _attach_components(reg: ContentRegistry, def: Dictionary, start_built: bool = true) -> void:
	# Health
	var h := HealthComponent.new()
	h.setup(def, self)
	health = h
	# Sensor
	var s := SensorComponent.new()
	s.setup(def, self)
	sensor = s
	# Movement (units only, from move profile)
	if def.has("moveProfileId"):
		var mp := reg.get_moveprofile(def["moveProfileId"])
		var m := MovementComponent.new()
		m.setup(def, mp)
		movement = m
		is_airborne = m.path_layer == "air"
	# Weapon (first weapon slot as primary combiner for now)
	if def.has("weaponSlots") and def["weaponSlots"].size() > 0:
		var wdef := reg.get_weapon(def["weaponSlots"][0])
		var w := WeaponComponent.new()
		w.setup(wdef, self)
		weapon = w
	# Production (structures that train units)
	if def.has("trainsUnits"):
		var p := ProductionComponent.new()
		p.setup(def, self)
		production = p
	# Construction (structures build over time; pre-placed spawn built)
	if def.has("footprint"):
		var c := ConstructionComponent.new()
		c.setup(def, start_built)
		construction = c
