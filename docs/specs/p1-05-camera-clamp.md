# p1-05 — Camera clamp uses viewport / zoom

**Tier:** C (DeepSeek Flash) · **Repo:** `~/Dev/vibe-command` · **Touches:** `presentation/RTSCamera.gd`

## Problem
`presentation/RTSCamera.gd::_clamp_to_world`:
```gdscript
position.x = clampf(position.x, zoom.x * viewport_width() * 0.5, _world_width - zoom.x * viewport_width() * 0.5)
```
In Godot 4 a **larger** `zoom` means **closer** (fewer world units on screen). The visible
half-extent is `viewport / (2 * zoom)`, not `viewport * zoom / 2`. At zoom 2 the clamp allows the
camera to run off the map edge; at zoom 0.5 it over-clamps and pins the view. (`screen_to_world`
in the same file already divides by zoom — it's correct; only the clamp is inverted.)

## Change
Replace the two clamp lines with:
```gdscript
var half_w := viewport_width() * 0.5 / zoom.x
var half_h := viewport_height() * 0.5 / zoom.y
# If the world is smaller than the view (zoomed far out), centre it instead of jittering.
if _world_width <= half_w * 2.0:
    position.x = _world_width * 0.5
else:
    position.x = clampf(position.x, half_w, _world_width - half_w)
if _world_height <= half_h * 2.0:
    position.y = _world_height * 0.5
else:
    position.y = clampf(position.y, half_h, _world_height - half_h)
```
Leave `_zoom_at` alone in this ticket (cursor-anchored zoom is a Phase 4 ticket).

## Test
No headless test (needs a viewport). Verify by reasoning + one capture:
```
cd ~/Dev/vibe-command
DISPLAY=:99 godot-4 --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution 1280x720 -- --capture=$PWD/docs/screenshot_camera_clamp.png --frame=60
```
The map should fill the window with no black band on the left/top (camera starts at 1230,1230
on a 2000×2000 world, so at zoom 1 the view is 1280×720 fully inside the world).
Then run all suites anyway (they must still `ALL PASS`) and commit + push:
`fix: camera clamp uses viewport/zoom (Godot 4 zoom semantics)`
Include `docs/screenshot_camera_clamp.png` in the commit.
