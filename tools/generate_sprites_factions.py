#!/usr/bin/env python3
"""Titan Systems + The Signal sprite pass, plus the Federal Command gaps.

Art language comes from the three faction roster sheets (2026-09-08):

  TS  Titan Systems   graphite / ceramic white / amber / network teal
                      Premium corporate war machine: sleek angular panels,
                      polished, minimal, high-contrast trim.
  SG  The Signal      blackened alloy / bone grey / iridescent oil / ember / violet
                      Assimilated machines: asymmetric, organic-mechanical,
                      glowing ember and violet seams.
  FC  Federal Command olive drab / coyote tan / matte black / steel
                      Rugged near-future combined arms, field-repairable.

Palette provenance: the sheet hex codes were verified against the source images
by pixel match -- 9 of 15 matched exactly. The four that did not (TS titanium,
TS network teal, SG bone grey, SG ember) were recovered from each sheet's
dominant saturated colours: TS amber e8b040, TS teal 188080, SG ember c05010,
SG violet 684090. No colour here is invented.

Facing convention: sprites point up (-Y) = rotation 0.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_sprites as G  # noqa: E402
from generate_sprites import (  # noqa: E402
    canvas, save, shadow, outline_rect, shade, wheel, led, rotor,
    tracked, wheeled, METAL, METAL_D, OUT,
)
from PIL import Image  # noqa: E402

# ------------------------------------------------------------------ palettes
TS_GRAPHITE = (36, 38, 41)
TS_GRAPHITE_L = (60, 64, 68)
TS_CERAMIC = (231, 231, 231)
TS_AMBER = (232, 176, 64)
TS_TEAL = (24, 128, 128)

SG_ALLOY = (23, 23, 25)
SG_ALLOY_L = (46, 48, 52)
SG_BONE = (184, 186, 131)
SG_OIL = (52, 58, 66)
SG_EMBER = (192, 80, 16)
SG_VIOLET = (104, 64, 144)

FC_OLIVE = (78, 91, 58)
FC_TAN = (154, 131, 101)
FC_BLACK = (29, 31, 32)
FC_STEEL = (102, 110, 114)
FC_IR = (190, 166, 106)

M2 = {}


def reg(def_id, stem):
    M2[def_id] = stem


# ------------------------------------------------------------------ builders
def glow(d, x, y, r, col):
    """Ember/violet seam glow: a soft halo then a hot core."""
    d.ellipse([x - r - 2, y - r - 2, x + r + 2, y + r + 2], fill=shade(col, 0.45))
    d.ellipse([x - r, y - r, x + r, y + r], fill=col)


def ceramic_trim(d, cx, cy, w, h):
    """TS signature: white ceramic plate over graphite hull."""
    outline_rect(d, [cx - w / 2, cy - h / 2, cx + w / 2, cy - h / 2 + 7], 3,
                 TS_CERAMIC, shade(TS_CERAMIC, 0.6), 1)
    d.rounded_rectangle([cx - w / 2 + 4, cy + h / 2 - 8, cx + w / 2 - 4, cy + h / 2 - 4],
                        radius=2, fill=TS_AMBER)


def heli(d, cx, cy, col, accent, w=20, h=30, guns=False):
    shadow(d, cx, cy + 2, w + 14, h + 6, 3)
    d.ellipse([cx - 3, cy + h / 2 - 4, cx + 3, cy + h / 2 + 12], fill=shade(col, 0.7))
    d.ellipse([cx - 5, cy + h / 2 + 8, cx + 5, cy + h / 2 + 14], fill=(30, 32, 36))
    outline_rect(d, [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], int(w / 2), col, (12, 13, 15), 2)
    d.rounded_rectangle([cx - w / 2 + 4, cy - h / 2 + 4, cx + w / 2 - 4, cy - h / 2 + 11],
                        radius=3, fill=shade(accent, 0.9))
    d.ellipse([cx - 5, cy - h / 2 + 1, cx + 5, cy - h / 2 + 11], fill=(20, 22, 26))
    if guns:
        d.rounded_rectangle([cx - w / 2 - 6, cy - 2, cx - w / 2 + 1, cy + 2], radius=1, fill=(40, 42, 46))
        d.rounded_rectangle([cx + w / 2 - 1, cy - 2, cx + w / 2 + 6, cy + 2], radius=1, fill=(40, 42, 46))
    d.line([cx - 16, cy - h / 2 + 2, cx + 16, cy - h / 2 + 2], fill=shade(col, 1.4), width=2)


def jet(d, cx, cy, col, accent):
    shadow(d, cx, cy + 2, 34, 30, 3)
    d.polygon([(cx, cy - 22), (cx - 7, cy - 4), (cx - 7, cy + 14), (cx + 7, cy + 14), (cx + 7, cy - 4)],
              fill=col, outline=(12, 13, 15))
    d.polygon([(cx - 7, cy - 2), (cx - 22, cy + 12), (cx - 20, cy + 16), (cx - 7, cy + 10)],
              fill=shade(col, 0.8), outline=(12, 13, 15))
    d.polygon([(cx + 7, cy - 2), (cx + 22, cy + 12), (cx + 20, cy + 16), (cx + 7, cy + 10)],
              fill=shade(col, 0.8), outline=(12, 13, 15))
    d.polygon([(cx, cy - 20), (cx - 4, cy - 8), (cx + 4, cy - 8)], fill=shade(accent, 0.95))
    d.ellipse([cx - 4, cy + 8, cx + 4, cy + 16], fill=(30, 34, 40))


def quad(d, cx, cy, col, accent, r=13, blades=4):
    shadow(d, cx, cy + 1, r * 2 + 6, r * 2 + 4, 2)
    for i in range(blades):
        ang = 0.7854 + i * (6.2832 / blades)
        ax, ay = cx + r * 0.72 * __import__("math").cos(ang), cy + r * 0.72 * __import__("math").sin(ang)
        d.line([cx, cy, ax, ay], fill=shade(col, 1.3), width=2)
        rotor(d, ax, ay, 4)
    outline_rect(d, [cx - r * 0.5, cy - r * 0.5, cx + r * 0.5, cy + r * 0.5], 4, col, (12, 13, 15), 2)
    d.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=accent)
    led(d, cx, cy - r * 0.5 + 2)


def legs(d, cx, cy, span, count, col, spread=0.0):
    """Splayed walking legs for TS/SG walkers."""
    import math
    for i in range(count):
        side = -1 if i % 2 == 0 else 1
        t = i // 2
        y = cy - span / 2 + (span / max(1, count // 2 - 1)) * t
        kx = cx + side * (span * 0.42 + spread)
        d.line([cx + side * 4, y, kx, y + side * 3], fill=shade(col, 1.2), width=3)
        d.line([kx, y + side * 3, kx + side * 3, y + 7], fill=shade(col, 0.8), width=3)
        d.ellipse([kx + side * 3 - 2, y + 5, kx + side * 3 + 2, y + 10], fill=(20, 21, 24))


def mech(d, cx, cy, col, accent, w=24, h=26, heavy=False):
    shadow(d, cx, cy + 3, w + 16, h + 8, 3)
    legs(d, cx, cy, h + 6, 4 if not heavy else 6, col)
    outline_rect(d, [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], 5, col, (12, 13, 15), 2)
    d.rounded_rectangle([cx - w / 2 + 3, cy - h / 2 + 3, cx + w / 2 - 3, cy - h / 2 + 9],
                        radius=2, fill=shade(accent, 0.85))
    d.ellipse([cx - 4, cy - h / 2 - 3, cx + 4, cy - h / 2 + 5], fill=shade(col, 1.35))
    d.rounded_rectangle([cx - w / 2 - 6, cy - 6, cx - w / 2 + 2, cy + 6], radius=2, fill=shade(col, 0.85))
    d.rounded_rectangle([cx + w / 2 - 2, cy - 6, cx + w / 2 + 6, cy + 6], radius=2, fill=shade(col, 0.85))
    d.line([cx, cy + h / 2 - 6, cx, cy + h / 2 + 2], fill=accent, width=2)


def humanoid_bot(d, cx, cy, col, accent, s=1.0):
    shadow(d, cx, cy + 3, int(18 * s), int(22 * s), 2)
    d.rounded_rectangle([cx - 5 * s, cy - 9 * s, cx + 5 * s, cy + 3 * s], radius=int(3 * s),
                        fill=col, outline=(12, 13, 15))
    d.ellipse([cx - 4 * s, cy - 14 * s, cx + 4 * s, cy - 7 * s], fill=shade(col, 1.3))
    d.line([cx - 3 * s, cy - 12 * s, cx + 3 * s, cy - 12 * s], fill=accent, width=2)
    d.rounded_rectangle([cx - 9 * s, cy - 8 * s, cx - 5 * s, cy + 2 * s], radius=int(2 * s), fill=shade(col, 0.85))
    d.rounded_rectangle([cx + 5 * s, cy - 8 * s, cx + 9 * s, cy + 2 * s], radius=int(2 * s), fill=shade(col, 0.85))
    d.rounded_rectangle([cx - 4 * s, cy + 3 * s, cx - 1 * s, cy + 12 * s], radius=1, fill=shade(col, 0.7))
    d.rounded_rectangle([cx + 1 * s, cy + 3 * s, cx + 4 * s, cy + 12 * s], radius=1, fill=shade(col, 0.7))


def six_leg(d, cx, cy, col, accent):
    import math
    shadow(d, cx, cy + 1, 24, 20, 2)
    for i in range(6):
        side = -1 if i % 2 == 0 else 1
        y = cy - 6 + (i // 2) * 6
        d.line([cx, y, cx + side * 11, y - 4], fill=shade(col, 1.25), width=2)
        d.line([cx + side * 11, y - 4, cx + side * 13, y + 3], fill=shade(col, 0.8), width=2)
    outline_rect(d, [cx - 6, cy - 7, cx + 6, cy + 7], 5, col, (10, 11, 13), 2)
    glow(d, cx, cy - 3, 2, accent)


def tint_deck(src_key, dst_key, mul):
    """Faction-tinted variant of a CC0 Kenney character deck (RGB multiply)."""
    src = os.path.join(OUT, "characters", src_key + ".png")
    if not os.path.exists(src):
        return None
    im = Image.open(src).convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            px[x, y] = (min(255, int(r * mul[0])), min(255, int(g * mul[1])),
                        min(255, int(b * mul[2])), a)
    im.save(os.path.join(OUT, "characters", dst_key + ".png"))
    return "characters/" + dst_key


# ------------------------------------------------------------------ TS units
def gen_ts():
    # infantry: faction-tinted CC0 decks (graphite / teal)
    for did, deck, mul in (("TS-U01", "manbrown", (0.62, 0.70, 0.72)),
                           ("TS-U02", "manold", (0.60, 0.80, 0.82))):
        stem = tint_deck(deck, did + "_tsInf", mul)
        if stem:
            reg(did, stem)

    im, d = canvas(44); quad(d, 22, 23, TS_GRAPHITE, TS_TEAL, r=11); reg("TS-U03", "TS-U03_recon"); save(im, "TS-U03_recon")

    im, d = canvas(48); wheeled(d, 24, 25, 22, 18, TS_GRAPHITE, TS_AMBER)
    ceramic_trim(d, 24, 25, 18, 14); d.ellipse([20, 12, 28, 20], fill=shade(TS_GRAPHITE, 1.5))
    reg("TS-U04", "TS-U04_suv"); save(im, "TS-U04_suv")

    im, d = canvas(56); wheeled(d, 28, 29, 28, 22, TS_GRAPHITE, TS_TEAL)
    ceramic_trim(d, 28, 29, 24, 16); d.rounded_rectangle([24, 8, 32, 16], radius=3, fill=shade(TS_GRAPHITE_L, 1.3))
    d.line([28, 8, 28, 16], fill=TS_TEAL, width=2); reg("TS-U05", "TS-U05_apc"); save(im, "TS-U05_apc")

    im, d = canvas(48); mech(d, 24, 24, TS_GRAPHITE, TS_AMBER, w=20, h=22)
    ceramic_trim(d, 24, 24, 16, 12); reg("TS-U06", "TS-U06_exo"); save(im, "TS-U06_exo")

    im, d = canvas(60); tracked(d, 30, 31, 30, 24, TS_GRAPHITE, TS_AMBER, barrel=16, barrel_w=6, turret=(24, 20))
    ceramic_trim(d, 30, 28, 22, 16); reg("TS-U07", "TS-U07_paladin"); save(im, "TS-U07_paladin")

    im, d = canvas(60); tracked(d, 30, 31, 30, 24, TS_GRAPHITE, TS_TEAL, barrel=0, turret=(22, 18))
    d.rounded_rectangle([29, 2, 31, 20], radius=1, fill=(180, 190, 196)); d.rounded_rectangle([27, 16, 33, 22], radius=2, fill=shade(TS_GRAPHITE_L, 1.2))
    reg("TS-U08", "TS-U08_rail"); save(im, "TS-U08_rail")

    im, d = canvas(52); wheeled(d, 26, 27, 26, 20, TS_GRAPHITE, TS_TEAL)
    d.ellipse([22, 8, 30, 16], fill=shade(TS_GRAPHITE_L, 1.4), outline=(12, 13, 15), width=2)
    d.ellipse([24, 10, 28, 14], fill=TS_TEAL); d.line([26, 16, 26, 22], fill=shade(TS_GRAPHITE_L, 1.6), width=3)
    reg("TS-U09", "TS-U09_aegis"); save(im, "TS-U09_aegis")

    im, d = canvas(60); heli(d, 30, 30, TS_GRAPHITE, TS_AMBER, w=20, h=30, guns=True)
    reg("TS-U10", "TS-U10_gunship"); save(im, "TS-U10_gunship")

    im, d = canvas(56)
    for ox, oy, w in ((-13, -8, 7), (13, -8, 7), (0, 10, 9)):
        cx, cy = 28 + ox, 28 + oy
        d.polygon([(cx, cy - 12), (cx - w, cy + 8), (cx + w, cy + 8)], fill=TS_GRAPHITE, outline=(12, 13, 15))
        d.polygon([(cx, cy - 10), (cx - 2, cy + 1), (cx + 2, cy + 1)], fill=TS_AMBER)
        d.line([cx - w + 1, cy + 5, cx + w - 1, cy + 5], fill=shade(TS_GRAPHITE_L, 1.5), width=2)
    reg("TS-U11", "TS-U11_interceptors"); save(im, "TS-U11_interceptors")

    im, d = canvas(56); mech(d, 28, 28, TS_GRAPHITE, TS_AMBER, w=26, h=28, heavy=True)
    ceramic_trim(d, 28, 28, 20, 16); reg("TS-U12", "TS-U12_heavExo"); save(im, "TS-U12_heavExo")

    im, d = canvas(64); mech(d, 32, 32, TS_GRAPHITE, TS_TEAL, w=28, h=30, heavy=True)
    d.line([32, 6, 32, 18], fill=TS_AMBER, width=3); d.rounded_rectangle([18, 14, 26, 26], radius=3, fill=shade(TS_GRAPHITE_L, 1.2))
    d.rounded_rectangle([38, 14, 46, 26], radius=3, fill=shade(TS_GRAPHITE_L, 1.2)); led(d, 32, 20, 2)
    reg("TS-U13", "TS-U13_mech"); save(im, "TS-U13_mech")

    im, d = canvas(72); heli(d, 36, 34, TS_GRAPHITE, TS_TEAL, w=28, h=40)
    d.rounded_rectangle([22, 12, 50, 22], radius=4, fill=shade(TS_GRAPHITE_L, 1.25))
    d.line([24, 17, 48, 17], fill=TS_AMBER, width=2)
    for lx in (26, 34, 42, 46):
        led(d, lx, 20, 1)
    reg("TS-U14", "TS-U14_skyhook"); save(im, "TS-U14_skyhook")


# ------------------------------------------------------------------ SG units
def gen_sg():
    im, d = canvas(36); six_leg(d, 18, 19, SG_ALLOY, SG_EMBER)
    reg("SG-U01", "SG-U01_skitter"); save(im, "SG-U01_skitter")

    im, d = canvas(40)
    shadow(d, 20, 21, 22, 18, 2)
    d.ellipse([9, 10, 31, 32], fill=SG_OIL, outline=(10, 11, 13), width=2)
    d.ellipse([14, 15, 26, 27], fill=SG_ALLOY, outline=(10, 11, 13), width=1)
    glow(d, 20, 21, 4, SG_VIOLET); d.line([20, 4, 20, 10], fill=shade(SG_OIL, 1.4), width=2)
    reg("SG-U02", "SG-U02_watcher"); save(im, "SG-U02_watcher")

    im, d = canvas(52)
    shadow(d, 26, 27, 30, 24, 2)
    outline_rect(d, [12, 13, 40, 41], 6, SG_OIL, (10, 11, 13), 2)
    d.rounded_rectangle([17, 8, 35, 18], radius=4, fill=SG_ALLOY, outline=(10, 11, 13), width=2)
    d.polygon([(20, 18), (32, 18), (26, 34)], fill=shade(SG_BONE, 0.75))
    glow(d, 26, 30, 3, SG_EMBER)
    reg("SG-U03", "SG-U03_harv"); save(im, "SG-U03_harv")

    im, d = canvas(44)
    shadow(d, 22, 24, 20, 24, 2)
    d.rounded_rectangle([17, 16, 27, 32], radius=4, fill=SG_OIL, outline=(10, 11, 13), width=2)
    d.polygon([(17, 17), (27, 17), (26, 10), (18, 10)], fill=SG_BONE)
    d.ellipse([18, 4, 26, 14], fill=SG_ALLOY, outline=(10, 11, 13), width=2)
    d.line([19, 8, 25, 8], fill=SG_EMBER, width=2)
    d.polygon([(27, 18), (37, 11), (28, 25)], fill=shade(SG_ALLOY_L, 1.15))
    d.rounded_rectangle([13, 18, 17, 29], radius=2, fill=shade(SG_OIL, 0.8))
    d.rounded_rectangle([18, 32, 21, 41], radius=1, fill=shade(SG_ALLOY_L, 0.9))
    d.rounded_rectangle([23, 32, 26, 41], radius=1, fill=shade(SG_ALLOY_L, 0.9))
    glow(d, 22, 23, 2, SG_VIOLET)
    reg("SG-U04", "SG-U04_replicant"); save(im, "SG-U04_replicant")

    im, d = canvas(48)
    shadow(d, 24, 25, 26, 22, 2)
    for i in range(4):
        side = -1 if i % 2 == 0 else 1
        y = 18 + (i // 2) * 12
        d.line([24, y, 24 + side * 15, y + 8], fill=shade(SG_ALLOY_L, 1.2), width=3)
    outline_rect(d, [15, 15, 33, 34], 6, SG_ALLOY, (10, 11, 13), 2)
    d.polygon([(19, 15), (29, 15), (24, 6)], fill=SG_OIL)
    glow(d, 24, 24, 2, SG_VIOLET)
    reg("SG-U05", "SG-U05_stalker"); save(im, "SG-U05_stalker")

    im, d = canvas(52)
    shadow(d, 26, 27, 26, 24, 2)
    outline_rect(d, [15, 14, 37, 36], 8, SG_OIL, (10, 11, 13), 2)
    for i in range(6):
        a = -0.9 + i * 0.36
        d.line([26, 34, 26 + int(16 * __import__("math").sin(a)), 48], fill=shade(SG_ALLOY_L, 1.15), width=2)
    d.ellipse([21, 19, 31, 29], fill=SG_ALLOY, outline=(10, 11, 13), width=2)
    glow(d, 26, 24, 3, SG_EMBER)
    reg("SG-U06", "SG-U06_assimilator"); save(im, "SG-U06_assimilator")

    im, d = canvas(56)
    shadow(d, 28, 29, 30, 26, 2)
    legs(d, 28, 29, 28, 4, SG_ALLOY_L, spread=3)
    outline_rect(d, [17, 17, 39, 38], 6, SG_OIL, (10, 11, 13), 2)
    d.rounded_rectangle([22, 12, 34, 20], radius=4, fill=SG_ALLOY, outline=(10, 11, 13), width=2)
    glow(d, 28, 16, 3, SG_EMBER)
    reg("SG-U07", "SG-U07_walker"); save(im, "SG-U07_walker")

    im, d = canvas(60); tracked(d, 30, 31, 30, 24, SG_ALLOY, SG_VIOLET, barrel=14, barrel_w=6, turret=(22, 18))
    for sx in (20, 30, 40):
        d.polygon([(sx, 14), (sx - 4, 22), (sx, 30), (sx + 4, 22)], fill=shade(SG_BONE, 0.8))
    glow(d, 30, 26, 3, SG_EMBER)
    reg("SG-U08", "SG-U08_shard"); save(im, "SG-U08_shard")

    im, d = canvas(44); quad(d, 22, 23, SG_ALLOY, SG_EMBER, r=12)
    d.ellipse([16, 17, 28, 29], fill=SG_OIL, outline=(10, 11, 13), width=2)
    for sx in (19, 25):
        d.ellipse([sx, 19, sx + 3, 22], fill=SG_VIOLET)
    reg("SG-U09", "SG-U09_spore"); save(im, "SG-U09_spore")

    im, d = canvas(52)
    shadow(d, 26, 27, 28, 24, 2)
    d.ellipse([11, 13, 41, 42], fill=SG_OIL, outline=(10, 11, 13), width=2)
    d.ellipse([18, 20, 34, 36], fill=SG_ALLOY, outline=(10, 11, 13), width=1)
    for sx in (21, 26, 31):
        d.ellipse([sx, 24, sx + 4, 31], fill=SG_BONE)
    glow(d, 26, 28, 3, SG_EMBER)
    reg("SG-U10", "SG-U10_seeder"); save(im, "SG-U10_seeder")

    im, d = canvas(60)
    shadow(d, 30, 31, 32, 26, 2)
    legs(d, 30, 31, 26, 4, SG_ALLOY_L, spread=2)
    outline_rect(d, [16, 18, 44, 40], 7, SG_OIL, (10, 11, 13), 2)
    d.polygon([(30, 2), (24, 18), (36, 18)], fill=shade(SG_ALLOY_L, 1.15))
    d.rounded_rectangle([27, 0, 33, 8], radius=2, fill=SG_EMBER)
    reg("SG-U11", "SG-U11_reclaimer"); save(im, "SG-U11_reclaimer")

    im, d = canvas(64); tracked(d, 32, 33, 32, 26, SG_ALLOY, SG_VIOLET, barrel=0, turret=(24, 20))
    for sx in (20, 32, 44):
        d.ellipse([sx - 4, 30, sx + 4, 40], fill=SG_OIL, outline=(10, 11, 13), width=1)
        glow(d, sx, 35, 2, SG_EMBER)
    d.rounded_rectangle([26, 8, 38, 16], radius=3, fill=shade(SG_ALLOY_L, 1.1))
    reg("SG-U12", "SG-U12_swarmhost"); save(im, "SG-U12_swarmhost")

    im, d = canvas(80)
    shadow(d, 40, 42, 44, 40, 4)
    for i in range(6):
        side = -1 if i % 2 == 0 else 1
        y = 22 + (i // 2) * 13
        d.line([40, y, 40 + side * 24, y + 9], fill=shade(SG_ALLOY_L, 1.2), width=4)
        d.ellipse([40 + side * 24 - 3, y + 6, 40 + side * 24 + 3, y + 13], fill=(18, 19, 22))
    outline_rect(d, [22, 20, 58, 58], 10, SG_OIL, (10, 11, 13), 3)
    d.ellipse([32, 30, 48, 46], fill=SG_ALLOY, outline=(10, 11, 13), width=2)
    glow(d, 40, 38, 6, SG_EMBER)
    d.polygon([(40, 4), (32, 20), (48, 20)], fill=shade(SG_ALLOY_L, 1.15))
    glow(d, 40, 16, 3, SG_VIOLET)
    reg("SG-U13", "SG-U13_leviathan"); save(im, "SG-U13_leviathan")

    im, d = canvas(44); humanoid_bot(d, 22, 23, SG_ALLOY, SG_VIOLET, s=1.15)
    d.polygon([(14, 15), (9, 7), (15, 11)], fill=shade(SG_OIL, 1.2))
    d.polygon([(30, 15), (35, 7), (29, 11)], fill=shade(SG_OIL, 1.2))
    glow(d, 22, 17, 2, SG_EMBER)
    reg("SG-U14", "SG-U14_echo"); save(im, "SG-U14_echo")


# ------------------------------------------------------------------ FC gaps
def gen_fc_gap():
    for did, deck, mul in (("FC-U04", "soldier", (0.78, 0.82, 0.66)),
                           ("FC-U14", "hitman", (1.12, 1.02, 0.78))):
        stem = tint_deck(deck, did + "_fcInf", mul)
        if stem:
            reg(did, stem)

    im, d = canvas(60); tracked(d, 30, 31, 30, 24, FC_OLIVE, FC_IR, barrel=0, turret=(20, 16))
    d.rounded_rectangle([16, 12, 44, 26], radius=3, fill=FC_BLACK, outline=shade(FC_STEEL, 0.7), width=2)
    for ry in (15, 19, 23):
        d.line([18, ry, 42, ry], fill=FC_IR, width=1)
    reg("FC-U10", "FC-U10_mlrs"); save(im, "FC-U10_mlrs")

    im, d = canvas(64); heli(d, 32, 32, FC_OLIVE, FC_TAN, w=24, h=34)
    d.rounded_rectangle([24, 12, 40, 20], radius=3, fill=shade(FC_OLIVE, 1.25))
    reg("FC-U11", "FC-U11_blackhawk"); save(im, "FC-U11_blackhawk")

    im, d = canvas(60); heli(d, 30, 30, FC_OLIVE, FC_BLACK, w=18, h=30, guns=True)
    d.rounded_rectangle([26, 16, 34, 26], radius=2, fill=FC_BLACK)
    reg("FC-U12", "FC-U12_apache"); save(im, "FC-U12_apache")

    im, d = canvas(60); jet(d, 30, 30, FC_OLIVE, FC_IR)
    reg("FC-U13", "FC-U13_fighter"); save(im, "FC-U13_fighter")


def main():
    G.main()                      # regenerate VC/FC/structures + base manifest
    gen_ts()
    gen_sg()
    gen_fc_gap()

    mpath = os.path.join(OUT, "manifest.json")
    manifest = json.load(open(mpath))
    for k, v in M2.items():
        manifest[k] = v + ".png"
    json.dump(manifest, open(mpath, "w"), indent=2)

    print("faction sprites written:", len(M2))
    print("manifest entries:", len(manifest))
    print("total png files:", len([x for x in os.listdir(OUT) if x.endswith(".png")]))


if __name__ == "__main__":
    main()
