# p4-06 — Units must not acquire, chase, shoot or splash neutral resource fields

**Tier:** C (DeepSeek Flash) · **Repo:** `~/Dev/vibe-command` (HEAD `9ed362d` or later) · **Touches:** `gameplay/systems/CombatSystem.gd`, new `tests/test_neutral_targets.gd`

Why C: one gameplay file, one new predicate used in three places, a headless sim test that pins the
behaviour. No presentation change, no data change.

Read `docs/specs/README.md` first. **Order:** any time after Phase 4; it depends on nothing in Phase 4
and nothing depends on it.

## Keys
None. This ticket binds nothing.

## Why (a real bug, found while verifying p4-03)
Resource fields are spawned as faction-less structures: `core/simulation/Simulation.gd:142-148`
`spawn_resource_field` builds `Entity.new({}, "", _next_id)` — empty `def_data`, empty
`faction_id` — with `kind = "structure"` and a `ResourceNodeComponent` (`Entity.resource`,
`core/simulation/Entity.gd:54`, attached at `:125-128`). It is the ONLY caller of `Entity.new` with an
empty faction (`grep -rn "Entity.new(" core gameplay` → `Simulation.gd:98, :111, :144`).

Combat only ever excludes **same-faction** entities, so a faction-less field is "enemy" to everyone:
- `gameplay/systems/CombatSystem.gd:109-125` `_acquire_target`: the only faction test is
  `cand.faction_id == e.faction_id` (`:116`). A field passes.
- `:141-159` `_target_tag_valid`: `armorClass` defaults to `"Infantry"` (`:142`) for an entity with
  empty `def_data`, so any weapon with the `infantry` or `ground` or `structure` tag accepts it.
- `:161-165` `_valid_target` (used every tick at `:38` and `:67` to keep or drop the current target)
  has the same single faction test (`:163`).
- `:195-208` `_apply_splash` damages anything alive in the radius except the shooter (`:200`).

Observed (headless probe, p4-03 review): a VC-U01 spawned next to a field acquired it
(`weapon.current_target_id == field`) and the field's HP fell to 92 in 30 ticks. In play this
means idle units plink at your own ore, harvesters mine a target that is being shot, and splash
from a fight near a field erodes it.

## Change — `gameplay/systems/CombatSystem.gd`
Add one predicate and use it in the three places above. Nothing else in the file changes.

### 1. The predicate (add directly above `_acquire_target`, after `_can_see` at `:104-106`)
```gdscript
## Only real combatants are targets. Resource fields are spawned with an empty faction and a
## ResourceNodeComponent (Simulation.spawn_resource_field) and must never be acquired, kept as a
## target, or splashed — they are the map's ore, not a unit of anybody's.
func _is_combatant(cand: Entity) -> bool:
	return cand.faction_id != "" and cand.resource == null
```

### 2. `_acquire_target` — extend the skip at `:116`
```gdscript
		if cand == null or not cand.alive or cand.faction_id == e.faction_id or not _is_combatant(cand):
			continue
```

### 3. `_valid_target` — extend the early return at `:163`
```gdscript
	if t == null or not t.alive or t.faction_id == e.faction_id or not _is_combatant(t):
		return false
```
This also drops an explicit `ATTACK` command aimed at a field: the next tick's validity check
(`:38` / `:67`) fails and the weapon's `current_target_id` resets to `-1`, exactly as for a dead
target.

### 4. `_apply_splash` — extend the skip at `:200`
```gdscript
		if t == null or not t.alive or t.id == e.id or not _is_combatant(t):
			continue
```

## Test — new file `tests/test_neutral_targets.gd`
Copy the harness style of `tests/test_phase7.gd` (`extends SceneTree`, `_init`, `_check`, `_fail`,
`_run`, `_finish` at `tests/test_phase7.gd:167-183`; result line style at `:161-164`).

```gdscript
extends SceneTree
## test_neutral_targets.gd — p4-06: combat ignores neutral resource fields.
## Headless: `godot-4 --headless --path . --script tests/test_neutral_targets.gd`

var failures: int = 0

func _init() -> void:
	var registry := ContentRegistry.new("res://content/data/")
	registry.load_all()
	var sim := Simulation.new(registry, GameEvents.new(), 50, 50)
	sim.add_player("VC")
	sim.add_player("FC")

	# --- a lone unit next to a field: never acquires it, field HP untouched ---
	var field_id := sim.spawn_resource_field(Vector2(1000, 1000), 4000.0)
	var field: Entity = sim.entities[field_id]
	var u_id := sim.spawn_unit("VC-U01", "VC", Vector2(1040, 1000))
	var u: Entity = sim.entities[u_id]
	_check(u.weapon != null, "premise: VC-U01 has a weapon")
	_check(field.faction_id == "" and field.resource != null, "premise: field is faction-less with a resource component")
	var hp0: float = field.health.current
	_run(sim, 45)
	_check(u.weapon.current_target_id != field_id, "unit never acquires the field (target=%d)" % u.weapon.current_target_id)
	_check(is_equal_approx(field.health.current, hp0), "field HP unchanged after 45 ticks (%.1f -> %.1f)" % [hp0, field.health.current])

	# --- explicit ATTACK on the field is dropped on the next tick ---
	sim.run_commands(0, [{"type": "ATTACK", "entityIds": [u_id], "targetEntityId": field_id}])
	_run(sim, 3)
	_check(u.weapon.current_target_id != field_id, "explicit ATTACK on a field does not stick")
	_check(is_equal_approx(field.health.current, hp0), "field HP still unchanged after explicit ATTACK")

	# --- regression: a real enemy next to the same unit IS acquired and takes damage ---
	var enemy_id := sim.spawn_unit("FC-U01", "FC", Vector2(1040, 1040))
	var enemy: Entity = sim.entities[enemy_id]
	var ehp0: float = enemy.health.current
	_run(sim, 45)
	_check(enemy.health.current < ehp0 or not enemy.alive, "real enemy still gets shot (%.1f -> %.1f)" % [ehp0, enemy.health.current])
	_check(is_equal_approx(field.health.current, hp0), "field HP unchanged while a fight happens beside it")

	if failures == 0:
		print("NEUTRAL_RESULT: ALL PASS")
	else:
		print("NEUTRAL_RESULT: %d FAILURE(S)" % failures)
	_finish()

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: " + msg)
	else:
		_fail(msg)

func _fail(msg: String) -> void:
	failures += 1
	push_error("FAIL: " + msg)
	print("FAIL: " + msg)

func _run(sim: Simulation, ticks: int) -> void:
	for i in range(ticks):
		sim.step(1.0 / 15.0)

func _finish() -> void:
	quit()
```
If `spawn_unit` returns `-1` for either spot, move it one cell (40 px) away; both spots are open
dirt on the default 50×50 grid (no obstacles are placed by `Simulation` itself). VC-U01 and FC-U01
both carry weapons in `content/data/units.json`; the fog system is created by `Simulation.new` and
both units reveal their own surroundings, so visibility is not the limiting factor at 40 px.
No new `class_name`, so no `--import` step.

**Before touching the code**, run the new test once against HEAD and confirm the first
"never acquires" or "HP unchanged" check FAILS — that proves the test sees the bug. Then apply the
change and run it again.

## Screenshot
None. This is a sim rule; there is nothing to see. F does not need to eyeball anything.

## Done when
- `godot-4 --headless --path . --script tests/test_neutral_targets.gd` printed at least one `FAIL:`
  before the change and prints `NEUTRAL_RESULT: ALL PASS` after it.
- The full loop from `docs/specs/README.md` shows every suite `ALL PASS`, no `SCRIPT ERROR`, no
  `Parse Error` — 16 suites including the new one.
- `grep -n "_is_combatant" gameplay/systems/CombatSystem.gd` returns exactly four lines (the
  definition and three uses).
- `git status --short` shows exactly ` M gameplay/systems/CombatSystem.gd` and
  `?? tests/test_neutral_targets.gd` from your work. Nothing under `core/`, `presentation/`, `ui/`,
  `presentation3d/`. `*.import` and `*.uid` are gitignored — do not add them. The tree may carry
  unrelated untracked files (e.g. `tools/deepseek_*.py`); leave them alone — `git add` only the two
  files above, never `-A`.
- Commit, then `git push origin master`:
  `fix(combat): neutral resource fields are never acquired, kept as a target, or splashed`
  Body (3–5 lines): fields spawn faction-less, so the same-faction-only exclusion treated them as
  enemies; one `_is_combatant` predicate now gates acquisition, per-tick target validity and splash.
- Report: `git log --oneline -1`, the `NEUTRAL_RESULT` line and the before-fix `FAIL:` line(s),
  the full-loop RESULT lines.
