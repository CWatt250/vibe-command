# p3-03 — Visible motion on moving units, in 2D (rotor blur + hover, body rock + dust, walk bob)

**Tier:** P (DeepSeek Pro) · **Repo:** `~/Dev/vibe-command` · **Adds:** `presentation/UnitMotion.gd`, `tests/test_p3_03_motion.gd`, `docs/screenshot_2d_motion_*.png` · **Touches:** `presentation/EntityRenderer.gd`, `presentation/FxRenderer.gd`, `presentation/Game.gd`. **`core/` and `gameplay/` are not touched. `presentation3d/` is not touched.**

Why P and not C: this is one small system (a shared per-unit speed sampler + three per-class
motion rules) spread over three presenters plus a capture flag and a screenshot that has to be
judged, not a single-file test-gated change. Why not O: every constant, function and line is
specified below; there is nothing to design.

Read `docs/specs/README.md` first. **Order: run after p3-01 and p3-02.** p3-01 restructures
`EntityRenderer._draw()` into a shadow pass plus a sprite pass and removes the old inline shadow
code (`EntityRenderer.gd:73-74`, `:100-105`). Every line number below is from commit `b261709`,
before p3-01 landed — locate each edit by the quoted code, not the line number, and leave p3-01's
shadow pass and helpers (`_draw_shadow`, `shadow_rect`, `structure_shadow_quad`, `_draw_feathered`,
`_unit_size_px`) exactly as they are.

## Why (what the 3D prototype proved, and what the 2D sprites can and cannot do)
The 3D showcase strip (`docs/screenshot_3d_showcase_strip.png`) showed wheels, legs and rotors in
different phases across four frames. The 2D game shows nothing: a moving unit is the same facing
frame sliding across the ground.

**Real animation frames are not available from the sprite pipeline — this ticket is procedural
motion only.** Evidence:
- `tools/render_sprites.py` renders one static pose per facing: `main()` picks a kit, then loops
  `for k in range(facings)` rotating the whole root about Z and rendering one still per facing
  (`render_sprites.py:633-636`). There is no armature, no action, no per-part animation anywhere
  in the file. Vehicles are single fused Hunyuan3D meshes imported by `kit_generated`
  (`render_sprites.py:232-269`; the docstring at 233 says so); infantry are Kenney Blocky
  Characters with boxes bolted on (`kit_infantry`, `render_sprites.py:498-529`) — the character
  is appended as one GLB, legs are never posed. p2-01 said the same thing up front
  (`docs/specs/p2-01-runtime-3d-prototype.md:7-9`).
- `tools/pack_facings.py` packs `<id>_NN.png` frames left-to-right into one strip and writes the
  manifest entry `{"file", "facings": N, "frame": [w, h], "scale": 1.4}` (`pack_facings.py:65-77`).
  The strip has exactly one row = one frame per facing. There is no animation axis in the format.
- `presentation/SpriteAtlas.gd` reads that entry: `facings(id)` (`SpriteAtlas.gd:79-81`),
  `frame_size(id)` (`83-86`), `facing_region(id, k)` = `Rect2(k * fw, 0, fw, fh)` (`89-91`).
  58 of 139 manifest entries carry facings (all of them 16).
- `EntityRenderer._draw_unit` picks facing `k` from `e.movement.facing` and draws
  `SpriteAtlas.facing_region(e.def_id, k)` (`EntityRenderer.gd:107-123`). One region per heading,
  no time axis.

So: rotors, wheels and legs are baked into a single silhouette. Adding frame animation would mean
16 facings × N frames × 58 units through Blender — not this ticket. We fake it the way 2D RTS
games always have: offsets, overlays and particles keyed by armor class.

## What already exists (do not duplicate; replace where stated)
- **Infantry walk bob exists but is sim-driven:** `EntityRenderer.gd:118-122` hops the box
  `-1.5 px` when `((sim.tick + e.id) / 4) % 2 == 0` and `e.movement.is_moving()`. Keep the look;
  replace the source of truth with the presenter's own speed (below). A unit that `is_moving()`
  but is stuck against another unit currently bobs in place.
- **Dust behind ground units exists:** `FxRenderer._on_game_tick` spawns one `"puff"` behind every
  non-airborne moving unit every `Simulation.ticks_per(4.0)` ticks (`FxRenderer.gd:51-58`), again
  gated on `e.movement.is_moving()`. Keep the puff; re-gate it on measured speed and make the
  cadence per class.
- **Rotor blur and vehicle rock do not exist.** Airborne units get only a wider, fainter shadow
  (`EntityRenderer.gd:100-105`) and draw on top (`_sort_y`, `147-150`).
- The 2D presenters redraw once per sim tick, not per frame: `Game._process` calls
  `entity_renderer.queue_redraw()` inside the fixed-step loop (`Game.gd:213-222`), 15 Hz
  (`Simulation.TICK_HZ = 15`, `Simulation.gd:7-8`). Motion below is therefore sampled at 15 Hz;
  that is fine for the capture and matches how `sim.tick` already drives the bob.
- `Game.gd` has `--capture=` and `--frame=` (`Game.gd:109-132`) but **no `--capture-frames`**;
  that exists only in the shelved `presentation3d/Game3D.gd:50-53, 62-63, 334-357`. Port it.
- The armor classes in `content/data/units.json` are exactly: `Infantry` (7 units),
  `HeavyInfantry` (6), `Light` (9, incl. `VC-SRV`/`FC-SRV`), `Medium` (15), `Heavy` (9),
  `AirLight` (5), `AirHeavy` (7). Read via `e.def_data.get("armorClass", "")`
  (`EntityRenderer.gd:99, 120`).
- Presenters read speed nowhere today; `MovementComponent` has `speed` (the profile max,
  `MovementComponent.gd:5`), `facing` (`:15`) and `is_moving()` (`:37-38`) but no current
  velocity accessor (`_current_speed` is private, `:16`). The 3D prototype derived speed from its
  own position delta (`presentation3d/Entity3D.gd:30-32`); do the same here.

## Step 1 — `presentation/UnitMotion.gd` (new, pure, testable)
```gdscript
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
	"Infantry":      {"bob_px": 1.5, "bob_hz": 2.0, "rock_deg": 0.0, "dust_hz": 0.0, "dust_n": 0, "hover_px": 0.0, "hover_hz": 0.0, "rotors": 0},
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
```
New `class_name` → run `godot-4 --headless --path . --import` once before the headless tests.

## Step 2 — `presentation/Game.gd`
1. Add `var motion: UnitMotion` next to the presenters (`Game.gd:11-21`). After
   `entity_renderer.fx = fx_renderer` (`Game.gd:61`):
   ```gdscript
   motion = UnitMotion.new()
   entity_renderer.motion = motion
   fx_renderer.motion = motion
   ```
2. In `_process` (`Game.gd:213-222`) add `motion.sample(sim, step)` immediately after
   `sim.step(step)` (line 217), before the `queue_redraw()` calls, so the draw that follows sees
   this tick's speed.
3. Port `--capture-frames=` from `presentation3d/Game3D.gd`:
   - `var _capture_frames: Array[int] = []` next to `_capture_at` (`Game.gd:28`).
   - In the arg loop (`Game.gd:114-130`) add, copied from `Game3D.gd:50-53`:
     ```gdscript
     elif a.begins_with("--capture-frames="):
         for s in a.trim_prefix("--capture-frames=").split(","):
             if s != "":
                 _capture_frames.append(int(s))
     ```
   - Replace `if _capture_at < 0: _capture_at = 180` (`Game.gd:131-132`) with
     `if _capture_frames.is_empty() and _capture_at < 0: _capture_at = 180`.
   - Replace the capture check at `Game.gd:223-227` with the `Game3D.gd:334-340` shape:
     ```gdscript
     if not _capture_frames.is_empty():
         if _frame >= _capture_frames[0]:
             var n: int = _capture_frames.pop_front()
             _capture_now("_%03d" % n, _capture_frames.is_empty())
     elif _capture_at > 0 and _frame >= _capture_at:
         _capture_at = -1
         if _debug_pause:
             pause_menu.toggle()
         _capture_now("", true)
     ```
   - Change `_capture_now()` (`Game.gd:229-252`) to `_capture_now(suffix: String, should_quit: bool)`:
     build `path` as `Game3D.gd:351-353` does (`"%s%s.%s" % [_capture_out.get_basename(), suffix, _capture_out.get_extension()]` when suffix != ""), save to `path`, print `CAPTURED:` with `path`, and `get_tree().quit()` only if `should_quit`. Keep the VCU/FCU debug prints.
4. Add a `--motion` debug arg. Placement matters: `_spawn_starter_force()` (`Game.gd:100`) and
   `events.game_tick.connect(...)` (`:102`) run **before** the arg loop (`:114-130`), so the flag
   cannot be applied there. Do it the way `debug_select` / `debug_place` already are: declare
   `var debug_motion := false` beside `var debug_pause := false` (`:113`), parse it inside the
   loop, and put the spawn/camera block after the loop, right after `_debug_pause = debug_pause`
   (`:144`). It spawns four exemplars in their own lanes on open dirt and sends each 600 px east
   so nothing arrives inside the capture window (fastest first so the leftmost travels furthest).
   Lanes are 80 px apart because `spawn_unit` snaps to cell centres and the drawn sprites are
   40–100 px tall (`UNIT_PX` × 1.4 scale); 40-px lanes overlap on screen.
   ```gdscript
   elif a == "--motion":
       debug_motion = true
   ...
   if debug_motion:
       var lanes := [["VC-U02", Vector2(620, 380)], ["VC-U04", Vector2(720, 460)],
                     ["VC-U01", Vector2(820, 540)], ["VC-U12", Vector2(920, 620)]]
       for l in lanes:
           var id: int = sim.spawn_unit(l[0], "VC", l[1])
           if id >= 0:
               sim.run_commands(0, [{"type": "MOVE", "entityIds": [id], "targetPosition": l[1] + Vector2(600, 0)}])
       rts_cam.zoom = Vector2(2.0, 2.0)
       rts_cam.position = Vector2(900, 475)
   ```
   (`MOVE` command shape: `Simulation.run_commands` → `_issue_move`, `Simulation.gd:339-346,
   385`; the same shape is used in `tests/test_phase7.gd:146`. Profile speeds from
   `content/data/moveprofiles.json`: prof_air 150, prof_vehicle_fast 120, prof_infantry 60,
   prof_vehicle_heavy 70 px/s — at frame 44 (2.93 s) the drone is at x≈1060, the tank at ≈1100,
   all inside the 580..1220 view at zoom 2; lane y 380..620 sits inside the 295..655 vertical view.) `RTSCamera` is a `Camera2D`; zoom max is 3.0
   (`RTSCamera.gd:6-7`), `_clamp_to_world` keeps the position valid (`RTSCamera.gd:47-59`).

## Step 3 — `presentation/EntityRenderer.gd`
1. Add `var motion: UnitMotion = null` beside `var fx` (`EntityRenderer.gd:10`), and two helpers:
   ```gdscript
   func _speed(e: Entity) -> float:
       return motion.speed_of(e.id) if motion != null else 0.0
   func _t() -> float:
       return motion.time if motion != null else 0.0
   ```
2. In `_draw_unit`, facing-strip branch (`EntityRenderer.gd:108-123`):
   - Replace lines `118-123` — the sim-tick bob **and** the existing
     `draw_texture_rect_region(tex, box, region, Color.WHITE)` call right after it (the new block
     draws the sprite itself in both branches; leaving the old call would draw it twice, un-rocked,
     on top of the rotors) — with the following, directly after `var box := _scaled_sprite_box(...)` (117):
     ```gdscript
     var armor: String = e.def_data.get("armorClass", "")
     var spd := _speed(e)
     box.position.y += UnitMotion.bob_offset(armor, _t(), spd, e.id) + UnitMotion.hover_offset(armor, _t(), e.id)
     var rock := UnitMotion.rock_angle(armor, _t(), spd, e.id)
     if rock != 0.0:
         draw_set_transform(box.get_center(), rock, Vector2.ONE)
         draw_texture_rect_region(tex, Rect2(-box.size * 0.5, box.size), region, Color.WHITE)
         draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
     else:
         draw_texture_rect_region(tex, box, region, Color.WHITE)
     if e.is_airborne:
         _draw_rotors(e, box, armor)
     ```
     (The rotate-around-centre pattern is the one the single-sprite branch already uses,
     `EntityRenderer.gd:134-136`.)
   - Single-sprite branch (`124-136`): apply the same `bob_offset + hover_offset` to
     `draw_pos.y` and add `rock` to `angle`. No rotor call there (no such unit has a strip-less
     sprite today; keep it simple).
3. Rotor blur overlay, new function. Both `AirLight` VC sprites are quadcopters with arms to the
   four corners (`assets/sprites/rendered/VC-U02.png`, `VC-U03.png`); the `AirHeavy` ones are a
   fixed-wing (`VC-U11`) and a saucer (`VC-U13`), so `AirHeavy` gets hover only (`rotors: 0`) —
   a rotor disc on a fixed-wing would lie.
   ```gdscript
   const ROTOR_DISC := Color(0.85, 0.92, 1.0, 0.10)
   const ROTOR_BLADE := Color(0.90, 0.95, 1.0, 0.55)
   ## Spinning 2-blade cross + faint disc at each rotor. Corners of the drawn box, not yaw-
   ## rotated: a quad is 4-fold symmetric so this is exact at yaw multiples of 90 deg and a
   ## cheap cheat in between. Blades, not a disc, so each frame shows a different phase
   ## (the 3D prototype learned this the hard way — see presentation3d/Drone3D.gd:20-24).
   func _draw_rotors(e: Entity, box: Rect2, armor: String) -> void:
       var n: int = UnitMotion.params(armor).get("rotors", 0)
       if n <= 0:
           return
       var r := minf(box.size.x, box.size.y) * 0.17
       var c := box.get_center()
       var offs := [Vector2(-0.30, -0.30), Vector2(0.30, -0.30), Vector2(-0.30, 0.30), Vector2(0.30, 0.30)]
       for i in range(mini(n, offs.size())):
           var p: Vector2 = c + Vector2(offs[i].x * box.size.x, offs[i].y * box.size.y)
           var a := UnitMotion.rotor_angle(_t(), e.id) * (1.0 if i % 2 == 0 else -1.0)
           draw_set_transform(p, a, Vector2(1.0, 0.7))   # 0.7: the 3/4 view foreshortens the disc
           draw_circle(Vector2.ZERO, r, ROTOR_DISC)
           draw_line(Vector2(-r, 0), Vector2(r, 0), ROTOR_BLADE, 1.5)
           draw_line(Vector2(0, -r), Vector2(0, r), ROTOR_BLADE, 1.5)
           draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
   ```
   Draw the rotors **after** the sprite so they sit on top. Leave the shadow code
   (`100-105`), health bar, hit flash and selection ring exactly as they are.

## Step 4 — `presentation/FxRenderer.gd`
1. Add `var motion: UnitMotion = null` beside `var events` (`FxRenderer.gd:16`).
2. Replace the ground-unit branch of `_on_game_tick` (`FxRenderer.gd:55-58`) with:
   ```gdscript
   if e.kind == "unit" and not e.is_airborne and e.movement != null:
       var armor: String = e.def_data.get("armorClass", "")
       var spd: float = motion.speed_of(e.id) if motion != null else 0.0
       if UnitMotion.dust_due(armor, tick, e.id, spd):
           var n: int = UnitMotion.params(armor).get("dust_n", 1)
           for i in range(n):
               var back: Vector2 = e.position - e.movement.facing * 10.0
               _spawn("puff", back + _jitter(4.0 + 2.0 * i), _jitter(6.0) - e.movement.facing * 8.0, 0.5, 4.0 + 1.0 * i, DUST)
   ```
   Keep the `elif e.kind == "structure"` smoke branch (`59-63`) untouched. Net effect: no dust
   while a "moving" unit is actually stuck; Light keeps today's 4 Hz cadence; Medium 3 Hz; Heavy
   2.5 Hz with two bigger puffs. (`game_tick` is emitted at `Simulation.gd:183` before entities
   move that tick and `motion.sample()` runs after `sim.step()`, so `dust_due` sees the previous
   tick's speed — a one-tick lag. Harmless; do not chase it.)

## Test — `tests/test_p3_03_motion.gd` (new; harness style of `tests/test_phase7.gd`)
`extends SceneTree`, `_init`, `_check/_fail/_run/_finish` copied verbatim from
`tests/test_phase7.gd:167-183`, result line `P3_03_RESULT: ALL PASS`. Checks:
```gdscript
# --- pure helpers: 0 at rest, non-zero moving, bounded ---
for armor in ["Infantry", "HeavyInfantry", "Light", "Medium", "Heavy", "AirLight", "AirHeavy", ""]:
	var at_rest_zero := true
	for i in range(60):
		if UnitMotion.bob_offset(armor, i / 60.0, 0.0, 3) != 0.0 or UnitMotion.rock_angle(armor, i / 60.0, 0.0, 3) != 0.0:
			at_rest_zero = false
	_check(at_rest_zero, "%s: bob and rock are 0 at rest" % armor)
for armor in ["Light", "Medium", "Heavy"]:
	var amp: float = UnitMotion.P[armor]["bob_px"]
	var seen_nonzero := false
	var bounded := true
	for i in range(60):
		var v := UnitMotion.bob_offset(armor, i / 60.0, 100.0, 3)
		seen_nonzero = seen_nonzero or v != 0.0
		bounded = bounded and absf(v) <= amp + 0.0001
	_check(seen_nonzero and bounded, "%s: bob moves and stays within +-%.1f px" % [armor, amp])
	_check(UnitMotion.rock_angle(armor, 0.13, 100.0, 3) != 0.0, "%s: rocks while moving" % armor)
var infantry_vals := {}
for i in range(120):
	infantry_vals[UnitMotion.bob_offset("Infantry", i / 60.0, 60.0, 3)] = true
_check(infantry_vals.size() == 2 and infantry_vals.has(0.0) and infantry_vals.has(-1.5), "Infantry: 2-frame walk bob (0 / -1.5)")
_check(UnitMotion.hover_offset("AirLight", 0.2, 3) != 0.0 and UnitMotion.hover_offset("Light", 0.2, 3) == 0.0, "hover: air only, on at rest")
_check(UnitMotion.rotor_angle(1.0 / 15.0) != UnitMotion.rotor_angle(2.0 / 15.0), "rotor phase changes every tick")
# --- dust cadence ---
var dust_rest := 0
var dust_move := 0
for t in range(60):
	if UnitMotion.dust_due("Light", t, 7, 0.0): dust_rest += 1
	if UnitMotion.dust_due("Light", t, 7, 100.0): dust_move += 1
_check(dust_rest == 0, "no dust at rest")
_check(dust_move == 15, "Light dust every 4 ticks -> 15 in 60 (got %d)" % dust_move)
_check(not UnitMotion.dust_due("AirLight", 4, 0, 100.0) and not UnitMotion.dust_due("Infantry", 4, 0, 100.0), "no dust for air / infantry")
# --- speed from position delta, against the real sim ---
var registry := ContentRegistry.new("res://content/data/")
registry.load_all()
var sim := Simulation.new(registry, GameEvents.new(), 50, 50)
sim.add_player("VC")
var motion := UnitMotion.new()
var tech := sim.spawn_unit("VC-U04", "VC", Vector2(600, 1500))
for i in range(3):
	sim.step(1.0 / 15.0); motion.sample(sim, 1.0 / 15.0)
_check(motion.speed_of(tech) == 0.0, "idle unit: speed 0")
sim.run_commands(0, [{"type": "MOVE", "entityIds": [tech], "targetPosition": Vector2(1400, 1500)}])
for i in range(10):
	sim.step(1.0 / 15.0); motion.sample(sim, 1.0 / 15.0)
_check(motion.speed_of(tech) >= UnitMotion.MOVING_SPEED, "moving unit: speed %.1f >= MOVING_SPEED" % motion.speed_of(tech))
_check(motion.speed_of(99999) == 0.0, "unknown id: speed 0")
```
`Simulation.ticks_per(4.0)` is 4 at 15 Hz (`Simulation.gd:11-12`), hence 15 emits in 60 ticks.
If `spawn_unit` returns -1 at (600, 1500) pick another open cell; `tests/test_phase7.gd:132` uses
that spot for a VC-U04 today.

## Screenshot — `docs/screenshot_2d_motion_strip.png`
```
cd ~/Dev/vibe-command
DISPLAY=:99 godot-4 --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution 1280x720 -- --motion --capture=$PWD/docs/screenshot_2d_motion.png --capture-frames=20,28,36,44
python3 - <<'EOF'
from PIL import Image
fs=[Image.open(f"docs/screenshot_2d_motion_{n:03d}.png") for n in (20,28,36,44)]
out=Image.new("RGB",(sum(f.width for f in fs),fs[0].height))
x=0
for f in fs: out.paste(f,(x,0)); x+=f.width
out.save("docs/screenshot_2d_motion_strip.png")
EOF
DISPLAY=:99 godot-4 --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution 1280x720 -- --capture=$PWD/docs/screenshot_2d_motion_wide.png --frame=90 --attack
```
Same 4-frames-side-by-side format as `docs/screenshot_3d_showcase_strip.png` (5120×720, no
scaling). In the strip: the Scout Quad's rotor crosses must be at a different angle in every
frame; the Technical and AI Battle Tank must have dust puffs trailing behind and sit at
different vertical offsets / tilts frame to frame; the Maker Crew must alternate between its two
bob positions. If a unit looks identical across all four frames, print
`motion.speed_of(id)` for it in `_capture_now` and check `sample()` is running before the redraw.

## Done when
- `presentation/UnitMotion.gd` exists and `tests/test_p3_03_motion.gd` prints `P3_03_RESULT: ALL PASS`;
  every other suite still `ALL PASS`, no `SCRIPT ERROR`.
- `git status --short` shows only (` M` or `??`): `presentation/UnitMotion.gd`,
  `presentation/EntityRenderer.gd`, `presentation/FxRenderer.gd`, `presentation/Game.gd`,
  `tests/test_p3_03_motion.gd`, the new `docs/screenshot_2d_motion*.png`. `*.import` and `*.uid`
  are gitignored — do not add them. Nothing under `core/`, `gameplay/`, `presentation3d/`. p3-01's
  shadow pass and helpers unchanged. `git add` only those files, never `-A` (the tree may carry
  unrelated untracked `tools/deepseek_*.py`).
- `docs/screenshot_2d_motion_strip.png` shows visibly different rotor / bob / dust phases in all
  four frames; `docs/screenshot_2d_motion_wide.png` shows the normal game unharmed (idle units do
  not bob, aircraft hover and show rotor blur).
- Commit, then `git push origin master`:
  `feat(2d): procedural unit motion — rotor blur + hover (air), rock + dust (vehicles), walk bob (infantry); --capture-frames`
- Report: `git log --oneline -1`, all test result lines, the list of `docs/screenshot_2d_motion*.png`.
