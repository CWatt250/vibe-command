# p1-01 — One authoritative tick rate

**Tier:** C (DeepSeek Flash) · **Repo:** `~/Dev/vibe-command` (Godot 4.7, GDScript) · **Touches:** 4 files

## Problem
`core/simulation/Simulation.gd` declares `const TICK_HZ: int = 15`, but `presentation/Game.gd`
drives the sim with its own `const TICK_RATE: float = 30.0`. Every `tick % N` cadence in the UI and
FX was written assuming 15 Hz (`ui/HUD.gd` says `tick % 5` is "~3 Hz"), so at 30 Hz they all run
twice as fast, and the headless tests step at `1.0 / 15.0` while the game steps at `1.0 / 30.0` —
the sim is tested at a different rate than it is played.

## Change
1. `presentation/Game.gd`: delete `const TICK_RATE`. Replace `var step := 1.0 / TICK_RATE` with
   `var step := Simulation.TICK_DT`. Update the file's header comment if it mentions 30.
2. Add to `core/simulation/Simulation.gd`, right after `TICK_DT`:
   ```gdscript
   ## Ticks per second-fraction, for presenters that refresh "about N times a second".
   static func ticks_per(hz: float) -> int:
       return maxi(1, int(roundf(float(TICK_HZ) / hz)))
   ```
3. Replace the hard-coded cadences with calls to that:
   - `ui/HUD.gd` line ~100: `tick % 5` → `tick % Simulation.ticks_per(3.0)`
   - `ui/ResourceBar.gd`, `ui/BuildGrid.gd`, `ui/ProductionQueuePanel.gd`: replace
     `const REFRESH_EVERY_TICKS := 5` with `var REFRESH_EVERY_TICKS := Simulation.ticks_per(3.0)`
     (keep the name; `const` can't call a function).
   - `presentation/FxRenderer.gd` line ~56: `% 4` → `% Simulation.ticks_per(4.0)`; line ~59:
     `% 12` → `% Simulation.ticks_per(1.25)`.
4. Do **not** change `TICK_HZ` itself. 15 is what every test was tuned against.

## Test
Add to `tests/test_phase7.gd`, before the final result print:
```gdscript
# --- p1-01: one tick rate ---
_check(Simulation.ticks_per(3.0) == 5, "ticks_per(3 Hz) at 15 Hz is 5")
_check(is_equal_approx(Simulation.TICK_DT, 1.0 / 15.0), "TICK_DT derives from TICK_HZ")
```

## Done when
- `grep -rn "TICK_RATE" presentation/ ui/` returns nothing.
- `grep -rn "% 5\b\|% 4\b\|% 12\b" ui/ presentation/` returns nothing (all cadences go through `ticks_per`).
- All `tests/test_*.gd` print `ALL PASS`. Then commit + push:
  `fix: one authoritative sim tick rate (15 Hz); presenters derive cadences from it`
