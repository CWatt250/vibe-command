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
const GarrisonComponent := preload("res://gameplay/components/GarrisonComponent.gd")
const GarrisonableComponent := preload("res://gameplay/components/GarrisonableComponent.gd")
const VeterancyComponent := preload("res://gameplay/components/VeterancyComponent.gd")
const HarvestComponent := preload("res://gameplay/components/HarvestComponent.gd")
const ResourceNodeComponent := preload("res://gameplay/components/ResourceNodeComponent.gd")

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

## Order state (Blueprint p1-07) — what the unit is currently doing, set by Simulation's order
## handlers and read by CombatSystem to decide acquisition/chase/fire behaviour.
enum Order { IDLE, MOVE, ATTACK, ATTACK_MOVE, HOLD }
var order: Order = Order.IDLE
var order_target: int = -1              # entity id for ATTACK
var order_dest: Vector2 = Vector2.ZERO  # for MOVE / ATTACK_MOVE
## p4-03: orders waiting behind the current one (Shift = queue). Each entry is a command dict
## in run_commands' own shape: {"type": "MOVE"|"ATTACK_MOVE", "targetPosition": Vector2} or
## {"type": "ATTACK", "targetEntityId": int}. Drained by Simulation._tick_entity once `order` is
## back to IDLE; cleared by any non-queued order, STOP or HOLD.
var order_queue: Array = []

# --- components (Blueprint §2 / §4) ---
var health: HealthComponent = null
var movement: MovementComponent = null
var weapon: WeaponComponent = null
var sensor: SensorComponent = null
var production: ProductionComponent = null
var construction: ConstructionComponent = null
var garrison: GarrisonComponent = null
var garrisonable: GarrisonableComponent = null
var veterancy: VeterancyComponent = null
var harvest: HarvestComponent = null
var resource: ResourceNodeComponent = null
var def_data: Dictionary = {}

## Garrison / repair runtime state (§5.7, repair).
var garrisoned_into: int = -1          # id of structure this unit is garrisoned in (-1 = free)
var repair_target: int = -1            # id that is repairing this unit (-1 = none)

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
	# Garrison (structures with slots: infantry can occupy + fire)
	if def.has("garrisoned"):
		var g := GarrisonComponent.new()
		g.setup(def)
		garrison = g
	# Garrisonable (units/infantry that can enter a garrison structure)
	if def.has("garrisonCapable") and def.get("garrisonCapable", false):
		var gb := GarrisonableComponent.new()
		gb.setup(def)
		garrisonable = gb
	# Veterancy (combat XP + ranks) — attached to combat units, not produced structures.
	if def.get("kind", "unit") == "unit" and def.get("veterancyCapable", true) and def.has("weaponSlots"):
		var v := VeterancyComponent.new()
		v.setup(def, self)
		veterancy = v
	# Harvest (units that mine credits from resource fields — §5.4)
	if def.get("harvest", false) and def.get("kind", "unit") == "unit":
		var hc := HarvestComponent.new()
		hc.setup(def, self)
		harvest = hc
	# Resource node (a depletable harvestable field — §5.4)
	if def.get("resource", false):
		var rc := ResourceNodeComponent.new()
		rc.setup(def, self)
		resource = rc
