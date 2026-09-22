# p2-02 — Prototype fixes + a showcase capture that actually answers the question

**Tier:** O (Sonnet 5) · **Repo:** `~/Dev/vibe-command` · **Touches:** `tools/prep_mesh_for_engine.py`, `presentation3d/Models.gd`, `presentation3d/Game3D.gd`, `core/simulation/GameEvents.gd` (one line), `assets/models/VC-B01.glb` (regenerated), new `docs/screenshot_3d_showcase_*.png`

Read `docs/specs/README.md` first. Run after p2-01.

## Why (what the review found)
p2-01 works mechanically — sim → 3D, shadows, terrain via SubViewport, tests green — but the
three captures can't answer the decision question:
1. **The Garage Core renders as a grey/white blob.** Root cause is visible in
   `assets/models/VC-B01_VC-B01_diffuse.png`: Smart UV Project on the voxel-remeshed mesh made
   thousands of tiny UV islands with black between them and no margin. Any filtered texel fetch
   near an island edge samples black. Baking was the wrong tool for this mesh.
2. **The four exemplars are too small to judge.** At `Camera3D.size = 720` a 40-unit soldier is
   ~40 px; nobody can see a leg swing. The whole point was wheels / legs / rotors.
3. **90% of the screen is cyan boxes**, so the wide shot looks worse than the 2D game even though
   the 3D parts are better. The fallback needs to carry the existing AI art.

## Step 1 — vertex colours instead of a baked texture (`tools/prep_mesh_for_engine.py`)
- Keep: import, `drop_loose_debris`, normalise, Voxel Remesh, Decimate.
- Change the Decimate target default to **30,000** triangles (`--max-tris 30000`). 8k was for
  a texture-mapped mesh; with per-vertex colour we want ~15k+ vertices carrying colour. 30k tris
  is nothing for the GPU.
- Call `project_portrait(obj, image)` **after** remesh + decimate (so the surviving vertices are
  the ones that get colour), then **delete** the Smart-UV / bake / image steps entirely.
- Material: a Principled BSDF whose Base Color is the `portrait` colour attribute
  (`ShaderNodeVertexColor` → Base Color; `render_sprites.vertex_color_material` already builds
  exactly this — reuse it). Also keep the `glow` attribute wired to Emission as that function does.
- Export GLB with `export_colors=True` (Blender ≥ 4.2 exports active colour attributes as
  `COLOR_0` by default; verify the exported file has it:
  `python3 -c "import json,struct;d=open('assets/models/VC-B01.glb','rb').read();n=struct.unpack('<I',d[12:16])[0];j=json.loads(d[20:20+n]);print(j['meshes'][0]['primitives'][0]['attributes'])"`
  must list `COLOR_0`). Delete `assets/models/VC-B01_VC-B01_diffuse.png` and its `.import`.
- Print `PREPPED <id> tris=<n> verts=<n> color=COLOR_0`.
- Re-run for `VC-B01`. The GLB should be ≤ 3 MB.

## Step 2 — Godot reads the vertex colours (`presentation3d/Models.gd`)
In `structure()`: after instancing the GLB, walk every `MeshInstance3D`; for each surface, take
its material (or create a `StandardMaterial3D`), set `vertex_color_use_as_albedo = true`,
`vertex_color_is_srgb = true`, `roughness = 0.85`, and assign it via
`set_surface_override_material(i, mat)`. If the imported material already has an emission
texture from the glow attribute, leave emission as is; otherwise skip emission.
Add a helper `_use_vertex_colors(root: Node)` and call it for any generated mesh.

## Step 3 — fallbacks carry the AI art (`presentation3d/Models.gd`)
Replace the cyan `BoxMesh` fallback with billboards of the art we already have:
- **Units:** `Sprite3D` using `SpriteAtlas.portrait(def_id)` (falls back to the box only if
  null). `billboard = BaseMaterial3D.BILLBOARD_FIXED_Y`, `pixel_size` chosen so the sprite's
  height = the `UNIT_PX` value for its armor class (read `EntityRenderer.UNIT_PX`), origin at the
  feet (`offset.y = height/2`), `shaded = true`, `alpha_cut = ALPHA_CUT_DISCARD` so it casts a
  real shadow, `texture_filter = NEAREST`. Airborne units at `y = 24`.
- **Structures without a GLB:** `Sprite3D` of the structure's AI sprite
  (`SpriteAtlas.texture(def_id)` — these are the 3/4-view AI renders), standing upright on the
  pad: `billboard = DISABLED`, rotated to face the camera direction (yaw = camera yaw), height =
  footprint width × `SpriteAtlas.scale(def_id)` × 40 / aspect, base at the pad's near edge.
  `alpha_cut = DISCARD`, casts shadow.
This is a comparison aid, not the destination — say so in a comment.

## Step 4 — the showcase (`presentation3d/Game3D.gd`)
Add `--showcase`. When present, **instead of** `_spawn_starter_force()`:
- Spawn on open dirt (cells ~(10..20, 10)): `VC-B01` structure at `(720, 400)`; then in a row at
  `y = 620`: `VC-U04` at x=560, `VC-U01` at x=680, `VC-U02` at x=800 (3D y 24), plus `VC-U05`
  (Bot Dog, a fallback billboard so we see one) at x=920.
- Give the three unit exemplars a `MOVE` order to `(x + 260, 620)` on frame 1 so they drive /
  walk / fly across the camera for the whole capture.
- Camera: `size = 260`, centred on `(760, 0, 560)`. Same tilt.
- Add `--tilt=<deg>` to override the camera pitch (default 40) so we can shoot the same set
  at 40 and at 55.
Also add a `--no-hud` arg that skips `HUD.new(...)`.

## Step 5 — captures
```
cd ~/Dev/vibe-command
for T in 40 55; do
  DISPLAY=:99 godot-4 --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
    --resolution 1280x720 res://scenes/Main3D.tscn -- --showcase --no-hud --tilt=$T \
    --capture=$PWD/docs/screenshot_3d_showcase_t$T.png --capture-frames=20,28,36,44
done
DISPLAY=:99 godot-4 --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution 1280x720 res://scenes/Main3D.tscn -- --attack --capture=$PWD/docs/screenshot_3d_wide.png --frame=90
```
Then build one review strip: `docs/screenshot_3d_showcase_strip.png` = the four t40 frames
side by side (PIL, no scaling). In it, wheels must show different rotation phases, the
soldier's legs different swing phases, the rotors different angles. If any of the three is
identical across frames, that animation isn't driven — fix it before committing (check that
`speed` is computed from the position delta per frame and that the model script's `_process`
runs; `Truck3D`/`Soldier3D`/`Drone3D` should each expose a `debug_phase` you can print).

## Step 6 — one-line core bug (allowed here)
`core/simulation/GameEvents.gd`: `entity_destroyed` is declared `(entity_id: int, pos: Vector2)`
but `Simulation.remove_entity` emits `(id, e.def_id, e.position)`. Change the declaration to
`(entity_id: int, def_id: String, pos: Vector2)`. `grep -rn "entity_destroyed" --include=*.gd .`
and fix any connected handler's arity. This is the only change under `core/` in this ticket.

## Done when
- `assets/models/VC-B01.glb` carries `COLOR_0`, no diffuse PNG remains, and in the wide shot the
  Garage Core reads as the tan garage with the cyan-lit door — not a grey blob.
- `docs/screenshot_3d_showcase_strip.png` shows visibly different wheel / leg / rotor phases
  across its four frames, at a size where a person can see them.
- `docs/screenshot_3d_wide.png` shows the roster as AI-art billboards on the 3D terrain with
  shadows — no cyan boxes.
- `presentation/` untouched; `scenes/Main.tscn` still the main scene; all suites `ALL PASS`.
- Commit + push: `fix(3d): vertex-colour meshes, art billboards for fallbacks, showcase capture; entity_destroyed arity`
- Report: `git log --oneline -2`, test output, the list of `docs/screenshot_3d_*.png` files.
