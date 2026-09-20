#!/usr/bin/env python3
"""Generate the Vibe Command terrain tile set (visual-roadmap V3).

Same idea as generate_sprites.py: procedural, CC0, regenerable. Tiles are
NavGrid.CELL (40 px) squares; props are alpha sprites scattered by MapRenderer.

  dirt_0..3   open ground, seeded speckle variation so a field isn't a flat fill
  road_h/v/x  cracked asphalt with a worn centre line; x = intersection
  pad         dark concrete pad with corner bolts — under structures / rubble
  rock_0..1, scrap_0..1, bush, tiremarks   props (alpha)

Writes assets/terrain/*.png + manifest.json.
"""
import json
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "..", "assets", "terrain")
os.makedirs(OUT, exist_ok=True)
T = 40  # tile px == NavGrid.CELL

DIRT = (82, 78, 62)
DIRT_D = (66, 62, 48)
DIRT_L = (98, 94, 76)
ASPHALT = (56, 55, 52)
ASPHALT_D = (42, 41, 39)
ASPHALT_L = (74, 72, 68)
LINE = (140, 128, 82)
PAD = (40, 42, 41)
PAD_D = (30, 31, 30)
PAD_L = (58, 60, 58)
ROCK = (110, 108, 100)
ROCK_D = (72, 70, 64)
SCRAP = (120, 96, 60)
SCRAP_D = (74, 58, 36)
METAL = (128, 132, 138)
BUSH = (60, 82, 46)
BUSH_D = (38, 56, 30)
SHADOW = (0, 0, 0, 70)

manifest = {}


def save(im, name):
    path = os.path.join(OUT, name + ".png")
    im.save(path)
    manifest[name] = name + ".png"


def speckle(d, rng, base_d, base_l, n, size=(1, 2)):
    for _ in range(n):
        x, y = rng.randrange(T), rng.randrange(T)
        s = rng.randint(*size)
        d.rectangle([x, y, x + s - 1, y + s - 1], fill=base_d if rng.random() < 0.6 else base_l)


def dirt(seed):
    rng = random.Random(seed)
    im = Image.new("RGBA", (T, T), DIRT + (255,))
    d = ImageDraw.Draw(im)
    speckle(d, rng, DIRT_D, DIRT_L, 70)
    # a few pebbles
    for _ in range(rng.randint(1, 3)):
        x, y = rng.randrange(3, T - 3), rng.randrange(3, T - 3)
        d.ellipse([x, y, x + 2, y + 2], fill=ROCK_D)
    return im


def asphalt_base(seed):
    rng = random.Random(seed)
    im = Image.new("RGBA", (T, T), ASPHALT + (255,))
    d = ImageDraw.Draw(im)
    speckle(d, rng, ASPHALT_D, ASPHALT_L, 55)
    # cracks: short jittered polylines
    for _ in range(rng.randint(1, 2)):
        x, y = rng.randrange(T), rng.randrange(T)
        pts = [(x, y)]
        for _ in range(rng.randint(3, 6)):
            x += rng.randint(-5, 5)
            y += rng.randint(-5, 5)
            pts.append((x, y))
        d.line(pts, fill=ASPHALT_D, width=1)
    return im, d


def road_h(seed):
    im, d = asphalt_base(seed)
    # shoulders + worn dashed centre line
    d.line([(0, 1), (T, 1)], fill=ASPHALT_L, width=1)
    d.line([(0, T - 2), (T, T - 2)], fill=ASPHALT_L, width=1)
    for x in range(2, T, 12):
        d.line([(x, T // 2), (x + 6, T // 2)], fill=LINE, width=2)
    return im


def road_v(seed):
    return road_h(seed).transpose(Image.ROTATE_90)


def road_x(seed):
    im, d = asphalt_base(seed)
    for x in range(2, T, 12):
        d.line([(x, T // 2), (x + 6, T // 2)], fill=LINE, width=2)
        d.line([(T // 2, x), (T // 2, x + 6)], fill=LINE, width=2)
    return im


def pad(seed):
    rng = random.Random(seed)
    im = Image.new("RGBA", (T, T), PAD + (255,))
    d = ImageDraw.Draw(im)
    speckle(d, rng, PAD_D, PAD_L, 30)
    d.rectangle([0, 0, T - 1, T - 1], outline=PAD_D)
    for (x, y) in [(4, 4), (T - 6, 4), (4, T - 6), (T - 6, T - 6)]:
        d.ellipse([x, y, x + 2, y + 2], fill=PAD_L)
    return im


def prop_canvas():
    return Image.new("RGBA", (T, T), (0, 0, 0, 0))


def rock(seed):
    rng = random.Random(seed)
    im = prop_canvas()
    d = ImageDraw.Draw(im)
    cx, cy = T // 2, T // 2
    w, h = rng.randint(10, 16), rng.randint(7, 11)
    d.ellipse([cx - w // 2 + 2, cy - h // 2 + 3, cx + w // 2 + 2, cy + h // 2 + 3], fill=SHADOW)
    d.ellipse([cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2], fill=ROCK, outline=ROCK_D)
    d.ellipse([cx - w // 4, cy - h // 3, cx, cy], fill=(130, 128, 120))
    return im


def scrap(seed):
    rng = random.Random(seed)
    im = prop_canvas()
    d = ImageDraw.Draw(im)
    for _ in range(rng.randint(3, 5)):
        x, y = rng.randint(8, T - 16), rng.randint(8, T - 16)
        w, h = rng.randint(5, 10), rng.randint(4, 8)
        d.rectangle([x + 2, y + 3, x + w + 2, y + h + 3], fill=SHADOW)
        col = SCRAP if rng.random() < 0.6 else METAL
        d.rectangle([x, y, x + w, y + h], fill=col, outline=SCRAP_D)
    return im


def bush(seed):
    rng = random.Random(seed)
    im = prop_canvas()
    d = ImageDraw.Draw(im)
    cx, cy = T // 2, T // 2
    d.ellipse([cx - 9, cy - 5, cx + 11, cy + 9], fill=SHADOW)
    for _ in range(5):
        x, y = cx + rng.randint(-6, 6), cy + rng.randint(-5, 5)
        r = rng.randint(4, 7)
        d.ellipse([x - r, y - r, x + r, y + r], fill=BUSH, outline=BUSH_D)
    return im


def tiremarks(seed):
    im = prop_canvas()
    d = ImageDraw.Draw(im)
    for x in (12, 24):
        d.arc([x - 10, 4, x + 10, T + 10], start=200, end=340, fill=(0, 0, 0, 60), width=3)
    return im


if __name__ == "__main__":
    for i in range(4):
        save(dirt(100 + i), f"dirt_{i}")
    save(road_h(201), "road_h")
    save(road_v(201), "road_v")
    save(road_x(202), "road_x")
    save(pad(300), "pad")
    save(rock(401), "rock_0")
    save(rock(402), "rock_1")
    save(scrap(501), "scrap_0")
    save(scrap(502), "scrap_1")
    save(bush(601), "bush")
    save(tiremarks(701), "tiremarks")
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    print(f"wrote {len(manifest)} terrain tiles to {os.path.abspath(OUT)}")
