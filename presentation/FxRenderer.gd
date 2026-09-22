extends Node2D
class_name FxRenderer
## FxRenderer — transient visual effects layered over the entities (visual-roadmap V4/V5).
## Pure presentation: subscribes to GameEvents and reads the sim; never writes it.
##
## V4 ambient: dust behind moving ground units, smoke from power structures, pulsing
##             faction LED on every built structure.
## V5 combat:  muzzle flash + tracer on combat_occurred, impact sparks, a white hit
##             flash the EntityRenderer reads via flash_left(), and an explosion
##             (ring + smoke + debris) on unit_died / structure_destroyed.
##
## Particles are a plain array of dictionaries stepped in _process. Cheap, deterministic
## enough for screenshots, and no GPUParticles2D lifetime/seek headaches.

var sim: Simulation
var events: GameEvents

var _particles: Array = []      # {kind, pos, vel, life, max, size, color, [end]}
var _flash: Dictionary = {}     # entity id -> seconds of hit flash left
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()

const FC_COLORS := {
	"VC": Color(0.0, 0.82, 1.0),
	"FC": Color(0.95, 0.75, 0.15),
}
const DUST := Color(0.62, 0.56, 0.44, 0.45)
const SMOKE := Color(0.45, 0.45, 0.47, 0.35)
const FLASH := Color(1.0, 0.95, 0.7, 0.95)
const TRACER := Color(1.0, 0.9, 0.5, 0.85)
const SPARK := Color(1.0, 0.7, 0.3, 0.9)
const RING := Color(1.0, 0.6, 0.25, 0.9)
const DEBRIS := Color(0.25, 0.24, 0.22, 0.95)

func _init(simulation: Simulation, ev: GameEvents) -> void:
	sim = simulation
	events = ev
	z_index = 8   # above entities (6), below the fog is wrong — fog is 5, we sit over units
	_rng.seed = 11

func _ready() -> void:
	events.game_tick.connect(_on_game_tick)
	events.combat_occurred.connect(_on_combat)
	events.unit_died.connect(_on_died)   # CombatSystem emits this for structures too

## Seconds of hit flash left for an entity (EntityRenderer overlays white while > 0).
func flash_left(id: int) -> float:
	return _flash.get(id, 0.0)

# --- V4 ambient emitters, driven by the sim tick so they pause with it ---
func _on_game_tick(tick: int, _dt: float) -> void:
	for e in sim.entities.values():
		if not e.alive:
			continue
		if e.kind == "unit" and not e.is_airborne and e.movement != null and e.movement.is_moving():
			if (tick + e.id) % Simulation.ticks_per(4.0) == 0:
				var back: Vector2 = e.position - e.movement.facing * 10.0
				_spawn("puff", back + _jitter(4.0), _jitter(6.0) - e.movement.facing * 8.0, 0.5, 4.0, DUST)
		elif e.kind == "structure" and (tick + e.id) % Simulation.ticks_per(1.25) == 0:
			if e.def_data.get("componentFlags", []).has("PowerSource") and _built(e):
				var fp := _footprint_rect(e)
				var stack := fp.position + Vector2(fp.size.x * 0.25, fp.size.y * 0.2)
				_spawn("puff", stack + _jitter(2.0), Vector2(_rng.randf_range(-4, 4), -18.0), 1.3, 3.0, SMOKE)

# --- V5 combat ---
func _on_combat(attacker_id: int, target_id: int, weapon_id: String, _dmg: float) -> void:
	var a: Entity = sim.entities.get(attacker_id)
	var t: Entity = sim.entities.get(target_id)
	if a == null or t == null:
		return
	var dir: Vector2 = (t.position - a.position).normalized()
	var muzzle: Vector2 = a.position + dir * 14.0
	_spawn("flash", muzzle, Vector2.ZERO, 0.08, 7.0, FLASH)
	var wdef: Dictionary = sim.registry.get_weapon(weapon_id)
	if wdef.get("projectileId", null) == null:
		_spawn("line", muzzle, Vector2.ZERO, 0.1, 1.5, TRACER, t.position)
	for i in range(4):
		_spawn("spark", t.position + _jitter(3.0), -dir * 30.0 + _jitter(50.0), 0.25, 2.0, SPARK)
	_flash[target_id] = 0.1

func _on_died(_id: int, def_id: String, _faction: String, pos: Vector2) -> void:
	var big := sim.registry.get_structure(def_id).size() > 0
	var scale := 2.2 if big else 1.0
	_spawn("ring", pos, Vector2.ZERO, 0.35 * scale, 6.0, RING, Vector2.ZERO, 34.0 * scale)
	_spawn("flash", pos, Vector2.ZERO, 0.1, 12.0 * scale, FLASH)
	for i in range(int(6 * scale)):
		_spawn("puff", pos + _jitter(8.0 * scale), _jitter(30.0) + Vector2(0, -12), 1.1 * scale, 5.0 * scale, SMOKE)
	for i in range(int(5 * scale)):
		_spawn("debris", pos, _jitter(90.0), 0.5, 2.5, DEBRIS)

# --- particle plumbing ---
func _spawn(kind: String, pos: Vector2, vel: Vector2, life: float, size: float, color: Color,
		end: Vector2 = Vector2.ZERO, grow_to: float = 0.0) -> void:
	_particles.append({"kind": kind, "pos": pos, "vel": vel, "life": life, "max": life,
		"size": size, "color": color, "end": end, "grow": grow_to})

func _process(delta: float) -> void:
	_time += delta
	var keep: Array = []
	for p in _particles:
		p["life"] -= delta
		if p["life"] <= 0.0:
			continue
		p["pos"] += p["vel"] * delta
		p["vel"] *= 0.92
		keep.append(p)
	_particles = keep
	for id in _flash.keys():
		_flash[id] -= delta
		if _flash[id] <= 0.0:
			_flash.erase(id)
	queue_redraw()

func _draw() -> void:
	# Faction LED pulse on built structures — the cheapest "this thing is alive" cue.
	var pulse := 0.55 + 0.45 * sin(_time * 4.0)
	for e in sim.entities.values():
		if e.alive and e.kind == "structure" and _built(e):
			var fp := _footprint_rect(e)
			var led: Vector2 = fp.end - Vector2(fp.size.x * 0.18, fp.size.y * 0.18)
			var col: Color = FC_COLORS.get(e.faction_id, Color.WHITE)
			draw_circle(led, 4.5, Color(col.r, col.g, col.b, 0.25 * pulse))
			draw_circle(led, 2.0, Color(col.r, col.g, col.b, pulse))
	for p in _particles:
		var t: float = p["life"] / p["max"]     # 1 → 0
		var c: Color = p["color"]
		match p["kind"]:
			"puff":
				c.a *= t
				draw_circle(p["pos"], p["size"] * (1.6 - 0.6 * t), c)
			"spark", "debris":
				c.a *= t
				draw_rect(Rect2(p["pos"] - Vector2.ONE * p["size"] * 0.5, Vector2.ONE * p["size"]), c)
			"flash":
				c.a *= t
				draw_circle(p["pos"], p["size"] * (0.6 + 0.4 * t), c)
			"line":
				c.a *= t
				draw_line(p["pos"], p["end"], c, p["size"])
			"ring":
				c.a *= t
				var r: float = p["size"] + (p["grow"] - p["size"]) * (1.0 - t)
				draw_arc(p["pos"], r, 0.0, TAU, 32, c, 3.0 * t + 1.0)

func _built(e: Entity) -> bool:
	return e.construction == null or e.construction.is_built()

func _jitter(r: float) -> Vector2:
	return Vector2(_rng.randf_range(-r, r), _rng.randf_range(-r, r))

## Same anchor-cell math as EntityRenderer/PlacementGhost/sim.
func _footprint_rect(e: Entity) -> Rect2:
	var fp: Array = e.def_data.get("footprint", [1, 1])
	var w: int = int(fp[0]) if fp.size() > 0 else 1
	var h: int = int(fp[1]) if fp.size() > 1 else w
	var c: Vector2i = sim.grid_map.world_to_cell(e.position.x, e.position.y)
	return Rect2(Vector2(c.x - w / 2, c.y - h / 2) * NavGrid.CELL, Vector2(w, h) * NavGrid.CELL)
