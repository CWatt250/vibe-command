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

### V1 — Readability quick wins — DONE 2026-09-20 (`docs/screenshot_v1*.png`)
- Health bars only when selected, hurt, or Alt held (`EntityRenderer._show_health`).
- Contact shadows: footprint-shaped under structures; ellipse under units, wider/fainter for airborne.
- Structures draw to their real footprint rect (`_footprint_rect`, same anchor-cell math as the sim), so
  even footprints no longer sit half a cell off their blocked cells. Build sites fade in with progress.
- Unit size by armor class (`UNIT_PX`: Infantry 30 … Heavy 68, AirHeavy 64); health-bar width and
  selection ring scale with it. C&C corner brackets on selected structures.
- Camera zoom left alone — the size table did the work.

### V2 — Fog of war — DONE 2026-09-20 (`docs/screenshot_v2_fog.png`)
- `FogRenderer` packs the fog grid into a grid-sized `Image` → `ImageTexture`, drawn scaled with
  `TEXTURE_FILTER_LINEAR`; the edge feathers across one cell. Re-packs only when a cell changes.
  Explored = blue-black at 65% (cooled, not just darker); unexplored = black.
- `MiniMapRenderer` draws a one-texel-per-cell terrain silhouette from `NavGrid.land_types` (open /
  street / blocked incl. structure pads) with `FogRenderer.texture` over it — one fog authority.

### V3 — Terrain — DONE 2026-09-20 (`docs/screenshot_v3_terrain.png`)
- Procedural tile set via `tools/generate_terrain.py` → `assets/terrain/` (no external tileset; same
  pipeline as the sprites). 4 dirt variants, auto-tiled roads (h/v/x), concrete pad, 6 props.
- `MapRenderer` draws tiles per visible cell (nearest filter), dirt variant by cell hash, pad wherever
  the grid is blocked (structures and rubble alike), props from a fixed-seed scatter on open cells.
  Falls back to the old flat colours if the tile set is missing.
- Roads are now painted in `Game._build_map` (land type 1 was never set before).
- Minimap terrain silhouette landed in V2. Structure rectangles instead of dots: still open.

### V4 — Rendering framework — DONE 2026-09-20 (with V5, `presentation/FxRenderer.gd`)
- `CanvasModulate` warm sun tint on the world canvas (HUD/minimap layers unaffected).
- Unit facing was already continuous from `movement.facing`; left as-is (8-dir snap is a taste call).
- Faction LED pulse on every built structure (cyan VC / amber FC) — drawn, not a manifest sprite yet.
  Per-def emissive sprites stay with the generator work in V6.
- Particles: dust behind moving ground units, smoke from `PowerSource` structures. Plain dictionary
  particles stepped in `_process`; no GPUParticles2D.

### V5 — Combat feedback — DONE 2026-09-20 (`docs/screenshot_v5_combat.png`)
- `combat_occurred` → muzzle flash at the attacker, tracer to the target for non-projectile weapons,
  four impact sparks, and a 0.1 s white hit flash the `EntityRenderer` overlays via `fx.flash_left()`.
- `unit_died` (fires for structures too; `structure_destroyed` is declared but never emitted) →
  expanding ring + flash + smoke + debris, scaled ×2.2 for structures.
- Still open: projectile sprites for rocket/artillery weapons, damage-state overlay below 50%,
  wrecks from `wreckDefinitionId`.
- Debug: `-- --attack` drops an FC squad inside the base's acquire radius; capture at frame 25–45.

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
