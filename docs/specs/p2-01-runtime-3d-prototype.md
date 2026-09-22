# p2-01 — Runtime-3D presentation prototype (the decision gate)

**Tier:** O (Sonnet 5 via Claude Code `/model sonnet`) · **Repo:** `~/Dev/vibe-command` · **Adds:** `scenes/Main3D.tscn`, `presentation3d/*.gd`, `tools/prep_mesh_for_engine.py` · **Touches:** `tools/image_to_3d.py` (one flag). **Sim is not touched.**

Read `docs/specs/README.md` first. Run this after p1-01…p1-07.

## Why
The 16-facing sprite pipeline cannot animate parts (wheels, legs, rotors) — a Hunyuan mesh is
one fused blob and sprites would need 16 facings × N frames per animation. Real 3D models in a
Godot 3D viewport with a fixed C&C-style camera give spinning wheels, walking legs, rotor blur,
smooth turning, real shadows — for free. This ticket builds **one scene with four exemplars** so
Colton can look at it next to the 2D game and decide. Do not port the roster; do not touch
`presentation/` (the 2D path stays as the fallback).

## Coordinate contract
Sim is 2D: `e.position = Vector2(x, y)`, 1 unit = 1 world px, 2000×2000 world, `NavGrid.CELL = 40`.
3D mapping: `Vector3(x, 0, y)` — sim `y` becomes 3D `z`. Height (`y` in 3D) is free for us.
Sim "facing" is a `Vector2`; 3D yaw = `atan2(-facing.y, facing.x)` (Godot: +X right, -Z forward).
Verify on the truck: facing `(1,0)` must point the truck's nose along +X on screen.

## Step 0 — a mesh for the Garage Core (L can do this part; ~5 min)
`tools/image_to_3d.py` takes a unit id and reads `assets/portraits/<id>.png`. Add
`--image <path>` so any keyed image works, and `--out-id <name>` for the output name:
```
cd ~/Dev/ComfyUI && (setsid bash launch.sh > /tmp/comfy.log 2>&1 < /dev/null &)
# wait until: curl -s localhost:8188/system_stats returns JSON (~2 min)
cd ~/Dev/vibe-command
~/AI_Agent/venv/bin/python tools/image_to_3d.py VC-B01 --image assets/sprites/VC-B01_hq_ai.png --steps 40 --octree 320
# -> ~/Dev/assets/generated3d/VC-B01.glb
P=$(pgrep -f "[m]ain.py --listen 127.0.0.1 --port 8188"); [ -n "$P" ] && kill $P
```
(Keep `pad_portrait`'s alpha binarisation and 18% margin; it applies to this image too.)

## Step 1 — engine-ready meshes: `tools/prep_mesh_for_engine.py` (Blender headless)
Hunyuan meshes are ~500k verts with no UVs and colour only as a vertex layer after projection.
Write a Blender script that, for one id:
1. Imports `~/Dev/assets/generated3d/<id>.glb`; drops loose debris (copy `drop_loose_debris`
   from `tools/render_sprites.py`); normalises so the largest extent = the sim footprint
   (structures: `footprint * 40` on X/Z from `content/data/structures.json`; units: the
   `FIT_BY_ARMOR` table in `render_sprites.py` × 40 / 3 so a Light vehicle is ~37 px long).
2. Paints it: call `project_portrait(obj, image)` from `render_sprites.py` (import the module;
   it's plain Python) with the same image used to generate the mesh.
3. Decimate to ≤ 8,000 triangles (`Decimate` modifier, ratio = 8000 / current, apply).
4. `Smart UV Project`, create a 1024² image, bake **vertex colour → diffuse** into it
   (Cycles bake type `DIFFUSE`, colour only; use an Emit-based bake if Cycles is slow: assign
   an Emission shader driven by the `portrait` colour attribute, bake `EMIT`).
5. Assign a Principled material with that image as Base Color; export
   `assets/models/<id>.glb` (embedded texture). Print `PREPPED <id> tris=<n>`.
Run it for `VC-B01`. Commit the GLB (it should be < 3 MB).

## Step 2 — the scene
`scenes/Main3D.tscn`: root `Node3D` with script `presentation3d/Game3D.gd`.

`presentation3d/Game3D.gd` — copy the sim setup from `presentation/Game.gd` verbatim
(registry, events, sim, `_build_map`, `_spawn_starter_force`, the fixed-tick `_process`,
the `--capture=` / `--frame=` args). Replace the 2D presenters with:

- **Camera:** `Camera3D`, `projection = PROJECTION_ORTHOGONAL`, `size = 720` (world units of
  height visible), pitched **40° from straight down** looking toward +Z, centred over
  `(1230, 0, 1230)` (same start as the 2D camera). `current = true`. No controls needed yet.
- **Sun:** `DirectionalLight3D`, `shadow_enabled = true`, rotated so light comes from the
  screen's upper-left (same as the sprite rig: yaw −135°, pitch −50°), energy 1.2; plus
  `WorldEnvironment` with an `Environment`: ambient light colour `(0.5,0.5,0.5)` energy 0.35,
  `ssao_enabled = true`, tonemap `TONE_MAPPER_FILMIC` off (use Linear), background a flat
  colour `(0.02,0.02,0.03)`.
- **Terrain + fog, reused:** a `SubViewport` (2000×2000, `render_target_update_mode = ALWAYS`,
  transparent bg off) containing the existing 2D `MapRenderer` and `FogRenderer` exactly as
  `Game.gd` creates them. A `MeshInstance3D` with a `PlaneMesh` `size = (2000, 2000)` at
  `(1000, 0, 1000)` whose `StandardMaterial3D.albedo_texture` is the SubViewport's
  `get_texture()`, `texture_filter = NEAREST`, unshaded off (let the sun light it). This gives
  tiles, roads, pads and the feathered fog with zero new terrain code. Check UV orientation:
  the road at sim y=33 must appear at 3D z=1320.
- **Entities:** `presentation3d/Entity3D.gd` (`Node3D`). `Game3D` keeps `Dictionary id -> Entity3D`;
  on `events.entity_created` create one, on `events.entity_destroyed` free it. Each frame (in
  `_process`, after sim steps): `position = Vector3(e.position.x, 0, e.position.y)` and
  **smooth yaw**: rotate toward the target yaw at `e.movement.turn_rate_deg` deg/s if movement
  exists, else snap. Expose `speed` (world units/s, from position delta) and `turning`
  (signed yaw rate) for the models.
- **Models** — `presentation3d/Models.gd` static builders, one per exemplar, fallback for the rest:
  - `structure(id)`: `load("res://assets/models/%s.glb" % id)` instantiated, base on y=0. For
    VC-B01 only in this ticket. Any other structure: a `BoxMesh` of footprint size × 60 tall,
    faction colour, so the base still reads.
  - `truck()` — VC-U04: instantiate `~/Dev/assets/kenney/car-kit/Models/GLB format/truck.glb`
    (copy it to `assets/models/kenney/truck.glb`; CC0). Scale so its length is 52 world units.
    Override the body material to faded tan `(0.47,0.42,0.33)`; wheels to dark. In
    `_process`: each child whose name begins with `wheel` rotates about its local X by
    `speed / wheel_radius` rad/s; body node rolls `clamp(-turning * 0.02, -0.12, 0.12)` rad
    and pitches `-accel * 0.002`.
  - `soldier()` — VC-U01: `assets/models/kenney/character-c.glb`. Scale to 40 units tall.
    Materials: torso OSB `(0.69,0.54,0.32)`, limbs dark, head skin. Procedural walk when
    `speed > 1`: `leg-left.rotation.x = sin(t*8) * 0.6`, `leg-right = -sin(...)`, arms the
    opposite sign at 0.4; body bob `sin(t*16) * 0.6` units. Idle: all zero, lerped back.
  - `drone()` — VC-U02: no kit mesh; build it: a `BoxMesh (10, 3, 10)` hull dark, four arms
    (`BoxMesh (12,1,1.5)` at ±45°), four rotors = flattened `CylinderMesh` radius 5, height 0.4,
    at the arm ends, spinning at 40 rad/s about Y (alternate directions). Hover: `y = 24 +
    sin(t*2) * 1.5`; tilt nose-down 0.15 rad when `speed > 1`. A cyan emissive `SphereMesh`
    radius 1 under the hull.
  - `fallback(e)`: `BoxMesh` sized by armor class (Infantry 14, Light 24, Medium 32, Heavy 40,
    air 24 at y=24), faction colour — so every entity in the sandbox appears.
  - Faction colours: reuse `EntityRenderer.FC_COLORS`.
- **Shadows:** every model's `MeshInstance3D` casts; the terrain plane receives.
- **HUD:** add the existing `HUD.new(sim, events, "VC")` CanvasLayer exactly as `Game.gd`
  does. It draws over the 3D view unchanged. (Selection/placement input is out of scope.)

## Step 3 — captures
Add to `Game3D` the same `--capture=<png> --frame=N` handling as `Game.gd`, plus
`--capture-frames=60,75,90` that saves three files with the frame number appended, so motion
(wheels, legs, rotors) is visible across the set. Run:
```
cd ~/Dev/vibe-command
DISPLAY=:99 godot-4 --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution 1280x720 res://scenes/Main3D.tscn -- --capture=$PWD/docs/screenshot_3d_prototype.png --capture-frames=60,75,90 --attack
```
(`--attack` spawns an enemy squad so units move and turn. If Godot won't take a scene path
that way, set `run/main_scene` temporarily and put it back before committing.)
Also add `--select`-free: nothing else.

## Done when
- `docs/screenshot_3d_prototype_060.png / _075.png / _090.png` exist and show: the Garage Core
  mesh standing on the tiled terrain with fog; the Technical with wheels that visibly differ
  between frames; the Maker Crew mid-stride; the Scout Quad hovering with rotors; the other
  entities as faction-coloured boxes; the HUD on top.
- `presentation/` unchanged; `scenes/Main.tscn` still the main scene; all suites `ALL PASS`.
- Commit + push: `feat: runtime-3D presentation prototype (Main3D) — camera, sun+shadows, terrain via SubViewport, four animated exemplars`
- Then tell Colton. **F reviews the three frames and the 2D screenshot side by side. Nothing in
  Phase 3 starts until that review.**
