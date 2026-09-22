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

After all seven: an **F** review of `git log --oneline -7` and one screenshot from
`godot-4 --path . -- --capture=docs/screenshot_phase1.png --frame=90 --attack` (needs `DISPLAY=:99`
and `--rendering-method gl_compatibility --rendering-driver opengl3`).
