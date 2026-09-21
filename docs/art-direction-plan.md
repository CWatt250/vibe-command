# Art direction plan — from "programmer art" to C&C / Warcraft readability

_2026-09-20. Supersedes the polish-only `visual-roadmap.md` V1–V7 (those shipped; they were the
floor, not the ceiling). This is the plan for the actual look._

## Why it still looks bad, honestly

The V1–V7 passes fixed the presentation layer. They could not fix the assets, and the assets are the
problem. Specifically:

1. **Pure top-down camera.** We look straight down. Buildings are lids, vehicles are outlines, infantry
   are dots. C&C, Red Alert, Warcraft, StarCraft all use a **3/4 view** (~35–45° tilt): you see a
   building's front wall *and* its roof, a tank's turret *and* its side. Height is what makes things
   read as objects instead of icons.
2. **Hand-drawn PIL sprites.** `generate_sprites.py` draws rectangles and ellipses. It has no volume,
   no consistent light direction, no material response. That is why everything looks like the same
   flat sticker regardless of what it is.
3. **No facings.** We rotate one sprite. In 3/4 view that is impossible — a rotated 3/4 sprite is
   wrong from every angle but one. Real RTS sprites are rendered per facing (C&C: 32 for vehicles,
   8 for infantry).
4. **No animation.** Nothing idles, walks, fires, or builds. Motion is half of "alive".
5. **One flat sun.** A `CanvasModulate` tint is not lighting. No normal response, no cast shadows
   with direction, no emissive.

## What the good games actually did

- **Command & Conquer / Red Alert (1995–96):** every unit and structure was a 3D model, rendered once
  to sprites with the facings coming from rotating the model, then blitted in 2D. Nothing was drawn by
  hand. The "look" is a rendering choice (ortho camera, hard key light, flat facets), not artist hours.
  Source: [OpenRA-style reimplementation notes](https://github.com/jpresseau/command-conquer),
  [RA on Wikipedia](https://en.wikipedia.org/wiki/Command_%26_Conquer:_Red_Alert),
  [RA sprite rips for reference](https://www.spriters-resource.com/ms_dos/commandconquerredalert/).
- **Warcraft III:** the early realistic style *failed* at RTS zoom. Samwise Didier's fix: bulk up the
  silhouette, enlarge limbs, weapons and buildings, exaggerate animation, paint the texture as a
  simplified reading of the silhouette. Bigger silhouette = readable in a split second.
  Source: [Warcraft III evolution guide](https://warcraft.wiki.gg/wiki/Warcraft_III_evolution_guide),
  [80.lv on the Blizzard stylized method](https://80.lv/articles/matt-mcdaid-mastering-the-stylized-art).
- **Readability rules that survive every era:** simplified forms + strong value separation (realism
  becomes noise at this scale); team identity layered as hue + value contrast + silhouette, never hue
  alone; one high-contrast accent on an otherwise neutral body is what the eye tracks.
  Source: [strategy game design](https://retrostylegames.com/blog/mastering-the-art-of-strategy-game-design/),
  [readability in TF2/Overwatch](https://medium.com/@xavierck/character-readability-in-team-fortress-2-and-overwatch-68c41d454465).

## The plan: do what Westwood did, with what is on this machine

**Blender 4.5 LTS is installed** (`~/Dev/tools/blender-4.5.13-linux-x64`, headless EEVEE render
verified today). **Qwen-Image-2.1 is installed in ComfyUI** (`~/Dev/ComfyUI`, on-demand). Both sit
idle. This plan puts them to work in a pipeline that is as regenerable as the PIL generator is now.

### Target look (one sentence)

C&C Remastered's clarity at Warcraft III's proportions: 3/4 view, pre-rendered low-poly models with
hard directional light and baked contact shadows, chunky oversized silhouettes, one faction accent
colour, hand-painted-feel textures, 16 facings for vehicles and 8 for infantry.

### Pipeline A — pre-rendered 3D units and structures (the core of it)

1. **Models.** Kitbash from CC0 low-poly kits first, model our own only where the faction language
   demands it:
   - [Kenney Tower Defense Kit](https://kenney.nl/assets/tower-defense-kit) (160 pieces: towers,
     turrets, tanks, soldiers, tiles — CC0), Kenney Car Kit, Blocky Characters.
   - [Quaternius](https://quaternius.itch.io/) CC0 packs: vehicles, robots, sci-fi modular, characters
     (rigged + animated — walk/attack cycles for free).
   - VC "Garage" language = Blender materials, not new geometry: OSB / plywood / tape / battery
     textures on Kenney's shapes, plus a small part library (laptop, PVC antenna, zip-tied battery
     pack, mismatched wheels) glued on. FC = the same shapes, matte angular panels, amber accents.
2. **Render rig** — `tools/render_sprites.py`, run as `blender -b -P`:
   - Orthographic camera at 40° tilt, fixed pixels-per-metre so every asset shares one scale
     (infantry ≈ 32 px, vehicles 48–72, structures 96–192 at zoom 1 — the WC3 "bulk it up" numbers).
   - Sun key light upper-left + soft fill, matching the contact shadows the renderer already draws.
   - Toon shader + Freestyle outline for the Warcraft punch (1 px dark outline, 3-step shading).
   - Per model: **16 facings** (8 for infantry) × animation states (idle 4 f, move 8 f, attack 4 f,
     death 8 f; structures: build-up 8 f, idle 4 f, damaged, destroyed) at 2× and downsampled.
   - Extra passes per frame: **shadow** (separate, so it can be drawn under other units),
     **normal map** (Godot 2D lights respond to it), **team-colour mask** (one channel → any faction
     tint at runtime, one render for all four factions).
   - Output: one atlas per def + `manifest.json` extension (`frames`, `facings`, `anims`, `normal`,
     `mask`). Same idempotent-regenerate discipline as today.
3. **Engine side** (`presentation/`):
   - `EntityRenderer` stops rotating sprites; it picks the facing frame from `movement.facing` and
     the anim frame from state (moving / firing / idle / building). Firing = `WeaponComponent`
     cooldown just reset — no sim change needed.
   - Sprites become `Sprite2D`/`AnimatedSprite2D` nodes with `CanvasTexture` (diffuse + normal) so
     `DirectionalLight2D` (sun) and `PointLight2D` (muzzle flash, explosions, LEDs, generator glow)
     light them for real. Source: [GDQuest 2D normal-map lighting](https://www.gdquest.com/tutorial/godot/2D/lighting-with-normal-maps/).
   - Team colour: a 10-line canvas shader that lerps the mask channel to the faction colour.
   - Draw order becomes y-sorted (3/4 view needs it): `y_sort_enabled` on the entity layer.

### Pipeline B — local AI for the things 3D is bad at

Qwen-Image-2.1 is here; use it where consistency doesn't matter and volume does:

- **Seamless terrain textures** (dirt, cracked concrete, asphalt, gravel, scorched ground) — prompt
  for tileable, tile-check in PIL, 4 variants each. Replaces the speckle tiles from V3.
- **Cliff / ramp / crater pieces** and **decals** (oil stains, tire marks, rubble) — generated, then
  background-removed (hyperframes `remove-background` is installed) and cut to the tile grid.
- **Unit portraits / cameos** for the HUD and briefing screens. Generate from the rendered model as
  an image-to-image pass so they match the sprite.
- **Faction concept sheets** to pick the look *before* modelling. Cheap to iterate; this is where
  Colton's taste goes in.
- Not for units. AI can't hold 16 consistent facings; the 3D pipeline can.

### Terrain, properly

- 3/4-view tileset with **height**: cliffs, ramps, plateaus. Use Godot `TileMapLayer` terrain sets
  (autotiling) instead of the per-cell `draw_texture_rect` loop — transitions dirt↔concrete↔road
  stop looking like a checkerboard.
- Roads with real corners/T-junctions/ends (Wang set), tire-mark decals along them.
- Structure pads that match footprint *and* faction (VC: gravel + pallets; FC: poured concrete).
- Ore / resource fields that look like something (tiberium-style crystals or scrap fields).
- Map is authored data (`missions/*.json`), not hardcoded in `Game._build_map`.

### Lighting & VFX

- `DirectionalLight2D` sun with normal maps; time-of-day as a colour ramp.
- Every emissive is a `PointLight2D`: LEDs, generator glow, muzzle flash (2-frame), explosion (bright
  → orange → gone), tracers. Lights on normal-mapped sprites is the single biggest "this looks like a
  game" jump in 2D Godot.
- Explosions and smoke as rendered sprite sheets (Blender Mantaflow smoke → 16 frames, or CC0 sheets)
  instead of drawn circles. Scorch decals that persist. Wrecks from `wreckDefinitionId` (already in
  the data, ignored by the renderer).
- Projectiles with sprites and trails for rockets / artillery (`projectileId` is already in the data).

### HUD

- C&C-style **right sidebar**: radar top, cameo build tabs (structures / infantry / vehicles / air),
  power bar, credits ticker that counts up. Cameos rendered from the same models, one camera preset.
- Or keep the bottom card if you prefer StarCraft's layout. Taste call — pick one.
- A real font (pixel-military or Blizzard-style serif for WC feel); the default Godot font screams
  prototype.

## Step 0 result — Pipeline B on the Garage Core (2026-09-20)

Colton's call: try the AI pipeline on a structure first (one facing, so the "AI can't hold 16
facings" objection doesn't apply). Result: **it works, first try.**

- Four candidates from Qwen-Image-2.1, 22 steps, 1024², ~80 s each warm (105 s incl. cold load), prompt
  in `tools/`-adjacent scratch (3/4 view, plywood/OSB, open roll-up door with monitors, battery
  packs, PVC antenna with cyan LED, hard upper-left sun, flat magenta background). All four are
  usable; `docs/concepts/garage_core_qwen_*.png` (raw) and `garage_core_sprite_*.png` (keyed).
- `tools/ai_sprite_prep.py` keys the magenta by hue ratio (so the near-black baked shadow goes too),
  despills edges, crops, resizes to 256 wide. `#101` shipped as `assets/sprites/VC-B01_hq_ai.png`.
- Manifest entries can now be `{"file", "scale", "tint"}`: the Garage Core draws at 1.3× its pad
  width (C&C buildings overhang their footprint) with no faction wash (the LEDs carry the colour).
  `SpriteAtlas.scale()/tint()`, `EntityRenderer._draw_structure` bottom-anchors 3/4 art on the pad.
- In-game: `docs/screenshot_poc_garage_selected.png`. Portrait and build cameo come from the same
  sprite for free.

What it tells us: **structures can go through Pipeline B wholesale** — 40 of them, one prompt
template with the def's `displayName` + `function` + faction language, ~1 hour of GPU. Units still
need facings → Pipeline A, *but* the AI renders are the concept sheets the 3D kitbash should match.

### All 20 VC structures — done the same evening

`tools/gen_structures_ai.py VC` — shared faction prefix (`PREFIX["VC"]`), a hand-written one-line
description per structure (`DESC`), the def's `function` appended, shared suffix (view, light, key
colour). Seed = md5(id + bump) so any one structure re-rolls without moving the others
(`--only VC-D08 --seed-bump 1 --force`). Draw scale by footprint: 1×1 → 1.7, 2×n → 1.4, 3×3 → 1.3.
Runs in ~80 s per structure on a warm server; run in foreground chunks of six (a background job got
killed once). Review sheet: `docs/concepts/vc_structures_sheet.png`; raws in `docs/concepts/vc/`.
In-game: `docs/screenshot_poc_vc_base.png`, `screenshot_poc_vc_build.png` (every cameo populated).

Hit rate: 18/20 first roll; D04 and D08 re-rolled once (dark background / pink ground disc).

### All four factions — 80 structures, same night

- **FC and TS/SG prefixes** in `gen_structures_ai.py`: FC = matte grey federal-industrial, chevrons,
  amber lights. TS = white/graphite composite, tinted glass, holographic teal (corporate campus).
  SG = captured machinery fused with black crystal shards, orange-red light seams (the strangest,
  and the most distinctive on screen).
- **TS and SG had no structures in the data** — the Bible import was units only. `tools/
  scaffold_ts_sg_structures.py` mirrors FC's 20 slots 1:1 (same cost/time/HP/footprint/flags),
  faction names, `trainsUnits` remapped to each faction's real units, `"draft": true` on every def.
  Balance is *FC's*, deliberately; replace from the Bible when the docx turns up.
- Review sheets: `docs/concepts/{vc,fc,ts,sg}_structures_sheet.png` (`tools/make_structure_sheet.py`).
- Hit rate across 80: ~74 first roll. The failure mode is always the same — the model paints a dark
  backdrop instead of the magenta key, leaving a grey halo. `--seed-bump N --force` fixes it; two
  needed a second bump. One design miss: TS-D01 Composite Barrier renders as a building, not a
  wall segment (1×1 walls want a different prompt shape, or a drawn tile).
- ComfyUI serves a cached result in ~3 s for an identical prompt+seed, so re-running the batch is
  free for anything already rendered.

### Unit portraits for the HUD — all 58, same night

`tools/gen_portraits_ai.py <FAC>` — full 3/4-view renders, every unit facing the viewer's lower-left
so the cameo row reads as one set. Per-faction prefix plus a separate **aircraft prefix** (the
ground prefix's "armor / visor" cues turn any "drone" or "craft" into a mech with wings — three
Titan aircraft needed it). One hand-written line per unit. Output `assets/portraits/<id>.png` +
`manifest.json`; `SpriteAtlas.portrait()` loads them and `UiTheme.icon_for()` prefers a portrait
over the battlefield sprite, so the selection card, build grid and queue picked them up with no
UI changes. Review sheets: `docs/concepts/{vc,fc,ts,sg}_portraits_sheet.png`.

Hit rate 55/58 first roll. These are also the **reference sheets for Pipeline A**: the Blender
kitbash for each unit now has a target image in the faction's language.

### Pipeline A proof of concept — the render rig works (2026-09-21)

- `tools/render_sprites.py` (run under `blender -b -P`): ortho camera pitched 40° looking +Y,
  key sun from screen upper-left + weak fill + cool ambient, Freestyle 1.6 px outline,
  transparent film, EEVEE Next. Frame k = model rotated −k·(360/N)° about Z (clockwise on screen =
  Godot's y-down angle). **16 facings of the Technical render in 2.5 s.**
- `tools/pack_facings.py`: trims all frames to one symmetric union bbox (so the anchor doesn't
  wander between facings), downsamples 2×→1×, packs a left-to-right strip to
  `assets/sprites/rendered/<id>.png`, manifest `{"file", "facings", "frame", "scale"}`.
- Engine: `SpriteAtlas.facings()/frame_size()/facing_region()`; `EntityRenderer._draw_unit`
  picks frame `round(((angle − 90°) / 360°) · N)` and never rotates a facing sprite. Units with
  `facings: 0` keep the old rotate-in-place path, so the roster migrates one unit at a time.
- In-game: `docs/screenshot_poc_technical.png`.

**What it proves:** the C&C method runs on this machine and plugs into the game with no sim change.
**What it doesn't:** the model. A primitive kitbash (boxes, cylinders, plywood materials) reads as
a truck but is nowhere near the AI portrait sitting on the same card. The rig is done; the
remaining work is *models*. Options, cheapest first: (1) CC0 kits (Kenney Tower Defense / Car Kit,
Quaternius) kitbashed with the garage part library; (2) image-to-3D from the AI portraits (local
options exist — TripoSR / Hunyuan3D-2 run on this box's VRAM; unverified here); (3) modelling.

### Models: both routes tried the same afternoon (2026-09-21)

1. **Kenney kitbash** — `~/Dev/assets/kenney/` (Car Kit + Tower Defense Kit, CC0). `kenney()` appends
   a GLB and recolours named meshes; `kit_technical_kenney()` = Car Kit truck + plywood panels, tape,
   bed gun, batteries, antenna, LEDs. Reads as a truck. Limits: the Car Kit is civilian (truck, van,
   SUV, delivery, tractor), the Tower Defense Kit is medieval — no tanks, no soldiers, no mechs.
   Fine for ~6 VC vehicles; not a roster solution.
2. **Image-to-3D from the portraits** — `tools/image_to_3d.py` through ComfyUI's native Hunyuan3D-2
   nodes (weights: `models/checkpoints/hunyuan3d-dit-v2.safetensors`, 4.9 GB, from
   tencent/Hunyuan3D-2). **The Technical portrait became a detailed mesh in 104 s** — bed gun,
   antennas, wheel wells, correct from all 16 facings. Shape only (no texture), so
   `project_portrait()` paints the mesh with the portrait by orthographic projection into a vertex
   colour layer; hidden faces get the nearest visible edge. Misaligned up close, correct at sprite
   size. `kit_generated(uid, yaw_deg=180)` — Hunyuan3D meshes face −Y. 16 facings render in 37 s.
   In-game: `docs/screenshot_poc_technical_hy3d.png`.

**Decision:** route 2 is the roster path. 58 portraits → 58 meshes ≈ 2 hours of GPU, then the
rig renders the lot in ~40 min. Route 1 stays for props and anything the generator gets wrong.
Open: texture quality (Hunyuan3D-2.1 paint or a multi-view projection), infantry (humanoid meshes
are fine but need a walk cycle — rig or 2-frame bob), and per-unit yaw/scale sanity checks.

## Order of work

| # | Step | Output | Effort |
|---|---|---|---|
| 0 | **Proof of concept.** One vehicle (VC-U04 Technical) + one structure (Garage Core) through Pipeline A end-to-end: kitbash in Blender, 16 facings, shadow + normal + mask passes, into the game with facing frames and a `DirectionalLight2D`. Side-by-side screenshot vs today. **Decide on the look here, not after 58 units.** | `docs/poc_*.png` | 1–2 days |
| 1 | Render rig hardened: `tools/render_sprites.py` + manifest schema + atlas packer + engine facing/anim reader. | regenerable pipeline | 1–2 days |
| 2 | Faction concept sheets via Qwen-Image (VC garage, FC federal). Colton picks. | `docs/concepts/` | half day + review |
| 3 | VC roster (14 units, 20 structures) modelled/kitbashed and rendered. FC next. | full VC in-game | 3–5 days |
| 4 | Terrain v2: AI seamless textures + `TileMapLayer` autotiles + height + authored map. | new maps | 2–3 days |
| 5 | Lighting + VFX: normal-mapped lights, sprite explosions, projectiles, wrecks, decals. | | 2 days |
| 6 | HUD sidebar + cameos + font. | | 1–2 days |
| 7 | Animation polish: build-up, harvester load, turret tracking, death anims. | | 2 days |

Sim (`core/`, `gameplay/`) is untouched throughout. Every step keeps the seven suites green.

## What I need from Colton

- Step 0 sign-off: the POC screenshot is the moment to say "more Warcraft" or "more C&C", not later.
- Sidebar vs bottom card.
- Any reference screenshots you love. Two or three is enough; I'll match them.

## Sources

- C&C sprites were pre-rendered 3D with rotated facings — [jpresseau/command-conquer](https://github.com/jpresseau/command-conquer), [Wikipedia: Red Alert](https://en.wikipedia.org/wiki/Command_%26_Conquer:_Red_Alert), [Spriters Resource: RA](https://www.spriters-resource.com/ms_dos/commandconquerredalert/)
- Warcraft III bulked silhouettes for readability — [Warcraft III evolution guide](https://warcraft.wiki.gg/wiki/Warcraft_III_evolution_guide), [80.lv Blizzard stylized art](https://80.lv/articles/matt-mcdaid-mastering-the-stylized-art), [Pixune stylized art](https://pixune.com/blog/stylized-art-style/)
- Readability principles — [RetroStyle: strategy game design](https://retrostylegames.com/blog/mastering-the-art-of-strategy-game-design/), [Sunstrike: realism vs stylization](https://sunstrikestudios.com/en/blog/game_art_visual_direction/), [Character readability, TF2/Overwatch](https://medium.com/@xavierck/character-readability-in-team-fortress-2-and-overwatch-68c41d454465)
- CC0 3D kits — [Kenney Tower Defense Kit](https://kenney.nl/assets/tower-defense-kit), [Kenney on OpenGameArt](https://opengameart.org/content/all-cc0-uploader-kenney), [Quaternius](https://quaternius.itch.io/150-lowpoly-nature-models), [awesome-cc0](https://github.com/madjin/awesome-cc0)
- Blender sprite rendering — [Sprite Render Kit](https://www.blendernation.com/2016/03/10/sprite-render-kit-tool-top-game-sprite-rendering/), [Get Sheet Done](https://kilbee.github.io/GetSheetDone/docs.html), [8 Directions Render plugin](https://auteddy.itch.io/8-directions-render-plugin-for-blender), [OGA: isometric sheet from Blender](https://opengameart.org/forumtopic/how-to-make-a-2d-isometric-spritesheet-from-a-3d-model-using-blender)
- Godot 2D lighting with normal maps — [GDQuest](https://www.gdquest.com/tutorial/godot/2d/lighting-with-normal-maps/), [Merxon: mastering 2D lighting](https://medium.com/@merxon22/godot-mastering-2d-lighting-a949320e1f68)
