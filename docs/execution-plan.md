# Execution plan — who does what (model assignment)

_2026-09-21. Goal: ship the roadmap in `art-direction-plan.md` + the review findings without
burning the expensive model on work a cheap one can do. Every task below names the cheapest
model that can do it well, and what the expensive model is reserved for._

## The model ladder

| Tier | Model | Cost | Good at | Not for |
|---|---|---|---|---|
| **F** | Fable 5.1 (Claude Code) | highest | Architecture decisions, novel prototypes, visual QA of screenshots, cross-system debugging, writing specs the tiers below execute | Mechanical edits, batch chores, watching logs |
| **O** | Opus 5 / Sonnet 5 (Claude Code `/model`) | high / mid | Well-specified features touching 2–4 files with tests; Sonnet 5 is the workhorse | Open-ended design |
| **H** | Haiku 4.5 (Claude Code `/model haiku`) | low | Boilerplate, config, docs, renames, CI yaml, test scaffolds from a template | Anything needing judgment |
| **P** | DeepSeek V4 Pro (Nexus `/pro`) | ~$0.05/dispatch | One-system implementation from a spec (steering, audio manager, camera) | Multi-file refactors |
| **C** | DeepSeek V4 Flash (Nexus `/code`) | ~$0.005/dispatch | Single-file, test-gated edits: a bug fix, a helper, a rewording | Design |
| **L** | Ornith-1.5 local (Nexus `/local`, default) | $0 | Shell chores, batch scripts, packing, sheets, running suites, JSON content edits, doc updates from a template, commit messages, first-pass "obvious defect?" on a sheet (it has vision) | Final art judgment, architecture |

Rules that make the ladder work:
1. **F writes the spec, a lower tier does the work, tests are the gate.** A spec = file list, exact
   behaviour, test to add, screenshot to produce. If a task can't be specified that tightly, it's an
   F task. Specs go in `docs/specs/<task>.md`.
2. **Tests before review.** Nothing comes back to F unless the seven suites (and any new test) are
   green. L runs them: `for t in tests/test_*.gd; do godot-4 --headless --path . --script $t; done`.
3. **F reviews diffs and screenshots, not sessions.** Hand F the `git diff --stat`, the test output,
   and one image. Not a transcript.
4. **No F turns on log-watching.** Long jobs run detached (`setsid`), L polls and reports once.
   Monitors report completion only, never per-item.
5. **Push after every commit** (Colton's standing rule) — L can do this.
6. `/max` is broken headless (inherits a "fable" default the CLI can't use) — don't route there.
7. All cloud dispatch is **explicit-only** through Nexus (`/code`, `/pro`); the router never infers it.

## Roadmap with assignments

**Ready-to-paste tickets live in `docs/specs/`** — start with `docs/specs/README.md`, which says
where to run each tier and what every ticket must end with. Phase 1 is fully written
(`p1-01` … `p1-07`); later phases get their specs written by F when the phase starts.

### Phase 1 — Correctness (sim only, ~1 day)
| Task | Tier | Notes |
|---|---|---|
| Unify tick rate: one constant, `Game.gd`/`HUD.gd`/`FxRenderer.gd` cadences derived from it | **C** | Spec: `Simulation.TICK_HZ` authoritative; `Game.TICK_RATE` removed; `tick % N` sites use `TICK_HZ` ratios. Test: existing suites + a cadence assert. |
| Drag-select filters to player faction; click-select enemy only if visible | **C** | `SelectionInput._units_in_rect`, `_unit_at_world`. Test in `test_phase7.gd`. |
| Target acquisition respects fog (`fog_sys.is_visible`) | **C** | `CombatSystem._acquire_target`. Add a test: hidden enemy not acquired, then revealed → acquired. |
| NavGrid: separate `land_types` (terrain) from occupancy so unblocking restores the road | **C** | Add `_occupied` PackedByteArray; `set_blocked` stops mutating `land_types`; renderer reads both. Test: block road, unblock, land type still 1. |
| Real order state: `IDLE/MOVE/ATTACK/ATTACK_MOVE/HOLD/STOP` on `MovementComponent`/entity; `ATTACK_MOVE` = advance, engage in range, resume | **O** (Sonnet) | Spec by F first (state table + transitions). Test: attack-move squad stops for an enemy in range and resumes after the kill. |
| Surface win/lose: sim emits `match_over(faction)`; HUD shows result + Restart | **C** + **L** | C for the sim signal + test; L wires the HUD label from the existing panel style. |
| Camera clamp uses `viewport / zoom` (Godot 4: higher zoom = closer) | **C** | `RTSCamera._clamp_to_world`. |

### Phase 2 — Runtime-3D presentation prototype (~2 days) — **F**
The decision gate. One scene: `Camera3D` ortho at the C&C tilt, `DirectionalLight3D` with shadows,
terrain plane from the tile atlas, fog quad from `FogRenderer.texture`, and four exemplars:
Garage Core (decimated Hunyuan mesh, baked texture), Technical (Hunyuan hull + Kenney wheels that
spin and a chassis that tilts on turns), Maker Crew (Blocky character, procedural walk), Scout Quad
(rotors spin, hover bob). Sim untouched; a `Presentation3D` node reads `sim.entities` exactly as
`EntityRenderer` does. Output: one screenshot beside today's. **Colton decides here.**
- **L** does the prep chores: decimate all 80 structure GLBs to ≤8k tris (`DecimateMesh` in ComfyUI
  or Blender `--python` decimate), bake vertex colours to a 512² texture per mesh (Blender script),
  write `assets/models/manifest.json`. F writes the script once; L runs it as a batch.

> **Phase 2 outcome (2026-09-22): STAY 2D.** Colton compared `docs/screenshot_3d_wide.png` and
> `docs/screenshot_3d_showcase_strip.png` against the 2D game and chose 2D. The single-view AI
> meshes lose the painted detail (compare the Garage Core sprite with its 3D mesh), and the three
> things 3D genuinely won — cast shadows, a soft fog edge, visible motion on moving units — are
> cheap to reproduce in 2D. `presentation3d/` and `scenes/Main3D.tscn` stay in the repo as a
> shelved prototype; nothing builds on them. The original Phase 3 (roster port to 3D) is
> **cancelled** and replaced by the 2D polish phase below.

### Phase 3 — 2D polish: what 3D won, done in 2D (~1 day)
Tickets in `docs/specs/p3-0x-*.md`. All presentation-only; `core/` and `gameplay/` untouched.
| Task | Tier |
|---|---|
| `p3-01-cast-shadows-2d` Cast-shadow pass under units/structures, drawn before sprites, sun from upper-left like the 3D rig | **C** |
| `p3-02-soft-fog-edge` Soft 3-cell fog-of-war edge (eroded + blurred overlay; explored stays dim; minimap stays crisp) | **C** |
| `p3-03-2d-unit-motion` Procedural motion on moving units: rotor blur + hover (air), rock + dust (vehicles), walk bob (infantry); `--capture-frames` for 2D | **P** |

<details><summary>Cancelled: Phase 3 — Roster port to 3D (kept for the record)</summary>

| Task | Tier |
|---|---|
| Per-class rig recipes (wheeled / tracked / legged / rotor / jet / infantry): attach points, spin axes, tilt | **F** designs, **P** implements |
| Batch-apply recipes to all 45 vehicles + 13 infantry → `assets/models/units/<id>.tscn` | **L** |
| Turret nodes that track `weapon.current_target_id`; recoil on `combat_occurred` | **P** |
| Death: tip over + darken + emit smoke; wreck stays if `wreckDefinitionId` | **P** |
| Review sheets: render each unit from 3 angles into a grid | **L** builds, **F** reviews once per faction |
</details>

### Phase 4 — Camera + controls — SHIPPED 2026-09-22 (b3e1ce9, 1f53df0, e007564, 0d1fc8b, 9ed362d) + `p4-06` bugfix ticket pending
Landing order is fixed: p4-01, p4-02, p4-04, p4-03, p4-05 (see `docs/specs/README.md`). WASD is
unbound so A/S/G can be command keys; pan is arrows + edge scroll + middle-drag.
| Task | Tier |
|---|---|
| `p4-01` Arrow/edge/middle-drag pan, cursor-anchored eased zoom, `H` home | **P** |
| `p4-02` Minimap click-to-jump + right-click move | **C** |
| `p4-04` `A` attack-move (armed click), `S` stop, `G` hold, Escape; HUD ATTACK/GUARD chips | **P** |
| `p4-03` Ctrl+0–9 groups, double-click type-select, Shift order queue (adds `Entity.order_queue` in the sim) | **O** (Sonnet) or **P** |
| `p4-05` Contextual cursor sprites (procedural, 32×32) | **C** |

### Phase 5 — Movement feel (~3 days)
| Task | Tier |
|---|---|
| Steering spec: turn-rate-limited heading, separation, path smoothing, formation slots while moving | **F** |
| Implement per spec with a headless test (no overlap after 200 ticks, group arrives in formation) | **P** |
| Tune constants against a screenshot/GIF | **F** (one review) |

### Phase 6 — Audio (~2 days)
| Task | Tier |
|---|---|
| `AudioManager` on `GameEvents`: fire/impact/death/build/select/ack, per-weapon family, positional | **O** (Sonnet) |
| Source CC0 SFX (Kenney audio packs), write `THIRD_PARTY_NOTICES.md` entries, pack into `assets/audio/` | **L** |
| Faction announcer lines: generate with local TTS (Kokoro is installed) from a script F writes | **L** |

### Phase 7 — Game shell (~2 days)
| Task | Tier |
|---|---|
| Title scene → Skirmish (VC vs FC only), Quit; hide TS/SG in UI (data stays) | **O** (Sonnet) |
| Win/lose screen + Restart | **C** |
| Resource bar wording: `POWER 10/0` → `POWER 0 / 10` used/total with a bar; red on deficit | **C** |
| One real font in `UiTheme`, portraits 48 → 80 px, build buttons 64 → 72 | **H** |
| README (pitch, run line, controls table), LICENSE, THIRD_PARTY_NOTICES | **H** drafts, Colton picks the license |

### Phase 8 — Combat FX in 3D (~2 days)
| Task | Tier |
|---|---|
| Muzzle flash `OmniLight3D` + particle, tracer/projectile meshes, impact sparks, explosion + scorch decal | **P** |
| Tune against a GIF | **F** (one review) |

### Continuous — repo hygiene (cheap, do alongside)
| Task | Tier |
|---|---|
| GitHub Actions: Godot headless runs all suites on push | **H** |
| Content validation test: unknown weapon/unit/structure ids, duplicate ids, missing sprite/portrait, bad footprint, `trainsUnits` pointing at the wrong faction | **C** |
| Rename `test_phaseN.gd` → `test_combat/navigation/economy/building/fog/ai.gd` | **H** |
| `assets_sources.json` (Kenney kits, generated meshes: source, license, checksum, expected path) + bootstrap script | **L** |

## Where the F budget actually goes

Roughly: Phase 2 prototype (most of it), the three specs (order state, steering, rig recipes),
and one review per faction / per phase. Everything else is O/P/C/H/L. Expect F on maybe a fifth of
the calendar; the rest is cheaper models executing specs against tests.

## How Colton runs this without F in the loop

- Nexus Telegram: `/code <ticket text from this doc>` for C tasks, `/pro …` for P tasks. Router-inferred
  builds already go `/local` (Ornith) — fine for L tasks.
- Claude Code: `/model sonnet` or `/model haiku` before starting an O/H ticket; switch back to Fable
  only for the F rows.
- Each ticket ends with: suites green, commit, push, one screenshot in `docs/` if visual.
