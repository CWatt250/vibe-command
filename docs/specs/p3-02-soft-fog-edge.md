# p3-02 — Soft, feathered fog-of-war edge in the 2D game

**Tier:** C (DeepSeek Flash) · **Repo:** `~/Dev/vibe-command` · **Touches:** `presentation/FogRenderer.gd`, new `tests/test_fog_soft.gd`, `docs/visual-roadmap.md` (2 lines), new `docs/screenshot_2d_fog.png`

Read `docs/specs/README.md` first. **Order:** second Phase 3 ticket (after p3-01; it touches a
different file, so it can also run in parallel). This ticket is presentation-only: **do not touch anything under
`core/` or `gameplay/`**, do not touch `presentation/MiniMapRenderer.gd` or `presentation/Game.gd`.

Why tier C: one file of pure array math with the exact algorithm and the exact expected numbers
below, gated by a headless test, plus one screenshot. L (Ornith) could attempt it, but the test
asserts exact texel values, so a single off-by-one in the four filter passes turns into a retry
loop that costs more than Flash's ~$0.005.

## Problem (what is on screen today)
`presentation/FogRenderer.gd` already packs the fog grid into a one-texel-per-cell RGBA `Image`
(`FogRenderer.gd:32-37`), re-packs it only when `fog_sys.state_bytes()` changes
(`FogRenderer.gd:47-64`), and draws it once, scaled to the world, with
`texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR` (`FogRenderer.gd:31`, `:44`). That is the
"V2" fog from commit `1f4bfd6`. The three texel states are
`RGBA_UNEXPLORED = [0,0,0,255]`, `RGBA_EXPLORED = [6,9,16,165]`, `RGBA_VISIBLE = [0,0,0,0]`
(`FogRenderer.gd:23-25`).

So the edge is *not* a hard cutout any more — but it still looks blocky. Look at
`docs/screenshot_v2_fog.png`: the visibility ring around the VC base is a staircase of 40-px
cell steps, each step softened by a 40-px bilinear ramp. Bilinear filtering only interpolates
between adjacent texels, so the ramp is exactly one cell (`NavGrid.CELL = 40.0`,
`core/spatial/NavGrid.gd:8`; `Simulation.gd:50` builds `fog_sys` with that cell size) and the
cell-quantised circle from `FogOfWarSystem._stamp_circle` (`gameplay/systems/FogOfWarSystem.gd:52-68`)
shows straight through it. What is missing is a filter whose support is wider than one cell.

What the 3D prototype taught us: `presentation3d/Game3D.gd:173-198` reuses `FogRenderer`
**verbatim** inside a 2000×2000 `SubViewport` (`Game3D.gd:177-187`) and projects it on a
`PlaneMesh` with `TEXTURE_FILTER_NEAREST` (`Game3D.gd:196`). No fog code changed, so the 3D
edge is the same one-cell ramp; `docs/screenshot_3d_wide.png` merely reads softer because the
whole frame is lower-contrast (the lit ground plane under `Game3D.gd:156-165`'s environment is
not pitch black) and the tilt foreshortens the steps. There is nothing to port from
`presentation3d/` — the fix is a wider filter in the 2D renderer.

## Change (all in `presentation/FogRenderer.gd`)
Keep `texture` exactly as it is — it is the crisp one-texel-per-cell fog that the minimap draws
(`Game.gd:78` hands `fog_renderer.texture` to `minimap.fog_texture`; `MiniMapRenderer.gd:72-73`
draws it). Add a second, softened texture and draw *that* in the world.

Algorithm on the per-cell alpha (grid `w × h`, `w = fog_sys.grid_width()`, `h = fog_sys.grid_height()`):
1. `alpha[i] = rgba[3]` of the cell's state (255 unexplored / 165 explored / 0 visible).
2. **3×3 min filter**, separable (horizontal pass into `_tmp`, vertical pass back into `_alpha`),
   edges clamped. This erodes fog / dilates visibility by exactly one cell.
3. **3×3 box blur**, separable, integer `/ 3`, edges clamped.
4. **Pin:** every cell whose sim state is `2` (visible) is forced back to alpha `0`.

Result on a straight edge, in cells from the last visible cell outward: `0, 85, 170, 255`
(unexplored side) or `0, 55, 110, 165` (explored side). That is a 3-cell = 120 world-px
gradient replacing the 1-cell ramp; the staircase averages away. The RGB of each texel stays
per-state (unexplored black, explored blue-black), so explored-but-not-visible remains **dimmed,
not black**, exactly as today.

### 1. New members (after `var _last_states: PackedByteArray` at line 19)
```gdscript
## World-space overlay: fog alpha eroded by one cell then 3x3 box-blurred, visible cells
## pinned clear. `texture` above stays crisp (one texel per cell) for the minimap.
var soft_texture: ImageTexture

var _soft_image: Image
var _soft_data: PackedByteArray
var _alpha: PackedByteArray
var _tmp: PackedByteArray
```

### 2. `_init` — allocate the soft buffers (after `texture = ImageTexture.create_from_image(_image)`, line 37)
```gdscript
	_soft_data.resize(w * h * 4)
	_soft_data.fill(0)
	_alpha.resize(w * h)
	_tmp.resize(w * h)
	_soft_image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	soft_texture = ImageTexture.create_from_image(_soft_image)
```

### 3. `_draw` — draw the soft texture (line 44)
Change `draw_texture_rect(texture, ...)` to `draw_texture_rect(soft_texture, ...)`. Nothing else
in `_draw` changes; `texture_filter` stays `LINEAR` (line 31).

### 4. `_refresh_texture` — fill both textures
Replace lines 46-64 (from the `## Re-pack the grid only when a cell actually changed state.` doc
comment on line 46 through the end of `_refresh_texture`) with:
```gdscript
## Re-pack the grid only when a cell actually changed state.
func _refresh_texture() -> void:
	var states := fog_sys.state_bytes(player_faction)
	if states == _last_states:
		return
	_last_states = states
	var w := fog_sys.grid_width()
	var h := fog_sys.grid_height()
	for i in range(states.size()):
		var rgba: PackedByteArray
		match states[i]:
			0: rgba = RGBA_UNEXPLORED
			1: rgba = RGBA_EXPLORED
			_: rgba = RGBA_VISIBLE
		var o := i * 4
		_data[o] = rgba[0]
		_data[o + 1] = rgba[1]
		_data[o + 2] = rgba[2]
		_data[o + 3] = rgba[3]
		_soft_data[o] = rgba[0]
		_soft_data[o + 1] = rgba[1]
		_soft_data[o + 2] = rgba[2]
		_alpha[i] = rgba[3]
	_soften(states, w, h)
	for i in range(states.size()):
		_soft_data[i * 4 + 3] = _alpha[i]
	_image.set_data(w, h, false, Image.FORMAT_RGBA8, _data)
	texture.update(_image)
	_soft_image.set_data(w, h, false, Image.FORMAT_RGBA8, _soft_data)
	soft_texture.update(_soft_image)

## Erode fog by one cell (3x3 min), then 3x3 box blur, both separable with clamped edges;
## cells the sim reports visible are pinned fully clear. Operates on _alpha in place.
func _soften(states: PackedByteArray, w: int, h: int) -> void:
	for y in range(h):
		var r := y * w
		for x in range(w):
			_tmp[r + x] = mini(_alpha[r + maxi(x - 1, 0)], mini(_alpha[r + x], _alpha[r + mini(x + 1, w - 1)]))
	for y in range(h):
		for x in range(w):
			_alpha[y * w + x] = mini(_tmp[maxi(y - 1, 0) * w + x], mini(_tmp[y * w + x], _tmp[mini(y + 1, h - 1) * w + x]))
	for y in range(h):
		var r := y * w
		for x in range(w):
			_tmp[r + x] = (_alpha[r + maxi(x - 1, 0)] + _alpha[r + x] + _alpha[r + mini(x + 1, w - 1)]) / 3
	for y in range(h):
		for x in range(w):
			_alpha[y * w + x] = (_tmp[maxi(y - 1, 0) * w + x] + _tmp[y * w + x] + _tmp[mini(y + 1, h - 1) * w + x]) / 3
	for i in range(w * h):
		if states[i] == 2:
			_alpha[i] = 0

## Softened overlay alpha (0 clear .. 255 opaque) for a grid cell. Test hook.
func soft_alpha_at(cx: int, cy: int) -> int:
	return _soft_data[(cy * fog_sys.grid_width() + cx) * 4 + 3]
```

### 5. Update the header comment (lines 8-11)
Append one sentence: "V2b (p3-02): the world overlay draws `soft_texture` — alpha eroded one
cell and 3×3 box-blurred so the edge is a 3-cell gradient; `texture` stays crisp for the minimap."

## Performance (measured on WattBott, headless, real 50×50 grid)
- Steady-state tick with no cell change: `state_bytes` + compare = **0.075 ms**, and the early
  return at the top of `_refresh_texture` is unchanged, so the per-frame cost is identical.
- Forced re-pack today: **0.52 ms**. The four filter passes add **0.95 ms**; the second
  `set_data`/`update` is native and negligible. So a change costs ~1.5 ms instead of ~0.5 ms,
  and changes happen at most once per sim tick (`Game.gd:213-220` redraws per 15 Hz step) —
  worst case +15 ms per second, invisible at frame rate. Draw cost is unchanged: still one
  `draw_texture_rect`. Do not add per-frame work anywhere else.

## Minimap — must not change
`MiniMapRenderer.gd:72-73` draws `fog_texture`, which `Game.gd:78` sets to `fog_renderer.texture`
— the crisp texture, which this ticket leaves byte-identical. Do not point it at `soft_texture`.
(`presentation3d/Game3D.gd:186` also instantiates `FogRenderer`; the shelved 3D scene will pick up
the soft overlay automatically — fine, no change there.)

## Test — new file `tests/test_fog_soft.gd`
Copy the harness style of `tests/test_phase7.gd` (`extends SceneTree`, `_check`/`_fail`/`_finish`
at `test_phase7.gd:167-183`, result line printed at `:162-164`). `SensorComponent` has no
`class_name` — preload it the way `core/simulation/Entity.gd:9` does. `FogOfWarSystem.update()`
reads `alive`, `faction_id`, `sensor.vision_radius`, `position` off an untyped `e`
(`FogOfWarSystem.gd:40-46`), so a duck-typed eye works. `FogRenderer` builds headless
(`Image`/`ImageTexture` work under the dummy renderer) — verified.

```gdscript
extends SceneTree
## test_fog_soft.gd — p3-02: FogRenderer's world overlay is a soft 3-cell gradient while
## `texture` (minimap) stays crisp and the sim's fog state is untouched.
## Headless: `godot-4 --headless --path . --script tests/test_fog_soft.gd`

const SensorComponent := preload("res://gameplay/components/SensorComponent.gd")

var failures: int = 0

class Eye:
	var alive := true
	var faction_id := "VC"
	var position := Vector2.ZERO
	var sensor = null

func _init() -> void:
	# 9x9 grid, 40-px cells, one eye at the centre of cell (4,4) with a 10-px vision radius:
	# _stamp_circle reaches only that one cell (neighbour centres are 40 px away).
	var fog := FogOfWarSystem.new(9, 9, 40.0)
	var eye := Eye.new()
	eye.position = Vector2(4.5 * 40.0, 4.5 * 40.0)
	eye.sensor = SensorComponent.new()
	eye.sensor.vision_radius = 10.0
	fog.update({1: eye}, "VC")
	_check(fog.state_bytes("VC").count(2) == 1, "test premise: exactly one visible cell")

	var fr := FogRenderer.new(fog, "VC")
	fr._refresh_texture()

	# --- soft overlay: 0 at the eye, intermediate on the two neighbours, opaque beyond ---
	var c := fr.soft_alpha_at(4, 4)
	var n1 := fr.soft_alpha_at(5, 4)
	var n2 := fr.soft_alpha_at(6, 4)
	var n3 := fr.soft_alpha_at(7, 4)
	var far := fr.soft_alpha_at(0, 0)
	print("soft alpha row y=4 from centre: %d %d %d %d ; corner %d" % [c, n1, n2, n3, far])
	_check(c == 0, "centre texel is fully clear (got %d)" % c)
	_check(n1 > 0 and n1 < 255, "1st neighbour is intermediate (got %d)" % n1)
	_check(n2 > n1 and n2 < 255, "2nd neighbour is intermediate and darker (got %d)" % n2)
	_check(n3 == 255, "3rd cell out is opaque (got %d)" % n3)
	_check(far == 255, "far cell is opaque (got %d)" % far)
	_check(n1 == 85 and n2 == 170, "exact ramp 0/85/170/255 (got %d/%d)" % [n1, n2])

	# --- crisp texture (minimap) unchanged: hard 0/255 step ---
	var crisp_c := int(round(fr._image.get_pixel(4, 4).a * 255.0))
	var crisp_n := int(round(fr._image.get_pixel(5, 4).a * 255.0))
	_check(crisp_c == 0 and crisp_n == 255, "crisp texture keeps the 1-texel step (%d/%d)" % [crisp_c, crisp_n])

	# --- sim untouched: the dilated ring is still unexplored to the simulation ---
	_check(fog.state_at("VC", Vector2(5.5 * 40.0, 4.5 * 40.0)) == 0, "sim still reports neighbour unexplored")

	# --- explored cells stay dimmed, not black: move the eye, re-pack ---
	eye.position = Vector2(7.5 * 40.0, 7.5 * 40.0)
	fog.update({1: eye}, "VC")
	fr._refresh_texture()
	var explored := fr.soft_alpha_at(4, 4)
	_check(explored > 0 and explored <= 165, "vacated cell is dimmed, not opaque (got %d)" % explored)

	# Informational: re-pack cost on the real 50x50 grid (no assertion; ~1.5 ms expected).
	var fog50 := FogOfWarSystem.new(50, 50, 40.0)
	eye.position = Vector2(1000, 1000)
	eye.sensor.vision_radius = 280.0
	fog50.update({1: eye}, "VC")
	var fr50 := FogRenderer.new(fog50, "VC")
	var t0 := Time.get_ticks_usec()
	for i in range(20):
		fr50._last_states = PackedByteArray()
		fr50._refresh_texture()
	print("repack 50x50: %.2f ms" % ((Time.get_ticks_usec() - t0) / 20000.0))

	fr.free()
	fr50.free()
	if failures == 0:
		print("FOGSOFT_RESULT: ALL PASS")
	else:
		print("FOGSOFT_RESULT: %d FAILURE(S)" % failures)
	_finish()

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: " + msg)
	else:
		_fail(msg)

func _fail(msg: String) -> void:
	failures += 1
	push_error("FAIL: " + msg)
	print("FAIL: " + msg)

func _finish() -> void:
	quit()
```
Expected values were computed with this exact algorithm: row y=4 → `255 255 170 85 0 85 170 255 255`;
diagonal from the centre → `0 141 226 255` (Chebyshev, slightly squarer than on the axes — acceptable).

## Screenshot — `docs/screenshot_2d_fog.png`
```
cd ~/Dev/vibe-command
DISPLAY=:99 godot-4 --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution 1280x720 -- --capture=$PWD/docs/screenshot_2d_fog.png --frame=90 --attack
```
(`Game.gd:115-118` parse `--capture=`/`--frame=`, `:127-129` `--attack`, `:251` prints
`CAPTURED:<path>` on success. Xvfb `:99` is running on WattBott.) Compare with
`docs/screenshot_v2_fog.png`: the visibility edge around the VC base must be a smooth ~120-px
gradient with **no 40-px steps** visible; explored terrain still reads blue-black-dimmed,
unexplored still solid black; the minimap in the bottom-right still has a crisp fog edge; units
and structures unaffected (they render above the fog — `FogRenderer.gd:30` z=5, entities z=6,
`FxRenderer.gd:38` z=8 — and are gated by the sim, `EntityRenderer.gd:41-46`).

## Roadmap note — `docs/visual-roadmap.md`
Under the `### V2 — Fog of war` block (line 28-33) add:
```
- p3-02: the world overlay now draws `soft_texture` — alpha eroded one cell + 3×3 box blur, visible
  cells pinned clear → a 0/85/170/255 ramp over 3 cells (120 px). `texture` stays crisp for the
  minimap. `docs/screenshot_2d_fog.png`.
```

## Done when
- `tests/test_fog_soft.gd` prints `FOGSOFT_RESULT: ALL PASS`, and every existing suite still says
  `ALL PASS` with no `SCRIPT ERROR` (README loop).
- `git status --short` shows exactly ` M presentation/FogRenderer.gd`, ` M docs/visual-roadmap.md`,
  `?? tests/test_fog_soft.gd`, `?? docs/screenshot_2d_fog.png` from your work. Nothing under
  `core/` or `gameplay/`; `MiniMapRenderer.gd` and `Game.gd` untouched. `*.import` and `*.uid` are
  gitignored — do not add them. The tree may carry unrelated untracked files (e.g.
  `tools/deepseek_*.py`) — do **not** add them; `git add` only the four files above, never `-A`.
- `docs/screenshot_2d_fog.png` shows the smooth edge described above.
- Commit, then `git push origin master`: `feat(fog): soft 3-cell fog edge — eroded + blurred overlay texture; minimap stays crisp`
- Report: `git log --oneline -1`, the `soft alpha row` and `repack 50x50` lines from the test, and
  the `CAPTURED:` line.
