# p1-03 — Combat target acquisition respects fog

**Tier:** C (DeepSeek Flash) · **Repo:** `~/Dev/vibe-command` · **Touches:** `gameplay/systems/CombatSystem.gd`, `tests/test_phase7.gd`

## Problem
`gameplay/systems/CombatSystem.gd::_acquire_target(e)` picks any living enemy within
`w.acquire_radius` from the spatial index. It never asks the fog system, so units auto-fire at
enemies their faction cannot see. (`_valid_target` — used to keep an existing target — has the
same gap.)

`sim.fog_sys.is_visible(faction, pos)` is the authority. Note `acquire_radius` (220 default) can
exceed a unit's `visionRadius`, which is exactly when this bug shows.

## Change (in `CombatSystem.gd`)
1. Add a helper:
   ```gdscript
   ## A faction may only engage what its sensors currently reveal.
   func _can_see(faction: String, pos: Vector2) -> bool:
       return sim.fog_sys == null or sim.fog_sys.is_visible(faction, pos)
   ```
2. `_acquire_target`: inside the loop, after the `faction_id == e.faction_id` skip, add
   `if not _can_see(e.faction_id, cand.position): continue`.
3. `_valid_target`: add `and _can_see(e.faction_id, t.position)` to the return condition, so a
   target that slips back into fog is dropped and re-acquired later.
4. Explicit player `ATTACK` orders (`Simulation._issue_attack`) are **not** changed here — that's
   gated by selection (ticket p1-02).

## Test
Add to `tests/test_phase7.gd`:
```gdscript
# --- p1-03: no acquisition through fog ---
sim.add_player("FC")
var shooter := sim.spawn_unit("VC-U04", "VC", Vector2(1400, 1400))   # Technical, has a weapon
var s_e: Entity = sim.entities[shooter]
var vis_r: float = s_e.def_data.get("visionRadius", 200.0)
var acq_r: float = s_e.weapon.acquire_radius
_check(acq_r > vis_r, "test premise: acquire radius (%d) exceeds vision (%d)" % [acq_r, vis_r])
# Enemy inside acquire radius but outside vision -> must NOT be acquired.
var lurker := sim.spawn_unit("FC-U01", "FC", Vector2(1400 + (vis_r + acq_r) * 0.5, 1400))
_run(sim, 3)
_check(s_e.weapon.current_target_id != lurker, "enemy in fog is not acquired")
# Move it inside vision -> acquired.
sim.entities[lurker].position = Vector2(1400 + vis_r * 0.5, 1400)
sim.spatial.update(lurker, sim.entities[lurker].position)   # if SpatialIndex has update(); else remove+insert
_run(sim, 3)
_check(s_e.weapon.current_target_id == lurker, "enemy revealed is acquired")
```
Check `core/spatial/SpatialIndex.gd` for the actual method to move an entity (`update`, or
`remove` + `insert`) and use that. If `VC-U04`'s `acquire_radius <= visionRadius`, pick a unit
where the premise holds (print both and choose), or temporarily set `s_e.weapon.acquire_radius`
larger in the test.

## Done when
- Both new checks pass and all suites `ALL PASS`. Commit + push:
  `fix: combat acquisition and target validity respect fog of war`
