# Visual roadmap — from systems prototype to a game that looks like one

_2026-09-20. Follows the HUD phase (`hud-inventory.md`). Ordered so the renderer improves before
the assets do; putting nicer sprites into a flat presentation layer wastes them._

## Ground truth the passes must respect

- **2D top-down sprites**, not low-poly. "Lighting" here means `CanvasModulate` sun tint, contact-shadow
  ellipses, emissive overlay sprites for LEDs/screens, `GPUParticles2D` for dust/smoke. No normal maps.
- **Sprites are procedural**: `tools/generate_sprites.py` draws every unit and structure. Faction art
  language changes are generator changes, regenerable for all 58 units at once.
- **Sim/presentation split is sacred.** Nothing below touches `core/` or `gameplay/`. Renderers read the
  sim; they never write it.
- Current sizes: units 41px, structures 60px at zoom 1 (`EntityRenderer._scaled_sprite_box`).
  `NavGrid.CELL` = 40 world units.

## Passes, in order

### V1 — Readability quick wins (hours)
- Hide health bars at full HP; show when selected, damaged (<100%), or Alt held. `EntityRenderer._draw_health`.
- Contact shadow: dark ellipse at ~40% alpha under every unit/structure, offset +2/+3 px.
- Selection ring per footprint size for structures (today it's a fixed 34px arc regardless of 1×1 vs 3×3).
- Default camera zoom and sprite scale pass: infantry 28–36 px, vehicles 45–70, structures 90–180.
  Bump `_scaled_sprite_box` targets and `RTSCamera` default zoom together; re-shoot `docs/screenshot_*.png`.

### V2 — Fog of war (half a day)
- `FogRenderer` currently draws per-cell rects → staircase edges. Render the fog grid into an `Image`
  (one pixel per cell), upload as an `ImageTexture` with linear filtering, draw it scaled to the world.
  Feathering comes free from the filter. Three states: visible = clear, explored = ~55% darkened +
  desaturated, unexplored = near-black.
- Minimap reads the same texture instead of re-deriving cells.

### V3 — Terrain (1–2 days)
- Replace `MapRenderer`'s three flat colours with a `TileMapLayer` and a small CC0 tileset (Kenney
  top-down or roguelike-city). Base tiles: dirt, cracked concrete, asphalt. Roads from
  `NavGrid.land_types == 1`. Darker "pad" tiles under structure footprints.
- Prop scatter (rocks, scrap, fencing, tire marks) from a seeded RNG so screenshots are reproducible.
- Minimap draws the terrain silhouette; faction dots become small structure rectangles.

### V4 — Rendering framework (1–2 days)
- `CanvasModulate` sun tint (warm upper-left) + per-sprite shadow direction matching.
- Unit facing: rotate sprite to `movement` heading (already tracked); 8-direction snap reads better
  than continuous for chunky sprites.
- Emissive layer: a second `_draw` pass with `BLEND_ADD` for faction LEDs (cyan for VC, amber for FC),
  generator flicker, screen glow. Data-driven from a per-def `emissive` sprite in the manifest.
- Particles: dust behind moving vehicles, smoke from Generator Bank, hover shimmer under drones.

### V5 — Combat feedback (1 day)
- Muzzle flash sprite on `combat_occurred`; tracer line for guns, projectile sprite for rockets.
- Hit flash: white modulate for 2 frames on the target; damage-state overlay below 50% HP.
- Death: small explosion sprite sheet + debris that fades; wrecks if `wreckDefinitionId` is set.

### V6 — Faction art language (generator work, 1–2 days)
- VC "Garage": plywood armor panels, exposed battery packs, mismatched wheels, duct-tape stripes,
  laptops strapped on, PVC antennas. Oversized silhouettes, big readable features.
- FC: clean, matte, angular, amber lights. Same generator, different palette + part library.
- TS / SG when their slices are playable.

### V7 — HUD restyle (1 day)
- The panels from the HUD phase are functionally done; this is a skin. Compact metal/glass frame,
  icons instead of two-line text buttons, resource bar as `[ $1,524 ] [ POWER 10/10 ] [ COMPUTE 0/15 ]`
  chips, command buttons (Move / Attack / Stop / Rally) next to the selection card.
- Nothing selected → the bottom panel collapses to just the minimap.

## Not doing
- Normal-mapped 2D lighting, 3D, or a renderer rewrite. The C&C look is readability, not fidelity.
- Hand-drawing units. The generator is the asset pipeline.
