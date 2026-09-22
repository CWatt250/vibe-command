# Specs — ready-to-paste tickets for lower-tier models

Each file in this folder is one ticket. Paste the whole file as the prompt. They are written so
a model that has never seen this repo can do the job: files to touch, exact behaviour, the test
to add, and the done-criteria. Don't shorten them when pasting.

## How to dispatch

| Tier in the ticket header | Where to run it |
|---|---|
| **C** (DeepSeek Flash) | Telegram → Nexus: `/code` + paste the ticket |
| **P** (DeepSeek Pro) | Telegram → Nexus: `/pro` + paste |
| **O** (Sonnet) | Claude Code: `/model sonnet`, then paste |
| **H** (Haiku) | Claude Code: `/model haiku`, then paste |
| **L** (Ornith, local) | Telegram → Nexus, plain message (router sends builds to `/local`) |

Run tickets **in the numbered order** — later ones assume earlier ones landed.

## Every ticket ends the same way (the model must do all of it)

```
cd ~/Dev/vibe-command
for t in tests/test_*.gd; do godot-4 --headless --path . --script $t 2>&1 | grep -E "RESULT|SCRIPT ERROR|Parse Error"; done
```
All lines must say `ALL PASS`, none may say `SCRIPT ERROR`. Then:
```
git add <only the files you changed>
git commit -m "<title from the ticket>"      # body: what and why, 3–6 lines
git push origin master
```
Commit **and push** — pushing is a standing rule in this repo. Never `git add -A`, never force-push.

## Repo facts the tickets rely on

- Godot 4.7, GDScript. Engine binary is `godot-4` (snap).
- `core/` and `gameplay/` are the pure simulation (no Node types). `presentation/` and `ui/` only
  read the sim through `sim` and react to `GameEvents` signals. Keep that split.
- Tests are `tests/test_*.gd`, `extends SceneTree`, run headless, print `..._RESULT: ALL PASS` or
  a count of failures. Copy the harness style of `tests/test_phase7.gd` for new checks.
- New `class_name` scripts need `godot-4 --headless --path . --import` once before headless runs
  see them.
- Content is JSON under `content/data/`, loaded by `core/simulation/ContentRegistry.gd`.

## Phase 1 tickets (correctness)

1. `p1-01-tick-rate.md` — C
2. `p1-02-selection-faction-and-fog.md` — C
3. `p1-03-fog-aware-targeting.md` — C
4. `p1-04-navgrid-terrain-vs-occupancy.md` — C
5. `p1-05-camera-clamp.md` — C
6. `p1-06-win-lose.md` — C
7. `p1-07-order-state-attack-move.md` — O (Sonnet)

## Phase 2 — the decision gate (DONE — decided 2026-09-22: stay 2D)

8. `p2-01-runtime-3d-prototype.md` — O (Sonnet). Shipped (`0c4e96b`).
9. `p2-02-prototype-fixes-and-showcase.md` — O (Sonnet). Shipped (`b261709`).

Outcome: Colton compared `docs/screenshot_3d_wide.png` / `docs/screenshot_3d_showcase_strip.png`
with the 2D game and chose **2D**. `presentation3d/` and `scenes/Main3D.tscn` are shelved — do
not build on them. The 3D roster port is cancelled; Phase 3 below is what 3D won, done in 2D.

## Phase 3 — 2D polish (presentation only; `core/` and `gameplay/` untouched)

Run in this order — p3-01 and p3-03 edit the same file.

10. `p3-01-cast-shadows-2d.md` — C. Shadow pass under every unit/structure, drawn before sprites.
11. `p3-02-soft-fog-edge.md` — C. Soft 3-cell fog edge; minimap stays crisp. (Different file from
    p3-01, so it may run in parallel with it.)
12. `p3-03-2d-unit-motion.md` — P. Rotor blur + hover, vehicle rock + dust, infantry walk bob;
    ports `--capture-frames` to the 2D game. Its line numbers are from `b261709` (pre p3-01) —
    the ticket says to locate edits by the quoted code.

After all three: an **F** review of the three new `docs/screenshot_2d_*.png` and the strip. Then
Phase 4 (camera + controls) per `docs/execution-plan.md`.
