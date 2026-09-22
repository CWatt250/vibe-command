extends RefCounted
class_name UnitMotion
## p3-03 — procedural motion for the 2D presenters. Speed is the presenter's own position
## delta per sim tick (never a sim field), so a unit that is "moving" but blocked reads as at
## rest. Static helpers are pure functions of (armor class, time, speed) so they test headless.

const MOVING_SPEED := 8.0            # world px/s; below this a unit is at rest
const ROTOR_RAD_S := 26.0            # rotor blade spin; 1.73 rad per 15 Hz tick -> visibly new phase every tick

# One table. bob_px: vertical offset amplitude while moving. bob_hz: cycles/s (infantry: 2-frame
# step toggles at 2*bob_hz). rock_deg: body roll amplitude while moving. dust_hz: puff cadence,
# dust_n: puffs per emit. hover_px/hover_hz: air-only, always on. rotors: blur overlays drawn.
const P := {
	# bob_hz is the walk-cycle rate; the 2-frame step below toggles at 2*bob_hz, so Infantry's
	# 0.9375 = exactly one leg change per 8 sim ticks (15 Hz). That matters: a step faster than
	# that aliases against any 8-tick sampling (the motion strip's frames are 20/28/36/44), which
	# pins the crew in one bucket forever instead of alternating.
	"Infantry":      {"bob_px": 1.5, "bob_hz": 0.9375, "rock_deg": 0.0, "dust_hz": 0.0, "dust_n": 0, "hover_px": 0.0, "hover_hz": 0.0, "rotors": 0},
	"HeavyInfantry": {"bob_px": 1.5, "bob_hz": 1.5, "rock_deg": 0.0, "dust_hz": 0.0, "dust_n": 0, "hover_px": 0.0, "hover_hz": 0.0, "rotors": 0},
	"Light":         {"bob_px": 1.0, "bob_hz": 9.0, "rock_deg": 1.5, "dust_hz": 4.0, "dust_n": 1, "hover_px": 0.0, "hover_hz": 0.0, "rotors": 0},
	"Medium":        {"bob_px": 1.0, "bob_hz": 7.0, "rock_deg": 1.0, "dust_hz": 3.0, "dust_n": 1, "hover_px": 0.0, "hover_hz": 0.0, "rotors": 0},
	"Heavy":         {"bob_px": 2.0, "bob_hz": 5.0, "rock_deg": 0.8, "dust_hz": 2.5, "dust_n": 2, "hover_px": 0.0, "hover_hz": 0.0, "rotors": 0},
	"AirLight":      {"bob_px": 0.0, "bob_hz": 0.0, "rock_deg": 0.0, "dust_hz": 0.0, "dust_n": 0, "hover_px": 2.0, "hover_hz": 1.5, "rotors": 4},
	"AirHeavy":      {"bob_px": 0.0, "bob_hz": 0.0, "rock_deg": 0.0, "dust_hz": 0.0, "dust_n": 0, "hover_px": 3.0, "hover_hz": 1.0, "rotors": 0},
}

var time: float = 0.0
var _prev: Dictionary = {}    # entity id -> Vector2 (last sampled position)
var _speed: Dictionary = {}   # entity id -> float (world px/s)

## Call once per sim tick, after sim.step(dt). Rebuilds the tables from live units only.
func sample(sim: Simulation, dt: float) -> void:
	time += dt
	var next_prev: Dictionary = {}
	var next_speed: Dictionary = {}
	for e in sim.entities.values():
		if not e.alive or e.kind != "unit":
			continue
		var last: Vector2 = _prev.get(e.id, e.position)
		next_speed[e.id] = e.position.distance_to(last) / dt if dt > 0.0 else 0.0
		next_prev[e.id] = e.position
	_prev = next_prev
	_speed = next_speed

func speed_of(id: int) -> float:
	return _speed.get(id, 0.0)

static func params(armor: String) -> Dictionary:
	return P.get(armor, {})

static func is_moving(speed: float) -> bool:
	return speed >= MOVING_SPEED

## Vertical sprite offset (world px, negative = up) while moving; 0 at rest. Infantry is a
## 2-frame step (either -bob_px or 0), vehicles a sine. `id` de-phases units in a group.
static func bob_offset(armor: String, t: float, speed: float, id: int = 0) -> float:
	var p := params(armor)
	if p.is_empty() or p["bob_px"] <= 0.0 or not is_moving(speed):
		return 0.0
	var phase: float = t * p["bob_hz"] + float(id) * 0.37
	if armor == "Infantry" or armor == "HeavyInfantry":
		return -p["bob_px"] if int(floor(phase * 2.0)) % 2 == 0 else 0.0
	return sin(phase * TAU) * p["bob_px"]

## Body roll (radians) while moving; 0 at rest. Half the bob frequency so it reads as rocking.
static func rock_angle(armor: String, t: float, speed: float, id: int = 0) -> float:
	var p := params(armor)
	if p.is_empty() or p["rock_deg"] <= 0.0 or not is_moving(speed):
		return 0.0
	return sin((t * p["bob_hz"] * 0.5 + float(id) * 0.37) * TAU) * deg_to_rad(p["rock_deg"])

## Air only: hover offset (world px, negative = up), on whether moving or not. 0 for ground.
static func hover_offset(armor: String, t: float, id: int = 0) -> float:
	var p := params(armor)
	if p.is_empty() or p["hover_px"] <= 0.0:
		return 0.0
	return sin((t * p["hover_hz"] + float(id) * 0.37) * TAU) * p["hover_px"]

## Rotor blade angle. Always spinning (aircraft hover); speed doesn't matter.
static func rotor_angle(t: float, id: int = 0) -> float:
	return fmod(t * ROTOR_RAD_S + float(id) * 0.9, TAU)

## Should FxRenderer emit dust for this unit this tick? Never at rest, never for air/infantry.
static func dust_due(armor: String, tick: int, id: int, speed: float) -> bool:
	var p := params(armor)
	if p.is_empty() or p["dust_hz"] <= 0.0 or not is_moving(speed):
		return false
	return (tick + id) % Simulation.ticks_per(p["dust_hz"]) == 0
