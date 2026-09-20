#!/usr/bin/env python3
"""Pipeline B post-process: AI render on a flat magenta key -> game sprite.

    python tools/ai_sprite_prep.py in.png out.png [--width 256]

Keys the magenta background to alpha (soft edge), drops the baked ground shadow
(it is magenta-hued too; the renderer draws its own contact shadow), crops to the
opaque bbox and resizes to `--width`. Structures are drawn width-fit to their
footprint, so 256 px wide leaves 2x headroom for zoom on a 3x3 (120 px) pad.
"""
import argparse
import numpy as np
from PIL import Image


def key_magenta(im: Image.Image) -> Image.Image:
    a = np.asarray(im.convert("RGB")).astype(np.float32) / 255.0
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    # Magenta-ness as a ratio of the pixel's own brightness, so the near-black
    # part of the baked shadow (same hue, tiny absolute chroma) keys out too.
    value = np.maximum(np.maximum(r, g), b)
    mag = np.clip((np.minimum(r, b) - g) / np.maximum(value, 0.05) * 1.6, 0.0, 1.0)
    # Soft alpha: fully opaque where score < 0.35, fully clear where > 0.7.
    alpha = 1.0 - np.clip((mag - 0.35) / 0.35, 0.0, 1.0)
    out = np.dstack([a, alpha])
    # Despill: pull residual magenta out of edge pixels.
    spill = np.clip(np.minimum(r, b) - g, 0, 1)[..., None] * 0.6
    out[..., 0:1] -= spill * (1 - alpha[..., None])
    out[..., 2:3] -= spill * (1 - alpha[..., None])
    out = np.clip(out, 0, 1)
    return Image.fromarray((out * 255).astype(np.uint8), "RGBA")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("src")
    p.add_argument("dst")
    p.add_argument("--width", type=int, default=256)
    args = p.parse_args()
    im = key_magenta(Image.open(args.src))
    bbox = im.getbbox()
    im = im.crop(bbox)
    scale = args.width / im.width
    im = im.resize((args.width, max(1, int(im.height * scale))), Image.LANCZOS)
    im.save(args.dst)
    print(f"{args.dst}: {im.size} from bbox {bbox}")


if __name__ == "__main__":
    main()
