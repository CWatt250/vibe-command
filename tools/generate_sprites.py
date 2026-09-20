#!/usr/bin/env python3
"""Generate the Vibe Command sprite set (v3 — Vibe Coder "Garage" build language).

Vibe Coder units are field-built from OSB, plywood, corrugated cardboard, duct
tape, zip ties and consumer battery cells (source: user-supplied roster sheet
"Vibe Coder - The Garage", VC-U01..VC-U14). Federal Command stays clean
mil-spec. Buildings are drawn top-down with drop shadows and dark outlines.

All output CC0. Facing convention: sprites point UP (facing -Y) == rotation 0.
"""
import os, json, random
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "..", "assets", "sprites")
KC = os.path.join("/tmp", "ktds", "PNG")
os.makedirs(OUT, exist_ok=True)

# ---- faction accents -------------------------------------------------------
VC = (0, 190, 255)          # Vibe Coder cyan (LEDs, screens, faction tint)
FC = (232, 178, 26)         # Federal Command gold
NEUTRAL = (150, 150, 155)
DARK = (18, 20, 26)
TREAD = (34, 36, 40)
SHDW = (0, 0, 0, 70)

# ---- garage materials ------------------------------------------------------
OSB = (176, 138, 82)        # oriented strand board
OSB_D = (124, 92, 54)
OSB_L = (206, 172, 116)
PLY = (214, 180, 122)       # plywood
PLY_D = (156, 124, 76)
CARD = (169, 116, 63)       # corrugated cardboard
CARD_D = (122, 80, 42)
TAPE = (158, 164, 172)      # duct tape
TAPE_D = (100, 106, 114)
TIE = (26, 28, 32)          # zip ties
BAT_B = (47, 111, 208)      # consumer battery cells
BAT_R = (192, 57, 43)
METAL = (86, 92, 100)
METAL_D = (54, 58, 64)
GLASS = (58, 78, 96)


def shade(c, f):
    return (max(0, min(255, int(c[0] * f))),
            max(0, min(255, int(c[1] * f))),
            max(0, min(255, int(c[2] * f))))


def canvas(size):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def shadow(d, cx, cy, w, h, off=3):
    d.rounded_rectangle([cx - w / 2 + off, cy - h / 2 + off + 2,
                         cx + w / 2 + off, cy + h / 2 + off - 2], radius=8, fill=SHDW)


def outline_rect(d, box, r, fill, outc, width=2):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outc, width=width)


def wheel(d, cx, cy, r=9):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(36, 38, 44), outline=(16, 16, 20), width=1)
    d.ellipse([cx - r * 0.35, cy - r * 0.35, cx + r * 0.35, cy + r * 0.35], fill=(58, 62, 70))


def save(im, name):
    im.save(os.path.join(OUT, name + ".png"))
    return name + ".png"


# ---- garage surface treatments --------------------------------------------
def osb_panel(d, box, seed=1):
    """OSB: tan board with visible wood strands."""
    d.rounded_rectangle(box, radius=4, fill=OSB, outline=OSB_D, width=2)
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box
    for _ in range(46):
        sx = rnd.uniform(x0 + 2, x1 - 6)
        sy = rnd.uniform(y0 + 2, y1 - 2)
        ln = rnd.uniform(4, 11)
        col = OSB_L if rnd.random() < 0.45 else OSB_D
        d.line([sx, sy, sx + ln, sy + rnd.uniform(-1.5, 1.5)], fill=col, width=1)


def ply_panel(d, box, seed=2):
    """Plywood: pale sheet with grain lines."""
    d.rounded_rectangle(box, radius=4, fill=PLY, outline=PLY_D, width=2)
    x0, y0, x1, y1 = box
    for y in range(int(y0) + 4, int(y1) - 2, 5):
        d.line([x0 + 3, y, x1 - 3, y], fill=PLY_D, width=1)


def card_panel(d, box, vertical=True):
    """Corrugated cardboard: kraft with flute lines."""
    d.rounded_rectangle(box, radius=3, fill=CARD, outline=CARD_D, width=2)
    x0, y0, x1, y1 = box
    if vertical:
        for x in range(int(x0) + 4, int(x1) - 2, 4):
            d.line([x, y0 + 2, x, y1 - 2], fill=CARD_D, width=1)
    else:
        for y in range(int(y0) + 4, int(y1) - 2, 4):
            d.line([x0 + 2, y, x1 - 2, y], fill=CARD_D, width=1)


def tape(d, x0, y0, x1, y1, w=4):
    """Duct tape strip."""
    d.line([x0, y0, x1, y1], fill=TAPE, width=w)
    d.line([x0, y0, x1, y1], fill=TAPE_D, width=1)


def ziptie(d, x0, y0, x1, y1):
    d.line([x0, y0, x1, y1], fill=TIE, width=2)


def cell(d, x, y, w, h, col):
    """Consumer battery cell with terminal nub."""
    d.rounded_rectangle([x, y, x + w, y + h], radius=2, fill=col, outline=shade(col, 0.55), width=1)
    d.rectangle([x + w * 0.35, y - 2, x + w * 0.65, y], fill=(200, 204, 210))


def led(d, x, y, r=2):
    d.ellipse([x - r, y - r, x + r, y + r], fill=VC)
    d.ellipse([x - r / 2, y - r / 2, x + r / 2, y + r / 2], fill=(220, 250, 255))


def antenna(d, x, y0, y1):
    d.line([x, y0, x, y1], fill=METAL_D, width=2)
    d.ellipse([x - 2, y1 - 2, x + 2, y1 + 2], fill=VC)


def camera(d, x, y):
    d.rounded_rectangle([x - 5, y - 4, x + 5, y + 4], radius=2, fill=METAL_D, outline=(14, 14, 18), width=1)
    d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(12, 14, 18))
    d.ellipse([x - 1, y - 1, x + 1, y + 1], fill=(90, 200, 230))


def rotor(d, cx, cy, r=5):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(52, 56, 62, 150), outline=METAL_D, width=1)
    d.line([cx - r, cy, cx + r, cy], fill=(40, 44, 50), width=1)
    d.line([cx, cy - r, cx, cy + r], fill=(40, 44, 50), width=1)


def tracks(d, cx, cy, w, h):
    for x0 in (cx - w / 2 - 4, cx + w / 2 - 4):
        d.rounded_rectangle([x0, cy - h / 2 + 2, x0 + 8, cy + h / 2 - 2],
                            radius=3, fill=TREAD, outline=(12, 12, 14), width=1)
        for ty in range(int(cy - h / 2) + 6, int(cy + h / 2) - 4, 7):
            d.line([x0 + 1, ty, x0 + 7, ty], fill=(56, 58, 64), width=1)


def barrel(d, cx, top_y, length, w=5):
    d.rounded_rectangle([cx - w / 2, top_y - length, cx + w / 2, top_y + 4],
                        radius=2, fill=(52, 54, 58), outline=(10, 10, 12), width=1)
    d.rounded_rectangle([cx - w / 2 - 1, top_y - length - 3, cx + w / 2 + 1, top_y - length + 3],
                        radius=2, fill=(40, 42, 46))


# ===========================================================================
# VIBE CODER — "The Garage" roster (VC-U01 .. VC-U14)
# ===========================================================================
def vc_u02_scout_quad():
    """Scout Quad — plywood deck, 4 knobby wheels, camera, whip antenna."""
    im, d = canvas(44)
    shadow(d, 22, 23, 26, 22)
    for wx, wy in ((14, 15), (30, 15), (14, 29), (30, 29)):
        wheel(d, wx, wy, 8)
    ply_panel(d, [12, 12, 32, 32], seed=11)
    d.rectangle([18, 17, 26, 25], fill=METAL_D)          # seat pad
    tape(d, 12, 13, 32, 13)                              # tape over the deck
    tape(d, 12, 31, 32, 31)
    camera(d, 22, 13)
    antenna(d, 30, 12, 6)
    led(d, 15, 27)
    return save(im, "VC-U02_scout")


def vc_u03_fpv_drone():
    """FPV Strike Drone — cardboard X-frame, taped battery, nose camera."""
    im, d = canvas(40)
    shadow(d, 20, 20, 26, 26, 1)
    d.line([8, 20, 32, 20], fill=CARD_D, width=4)
    d.line([20, 8, 20, 32], fill=CARD_D, width=4)
    d.line([8, 20, 32, 20], fill=CARD, width=2)
    d.line([20, 8, 20, 32], fill=CARD, width=2)
    for rx, ry in ((9, 9), (31, 9), (9, 31), (31, 31)):
        rotor(d, rx, ry, 5)
    card_panel(d, [15, 15, 25, 25], vertical=False)
    cell(d, 16, 21, 8, 3, BAT_B)
    tape(d, 14, 18, 26, 18)
    camera(d, 20, 13)
    ziptie(d, 15, 25, 25, 25)
    return save(im, "VC-U03_drone")


def vc_u04_technical():
    """Technical — pickup truck, plywood bed, bolt-on MG on a taped mount."""
    im, d = canvas(50)
    shadow(d, 25, 26, 26, 20)
    outline_rect(d, [11, 24, 39, 35], 5, (52, 60, 70), shade(VC, 0.4), 2)
    ply_panel(d, [11, 13, 39, 24], seed=4)
    for wx, wy in ((14, 26), (36, 26), (14, 33), (36, 33)):
        wheel(d, wx, wy, 7)
    d.rectangle([12, 25, 38, 27], fill=METAL_D)          # bed rail
    tape(d, 20, 13, 30, 13)
    d.rounded_rectangle([22, 8, 28, 14], radius=2, fill=METAL_D)
    barrel(d, 25, 9, 13, 4)
    cell(d, 14, 20, 9, 3, BAT_R)
    led(d, 36, 21)
    return save(im, "VC-U04_technical")


def vc_u05_bot_dog():
    """Bot Dog — OSB body on four servo legs, camera head."""
    im, d = canvas(40)
    shadow(d, 20, 21, 20, 18, 2)
    osb_panel(d, [11, 11, 29, 27], seed=7)
    for lx in (12, 17, 23, 28):
        d.line([lx, 26, lx - 1, 34], fill=METAL_D, width=3)
        d.line([lx - 2, 34, lx + 2, 34], fill=TIE, width=2)
    d.rounded_rectangle([12, 27, 28, 32], radius=3, fill=METAL_D)   # tail actuator
    camera(d, 24, 10)
    tape(d, 13, 15, 27, 15)
    cell(d, 14, 20, 8, 3, BAT_B)
    return save(im, "VC-U05_botdog")


def vc_u06_sentry_bot():
    """Sentry Bot — taped dome on a plywood base, camera, warning LED."""
    im, d = canvas(40)
    shadow(d, 20, 21, 22, 22, 2)
    ply_panel(d, [11, 25, 29, 33], seed=9)
    d.ellipse([9, 10, 31, 32], fill=OSB, outline=OSB_D, width=2)
    for a in range(0, 360, 45):
        import math
        r = 10
        cx, cy = 20, 21
        x = cx + r * math.cos(math.radians(a))
        y = cy + r * math.sin(math.radians(a))
        d.line([cx, cy, x, y], fill=OSB_D, width=1)
    camera(d, 20, 12)
    tape(d, 10, 24, 30, 24)
    led(d, 27, 17)
    return save(im, "VC-U06_sentry")


def vc_u07_hack_van():
    """Hack Van — boxy van, plywood side panels, rooftop dish, screens."""
    im, d = canvas(50)
    shadow(d, 25, 26, 26, 20)
    outline_rect(d, [11, 22, 39, 34], 5, (30, 34, 42), shade(VC, 0.45), 2)
    ply_panel(d, [11, 11, 39, 22], seed=13)
    for wx, wy in ((14, 24), (36, 24), (14, 32), (36, 32)):
        wheel(d, wx, wy, 7)
    d.rectangle([13, 13, 37, 20], fill=GLASS)
    d.ellipse([20, 6, 30, 16], fill=METAL, outline=METAL_D, width=2)   # dish
    d.ellipse([23, 9, 27, 13], fill=METAL_D)
    antenna(d, 35, 12, 5)
    cell(d, 15, 21, 10, 3, BAT_B)
    tape(d, 12, 12, 38, 12)
    led(d, 37, 23)
    return save(im, "VC-U07_hackvan")


def vc_u08_crawler():
    """Crawler — tracked heavy hauler, OSB hull, plywood plow, battery bank."""
    im, d = canvas(56)
    shadow(d, 28, 29, 32, 26)
    tracks(d, 28, 29, 30, 24)
    osb_panel(d, [14, 15, 42, 43], seed=17)
    ply_panel(d, [17, 9, 39, 16], seed=19)               # front plow
    tape(d, 15, 22, 41, 22)
    ziptie(d, 15, 36, 41, 36)
    for i, c in enumerate((BAT_B, BAT_R, BAT_B)):
        cell(d, 19 + i * 8, 27, 7, 3, c)
    antenna(d, 38, 15, 8)
    led(d, 17, 20)
    return save(im, "VC-U08_crawler")


def vc_u09_swarm_carrier():
    """Swarm Carrier — flatbed with four stacked drone pods and launch rails."""
    im, d = canvas(60)
    shadow(d, 30, 31, 36, 28)
    tracks(d, 30, 31, 34, 26)
    ply_panel(d, [14, 14, 46, 48], seed=23)
    for i in range(4):
        x = 18 + (i % 2) * 14
        y = 20 + (i // 2) * 13
        card_panel(d, [x, y, x + 12, y + 11], vertical=True)
        d.ellipse([x + 4, y + 4, x + 8, y + 8], fill=METAL_D)
    d.rectangle([17, 15, 43, 17], fill=METAL_D)          # launch rail
    tape(d, 15, 33, 45, 33)
    cell(d, 20, 43, 9, 3, BAT_B)
    led(d, 43, 19)
    return save(im, "VC-U09_swarmcarrier")


def vc_u10_atlas_bot():
    """Atlas Bot — heavy biped, OSB torso, plywood shoulder plates."""
    im, d = canvas(54)
    shadow(d, 27, 28, 30, 34, 2)
    osb_panel(d, [15, 15, 39, 43], seed=29)
    ply_panel(d, [10, 17, 16, 31], seed=31)              # left shoulder
    ply_panel(d, [38, 17, 44, 31], seed=33)              # right shoulder
    d.rounded_rectangle([21, 5, 33, 17], radius=4, fill=METAL, outline=METAL_D, width=2)
    camera(d, 27, 11)
    for sx in (16, 32):
        d.rounded_rectangle([sx, 43, sx + 6, 52], radius=2, fill=METAL_D)
    tape(d, 16, 24, 38, 24)
    ziptie(d, 16, 36, 38, 36)
    cell(d, 19, 30, 8, 3, BAT_R)
    led(d, 34, 30)
    return save(im, "VC-U10_atlas")


def vc_u11_hunter_drone():
    """Hunter Drone — long fixed-wing loiterer, cardboard fuselage, taped seams."""
    im, d = canvas(48)
    shadow(d, 24, 25, 34, 30, 1)
    card_panel(d, [21, 8, 27, 40], vertical=False)       # fuselage
    d.polygon([(24, 12), (6, 30), (24, 26)], fill=CARD, outline=CARD_D)   # left wing
    d.polygon([(24, 12), (42, 30), (24, 26)], fill=CARD, outline=CARD_D)  # right wing
    d.polygon([(21, 36), (27, 36), (27, 43), (21, 43)], fill=CARD, outline=CARD_D)  # tail
    tape(d, 8, 29, 40, 29, 3)
    rotor(d, 24, 41, 4)                                   # pusher prop
    camera(d, 24, 11)
    cell(d, 22, 20, 4, 8, BAT_B)
    led(d, 24, 34)
    return save(im, "VC-U11_hunterdrone")


def vc_u12_ai_battle_tank():
    """AI Battle Tank — tracked, plywood turret, taped-on cannon, sensor mast."""
    im, d = canvas(60)
    shadow(d, 30, 31, 34, 28)
    tracks(d, 30, 31, 32, 26)
    osb_panel(d, [15, 16, 45, 46], seed=37)
    ply_panel(d, [20, 20, 40, 40], seed=41)              # turret
    d.ellipse([26, 26, 34, 34], fill=METAL_D)            # hatch
    barrel(d, 30, 22, 18, 6)
    tape(d, 21, 30, 39, 30)
    ziptie(d, 21, 36, 39, 36)
    for i, c in enumerate((BAT_B, BAT_R)):
        cell(d, 18 + i * 9, 41, 8, 3, c)
    antenna(d, 41, 18, 8)
    led(d, 19, 24)
    return save(im, "VC-U12_battletank")


def vc_u13_drone_mothership():
    """Drone Mothership — heavy-lift hexacopter, cardboard hull, battery banks."""
    im, d = canvas(64)
    shadow(d, 32, 33, 42, 42, 2)
    for a in range(0, 360, 60):
        import math
        cx, cy, r = 32, 33, 24
        x = cx + r * math.cos(math.radians(a))
        y = cy + r * math.sin(math.radians(a))
        d.line([cx, cy, x, y], fill=CARD_D, width=5)
        d.line([cx, cy, x, y], fill=CARD, width=3)
        rotor(d, x, y, 6)
    card_panel(d, [19, 20, 45, 46], vertical=False)
    for i, c in enumerate((BAT_B, BAT_B, BAT_R)):
        cell(d, 22 + i * 8, 38, 7, 4, c)
    tape(d, 20, 25, 44, 25)
    ziptie(d, 20, 31, 44, 31)
    camera(d, 32, 17)
    led(d, 41, 24)
    return save(im, "VC-U13_mothership")


def vc_u14_titan_rig():
    """Titan Rig — massive tracked siege rig, OSB frame, scaffold crane."""
    im, d = canvas(76)
    shadow(d, 38, 39, 48, 40, 3)
    tracks(d, 38, 39, 46, 38)
    osb_panel(d, [16, 16, 60, 62], seed=43)
    ply_panel(d, [22, 22, 54, 44], seed=47)              # upper deck
    # scaffold crane
    d.line([50, 26, 50, 6], fill=METAL_D, width=3)
    d.line([50, 8, 26, 8], fill=METAL_D, width=3)
    ziptie(d, 46, 12, 54, 12)
    d.rounded_rectangle([22, 4, 30, 12], radius=2, fill=METAL)
    barrel(d, 30, 24, 16, 6)
    for i, c in enumerate((BAT_B, BAT_R, BAT_B)):
        cell(d, 22 + i * 10, 56, 9, 4, c)
    tape(d, 17, 50, 59, 50)
    led(d, 19, 30)
    led(d, 57, 30)
    return save(im, "VC-U14_titanrig")


def gen_vc_garage():
    return [vc_u02_scout_quad(), vc_u03_fpv_drone(), vc_u04_technical(),
            vc_u05_bot_dog(), vc_u06_sentry_bot(), vc_u07_hack_van(),
            vc_u08_crawler(), vc_u09_swarm_carrier(), vc_u10_atlas_bot(),
            vc_u11_hunter_drone(), vc_u12_ai_battle_tank(),
            vc_u13_drone_mothership(), vc_u14_titan_rig()]


# ===========================================================================
# FEDERAL COMMAND — clean mil-spec (unchanged)
# ===========================================================================
def tracked(d, cx, cy, w, h, camo, accent, barrel=0, barrel_w=5, turret=None):
    shadow(d, cx, cy, w + 8, h + 8)
    for x0 in (cx - w / 2 - 4, cx + w / 2):
        d.rounded_rectangle([x0, cy - h / 2 + 2, x0 + 8, cy + h / 2 - 2],
                            radius=3, fill=TREAD, outline=(12, 12, 14), width=1)
    outline_rect(d, [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], 7, camo, shade(camo, 0.45), 2)
    outline_rect(d, [cx - w / 2 + 4, cy - h / 2 + 3, cx + w / 2 - 4, cy - h / 2 + 10],
                 3, shade(camo, 1.25), shade(camo, 0.5), 1)
    if turret:
        tw, th = turret
        outline_rect(d, [cx - tw / 2, cy - th / 2 - 3, cx + tw / 2, cy + th / 2 - 3],
                     5, shade(camo, 0.85), shade(camo, 0.4), 2)
        d.rounded_rectangle([cx - 4, cy - 5, cx + 4, cy + 3], radius=2, fill=shade(camo, 1.15))
    if barrel:
        top_y = cy - h / 2.0
        d.rounded_rectangle([cx - barrel_w / 2, top_y - barrel, cx + barrel_w / 2, top_y + 4],
                            radius=2, fill=(52, 54, 58), outline=(10, 10, 12), width=1)
        d.rounded_rectangle([cx - barrel_w / 2 - 1, top_y - barrel - 3, cx + barrel_w / 2 + 1, top_y - barrel + 3],
                            radius=2, fill=(40, 42, 46))


def wheeled(d, cx, cy, w, h, camo, accent, barrel=0, barrel_w=4):
    shadow(d, cx, cy, w + 6, h + 6)
    outline_rect(d, [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], 6, camo, shade(camo, 0.45), 2)
    outline_rect(d, [cx - w / 2 + 3, cy - h / 2 + 2, cx + w / 2 - 3, cy - h / 2 + 9],
                 3, shade(camo, 1.25), shade(camo, 0.5), 1)
    for wx, wy in ((cx - w / 2 + 5, cy - h / 2 + 4), (cx + w / 2 - 5, cy - h / 2 + 4),
                   (cx - w / 2 + 5, cy + h / 2 - 4), (cx + w / 2 - 5, cy + h / 2 - 4)):
        wheel(d, wx, wy)


def gen_vehicles():
    im, d = canvas(60); tracked(d, 30, 31, 30, 24, (70, 76, 60), FC, barrel=16, barrel_w=6, turret=(24, 20)); save(im, "FC-U07_mbt")
    im, d = canvas(56); tracked(d, 28, 29, 27, 22, (78, 84, 68), FC, barrel=12, turret=(20, 16)); save(im, "FC-U06_ifv")
    im, d = canvas(48); wheeled(d, 24, 25, 22, 18, (90, 96, 80), FC); outline_rect(d, [15, 11, 33, 20], 4, shade((90, 96, 80), 0.75), shade(FC, 0.5), 1); save(im, "FC-U05_humvee")
    im, d = canvas(52); tracked(d, 26, 27, 24, 20, (74, 80, 66), FC, barrel=0, turret=(16, 14)); d.rounded_rectangle([21, 5, 27, 14], radius=2, fill=(28, 28, 32)); d.rounded_rectangle([25, 5, 31, 14], radius=2, fill=(28, 28, 32)); save(im, "FC-U08_aa")
    im, d = canvas(56); tracked(d, 28, 29, 26, 20, (66, 72, 56), FC, barrel=18, barrel_w=7, turret=(18, 16)); save(im, "FC-U09_arty")


def gen_human_characters():
    cdir = os.path.join(OUT, "characters")
    os.makedirs(cdir, exist_ok=True)
    decks = {
        "soldier": "Soldier 1/soldier1_gun.png", "survivor": "Survivor 1/survivor1_gun.png",
        "hitman": "Hitman 1/hitman1_gun.png", "manblue": "Man Blue/manBlue_gun.png",
        "manbrown": "Man Brown/manBrown_gun.png", "manold": "Man Old/manOld_gun.png",
    }
    for key, rel in decks.items():
        src = os.path.join(KC, rel)
        if os.path.exists(src):
            Image.open(src).convert("RGBA").save(os.path.join(cdir, key + ".png"))
    return list(decks.keys())


def gen_structures():
    def base(w, h, camo, accent, roof_bias=0.9):
        im, d = canvas(76)
        cx, cy = 38, 40
        shadow(d, cx, cy, w + 6, h + 6, 3)
        outline_rect(d, [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], 9, shade(camo, 0.55), shade(camo, 0.85), 3)
        outline_rect(d, [cx - w / 2 + 9, cy - h / 2 + 7, cx + w / 2 - 9, cy + h / 2 - 9], 6, shade(camo, roof_bias), shade(camo, 0.55), 2)
        return im, d, cx, cy, camo, accent

    def vent(d, x, y, accent):
        d.rounded_rectangle([x, y, x + 6, y + 6], radius=2, fill=shade(accent, 0.7))

    def garage(w, h, seed=1):
        """Vibe Coder building shell: OSB walls + plywood roof + duct-tape seams."""
        im, d = canvas(76)
        cx, cy = 38, 40
        shadow(d, cx, cy, w + 6, h + 6, 3)
        osb_panel(d, [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], seed=seed)
        ply_panel(d, [cx - w / 2 + 9, cy - h / 2 + 7, cx + w / 2 - 9, cy + h / 2 - 9], seed=seed + 1)
        tape(d, cx - w / 2 + 6, cy - h / 2 + 7, cx + w / 2 - 6, cy - h / 2 + 7, 4)
        tape(d, cx - w / 2 + 6, cy + h / 2 - 7, cx + w / 2 - 6, cy + h / 2 - 7, 4)
        return im, d, cx, cy

    # ---- Vibe Coder buildings (garage style) ----
    im, d, cx, cy = garage(46, 42, 51); d.rectangle([cx - 7, cy - 7, cx + 7, cy + 7], fill=(16, 18, 24)); d.polygon([(cx - 8, cy - 8), (cx + 8, cy - 8), (cx, cy - 20)], fill=VC); led(d, cx, cy); save(im, "VC-B01_hq")
    im, d, cx, cy = garage(48, 40, 53); d.line([cx - 16, cy - 4, cx + 16, cy - 4], fill=OSB_D, width=2); d.line([cx - 16, cy + 4, cx + 16, cy + 4], fill=OSB_D, width=2); vent(d, cx - 4, cy + 2, VC); save(im, "VC-B02_fab")
    im, d, cx, cy = garage(48, 40, 55); d.line([cx - 15, cy - 3, cx + 15, cy - 3], fill=OSB_D, width=2); d.line([cx - 15, cy + 6, cx + 15, cy + 6], fill=OSB_D, width=2); vent(d, cx - 3, cy, VC); save(im, "VC-B07_maker")
    im, d, cx, cy = garage(48, 40, 57); d.line([cx - 16, cy - 2, cx + 16, cy - 2], fill=OSB_D, width=2)
    for ex in (cx - 8, cx + 2):
        d.ellipse([ex, cy + 6, ex + 6, cy + 12], fill=(22, 24, 30))
    save(im, "VC-B08_robotshop")
    im, d, cx, cy = garage(38, 36, 59); d.ellipse([cx - 11, cy - 11, cx + 11, cy + 11], fill=(64, 68, 76), outline=(14, 16, 20), width=2); d.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], fill=(14, 16, 20)); save(im, "VC-B03_gen")
    im, d, cx, cy = garage(42, 38, 61); d.rectangle([cx - 11, cy - 11, cx + 11, cy + 11], fill=(12, 14, 20))
    for ly in (-6, 0, 6):
        d.line([cx - 9, cy + ly, cx + 9, cy + ly], fill=VC, width=2)
    save(im, "VC-B05_servers")
    im, d, cx, cy = garage(42, 38, 63); d.rounded_rectangle([cx - 13, cy - 11, cx + 13, cy + 11], radius=6, fill=(28, 78, 96), outline=shade(VC, 0.6), width=2); save(im, "VC-B06_cluster")
    im, d, cx, cy = garage(36, 34, 65); d.line([cx - 14, cy + 12, cx + 14, cy + 12], fill=(150, 190, 210), width=3); d.line([cx - 14, cy + 8, cx + 14, cy + 8], fill=(110, 150, 170), width=2); save(im, "VC-B04_cooling")
    im, d, cx, cy = garage(40, 36, 67); d.rounded_rectangle([cx - 16, cy - 6, cx + 16, cy + 8], radius=4, fill=(40, 44, 50), outline=shade(VC, 0.6), width=2); d.rounded_rectangle([cx - 16, cy - 12, cx + 16, cy - 6], radius=4, fill=(60, 64, 70)); save(im, "VC-B11_repair")
    im, d = canvas(64); shadow(d, 32, 33, 26, 22, 2); osb_panel(d, [20, 34, 44, 50], seed=69); outline_rect(d, [27, 16, 37, 36], 2, (14, 16, 22), VC, 1); d.rounded_rectangle([16, 10, 48, 16], radius=3, fill=METAL_D); save(im, "VC-D02_turret")

    # ---- Federal Command buildings ----
    im, d, cx, cy, c, a = base(46, 42, FC, FC, 0.9); d.rectangle([cx - 7, cy - 7, cx + 7, cy + 7], fill=(16, 18, 24)); d.polygon([(cx - 8, cy - 8), (cx + 8, cy - 8), (cx, cy - 20)], fill=shade(FC, 0.65)); save(im, "FC-B01_hq")
    im, d, cx, cy, c, a = base(48, 40, FC, FC, 0.75); d.line([cx - 15, cy - 3, cx + 15, cy - 3], fill=shade(FC, 0.45), width=2); d.line([cx - 15, cy + 6, cx + 15, cy + 6], fill=shade(FC, 0.45), width=2); vent(d, cx - 3, cy, FC); save(im, "FC-B04_barracks")
    im, d, cx, cy, c, a = base(48, 40, FC, FC, 0.7); d.line([cx - 16, cy - 2, cx + 16, cy - 2], fill=shade(FC, 0.4), width=2)
    for ex in (cx - 8, cx + 2):
        d.ellipse([ex, cy + 6, ex + 6, cy + 12], fill=(22, 24, 30))
    save(im, "FC-B05_motorpool")
    im, d, cx, cy, c, a = base(38, 36, FC, FC, 0.6); d.ellipse([cx - 11, cy - 11, cx + 11, cy + 11], fill=(64, 68, 76), outline=(14, 16, 20), width=2); d.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], fill=(14, 16, 20)); save(im, "FC-B03_gen")
    im, d, cx, cy, c, a = base(42, 38, FC, FC, 0.75); d.rounded_rectangle([cx - 12, cy - 11, cx + 12, cy + 11], radius=5, fill=shade(FC, 0.5), outline=shade(FC, 0.85), width=2); d.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], fill=(18, 20, 26)); save(im, "FC-B09_command")
    im, d, cx, cy, c, a = base(40, 36, FC, FC, 0.7); d.rounded_rectangle([cx - 16, cy - 6, cx + 16, cy + 8], radius=4, fill=(40, 44, 50), outline=shade(FC, 0.6), width=2); d.rounded_rectangle([cx - 16, cy - 12, cx + 16, cy - 6], radius=4, fill=(60, 64, 70)); save(im, "FC-B11_repair")
    im, d = canvas(64); shadow(d, 32, 33, 52, 16, 2); outline_rect(d, [6, 22, 58, 42], 5, shade(FC, 0.45), shade(FC, 0.75), 2); d.line([6, 30, 58, 30], fill=shade(FC, 0.4), width=2); d.line([6, 38, 58, 38], fill=shade(FC, 0.35), width=2); save(im, "FC-D01_wall")
    im, d = canvas(64); shadow(d, 32, 32, 16, 50, 2); outline_rect(d, [24, 6, 40, 58], 5, shade(FC, 0.5), shade(FC, 0.8), 2); outline_rect(d, [28, 14, 36, 26], 2, (16, 18, 24), shade(FC, 0.6), 1); d.rounded_rectangle([26, 30, 38, 34], radius=2, fill=shade(FC, 0.7)); save(im, "FC-D02_guard")


def gen_support():
    im, d = canvas(52); shadow(d, 26, 27, 28, 22, 2); tracked(d, 26, 27, 28, 20, (96, 104, 84), NEUTRAL, barrel=0, turret=(20, 18)); d.rounded_rectangle([32, 12, 42, 22], radius=3, fill=(120, 128, 108), outline=shade(NEUTRAL, 0.5), width=2); save(im, "SRV_harvester")
    im, d = canvas(52); shadow(d, 26, 27, 28, 22, 2); tracks(d, 26, 27, 26, 20); osb_panel(d, [13, 14, 39, 40], seed=71); d.rounded_rectangle([30, 10, 40, 20], radius=3, fill=METAL, outline=METAL_D, width=2); cell(d, 17, 33, 9, 4, BAT_B); tape(d, 14, 24, 38, 24); save(im, "VC-SRV_harvester")
    im, d = canvas(52); shadow(d, 26, 27, 28, 22, 2); tracked(d, 26, 27, 28, 20, (96, 104, 84), FC, barrel=0, turret=(20, 18)); d.rounded_rectangle([32, 12, 42, 22], radius=3, fill=(120, 128, 108), outline=shade(FC, 0.5), width=2); save(im, "FC-SRV_harvester")


def main():
    gen_vehicles()
    gen_vc_garage()
    gen_structures()
    gen_support()
    gen_human_characters()
    write_manifest()


M = {
    # ---- Vibe Coder units: "The Garage" ----
    "VC-U01": "characters/manblue",
    "VC-U02": "VC-U02_scout", "VC-U03": "VC-U03_drone", "VC-U04": "VC-U04_technical",
    "VC-U05": "VC-U05_botdog", "VC-U06": "VC-U06_sentry", "VC-U07": "VC-U07_hackvan",
    "VC-U08": "VC-U08_crawler", "VC-U09": "VC-U09_swarmcarrier", "VC-U10": "VC-U10_atlas",
    "VC-U11": "VC-U11_hunterdrone", "VC-U12": "VC-U12_battletank",
    "VC-U13": "VC-U13_mothership", "VC-U14": "VC-U14_titanrig",
    # ---- Federal Command units ----
    "FC-U01": "characters/soldier", "FC-U02": "characters/hitman", "FC-U03": "characters/survivor",
    "FC-U05": "FC-U05_humvee", "FC-U06": "FC-U06_ifv", "FC-U07": "FC-U07_mbt",
    "FC-U08": "FC-U08_aa", "FC-U09": "FC-U09_arty",
    # ---- Vibe Coder structures ----
    "VC-B01": "VC-B01_hq", "VC-B02": "VC-B02_fab", "VC-B03": "VC-B03_gen",
    "VC-B04": "VC-B04_cooling", "VC-B05": "VC-B05_servers", "VC-B06": "VC-B06_cluster",
    "VC-B07": "VC-B07_maker", "VC-B08": "VC-B08_robotshop", "VC-B11": "VC-B11_repair",
    "VC-D02": "VC-D02_turret",
    # ---- Federal Command structures ----
    "FC-B01": "FC-B01_hq", "FC-B03": "FC-B03_gen", "FC-B04": "FC-B04_barracks",
    "FC-B05": "FC-B05_motorpool", "FC-B09": "FC-B09_command", "FC-B11": "FC-B11_repair",
    "FC-D01": "FC-D01_wall", "FC-D02": "FC-D02_guard",
    # ---- shared support ----
    "SRV": "SRV_harvester", "VC-SRV": "VC-SRV_harvester", "FC-SRV": "FC-SRV_harvester",
}
def write_manifest():
    # Preserve dict entries (AI / pre-rendered sprites with scale/tint options,
    # see tools/ai_sprite_prep.py) so regenerating the flat set doesn't revert them.
    path = os.path.join(OUT, "manifest.json")
    keep = {}
    if os.path.exists(path):
        keep = {k: v for k, v in json.load(open(path)).items() if isinstance(v, dict)}
    out = {k: (v + ".png") for k, v in M.items()}
    out.update(keep)
    with open(path, "w") as f:
        json.dump(out, f, indent=2)
    print("Total sprite files:", len([x for x in os.listdir(OUT) if x.endswith(".png")]))
    print("Manifest entries:", len(M))


if __name__ == "__main__":
    main()
