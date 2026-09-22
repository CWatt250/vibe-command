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

## Phase 3 — 2D polish (DONE 2026-09-22; presentation only, `core/` and `gameplay/` untouched)

10. `p3-01-cast-shadows-2d.md` — C. Shipped `b6be7cf`.
11. `p3-02-soft-fog-edge.md` — C. Shipped `fd48b1e`.
12. `p3-03-2d-unit-motion.md` — P. Shipped `14767cc` (Infantry `bob_hz` 2.0 → 0.9375 so the
    prescribed capture frames don't alias the 2-frame step; see the commit body).

F reviewed `docs/screenshot_2d_shadows.png`, `docs/screenshot_2d_fog.png`,
`docs/screenshot_2d_motion_strip.png` and `docs/screenshot_2d_motion_wide.png`: all accepted.
Two small follow-ups, not blocking: dust puffs spawn 10 px behind `position`, which lands inside
a large (Heavy) sprite and is drawn over it by FxRenderer — should trail by half the sprite width;
rotor crosses read a little bright in the wide shot. Both are C-tier tweaks for a later pass.

**Dispatching long tickets:** Telegram caps a message at 4096 chars. For any ticket over that,
send a short `/code` or `/pro` message that names the ticket path and the hard rules, and let the
executor read the file — the dispatcher runs on WattBott with the repo checked out. DeepSeek
cannot view PNGs; it verifies captures by pixel measurement, so the visual sign-off stays with F.

Next: Phase 4 (camera + controls) per `docs/execution-plan.md` — specs to be written by F.
