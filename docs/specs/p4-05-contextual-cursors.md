# p4-05 — Contextual mouse cursor: five procedural 32 px cursors, switched once per sim tick

**Tier:** C (DeepSeek Flash) · **Repo:** `~/Dev/vibe-command` · **Touches:** new `presentation/Cursors.gd`, `presentation/Game.gd` (one var, two-line hook in `_ready`, a `ticked` flag in `_process`, one new function), new `tests/test_cursors.gd`, new `tools/cursor_sheet.gd`, new `docs/cursors_sheet.png`

Why C: one new self-contained script whose rules are a pure function pinned by a headless test, a
six-line hook into `Game.gd`, and a fixed sheet recipe. No sim code, no new input bindings, no
judgement beyond a priority table this ticket spells out. There is **no L (art) step**: the repo has
no cursor art at all (`grep -rln cursor assets ui presentation` finds only code comments —
`presentation/SelectionInput.gd:125`, `presentation/Game.gd:113`, `ui/PlacementGhost.gd:5,85`; `ls assets`
= `models portraits sprites terrain`), so the five cursors are drawn procedurally at startup.

Read `docs/specs/README.md` first. Do NOT touch `core/`, `gameplay/`, or `presentation3d/`. This
ticket is presentation-only: the cursor is advisory and changes no rule in the sim.

**Order:** lands fifth and last — after p4-01, p4-02, p4-04, p4-03, in that landing order. It reads
p4-04's `SelectionInput.armed` enum (see "Contract with p4-04" below) and p4-02's
`MiniMapRenderer.contains_screen`, and its `--import` step for the new `class_name` should not sit
in the middle of the run. Line numbers in this ticket are HEAD `bd73d1c`; the earlier Phase 4
tickets have moved lines in `Game.gd`, so re-locate by the quoted code, not the number.

## Keys
**None.** This ticket binds no key or mouse button. It only *reads* the mouse position and p4-04's
armed state (`SelectionInput.armed`, ATTACK_MOVE only — there is no armed guard mode). (Phase 4 key
map for reference, do not re-bind here: A attack-move (armed), S stop, G hold (instant), H home,
Escape cancel/deselect, arrows/MMB-drag/edge pan, 0–9 groups, Ctrl+digit assign, Shift queue.)

## Why
The pointer is the OS arrow everywhere. An RTS tells you what a click will do *before* you click:
chevrons over ground ("they'll go here"), a crosshair over an enemy ("they'll shoot this"), a slash
where you can't go, brackets over your own unit ("this selects"). Right-click already branches on
exactly this information (`presentation/SelectionInput.gd:121-133` — `_issue_context_order` picks
`ATTACK` when `_unit_at_world` finds a hostile pickable entity, else `MOVE`), so the cursor just
shows that branch ahead of time.

## Current facts you will rely on (all read at HEAD `bd73d1c`)
- **Nothing reads the mouse per tick.** Locate `while _accum >= step:` in `Game._process` — it runs
  the fixed-tick loop (`while _accum >= step: sim.step(step) … _frame += 1`) and never reads the
  mouse; the mouse is read per *frame* only by RTSCamera — in `_process` (edge scroll, zoom anchor)
  and `_input` (middle drag) — and by `ui/PlacementGhost.gd:87`. `Game._on_game_tick`
  (`Game.gd:288-289`) is a `pass` stub connected at line 108.
- **What is under the mouse:** `presentation/SelectionInput.gd:82-96` `_unit_at_world(p) -> int` —
  nearest pickable unit within 24 px, else `_structure_at_world(p)` (lines 98-108, footprint rect
  test), else `-1`. `_pickable` (lines 75-78) already hides enemies the player cannot see
  (`sim.fog_sys.is_visible`). So a hostile id from `_unit_at_world` is *visible* by construction.
  `SelectionInput.new(null, sim)` instantiates headless and `_unit_at_world` works with a null camera
  (verified in a throwaway copy: own unit at (1005,1000) → id 1, visible enemy at (1100,1000) → id 2).
  `SelectionInput._unit_at_world` is byte-identical after p4-03/p4-04 (both promise it).
- **Screen → world:** `RTSCamera.screen_to_world(screen_pos)` — unchanged by p4-01.
- **Walkability:** `core/spatial/NavGrid.gd:43-48` `is_blocked(cx, cy, air=false)` (out of bounds →
  blocked; `air=true` reads the air layer, which map obstacles do not block — `Game.gd:181-182`
  `block_rect` defaults to ground). `world_to_cell(x, y)` at `NavGrid.gd:37-38`. `sim.grid_map` is
  created in `Simulation._init` (`core/simulation/Simulation.gd:48`) and replaced by `Game._build_map`
  (`Game.gd:172`).
- **Fog:** `gameplay/systems/FogOfWarSystem.gd:71-81` `state_at(faction, pos) -> int` — 0 unexplored,
  1 explored, 2 visible; `is_visible` (84-85) is `state_at == 2`. `sim.fog_sys` exists from
  `Simulation.gd:50`. Fog is recomputed inside `sim.step` (`Simulation.gd:192`), so reading it *after*
  the tick loop sees this tick's state.
- **Selection:** `core/simulation/Simulation.gd:34` `selected_ids: Array`, `:35 selected_faction`.
  `Game.PLAYER_FACTION = "VC"` (`Game.gd:24`). `Entity.is_airborne` (`core/simulation/Entity.gd:28`),
  `Entity.faction_id` (25), `Entity.kind` (26).
- **UI hit-testing:** the HUD is a `CanvasLayer` (`ui/HUD.gd:1`) whose containers use
  `MOUSE_FILTER_IGNORE` (`HUD.gd:36,48`) but whose buttons (`HUD.gd:79-86` STOP, `ui/BuildGrid.gd:77`)
  are real Controls, so `get_viewport().gui_get_hovered_control()` is non-null over them (method exists
  in 4.7 — probed via `ClassDB.class_has_method`). The minimap is a **Node2D**, not a Control
  (`presentation/MiniMapRenderer.gd:1`), so `gui_get_hovered_control()` is null over it;
  `MiniMapRenderer.contains_screen(screen_pos)` (p4-02) is the minimap hit-test; `minimap_rect()` is
  the rect it draws. The placement ghost exposes `active()` (`ui/PlacementGhost.gd:28-29`) and draws its
  own green/red preview, so the cursor stays an arrow while placing.
- **Godot API (probed headless on 4.7.2):** `Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)`,
  `fill`, `fill_rect`, `set_pixelv`, `get_pixel`, `resize(…, Image.INTERPOLATE_NEAREST)`, `blend_rect`
  all work; `Input.set_custom_mouse_cursor(image, shape, hotspot)` takes the **`Image` directly** and
  `Input.set_default_cursor_shape` are no-ops headless without error. **Do not** wrap the image in an
  `ImageTexture`: the DisplayServer cursor cache keeps that `Texture2D` alive past RenderingServer
  teardown, and a windowed run then exits with `ERROR: Texture with GL ID of NN: leaked 5460 bytes`
  ×5, `ERROR: 5 RID allocations of type 'N5GLES37TextureE' were leaked at exit` and
  `Parameter "RenderingServer::get_singleton()" is null` ×5 (verified on Xvfb :99; passing the bare
  `Image` gives an exit log identical to the unmodified repo). `img.save_png("res://docs/x.png")`
  writes into the project (err 0). **Do not** build a path from `OS.get_environment("HOME")` — the
  snap remaps `$HOME` to `~/snap/godot-4/common/` and the save fails (err 7). Custom cursors must be
  ≤ 256×256; ours are 32.
- `*.import` and `*.uid` are gitignored (`.gitignore:3,17`); `docs/*.png` already carry ignored
  `.import` siblings.

## Design (implement exactly this)
Five named cursors: `arrow`, `move`, `attack`, `invalid`, `select`. Each is registered **once** at
startup into its own `Input.CursorShape` slot (`set_custom_mouse_cursor` replaces the image for a
shape); switching is then one `Input.set_default_cursor_shape(shape)` call, made **only when the
name changes**, **at most once per sim tick** (from `Game._process`, after the tick loop, so fog and
positions are this tick's). While a Control is hovered the viewport uses that Control's own shape
(`CURSOR_ARROW` for every Control in this repo) which maps to our custom arrow — so HUD buttons and
the pause menu's full-rect `ColorRect` (`ui/PauseMenu.gd:14-17`) show the arrow even though
`Game._process` is paused.

Priority table (`cursor_for`), first match wins:

| # | Context | Cursor | Reason |
|---|---|---|---|
| 1 | over a Control, over the minimap rect, or placement ghost active | `arrow` | UI owns the pointer; ghost draws its own preview |
| 2 | armed == `"attack"` | `attack` | A-click attack-moves anywhere, even into fog/blocked |
| 3 | own unit/structure under mouse | `select` | clicking selects, whatever else is true |
| 4 | no selection | `arrow` | nothing to order |
| 5 | visible enemy under mouse | `attack` | mirrors `_issue_context_order` (SelectionInput.gd:128-130) |
| 6 | unexplored fog (`state_at == 0`) or blocked cell | `invalid` | advisory only — the sim still accepts the order (NavGrid `find_path` re-targets to the nearest open cell, `NavGrid.gd:77-81`); do **not** change that here |
| 7 | otherwise | `move` | explored (dim) fog is still orderable |

Walkability uses the ground layer unless **every** selected unit is airborne, in which case the air
layer (`is_blocked(cx, cy, true)`) — a drone selection must not see a slash over a rubble pad. That is
the only judgement call; it is five lines.

Hotspots: `arrow` (4,4) = the tip; the other four (16,16) = the centre. Every cursor has an opaque
pixel at (16,16) (the arrow's shaft runs down the diagonal through it; the others carry a 2×2 centre
dot, the slash crosses it) and at its hotspot.

### Contract with p4-04
p4-04 exposes `armed: SelectionInput.Armed` where `enum Armed { NONE, ATTACK_MOVE }`. G is an
instant HOLD, not an armed mode — there is no "guard" state to read.

## Change 1 — new file `presentation/Cursors.gd`
```gdscript
extends RefCounted
class_name Cursors
## p4-05 — contextual mouse cursor. Five 32x32 cursors drawn procedurally at startup (the repo
## ships no cursor art), each registered once into its own Input.CursorShape slot; switching is
## one set_default_cursor_shape() call, made only when the name changes. cursor_for() is pure so
## the headless test pins the rules without a window.

const NAMES: Array[String] = ["arrow", "move", "attack", "invalid", "select"]
const SIZE := 32

# Hotspot = the pixel that "is" the pointer. Arrow points from its tip; the rest from the centre.
const HOTSPOT := {
	"arrow": Vector2(4, 4), "move": Vector2(16, 16), "attack": Vector2(16, 16),
	"invalid": Vector2(16, 16), "select": Vector2(16, 16),
}
# One shape slot per cursor. set_custom_mouse_cursor() replaces the image of a shape;
# set_default_cursor_shape() then switches between them with no re-upload.
const SHAPE := {
	"arrow": Input.CURSOR_ARROW, "move": Input.CURSOR_MOVE, "attack": Input.CURSOR_CROSS,
	"invalid": Input.CURSOR_FORBIDDEN, "select": Input.CURSOR_POINTING_HAND,
}
const INK := {
	"arrow": Color(1.0, 1.0, 1.0), "move": Color(1.0, 1.0, 1.0), "attack": Color(1.0, 0.45, 0.25),
	"invalid": Color(0.95, 0.22, 0.20), "select": Color(0.35, 0.95, 1.0),
}
const OUTLINE := Color(0.05, 0.05, 0.08)

var _current: String = ""

## Pure rule table (see the ticket). Keys, all optional:
##   ui: bool           mouse over a Control / the minimap / placement ghost active
##   armed: String      "" | "attack"   (p4-04 armed ATTACK_MOVE)
##   has_selection: bool
##   hover_own: bool    own unit or structure under the mouse
##   hover_enemy: bool  visible enemy under the mouse
##   fog: int           FogOfWarSystem.state_at: 0 unexplored, 1 explored, 2 visible
##   walkable: bool     not NavGrid.is_blocked for the selection's path layer
static func cursor_for(ctx: Dictionary) -> String:
	if ctx.get("ui", false):
		return "arrow"
	var armed: String = str(ctx.get("armed", ""))
	if armed == "attack":
		return "attack"
	if ctx.get("hover_own", false):
		return "select"
	if not ctx.get("has_selection", false):
		return "arrow"
	if ctx.get("hover_enemy", false):
		return "attack"
	if int(ctx.get("fog", 2)) == 0 or not ctx.get("walkable", true):
		return "invalid"
	return "move"

## Register all five images once (Game._ready). Headless this is a silent no-op.
## The bare Image goes in — wrapping it in an ImageTexture leaks GL textures at exit.
func install() -> void:
	for n in NAMES:
		Input.set_custom_mouse_cursor(build(n), SHAPE[n], HOTSPOT[n])
	_current = ""
	apply("arrow")

## Switch only on change — called once per sim tick, so most calls return here.
func apply(name: String) -> void:
	if name == _current:
		return
	_current = name
	Input.set_default_cursor_shape(SHAPE[name])

func current() -> String:
	return _current

## 32x32 RGBA image for one cursor: the ink pixels with a 1-px dark outline underneath.
static func build(name: String) -> Image:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := _pixels(name)
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_stamp(img, ink, off, OUTLINE)
	_stamp(img, ink, Vector2i.ZERO, INK[name])
	return img

static func _stamp(img: Image, px: Array[Vector2i], off: Vector2i, col: Color) -> void:
	for p in px:
		var q := p + off
		if q.x >= 0 and q.y >= 0 and q.x < SIZE and q.y < SIZE:
			img.set_pixelv(q, col)

## Ink pixels per cursor. Duplicates are harmless.
static func _pixels(name: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match name:
		"arrow":
			# Diagonal arrow: head = triangle x+y<=22 from the (4,4) tip; 3-px shaft down the
			# diagonal to (26,26). The centre (16,16) sits on the shaft.
			for y in range(4, 19):
				for x in range(4, 19):
					if x + y <= 22:
						out.append(Vector2i(x, y))
			for i in range(11, 27):
				out.append(Vector2i(i, i))
				out.append(Vector2i(i + 1, i))
				out.append(Vector2i(i, i + 1))
		"move":
			# Four outward chevrons on the axes (2 px thick, 5 px arms) + 2x2 centre dot.
			for k in range(5):
				for t in range(2):
					out.append(Vector2i(16 - k, 4 + k + t));  out.append(Vector2i(16 + k, 4 + k + t))    # N
					out.append(Vector2i(16 - k, 27 - k - t)); out.append(Vector2i(16 + k, 27 - k - t))   # S
					out.append(Vector2i(4 + k + t, 16 - k));  out.append(Vector2i(4 + k + t, 16 + k))    # W
					out.append(Vector2i(27 - k - t, 16 - k)); out.append(Vector2i(27 - k - t, 16 + k))   # E
			out.append_array(_dot())
		"attack":
			# Crosshair: ring r 9..10.5, four axis ticks r 3..7, 2x2 centre dot.
			out.append_array(_ring(9.0, 10.5))
			for r in range(3, 8):
				out.append(Vector2i(16 + r, 16)); out.append(Vector2i(16 - r, 16))
				out.append(Vector2i(16, 16 + r)); out.append(Vector2i(16, 16 - r))
			out.append_array(_dot())
		"invalid":
			# Circle-slash: ring r 9.5..11.5 and a 2-px diagonal bar through the centre.
			out.append_array(_ring(9.5, 11.5))
			for i in range(8, 25):
				out.append(Vector2i(i, i))
				out.append(Vector2i(i + 1, i))
		"select":
			# Bracket corners of the 22-px box (5..26), 6 px long, 2 px thick, + 2x2 centre dot.
			for c in [Vector2i(5, 5), Vector2i(26, 5), Vector2i(5, 26), Vector2i(26, 26)]:
				var sx := 1 if c.x == 5 else -1
				var sy := 1 if c.y == 5 else -1
				for i in range(6):
					for t in range(2):
						out.append(Vector2i(c.x + sx * i, c.y + sy * t))
						out.append(Vector2i(c.x + sx * t, c.y + sy * i))
			out.append_array(_dot())
	return out

static func _ring(r0: float, r1: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(SIZE):
		for x in range(SIZE):
			var d := Vector2(x - 16, y - 16).length()
			if d >= r0 and d <= r1:
				out.append(Vector2i(x, y))
	return out

static func _dot() -> Array[Vector2i]:
	var out: Array[Vector2i] = [Vector2i(15, 15), Vector2i(16, 15), Vector2i(15, 16), Vector2i(16, 16)]
	return out
```
`Cursors` is a new `class_name`: run `godot-4 --headless --path . --import` once before any headless
run sees it (README rule).

## Change 2 — `presentation/Game.gd` (four small edits)
1. After line 12 (`var selection_input: SelectionInput`) add:
   ```gdscript
   var cursors: Cursors
   ```
2. In `_ready`, after p4-04's `hud.bind_input(selection_input)` line (which follows
   `selection_input.selection_changed.connect(_on_selection)`) add:
   ```gdscript
   	# p4-05 contextual cursor: five procedural images registered once; switched per tick below.
   	cursors = Cursors.new()
   	cursors.install()
   ```
3. In `_process` (lines 238-248): declare `var ticked := false` before the `while`, set `ticked = true`
   inside it (next to `_frame += 1`), and immediately after the loop — before the existing
   `if not _capture_frames.is_empty():` at line 249 — add:
   ```gdscript
   	if ticked:
   		_update_cursor()   # once per sim tick, never per frame
   ```
4. Append at the end of the file (after `_on_selection`, line 300):
   ```gdscript
   ## p4-05: build the cursor context from what is under the mouse and let Cursors pick.
   ## Presentation only — reads the sim, issues nothing.
   func _update_cursor() -> void:
   	var mpos := get_viewport().get_mouse_position()
   	var over_minimap := minimap.contains_screen(mpos)   # p4-02's hit-test: one source of truth
   	var world := rts_cam.screen_to_world(mpos)
   	var hover_id: int = selection_input._unit_at_world(world)   # fog-aware: enemies only if visible
   	var hover: Entity = sim.entities.get(hover_id) if hover_id >= 0 else null
   	# Path layer for the walkability read: air only when every selected unit is airborne.
   	var air_only := not sim.selected_ids.is_empty()
   	for id in sim.selected_ids:
   		var e: Entity = sim.entities.get(id)
   		if e == null or not e.is_airborne:
   			air_only = false
   			break
   	var cell := sim.grid_map.world_to_cell(world.x, world.y)
   	var ctx := {
   		"ui": get_viewport().gui_get_hovered_control() != null or over_minimap or placement_ghost.active(),
   		"armed": "attack" if selection_input.armed == SelectionInput.Armed.ATTACK_MOVE else "",
   		"has_selection": not sim.selected_ids.is_empty(),
   		"hover_own": hover != null and hover.faction_id == PLAYER_FACTION,
   		"hover_enemy": hover != null and hover.faction_id != PLAYER_FACTION,
   		"fog": sim.fog_sys.state_at(PLAYER_FACTION, world),
   		"walkable": not sim.grid_map.is_blocked(cell.x, cell.y, air_only),
   	}
   	cursors.apply(Cursors.cursor_for(ctx))
   ```
   (`minimap` is the `MiniMapRenderer` var at `Game.gd:18`.)
Nothing else in `Game.gd` changes. `_unit_at_world` is underscore-named but GDScript has no privacy
and `tests/test_shadows.gd` already calls `_footprint_rect` the same way; do not add a wrapper to
`SelectionInput` (p4-01…p4-04 edit that file — avoid a collision).

## Change 3 — new file `tools/cursor_sheet.gd` (review sheet)
`tools/` is Python today; this one-shot SceneTree script lives there because it is a tool, not a
test. It writes `docs/cursors_sheet.png`: the five cursors at 4× nearest-neighbour on a ground-grey
background with an 8-px gutter, and a magenta 4×4 mark on each hotspot.
```gdscript
extends SceneTree
## Renders the five p4-05 cursors 4x (nearest) into docs/cursors_sheet.png for review.
## Run: godot-4 --headless --path . --script tools/cursor_sheet.gd

const SCALE := 4
const GUTTER := 8

func _init() -> void:
	var n := Cursors.NAMES.size()
	var tile := Cursors.SIZE * SCALE
	var sheet := Image.create_empty(n * tile + (n - 1) * GUTTER, tile, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.30, 0.32, 0.28, 1.0))   # MapRenderer-ish ground so white ink reads
	for i in range(n):
		var name: String = Cursors.NAMES[i]
		var img := Cursors.build(name)
		img.resize(tile, tile, Image.INTERPOLATE_NEAREST)
		var at := Vector2i(i * (tile + GUTTER), 0)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
		var hs: Vector2 = Cursors.HOTSPOT[name]
		sheet.fill_rect(Rect2i(at + Vector2i(int(hs.x), int(hs.y)) * SCALE, Vector2i(SCALE, SCALE)), Color(1, 0, 1))
	var err := sheet.save_png("res://docs/cursors_sheet.png")
	print("CURSOR_SHEET: docs/cursors_sheet.png size=%s err=%d" % [sheet.get_size(), err])
	quit()
```

## Test — new file `tests/test_cursors.gd`
Copy the harness style of `tests/test_phase7.gd` (`extends SceneTree`, `_init`, `_check`, `_fail`,
`RESULT` line, `quit()`). No window, no sim needed — the rules are pure and the images are data.
```gdscript
extends SceneTree
## test_cursors.gd — p4-05: Cursors.cursor_for() priority table + procedural cursor images.
## Headless: `godot-4 --headless --path . --script tests/test_cursors.gd`

var failures: int = 0

func _init() -> void:
	# --- rules: one context per row of the ticket's priority table ---
	var base := {"ui": false, "armed": "", "has_selection": true, "hover_own": false,
		"hover_enemy": false, "fog": 2, "walkable": true}
	_rule(base, "move", "selection over walkable visible ground -> move")
	_rule(_with(base, {"has_selection": false}), "arrow", "no selection over ground -> arrow")
	_rule(_with(base, {"hover_own": true}), "select", "own unit -> select")
	_rule(_with(base, {"hover_own": true, "has_selection": false}), "select", "own unit, nothing selected -> select")
	_rule(_with(base, {"hover_enemy": true}), "attack", "visible enemy with a selection -> attack")
	_rule(_with(base, {"hover_enemy": true, "has_selection": false}), "arrow", "enemy but nothing selected -> arrow")
	_rule(_with(base, {"walkable": false}), "invalid", "blocked cell -> invalid")
	_rule(_with(base, {"fog": 0}), "invalid", "unexplored fog -> invalid")
	_rule(_with(base, {"fog": 1}), "move", "explored (dim) fog is still orderable -> move")
	_rule(_with(base, {"armed": "attack", "walkable": false, "fog": 0}), "attack", "A armed -> attack anywhere")
	_rule(_with(base, {"armed": "attack", "hover_own": true}), "attack", "A armed beats own-unit select")
	_rule(_with(base, {"ui": true, "hover_enemy": true, "armed": "attack"}), "arrow", "over HUD/minimap -> arrow beats everything")
	_rule({}, "arrow", "empty context -> arrow")

	# --- images: 32x32, opaque centre and hotspot, drawn but not a blob, distinct shape slots ---
	var slots := {}
	for n in Cursors.NAMES:
		var img: Image = Cursors.build(n)
		_check(img.get_size() == Vector2i(32, 32), "%s is 32x32" % n)
		_check(img.get_pixel(16, 16).a > 0.99, "%s centre pixel is opaque" % n)
		var hs: Vector2 = Cursors.HOTSPOT[n]
		_check(img.get_pixel(int(hs.x), int(hs.y)).a > 0.99, "%s hotspot pixel is opaque" % n)
		var opaque := 0
		for y in range(32):
			for x in range(32):
				if img.get_pixel(x, y).a > 0.5:
					opaque += 1
		_check(opaque >= 60 and opaque <= 700, "%s draws a shape, not a blob (%d opaque px)" % [n, opaque])
		slots[Cursors.SHAPE[n]] = true
	_check(slots.size() == Cursors.NAMES.size(), "each cursor owns its own Input.CursorShape slot")
	var arrow := Cursors.build("arrow")
	_check(arrow.get_pixel(2, 2).a < 0.01, "nothing above-left of the arrow tip (hotspot is the tip)")

	# --- apply() is idempotent state; Input calls are no-ops headless ---
	var c := Cursors.new()
	c.install()
	_check(c.current() == "arrow", "install() starts on arrow")
	c.apply("attack")
	_check(c.current() == "attack", "apply() switches")
	c.apply("attack")
	_check(c.current() == "attack", "apply() with the same name is a no-op")

	if failures == 0:
		print("CURSORS_RESULT: ALL PASS")
	else:
		print("CURSORS_RESULT: %d FAILURE(S)" % failures)
	quit()

func _rule(ctx: Dictionary, expected: String, msg: String) -> void:
	var got := Cursors.cursor_for(ctx)
	_check(got == expected, "%s (got %s)" % [msg, got])

func _with(base: Dictionary, over: Dictionary) -> Dictionary:
	var d := base.duplicate()
	for k in over:
		d[k] = over[k]
	return d

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: " + msg)
	else:
		_fail(msg)

func _fail(msg: String) -> void:
	failures += 1
	push_error("FAIL: " + msg)
	print("FAIL: " + msg)
```
The per-tick hook in `Game.gd` is a scene-tree path and is not exercised headless; it is verified by
reading (`ticked` flag → one `_update_cursor()` per tick) and by the in-game check below.

## Screenshot — `docs/cursors_sheet.png` (the cursor itself cannot be captured)
`Game._capture_now` saves `get_viewport().get_texture().get_image()` (`Game.gd:263`). The OS cursor
is composited by the window system, **not** drawn into the viewport, so the `--capture` recipe
cannot show it and no new `Game.gd` debug flag would help. Instead:
```
cd ~/Dev/vibe-command
godot-4 --headless --path . --import          # once: Cursors is a new class_name
godot-4 --headless --path . --script tools/cursor_sheet.gd
```
Expect `CURSOR_SHEET: docs/cursors_sheet.png size=(672, 128) err=0`.

Executor pixel checks (PIL 10.2 is installed; `tools/generate_terrain.py` already uses it):
```
python3 - <<'EOF'
from PIL import Image
im = Image.open("docs/cursors_sheet.png").convert("RGBA"); assert im.size == (672, 128), im.size
bg = im.getpixel((0, 127)); names = ["arrow","move","attack","invalid","select"]
hot = {"arrow": (4, 4)}
for i, n in enumerate(names):
    x0 = i * 136; hx, hy = hot.get(n, (16, 16))
    assert im.getpixel((x0 + hx*4 + 1, hy*4 + 1))[:3] == (255, 0, 255), n + " hotspot mark"
    ink = sum(1 for y in range(128) for x in range(x0, x0 + 128) if im.getpixel((x, y)) != bg)
    assert 900 < ink < 12000, (n, ink)
    print(n, "ok", ink)
EOF
```
F eyeballs the sheet (left→right: arrow, move, attack, invalid, select): the arrow points up-left with
its magenta mark on the tip; the move chevrons point outward N/E/S/W; the crosshair has a gap between
ticks and ring; the slash runs top-left→bottom-right through the red ring; the brackets frame an
empty box with a centre dot; every shape has a visible dark outline against the grey.

Executor leak check (the cursor images must not leak GL textures at exit — see the Godot API fact):
```
DISPLAY=:99 godot-4 --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution 1280x720 -- --capture=/tmp/cursor_leak_probe.png --frame=60 2>&1 | tee /tmp/cursor_leak_probe.log
grep -i leaked /tmp/cursor_leak_probe.log | grep -vc "ObjectDB instances"   # must print 0
grep -c "RID allocations" /tmp/cursor_leak_probe.log                       # must print 0
```
(The capture goes to `/tmp` on purpose so no extra PNG lands in `docs/`. The pre-existing
`N ObjectDB instances were leaked` warning is baseline and is the only `leaked` line allowed.)

In-game check for F (not capturable): run the game, select units, sweep the mouse over open ground
(chevrons), a rubble pad (slash), the black unexplored corner (slash), an own unit (brackets), a
build button or the minimap (arrow); press A (p4-04) → crosshair everywhere; Escape → back.

## Done when
- `godot-4 --headless --path . --script tests/test_cursors.gd` prints `CURSORS_RESULT: ALL PASS`.
- `godot-4 --headless --path . --script tools/cursor_sheet.gd` prints
  `CURSOR_SHEET: docs/cursors_sheet.png size=(672, 128) err=0` and the PIL checks above pass.
- The windowed leak check above: the exit log has no `Texture with GL ID … leaked` and no
  `RID allocations` lines (`grep -i leaked … | grep -vc "ObjectDB instances"` prints `0`,
  `grep -c "RID allocations"` prints `0`).
- The full loop from `docs/specs/README.md` shows every suite `ALL PASS` — 15 suites including the
  new one — and no `SCRIPT ERROR`.
- `git status --short` shows exactly ` M presentation/Game.gd`, `?? presentation/Cursors.gd`,
  `?? tests/test_cursors.gd`, `?? tools/cursor_sheet.gd`, `?? docs/cursors_sheet.png` from your work.
  Nothing under `core/`, `gameplay/`, `presentation3d/`. `*.import` and `*.uid` are gitignored — do not
  add them. The tree may carry unrelated untracked files (`tools/deepseek_id_probe.py`,
  `tools/deepseek_vision_check.py`); leave them alone — `git add` only the five files above, never `-A`.
- `grep -n "_update_cursor" presentation/Game.gd` shows exactly two hits: the call under `if ticked:`
  and the definition.
- Commit:
  `feat(input): contextual mouse cursor — five procedural 32px cursors, switched once per sim tick`
  Body (3–6 lines): no cursor art existed, so Cursors.gd draws arrow/move/attack/invalid/select at
  startup and registers each into its own CursorShape slot; Game._process builds a context
  (UI hover via gui_get_hovered_control + p4-02 minimap.contains_screen, p4-04 armed ATTACK_MOVE,
  selection, entity under mouse via SelectionInput._unit_at_world, fog state, NavGrid walkability)
  once per tick and switches only on change; advisory only, no sim change;
  docs/cursors_sheet.png for review since the OS cursor is not in viewport captures.
- Then `git push origin master`.
- Report: `git log --oneline -1`, the `CURSORS_RESULT` line, the `CURSOR_SHEET` line, the PIL
  output, and the two leak-check counts.
