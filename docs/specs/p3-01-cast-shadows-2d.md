# p3-01 — Cast shadows: one shadow pass under every unit and structure (2D)

**Tier:** C (DeepSeek Flash) · **Repo:** `~/Dev/vibe-command` · **Touches:** `presentation/EntityRenderer.gd`, new `tests/test_shadows.gd`, new `docs/screenshot_2d_shadows.png`

Why C: one presentation file changes, the new behaviour is pure geometry that a headless test pins
down exactly, and the screenshot is a fixed recipe. No sim code, no new systems, no design
judgement beyond a constant table. That is the Flash profile (single file, test-gated).

Read `docs/specs/README.md` first. Do NOT touch `core/` or `gameplay/` — the shadow reads
`Entity.position`, `Entity.is_airborne`, `Entity.def_data` and nothing else. The decision to
stay 2D is final; `presentation3d/` is shelved and must not be edited either.

**Order:** first Phase 3 ticket. p3-03 edits this same file afterwards, so land this one first.

## Why
Sprites look pasted onto the ground. The 3D prototype's one clear win was a real cast shadow
under everything (`presentation3d/Game3D.gd:136-141` — a `DirectionalLight3D` from the screen's
upper-left with `shadow_enabled = true`). The 2D renderer already has *contact* shadows, but
they are too tight to read as cast and they are drawn in the wrong place:

- `presentation/EntityRenderer.gd:73-74` — structure shadow is the footprint rect nudged by
  `Vector2(3, 4)`. Under a sprite that fills 94% of the pad (`STRUCTURE_FILL`, line 64) that leaves
  a 3–4 px sliver: invisible.
- `presentation/EntityRenderer.gd:100-105` — unit shadow is a circle of radius `size_px * 0.42`
  squashed to `Vector2(1.0, 0.55)`, offset `Vector2(2, 3)` on the ground or `Vector2(6, 10)` airborne,
  with colours `SHADOW_GROUND` / `SHADOW_AIR` (lines 65-66).
- Both are drawn **inside** `_draw_structure` / `_draw_unit`, i.e. interleaved with the sprites in
  the back-to-front loop at lines 30-50. So the shadow of a unit in front is painted *over* the
  sprite of the unit behind it. In a crowd this reads as dark smudges on sprites, not shadows on
  the ground.

The sun direction is fixed by the art: the sprite rig and the 3D prototype both light from the
screen's upper-left (`presentation3d/Game3D.gd:139` comment, `docs/art-direction-plan.md:70`), so
every 2D shadow falls **down-right**. `docs/art-direction-plan.md:74` already asks for the shadow
to be "separate, so it can be drawn under other units" — this ticket does exactly that.

## Current facts you will rely on (all in `presentation/EntityRenderer.gd`, HEAD `b261709`)
- Draw loop: `_draw()` lines 23-50. Sorts `sim.entities.values()` by `_sort_y` (lines 147-150),
  then per entity: skips `not e.alive` (33), culls to the camera rect (35-38), applies the fog
  rule for enemy entities (41-46), then `_draw_structure(e)` (48) or `_draw_unit(e, cam_rect)` (50).
  Any other `e.kind` (Entity.gd:26 allows `"projectile"`) draws nothing.
- Unit size: line 99 — `UNIT_PX.get(e.def_data.get("armorClass", ""), UNIT_PX_DEFAULT) * SpriteAtlas.scale(e.def_id)`.
  `UNIT_PX` table lines 58-62, `UNIT_PX_DEFAULT` line 63. `SpriteAtlas.scale()` is
  `presentation/SpriteAtlas.gd:94-96` (manifest `scale`, default 1.0; every rendered unit and
  VC-B03 carry 1.4).
- Structure footprint: `_footprint_rect(e)` lines 163-168 — anchor-cell math, `NavGrid.CELL`
  (= 40.0, `core/spatial/NavGrid.gd:8`). For VC-B03 (footprint `[2, 2]`) placed at (1000, 1200) it
  returns `Rect2(960, 1160, 80, 80)` (verified headless).
- Airborne flag: `core/simulation/Entity.gd:28` `is_airborne`, set at line 82 from the move
  profile's `pathLayer == "air"` (`content/data/moveprofiles.json:9-10`, `prof_air` /
  `prof_air_fast`). VC-U02 uses `prof_air` (`content/data/units.json:1289`).
- Constructor: `_init(simulation: Simulation, cam: RTSCamera)` lines 19-21 — `cam` may be null;
  `EntityRenderer.new(sim, null)` instantiates fine headless (verified).
- `EntityRenderer` sets no `z_index` (it is 0). All ordering you need is *inside* its own `_draw`,
  so drawing shadows first in that function is sufficient — no node changes.
- The build-site fade: lines 84-85 scale the sprite alpha by `0.45 + 0.55 * construction.fraction()`.

## Change — `presentation/EntityRenderer.gd`

### 1. Replace the two shadow colours with one table
Delete lines 65-66 (`SHADOW_GROUND`, `SHADOW_AIR` — nothing else uses them; `grep -rn SHADOW_ presentation ui`
to confirm) and add, right after `STRUCTURE_FILL` (line 64):

```gdscript
# --- p3-01 cast shadows: one table, one pass, drawn before every sprite ---
# Sun is screen upper-left (same as presentation3d/Game3D.gd _build_lighting and the sprite
# rig), so every shadow falls down-right. Unit offsets are world px; rx/ry are fractions of the
# unit's draw size (UNIT_PX × atlas scale). Structure offset/shear are fractions of the
# footprint height so a taller pad throws a longer shadow. alpha = peak darkness.
const SHADOW := {
	"ground":    {"offset": Vector2(5.0, 7.0),   "rx": 0.46, "ry": 0.22, "alpha": 0.40},
	"air":       {"offset": Vector2(16.0, 24.0), "rx": 0.32, "ry": 0.15, "alpha": 0.20},
	"structure": {"offset": Vector2(0.10, 0.14), "shear": 0.22, "alpha": 0.38},
}
const SHADOW_COLOR := Color(0.03, 0.03, 0.06)      # near-black, slightly cool; alpha from the table
const SHADOW_FEATHER := [1.0, 0.86, 0.72]           # three stacked layers = a cheap soft edge
```

### 2. Pure-geometry helpers (public, so the test can call them; no drawing inside)
Add near `_footprint_rect`:

```gdscript
## One source of truth for a unit's draw size (was inlined in _draw_unit).
func _unit_size_px(e: Entity) -> float:
	return UNIT_PX.get(e.def_data.get("armorClass", ""), UNIT_PX_DEFAULT) * SpriteAtlas.scale(e.def_id)

## Bounding rect of the entity's cast shadow in world px. Units: the ellipse's box, centred at
## position + offset. Structures: the box around structure_shadow_quad().
func shadow_rect(e: Entity) -> Rect2:
	if e.kind == "structure":
		var q := structure_shadow_quad(e)
		var r := Rect2(q[0], Vector2.ZERO)
		for p in q:
			r = r.expand(p)
		return r
	var s: Dictionary = SHADOW["air"] if e.is_airborne else SHADOW["ground"]
	var half: Vector2 = Vector2(s["rx"], s["ry"]) * _unit_size_px(e)
	return Rect2(e.position + s["offset"] - half, half * 2.0)

## The pad sheared toward lower-right: bottom edge moves by offset, top edge by offset + shear,
## so a tall box reads as leaning away from the sun. Order: TL, TR, BR, BL.
func structure_shadow_quad(e: Entity) -> PackedVector2Array:
	var s: Dictionary = SHADOW["structure"]
	var fp := _footprint_rect(e)
	var off: Vector2 = s["offset"] * fp.size.y
	var shear := Vector2(s["shear"] * fp.size.y, 0.0)
	return PackedVector2Array([
		fp.position + off + shear,
		Vector2(fp.end.x, fp.position.y) + off + shear,
		fp.end + off,
		Vector2(fp.position.x, fp.end.y) + off,
	])
```
In `_draw_unit`, replace the right-hand side of line 99 with `_unit_size_px(e)` (same value, one place).

### 3. The shadow pass
Restructure `_draw()` so the visibility filter is one helper and the loop runs twice:

```gdscript
func _draw() -> void:
	if sim == null:
		return
	var cam_rect := _visible_world_rect()
	var ordered: Array = []
	for e in sim.entities.values():
		if _drawable(e, cam_rect):
			ordered.append(e)
	# 3/4-view sprites overlap; draw back-to-front by ground position so a unit in
	# front of a building covers it, not the other way round. Structures sort by the
	# bottom of their footprint (where they touch the ground).
	ordered.sort_custom(func(a: Entity, b: Entity) -> bool: return _sort_y(a) < _sort_y(b))
	# Shadow pass: every shadow lands on the ground before any sprite goes up, so the
	# shadow of a unit in front never paints over the sprite of the unit behind it.
	for e in ordered:
		_draw_shadow(e)
	for e in ordered:
		if e.kind == "structure":
			_draw_structure(e)
		else:
			_draw_unit(e, cam_rect)

## Same rules the old loop applied inline: alive, on screen, and (for enemies) fog-visible —
## structures persist as silhouettes through explored fog, units vanish (§5.6).
func _drawable(e: Entity, cam_rect: Rect2) -> bool:
	if not e.alive or (e.kind != "unit" and e.kind != "structure"):
		return false
	if e.position.x < cam_rect.position.x or e.position.x > cam_rect.end.x:
		return false
	if e.position.y < cam_rect.position.y or e.position.y > cam_rect.end.y:
		return false
	if fog_sys != null and e.faction_id != player_faction:
		var vis := fog_sys.is_visible(player_faction, e.position)
		if e.kind == "unit" and not vis:
			return false
		if e.kind == "structure" and fog_sys.state_at(player_faction, e.position) == 0:
			return false
	return true

func _draw_shadow(e: Entity) -> void:
	var col := SHADOW_COLOR
	if e.kind == "structure":
		col.a = SHADOW["structure"]["alpha"]
		if e.construction != null and not e.construction.is_built():
			col.a *= 0.45 + 0.55 * e.construction.fraction()   # same fade as the build-site sprite
		_draw_feathered(structure_shadow_quad(e), col)
	else:
		var s: Dictionary = SHADOW["air"] if e.is_airborne else SHADOW["ground"]
		col.a = s["alpha"]
		_draw_feathered(_ellipse_points(shadow_rect(e)), col)

## Soft edge without a shader: the polygon drawn SHADOW_FEATHER.size() times, each layer scaled
## about its centroid and carrying a third of the alpha, so the rim fades in three steps.
func _draw_feathered(points: PackedVector2Array, col: Color) -> void:
	var c := Vector2.ZERO
	for p in points:
		c += p
	c /= float(points.size())
	var layer := col
	layer.a = col.a / float(SHADOW_FEATHER.size())
	for k in SHADOW_FEATHER:
		var scaled := PackedVector2Array()
		for p in points:
			scaled.append(c + (p - c) * k)
		draw_colored_polygon(scaled, layer)

func _ellipse_points(r: Rect2, n: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c := r.get_center()
	var half := r.size * 0.5
	for i in range(n):
		var a := TAU * i / float(n)
		pts.append(c + Vector2(cos(a) * half.x, sin(a) * half.y))
	return pts
```

### 4. Remove the old inline shadows
- `_draw_structure`: delete lines 73-74 (the comment and the `draw_rect(... SHADOW_GROUND)`).
- `_draw_unit`: delete lines 100-105 (the comment, `shadow_off`, `shadow_col`, the
  `draw_set_transform` / `draw_circle` / reset). The sprite code that follows is unchanged.

Nothing else in the file changes. Do not touch `_sort_y`, `_draw_health`, `_draw_brackets`,
selection rings or hit flashes.

## Test — new file `tests/test_shadows.gd`
Copy the harness style of `tests/test_phase7.gd` (`extends SceneTree`, `_init`, `_check`, `_fail`,
`RESULT` line, `quit()`). The renderer is never added to the tree; the helpers are pure math.

```gdscript
extends SceneTree
## test_shadows.gd — p3-01: EntityRenderer cast-shadow geometry (pure math, no drawing).
## Headless: `godot-4 --headless --path . --script tests/test_shadows.gd`

var failures: int = 0

func _init() -> void:
	var registry := ContentRegistry.new("res://content/data/")
	registry.load_all()
	var events := GameEvents.new()
	var sim := Simulation.new(registry, events, 50, 50)
	sim.add_player("VC")
	var r := EntityRenderer.new(sim, null)

	var inf: Entity = sim.entities[sim.spawn_unit("VC-U01", "VC", Vector2(1000, 1000))]
	var heavy: Entity = sim.entities[sim.spawn_unit("VC-U12", "VC", Vector2(1100, 1000))]
	var air: Entity = sim.entities[sim.spawn_unit("VC-U02", "VC", Vector2(1200, 1000))]
	var bld: Entity = sim.entities[sim.spawn_structure("VC-B03", "VC", Vector2(1000, 1200), true)]
	_check(inf.def_data.get("armorClass") == "Infantry" and heavy.def_data.get("armorClass") == "Heavy",
		"premise: VC-U01 Infantry, VC-U12 Heavy")
	_check(air.is_airborne and not inf.is_airborne, "premise: VC-U02 airborne, VC-U01 not")

	var g: Dictionary = EntityRenderer.SHADOW["ground"]
	var a: Dictionary = EntityRenderer.SHADOW["air"]

	# --- infantry: ellipse centred at position + ground offset, sized from UNIT_PX × atlas scale ---
	var inf_px: float = EntityRenderer.UNIT_PX["Infantry"] * SpriteAtlas.scale("VC-U01")
	var ri := r.shadow_rect(inf)
	_check(ri.get_center().is_equal_approx(inf.position + g["offset"]), "infantry shadow centre = position + ground offset")
	_check(is_equal_approx(ri.size.x, 2.0 * g["rx"] * inf_px) and is_equal_approx(ri.size.y, 2.0 * g["ry"] * inf_px),
		"infantry shadow size derives from UNIT_PX (%s)" % ri.size)
	_check(ri.size.y < ri.size.x, "ground shadow is a flattened ellipse")
	_check(g["offset"].x > 0.0 and g["offset"].y > 0.0, "ground shadow falls down-right")

	# --- Heavy vehicle: same rule, bigger sprite -> bigger shadow ---
	var heavy_px: float = EntityRenderer.UNIT_PX["Heavy"] * SpriteAtlas.scale("VC-U12")
	var rh := r.shadow_rect(heavy)
	_check(is_equal_approx(rh.size.x, 2.0 * g["rx"] * heavy_px), "heavy shadow width from UNIT_PX Heavy")
	_check(rh.size.x > ri.size.x, "heavy shadow wider than infantry shadow")

	# --- airborne: smaller, lighter, further offset ---
	var air_px: float = EntityRenderer.UNIT_PX["AirLight"] * SpriteAtlas.scale("VC-U02")
	var ra := r.shadow_rect(air)
	_check(ra.get_center().is_equal_approx(air.position + a["offset"]), "air shadow centre uses the air offset")
	_check(a["offset"].length() > g["offset"].length(), "air offset is further than ground offset")
	_check(ra.size.x < 2.0 * g["rx"] * air_px, "air shadow smaller than the ground rule would give")
	_check(a["alpha"] < g["alpha"], "air shadow lighter than ground shadow")

	# --- 2x2 structure: sheared footprint quad, down-right only ---
	var fp := r._footprint_rect(bld)
	_check(fp.size == Vector2(80, 80), "premise: VC-B03 footprint is 2x2 cells (%s)" % fp.size)
	var s: Dictionary = EntityRenderer.SHADOW["structure"]
	var off: Vector2 = s["offset"] * fp.size.y
	var q := r.structure_shadow_quad(bld)
	_check(q.size() == 4, "structure shadow is a quad")
	_check(q[3].is_equal_approx(Vector2(fp.position.x, fp.end.y) + off), "quad bottom-left = pad bottom-left + offset")
	_check(q[2].is_equal_approx(fp.end + off), "quad bottom-right = pad bottom-right + offset")
	_check(is_equal_approx(q[0].x - q[3].x, s["shear"] * fp.size.y), "top edge sheared right by shear × pad height")
	_check(is_equal_approx(q[0].y - fp.position.y, off.y), "top edge sits offset.y below the pad top")
	var rb := r.shadow_rect(bld)
	_check(rb.position.x >= fp.position.x and rb.position.y >= fp.position.y, "structure shadow never extends up/left of the pad")
	_check(is_equal_approx(rb.size.y, fp.size.y), "structure shadow height = pad height")

	r.free()   # Node2D never entered the tree; free it so quit() doesn't report a leaked CanvasItem
	if failures == 0:
		print("SHADOWS_RESULT: ALL PASS")
	else:
		print("SHADOWS_RESULT: %d FAILURE(S)" % failures)
	quit()

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
No new `class_name` is introduced, so no `--import` step is needed.

## Screenshot
```
cd ~/Dev/vibe-command
DISPLAY=:99 godot-4 --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution 1280x720 -- --capture=$PWD/docs/screenshot_2d_shadows.png --frame=90 --attack
```
(`--capture` / `--frame` / `--attack` are parsed in `presentation/Game.gd:115-130`; the main scene
is `scenes/Main.tscn`, `project.godot:8`.) Look at the PNG before committing:
- every unit ringing the Garage Core has a dark ellipse under it, offset down-right, sitting
  *under* neighbouring sprites, not on top of them;
- the two AirLight drones (VC-U02, VC-U03) have a smaller, fainter ellipse noticeably further
  down-right — they read as hovering;
- each structure has a dark sheared quad spilling below and to the right of its pad;
- the sky-facing edges of every shadow are a soft 3-step gradient, not a hard line.
If a shadow reads as too heavy or too tight, adjust numbers in `SHADOW` only (the test asserts the
derivation from the table, not the literal values) and recapture.

## Done when
- `godot-4 --headless --path . --script tests/test_shadows.gd` prints `SHADOWS_RESULT: ALL PASS`.
- The full loop from `docs/specs/README.md` shows every suite `ALL PASS`, no `SCRIPT ERROR`.
- `git status --short` shows exactly ` M presentation/EntityRenderer.gd`, `?? tests/test_shadows.gd`,
  `?? docs/screenshot_2d_shadows.png` from your work. Nothing under `core/`, `gameplay/`,
  `presentation3d/`. `*.import` and `*.uid` are gitignored — do not add them. The tree may carry
  unrelated untracked files (e.g. `tools/deepseek_*.py`); leave them alone — `git add` only the
  three files above, never `-A`.
- `grep -n "SHADOW_GROUND\|SHADOW_AIR" presentation/EntityRenderer.gd` returns nothing.
- `docs/screenshot_2d_shadows.png` passes the four visual checks above.
- Commit, then `git push origin master`:
  `feat(2d): cast-shadow pass under units and structures — one table, drawn before sprites`
  Body (3–6 lines): shadows moved out of the per-sprite draw into a pass that runs first; ellipse
  for units / sheared pad quad for structures; airborne smaller-lighter-further; three-layer
  feather for a soft edge; sun direction matches the 3D prototype and the sprite rig.
- Report: `git log --oneline -1`, the `SHADOWS_RESULT` line, and the path of the screenshot.
