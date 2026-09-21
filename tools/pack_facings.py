#!/usr/bin/env python3
"""Pack Blender facing frames into one strip atlas + manifest entry.

    python3 tools/pack_facings.py <unit_id> <frames_dir> [--downscale 2]

Trims every frame to the union of their opaque bboxes (so all facings share one frame size and
the unit's anchor doesn't wander), optionally downsamples (render at 2x, ship at 1x), lays them
out left-to-right, writes assets/sprites/rendered/<id>.png and sets the manifest entry to
{"file": "rendered/<id>.png", "facings": N, "frame": [w, h]}.
"""
import argparse
import glob
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "assets", "sprites")
MANIFEST = os.path.join(SPRITES, "manifest.json")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("unit_id")
    ap.add_argument("frames_dir")
    ap.add_argument("--downscale", type=int, default=2)
    a = ap.parse_args()

    paths = sorted(glob.glob(os.path.join(a.frames_dir, f"{a.unit_id}_*.png")))
    if not paths:
        raise SystemExit("no frames")
    frames = [Image.open(p).convert("RGBA") for p in paths]
    boxes = [f.getbbox() for f in frames]
    x0 = min(b[0] for b in boxes); y0 = min(b[1] for b in boxes)
    x1 = max(b[2] for b in boxes); y1 = max(b[3] for b in boxes)
    # Keep the crop symmetric around the frame centre so rotation stays centred.
    cx, cy = frames[0].width / 2, frames[0].height / 2
    half_w = max(cx - x0, x1 - cx); half_h = max(cy - y0, y1 - cy)
    crop = (int(cx - half_w), int(cy - half_h), int(cx + half_w) + 1, int(cy + half_h) + 1)
    frames = [f.crop(crop) for f in frames]
    if a.downscale > 1:
        frames = [f.resize((f.width // a.downscale, f.height // a.downscale), Image.LANCZOS) for f in frames]
    fw, fh = frames[0].size
    atlas = Image.new("RGBA", (fw * len(frames), fh), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        atlas.paste(f, (i * fw, 0))
    out_dir = os.path.join(SPRITES, "rendered")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"{a.unit_id}.png")
    atlas.save(out)
    man = json.load(open(MANIFEST))
    # scale: the trim box includes masts/antennas, so the body lands well under the
    # armor-class size target; 1.4 puts the body itself near the target.
    man[a.unit_id] = {"file": f"rendered/{a.unit_id}.png", "facings": len(frames),
                      "frame": [fw, fh], "scale": 1.4}
    json.dump(man, open(MANIFEST, "w"), indent=1, sort_keys=True)
    print(f"{out}: {len(frames)} frames of {fw}x{fh}; manifest updated")


if __name__ == "__main__":
    main()
