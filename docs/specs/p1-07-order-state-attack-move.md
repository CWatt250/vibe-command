# p1-07 — Explicit order state; real ATTACK_MOVE

**Tier:** O (Sonnet 5 via Claude Code `/model sonnet`) · **Repo:** `~/Dev/vibe-command` · **Touches:** `core/simulation/Entity.gd`, `core/simulation/Simulation.gd`, `gameplay/systems/CombatSystem.gd`, `tests/test_phase7.gd`

Run this **after** p1-01…p1-06 have landed.

## Problem
`Simulation._issue_attack_move()` is literally `_issue_move()`. `_issue_attack()` only sets
`weapon.current_target_id` and does not cancel the unit's current path, so a unit already walking
somewhere finishes that walk before pursuing. There is no notion of *what a unit is doing*, so
"advance, stop and fight what you meet, then resume advancing" cannot exist.

## Design (implement exactly this)
Add to `Entity.gd`:
```gdscript
enum Order { IDLE, MOVE, ATTACK, ATTACK_MOVE, HOLD }
var order: Order = Order.IDLE
var order_target: int = -1              # entity id for ATTACK
var order_dest: Vector2 = Vector2.ZERO  # for MOVE / ATTACK_MOVE
```
Transitions (all in `Simulation.gd` order handlers; `CombatSystem` reads `e.order`):

| Order issued | Sets | Movement | Auto-acquire? | Ends when |
|---|---|---|---|---|
| `MOVE` | `order=MOVE, order_dest` | path to dest | **no** (ignore enemies en route) | reached → `IDLE` |
| `ATTACK` | `order=ATTACK, order_target` | **clear current path**; chase target via existing `_chase` | no (locked to target) | target dead/invalid → `IDLE` |
| `ATTACK_MOVE` | `order=ATTACK_MOVE, order_dest` | path to dest | **yes** | reached → `IDLE` |
| `STOP` | `order=IDLE`, clear path, `current_target_id=-1` | none | yes (idle units still defend themselves) | — |
| `HOLD` | `order=HOLD`, clear path | never moves | yes, but never chases | until another order |

`ATTACK_MOVE` engagement loop (in `CombatSystem.tick_all`, per unit with a weapon):
- If `e.order == ATTACK_MOVE` and there is no current target: acquire (fog-aware, from p1-03). If
  one is found: `e.movement.clear()` (stop advancing) and fight; **remember `order_dest`**.
- If `e.order == ATTACK_MOVE` and the target dies or becomes invalid: re-path to `order_dest`
  (`grid_map.find_path` as `_issue_move` does) and keep `order == ATTACK_MOVE`.
- `MOVE`: skip acquisition entirely while `movement.is_moving()`; a unit that finishes a MOVE
  becomes `IDLE` and then defends itself normally.
- `HOLD`: acquire and fire if in range; never call `_chase`.
- `IDLE`: current behaviour (acquire, chase a little).

`_issue_attack` must call `e.movement.clear()` before setting the target so the chase starts now.

Keep the JSON command names the same (`MOVE`, `ATTACK`, `ATTACK_MOVE`, `STOP`); add `HOLD`.
`SkirmishAI` already issues `ATTACK_MOVE` — it gets the new behaviour for free.

## Tests (add to `tests/test_phase7.gd`)
```gdscript
# --- p1-07: order state ---
sim.add_player("FC")
var am := sim.spawn_unit("VC-U04", "VC", Vector2(600, 1500))
var blocker := sim.spawn_unit("FC-U01", "FC", Vector2(900, 1500))      # on the way, in vision
sim.run_commands(0, [{"type": "ATTACK_MOVE", "entityIds": [am], "targetPosition": Vector2(1400, 1500)}])
_check(sim.entities[am].order == Entity.Order.ATTACK_MOVE, "order is ATTACK_MOVE")
_run(sim, 60)
var am_e: Entity = sim.entities[am]
_check(am_e.weapon.current_target_id == blocker or not sim.entities.has(blocker), "attack-mover engaged the blocker")
# Kill the blocker if still alive; the unit must resume toward its destination.
if sim.entities.has(blocker): sim.remove_entity(blocker)
_run(sim, 5)
_check(am_e.order == Entity.Order.ATTACK_MOVE and am_e.movement.is_moving(), "resumed advance after the kill")

var mv := sim.spawn_unit("VC-U04", "VC", Vector2(600, 1700))
var bait := sim.spawn_unit("FC-U01", "FC", Vector2(700, 1700))
sim.run_commands(0, [{"type": "MOVE", "entityIds": [mv], "targetPosition": Vector2(1400, 1700)}])
_run(sim, 10)
_check(sim.entities[mv].weapon.current_target_id == -1, "plain MOVE ignores enemies en route")

var hold := sim.spawn_unit("VC-U04", "VC", Vector2(600, 1900))
sim.run_commands(0, [{"type": "HOLD", "entityIds": [hold]}])
var far := sim.spawn_unit("FC-U01", "FC", Vector2(600 + 400, 1900))   # outside weapon range, inside acquire
_run(sim, 20)
_check(not sim.entities[hold].movement.is_moving(), "HOLD never chases")
```
Adjust distances if `VC-U04`'s weapon range / acquire radius make a premise false — print them
and pick values that satisfy "in acquire radius, out of weapon range".

## Done when
- `_issue_attack_move` no longer delegates to `_issue_move` unchanged.
- All new checks pass; **all** suites `ALL PASS` (especially `test_phase6.gd`, whose skirmish AI
  relies on ATTACK_MOVE). Commit + push:
  `feat: explicit unit order state; ATTACK_MOVE engages en route and resumes; HOLD`
