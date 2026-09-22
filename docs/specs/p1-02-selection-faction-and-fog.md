# p1-02 — Selection respects faction and fog

**Tier:** C (DeepSeek Flash) · **Repo:** `~/Dev/vibe-command` · **Touches:** `presentation/SelectionInput.gd`, `tests/test_phase7.gd`

## Problem
`presentation/SelectionInput.gd`:
- `_units_in_rect(box)` returns every unit inside the drag rectangle regardless of faction, so a
  drag over a mixed fight selects enemy units too.
- `_unit_at_world(p)` / `_structure_at_world(p)` return an enemy even if it is hidden in fog, so a
  player who knows where a hidden unit is can click-select and right-click-attack it.

The player's faction is `sim.selected_faction`. Fog is `sim.fog_sys` with
`is_visible(faction: String, pos: Vector2) -> bool`.

## Change (all in `SelectionInput.gd`)
1. `_units_in_rect`: add `and e.faction_id == sim.selected_faction` to the filter. Drag-select is
   own-units only (C&C convention).
2. Add a helper:
   ```gdscript
   ## Own entities are always pickable; enemy/neutral only if the player can see them now.
   func _pickable(e: Entity) -> bool:
       if e.faction_id == sim.selected_faction:
           return true
       return sim.fog_sys == null or sim.fog_sys.is_visible(sim.selected_faction, e.position)
   ```
3. In `_unit_at_world` and `_structure_at_world`, skip any entity for which `_pickable(e)` is false.
4. `_issue_context_order`: the attack branch already checks `faction_id != sim.selected_faction`;
   additionally require `_pickable(target)` — otherwise fall through to MOVE.

## Test
`SelectionInput` needs a camera to construct, so test the helper logic through a small headless
harness in `tests/test_phase7.gd`. Add a **static-free** copy of the rule as a sim-level check:
```gdscript
# --- p1-02: selection faction/fog rule (mirrors SelectionInput._pickable) ---
sim.selected_faction = "VC"
var far_fc := sim.spawn_unit("FC-U01", "FC", Vector2(200, 200))   # far from every VC sensor
_run(sim, 2)
_check(not sim.fog_sys.is_visible("VC", sim.entities[far_fc].position), "hidden FC unit is not visible to VC")
var near_fc := sim.spawn_unit("FC-U01", "FC", Vector2(1010, 1000))  # next to the VC HQ
_run(sim, 2)
_check(sim.fog_sys.is_visible("VC", sim.entities[near_fc].position), "FC unit beside VC HQ is visible")
```
(The HQ at (1000,1000) exists earlier in that test file.) This locks the sim behaviour the
selection code now relies on.

## Done when
- Dragging a box over enemies selects none of them (verify by reading the code path; no UI test).
- The two new checks pass; all suites `ALL PASS`. Commit + push:
  `fix: drag-select is own-faction only; enemies pickable only when visible`
