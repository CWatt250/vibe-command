# p1-06 — Win / lose is computed and shown

**Tier:** C (DeepSeek Flash) · **Repo:** `~/Dev/vibe-command` · **Touches:** `core/simulation/Simulation.gd`, `core/simulation/GameEvents.gd`, `ui/HUD.gd`, `tests/test_phase7.gd`

## Problem
`Simulation.gd` declares `var match_over_for: Dictionary = {}  # faction -> bool (base destroyed)`
and **nothing ever writes it**. `grep -rn match_over_for` finds only the declaration. The game
cannot be won or lost; nothing in `ui/` shows a result.

## Change
1. `core/simulation/GameEvents.gd`: add
   `signal match_over(loser: String, winner: String)`.
2. `Simulation.gd`: add a check at the end of `step()` (after `_cleanup_control_groups()`):
   ```gdscript
   _check_match_over()
   ```
   and the function:
   ```gdscript
   ## A faction loses when it has no built HQ-class structure left. First loser ends the
   ## match; with two players the other is the winner. Fires once.
   func _check_match_over() -> void:
       if not match_over_for.is_empty():
           return
       var alive_hq: Dictionary = {}
       for f in _players.keys():
           alive_hq[f] = false
       for e in entities.values():
           if e.alive and e.kind == "structure" and e.def_data.get("class", "") == "HQ" \
                   and (e.construction == null or e.construction.is_built()):
               alive_hq[e.faction_id] = true
       for f in alive_hq.keys():
           if not alive_hq[f]:
               match_over_for[f] = true
               var winner := ""
               for other in alive_hq.keys():
                   if other != f and alive_hq[other]:
                       winner = other
               events.match_over.emit(f, winner)
               events.log.emit("MATCH OVER: %s lost (HQ destroyed); winner %s" % [f, winner])
               return
   ```
   Guard: only run the loss check once a faction has had an HQ at some point — otherwise a
   sandbox that spawns units before structures loses instantly. Simplest: track
   `var _had_hq: Dictionary = {}` set to true in `spawn_structure` when `class == "HQ"`, and skip
   factions where `_had_hq.get(f, false)` is false.
3. `ui/HUD.gd`: connect `events.match_over` and show a centred `PanelContainer` (use
   `UiTheme.panel(faction)`) with a big label: `VICTORY` if `winner == faction` else `DEFEAT`,
   and a `Restart` button that calls `get_tree().reload_current_scene()`. Pause the sim by
   setting `get_tree().paused = true` (the pause menu already uses this pattern; note
   `PauseMenu` runs with `PROCESS_MODE_ALWAYS` — set the same on this panel).

## Test
Add to `tests/test_phase7.gd` (the VC HQ at (1000,1000) exists; FC has none yet in that test):
```gdscript
# --- p1-06: match over when the HQ falls ---
var fc_hq := sim.spawn_structure("FC-B01", "FC", Vector2(1600, 1600), true)
var over := []
events.match_over.connect(func(l, w): over.append([l, w]))
_run(sim, 1)
_check(over.is_empty(), "no result while both HQs stand")
sim.remove_entity(fc_hq)
_run(sim, 1)
_check(over.size() == 1 and over[0][0] == "FC" and over[0][1] == "VC", "FC loses, VC wins")
_run(sim, 5)
_check(over.size() == 1, "match_over fires exactly once")
```

## Done when
- Checks pass; all suites `ALL PASS`. Commit + push:
  `feat: win/lose — HQ loss ends the match; HUD shows result with Restart`
