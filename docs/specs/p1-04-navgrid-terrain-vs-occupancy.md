# p1-04 — NavGrid: terrain type is not occupancy

**Tier:** C (DeepSeek Flash) · **Repo:** `~/Dev/vibe-command` · **Touches:** `core/spatial/NavGrid.gd`, `presentation/MapRenderer.gd`, `presentation/MiniMapRenderer.gd`, `tests/test_phase7.gd`

## Problem
`core/spatial/NavGrid.gd::set_blocked` writes the *render* array: blocking a cell sets
`land_types[cy][cx] = 2`, and unblocking resets it to `0`. So a structure built on a road (`1`)
and later destroyed leaves dirt (`0`) — the road is gone. Terrain and occupancy are two facts
stored in one byte.

## Change
1. `NavGrid.gd`: remove the two `land_types` writes from `set_blocked`. `_blocked` already holds
   occupancy; `land_types` becomes terrain only (`0` open, `1` street; `2` may still be painted by
   maps for permanent rubble).
2. Add a read helper so renderers don't reach into `_blocked` by hand:
   ```gdscript
   ## What to draw at a cell: 2 if occupied (structure pad / rubble), else the terrain type.
   func render_type(cx: int, cy: int) -> int:
       return 2 if is_blocked(cx, cy) else land_types[cy][cx]
   ```
3. `presentation/MapRenderer.gd::_draw`: replace `var lt: int = land_grid[y][x]` with
   `var lt: int = grid.render_type(x, y)` (the tile picker already maps `>= 2` to the pad tile).
   The road auto-tiler `_is_road` should keep reading `land_grid` (terrain), so a road that runs
   under a pad still connects its neighbours — leave it.
4. `presentation/MiniMapRenderer.gd::_build_terrain_texture`: it's built once; use
   `sim.grid_map.render_type(x, y)` there too so pads show on the minimap.

## Test
Add to `tests/test_phase7.gd`:
```gdscript
# --- p1-04: blocking a road cell does not erase the road ---
var g := sim.grid_map
g.land_types[10][10] = 1
g.set_blocked(10, 10, true)
_check(g.is_blocked(10, 10), "cell is blocked")
_check(g.render_type(10, 10) == 2, "blocked cell renders as pad")
g.set_blocked(10, 10, false)
_check(g.land_types[10][10] == 1, "road survives block/unblock")
_check(g.render_type(10, 10) == 1, "unblocked cell renders as road again")
```

## Done when
- `grep -n "land_types" core/spatial/NavGrid.gd` shows no writes inside `set_blocked`.
- New checks pass; all suites `ALL PASS`. Commit + push:
  `fix: NavGrid keeps terrain type separate from occupancy; roads survive structures`
