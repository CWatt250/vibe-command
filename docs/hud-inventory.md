# HUD phase — godot-open-rts inventory

_2026-09-20. Source: `~/Dev/godot-open-rts` (MIT, Godot 4.3, shallow clone). Target: `ui/` (empty)._

## Verdict up front

godot-open-rts is **3D** (Node3D/Camera3D, Kenney space kit). Everything world-side — placement
ghost, selection handlers, minimap, unit scenes — is useless to a 2D game. The HUD is plain
`Control`/`CanvasLayer` and ports, but it is thinner than the README implies: ~650 lines,
hardcoded per-building menus, no data-driven anything. We already have a better minimap.

**Net lift: layout skeleton + two patterns. Not code.** Budget the HUD phase as a build, not a port.

## What to take

| Piece | Source file | Take as | Why |
|---|---|---|---|
| Screen layout | `source/match/Match.tscn` lines 267–410 | Structure | One `HUD` CanvasLayer, three `MarginContainer`s anchored to corners: resources top-left, minimap bottom-left, production queue + build grid bottom-right. Copy the anchor/preset values, nothing else. |
| Queue observer | `source/match/hud/ProductionQueue.gd` | Pattern | On selection change: detach old queue, find single selected producer, attach, rebuild element nodes; elements are `Button`s showing `NN%` that cancel on press. Rewrite against our signals. |
| Build grid | `source/match/hud/UnitMenus.tscn` | Structure | 4-column `GridContainer` of 48×48 slots under a `PanelContainer`. Reuse the grid; **replace** the hardcoded `VehicleFactoryMenu`/`WorkerMenu`/… scenes with one menu driven by `structures.json` `trainsUnits` and the faction's structure list. |
| Pause menu | `source/match/Menu.gd` | Verbatim | 25 lines: ESC toggles a CanvasLayer + `get_tree().paused`. Swap `MatchSignals.match_aborted` for our own. |
| Resource bar | `source/match/hud/ResourcesBar.tscn` | Skip | Two hardcoded labels. Ours needs credits + power + compute (VC) or credits + power + command capacity (FC) — write it from `factions.json` `resourceIds`. |
| Minimap | `source/match/hud/Minimap.gd` | Skip | 3D ray-plane projection. `presentation/MiniMapRenderer.gd` already does this in 2D. |
| Tooltips | `unit-menus/*.gd` | Skip | Every tooltip is a hand-typed `format()` of constants. Ours come from the def dict (`displayName`, `costCredits`, `buildTimeSec`, `maxHealth`, `function`). |
| Placement ghost | `players/human/StructurePlacementHandler.tscn` | Skip | 3D. Need a 2D one: draw footprint from `def.footprint` at the cursor cell, green/red via `Simulation._placement_valid` (currently private — expose it). |

## What our sim already gives the HUD

Signals on `GameEvents` a HUD can bind to today:
`resource_changed(faction, resource_id, amount)` (delta, not total — read `sim.get_resources(f)` for the number),
`production_queued`, `production_progress`, `building_constructed`, `unit_spawned`, `unit_died`, `structure_order`, `log`.

Commands the HUD can issue through `sim.run_commands(0, [...])`:
- `{"type":"TRAIN","entityIds":[producer_id],"unitDefId":"VC-U03"}`
- `{"type":"BUILD","structureDefId":"VC-B04","position":Vector2,"faction":"VC"}` (or `builderId`)
- `{"type":"SET_RALLY","entityIds":[...],"position":Vector2}`
- `STOP`, `GARRISON`, `UNGARRISON`, `REPAIR`, `CONTROL_ASSIGN/RECALL`

Per-entity state: `e.production.queue` (`[{unit, progress, total, paid_cost}]`), `e.production.progress()`,
`e.construction.fraction()`, `e.def_data.trainsUnits`.

## Gaps the HUD phase must close (found while reading)

_Status 2026-09-20: 1–4 closed and 5–6 answered by `Simulation.faction_status()`; see
`tests/test_phase7.gd`. Two extra sim bugs surfaced by the `can_place` test and fixed the same
day: `spawn_structure(start_built=true)` never blocked its footprint (pre-placed HQs were
walk-through and build-over), and `_unblock_footprint` had no caller (destroyed structures left
permanent rubble in the nav grid). First HUD render: `docs/screenshot_hud.png`._

1. **Structures are unselectable.** `SelectionInput._units_in_rect` / `_unit_at_world` filter on
   `e.kind == "unit"`. A build sidebar keyed off "click the factory" cannot work until click-select
   also hits structures (drag-select should probably still exclude them, C&C-style).
2. **No queue cancel command.** `ProductionComponent.cancel()` exists but nothing in
   `run_commands` routes to it, and there is no refund path. Add `CANCEL_TRAIN {entityIds, index}`
   that pops the item and `add_credits(paid_cost)`.
3. **Selection doesn't hit the event bus.** `Game._on_selection` sets `sim.selected_ids` directly;
   `events.entity_selected` is declared but never emitted. Emit it there so HUD panels can rebind
   without touching `SelectionInput`.
4. **`_placement_valid` is private.** The ghost needs it for live green/red. Expose a public
   `can_place(def_id, pos, faction)` wrapper.
5. **`resource_changed` carries a delta.** Fine for a ticker, useless for a label. HUD reads
   `sim.get_resources(faction)["credits"]` on each signal, or we add a `resource_total` signal.
6. **Power/compute/command have no HUD-facing accessor.** `PowerSystem`, `ComputeSystem`,
   `CommandCapacitySystem` recompute per tick but nothing caches "produced / drawn" per faction
   for display. Verify before building the bar.

## Proposed `ui/` layout

Code-built (no .tscn), matching the rest of `presentation/`:

```
ui/
  HUD.gd                  DONE  CanvasLayer(layer=30). Resources top-left, selection info bottom-left.
  ResourceBar.gd          DONE  Columns from factions.json resourceIds (+command for FC); reads faction_status().
  BuildGrid.gd            DONE  4×N grid. TRAIN mode (structure w/ trainsUnits) or BUILD mode (BuilderNetwork
                                structure = HQ → all faction structures → place_requested). Greyed if unaffordable.
  ProductionQueuePanel.gd DONE  Observer pattern from open-rts; head shows live %, click cancels via CANCEL_TRAIN.
  PlacementGhost.gd       DONE  Node2D in world space; snaps with the sim's anchor-cell math; can_place() colour;
                                LMB builds, RMB/Esc cancels; consumes input while active.
  PauseMenu.gd            DONE  Port of open-rts Menu.gd; Esc toggles, process_mode ALWAYS.
```

`MiniMapRenderer` stays where it is (bottom-right, own CanvasLayer at 20).

## Order of work

1. ~~Sim gaps 1–4~~ DONE — `tests/test_phase7.gd`.
2. ~~`HUD` skeleton + `ResourceBar`~~ DONE — `docs/screenshot_hud.png`.
3. ~~`BuildGrid` TRAIN mode + `ProductionQueuePanel`~~ DONE — `docs/screenshot_hud_build.png`.
   Debug capture args for HUD screenshots: `-- --capture=<png> --frame=N --select=<def_id> [--train=<unit_id>] [--place=<def_id>] [--pause]`.
4. ~~`BuildGrid` BUILD mode + `PlacementGhost`~~ DONE — `docs/screenshot_hud_place.png`.
5. ~~`PauseMenu`~~ DONE.

HUD phase is functionally complete: the game can be played from the UI (select, train, cancel,
build, place). Visual restyle of these panels belongs to the HUD pass in `docs/visual-roadmap.md`.

Licence note: only godot-open-rts is safe to copy from (MIT). OpenRA/OpenHV/Warzone are GPL — reference only.
