#!/usr/bin/env python3
"""Generate the Vibe Command sprite set (v2 — detailed, unit-readable).
Vehicles/buildings drawn top-down with drop shadows, dark outlines, layered hulls,
treads, turrets + gun barrels, faction accents. Infantry are Kenney CC0 humanoids.
All output CC0. Facing convention: sprites point UP (facing -Y) == rotation 0.
"""
import os, json
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "..", "assets", "sprites")
KC = os.path.join("/tmp", "ktds", "PNG")
os.makedirs(OUT, exist_ok=True)

VC = (0, 190, 255)
FC = (232, 178, 26)
NEUTRAL = (150, 150, 155)
DARK = (18, 20, 26)
TREAD = (34, 36, 40)
SHDW = (0, 0, 0, 70)

def shade(c, f):
    return (max(0, min(255, int(c[0]*f))), max(0, min(255, int(c[1]*f))), max(0, min(255, int(c[2]*f))))

def canvas(size):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)

def shadow(d, cx, cy, w, h, off=3):
    d.rounded_rectangle([cx-w/2+off, cy-h/2+off+2, cx+w/2+off, cy+h/2+off-2], radius=8, fill=SHDW)

def outline_rect(d, box, r, fill, outc, width=2):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outc, width=width)

# ---- vehicles (face UP). cx,cy are center; w,h are hull extent ----
def legs(d, cx, cy, half, color, n=3):
    for i in range(n):
        yy = cy - 12 + i * 12
        d.rounded_rectangle([cx-half, yy, cx-half+8, yy+8], radius=2, fill=color)
        d.rounded_rectangle([cx+half-8, yy, cx+half, yy+8], radius=2, fill=color)

def wheel(d, cx, cy):
    d.ellipse([cx-9, cy-9, cx+9, cy+9], fill=(36, 38, 44), outline=(16, 16, 20), width=1)

# helper: generic tracked vehicle
def tracked(d, cx, cy, w, h, camo, accent, barrel=0, barrel_w=5, turret=None, wheels=False):
    shadow(d, cx, cy, w+8, h+8)
    # treads
    ll = [cx-w/2-4, cx+w/2]
    for x0 in ll:
        d.rounded_rectangle([x0, cy-h/2+2, x0+8, cy+h/2-2], radius=3, fill=TREAD, outline=(12,12,14), width=1)
    # hull
    outline_rect(d, [cx-w/2, cy-h/2, cx+w/2, cy+h/2], 7, camo, shade(camo, 0.45), 2)
    # hull top highlight
    highlight = shade(camo, 1.25)
    outline_rect(d, [cx-w/2+4, cy-h/2+3, cx+w/2-4, cy-h/2+10], 3, highlight, shade(camo, 0.5), 1)
    if turret:
        tw, th = turret
        tcol = shade(camo, 0.85)
        outline_rect(d, [cx-tw/2, cy-th/2-3, cx+tw/2, cy+th/2-3], 5, tcol, shade(camo, 0.4), 2)
        d.rounded_rectangle([cx-4, cy-5, cx+4, cy+3], radius=2, fill=shade(camo, 1.15))  # hatch
    if barrel:
        # barrel: cylinder sticking out the TOP (facing -Y). hull top = cy-h/2.
        top_y = cy - h / 2.0
        d.rounded_rectangle([cx-barrel_w/2, top_y - barrel, cx+barrel_w/2, top_y + 4], radius=2, fill=(52, 54, 58), outline=(10, 10, 12), width=1)
        # muzzle tip
        d.rounded_rectangle([cx-barrel_w/2 - 1, top_y - barrel - 3, cx+barrel_w/2 + 1, top_y - barrel + 3], radius=2, fill=(40, 42, 46))

def wheeled(d, cx, cy, w, h, camo, accent, barrel=0, barrel_w=4):
    shadow(d, cx, cy, w+6, h+6)
    outline_rect(d, [cx-w/2, cy-h/2, cx+w/2, cy+h/2], 6, camo, shade(camo, 0.45), 2)
    highlight = shade(camo, 1.25)
    outline_rect(d, [cx-w/2+3, cy-h/2+2, cx+w/2-3, cy-h/2+9], 3, highlight, shade(camo, 0.5), 1)
    # wheels
    for wx, wy in [(cx-w/2+5, cy-h/2+4), (cx+w/2-5, cy-h/2+4), (cx-w/2+5, cy+h/2-4), (cx+w/2-5, cy+h/2-4)]:
        wheel(d, wx, wy)

def mount_gun(d, cx, cy, hh, accent, barrel=11):
    d.rounded_rectangle([cx-2, cy-hh, cx+2, cy-hh+9], radius=2, fill=(28,28,32))
    d.rounded_rectangle([cx-3, cy-hh-barrel, cx+3, cy-hh], radius=2, fill=(30,30,34), outline=(12,12,14), width=1)
    d.ellipse([cx-5, cy-hh-6, cx+5, cy-hh+4], fill=accent)

def save(im, name):
    im.save(os.path.join(OUT, name + ".png"))
    return name + ".png"

def gen_vehicles():
    # FC-U07 MBT: tracked + big turret + long barrel
    im, d = canvas(60); tracked(d, 30, 31, 30, 24, (70, 76, 60), FC, barrel=16, barrel_w=6, turret=(24, 20)); save(im, "FC-U07_mbt")
    # FC-U06 IFV: tracked + med turret
    im, d = canvas(56); tracked(d, 28, 29, 27, 22, (78, 84, 68), FC, barrel=12, turret=(20, 16)); save(im, "FC-U06_ifv")
    # FC-U05 Humvee: wheeled
    im, d = canvas(48); wheeled(d, 24, 25, 22, 18, (90, 96, 80), FC); outline_rect(d, [15, 11, 33, 20], 4, shade((90,96,80),0.75), shade(FC,0.5), 1); save(im, "FC-U05_humvee")
    # FC-U08 Mobile AA: tracked + twin stub barrels
    im, d = canvas(52); tracked(d, 26, 27, 24, 20, (74, 80, 66), FC, barrel=0, turret=(16, 14)); d.rounded_rectangle([21, 5, 27, 14], radius=2, fill=(28,28,32)); d.rounded_rectangle([25, 5, 31, 14], radius=2, fill=(28,28,32)); save(im, "FC-U08_aa")
    # FC-U09 SPA: tracked + long howitzer
    im, d = canvas(56); tracked(d, 28, 29, 26, 20, (66, 72, 56), FC, barrel=18, barrel_w=7, turret=(18, 16)); save(im, "FC-U09_arty")

    # VC-U04 Technical: pickup + mounted gun
    im, d = canvas(48); shadow(d, 24, 25, 24, 18); outline_rect(d, [11, 23, 37, 33], 5, (52, 60, 70), shade(VC, 0.4), 2); outline_rect(d, [11, 12, 37, 23], 5, (30, 36, 44), shade(VC, 0.5), 1)
    for wx, wy in [(13, 25), (35, 25), (13, 31), (35, 31)]:
        wheel(d, wx, wy)
    mount_gun(d, 24, 15, 10, VC); save(im, "VC-U04_technical")
    # VC-U02 Scout Quad: 4 wheels + open frame
    im, d = canvas(40); shadow(d, 20, 21, 22, 18)
    for wx, wy in [(13, 15), (27, 15), (13, 27), (27, 27)]:
        wheel(d, wx, wy)
    outline_rect(d, [12, 13, 28, 29], 4, (40, 48, 58), shade(VC, 0.4), 1); d.line([20, 15, 20, 27], fill=VC, width=2); save(im, "VC-U02_scout")
    # VC-U07 Hack Van: boxy black van
    im, d = canvas(48); shadow(d, 24, 25, 24, 18); outline_rect(d, [11, 21, 37, 32], 5, (24, 28, 36), shade(VC, 0.45), 2); outline_rect(d, [11, 11, 37, 21], 4, (34, 40, 50), shade(VC, 0.55), 1)
    for wx, wy in [(13, 23), (35, 23), (13, 31), (35, 31)]:
        wheel(d, wx, wy)
    d.ellipse([21, 14, 27, 20], fill=VC); save(im, "VC-U07_hackvan")
    # VC-U08 Crawler: tracked heavy
    im, d = canvas(52); tracked(d, 26, 27, 28, 22, (44, 52, 62), VC, barrel=0, turret=(20, 18)); save(im, "VC-U08_crawler")

def accent(colour): return colour

def gen_drones_bots():
    # VC-U03 FPV Drone: X-quad
    im, d = canvas(36); shadow(d, 18, 18, 24, 24, 1); d.line([7, 18, 29, 18], fill=(24,26,30), width=3); d.line([18, 7, 18, 29], fill=(24,26,30), width=3)
    for rx, ry in [(9,9),(27,9),(9,27),(27,27)]:
        d.ellipse([rx-4, ry-4, rx+4, ry+4], fill=(46,50,58), outline=(14,14,16), width=1)
    d.rounded_rectangle([15, 15, 21, 21], radius=2, fill=VC, outline=shade(VC,0.4), width=1); save(im, "VC-U03_drone")
    # VC-U05 Bot Dog: quadruped
    im, d = canvas(36); shadow(d, 18, 19, 18, 16, 2); outline_rect(d, [10, 10, 26, 24], 5, (26, 30, 36), shade(VC, 0.5), 2); d.rounded_rectangle([7, 24, 29, 30], radius=4, fill=(20, 22, 28))
    for lx in (11, 16, 21, 26):
        d.line([lx, 24, lx-1, 31], fill=(26,30,36), width=3)
    d.ellipse([24, 9, 31, 16], fill=VC); save(im, "VC-U05_botdog")
    # VC-U06 Sentry Bot
    im, d = canvas(36); shadow(d, 18, 19, 20, 20, 2); d.ellipse([8, 10, 28, 30], fill=(30, 34, 40), outline=shade(VC, 0.5), width=2); d.rounded_rectangle([14, 5, 22, 13], radius=2, fill=VC); d.ellipse([21, 13, 25, 17], fill=shade(VC, 0.8)); save(im, "VC-U06_sentry")
    # VC-U10 Atlas Bot: large heavy
    im, d = canvas(50); shadow(d, 25, 26, 26, 30, 2); outline_rect(d, [15, 14, 35, 42], 7, (28, 32, 38), shade(VC, 0.55), 2); outline_rect(d, [20, 6, 30, 16], 3, VC, shade(VC, 0.4), 2); d.ellipse([22, 9, 28, 15], fill=(8, 10, 12))
    for sx in (14, 24):
        d.rounded_rectangle([sx, 42, sx+6, 50], radius=2, fill=(22, 24, 28))
    save(im, "VC-U10_atlas")

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
        shadow(d, cx, cy, w+6, h+6, 3)
        # outer wall
        outline_rect(d, [cx-w/2, cy-h/2, cx+w/2, cy+h/2], 9, shade(camo, 0.55), shade(camo, 0.85), 3)
        # roof panel
        outline_rect(d, [cx-w/2+9, cy-h/2+7, cx+w/2-9, cy+h/2-9], 6, shade(camo, roof_bias), shade(camo, 0.55), 2)
        return im, d, cx, cy, camo, accent
    def vent(d, x, y, accent):
        d.rounded_rectangle([x, y, x+6, y+6], radius=2, fill=shade(accent, 0.7))
    # HQ
    im, d, cx, cy, c, a = base(46, 42, VC, VC, 0.9); d.rectangle([cx-7, cy-7, cx+7, cy+7], fill=(16, 18, 24)); d.polygon([(cx-8, cy-8), (cx+8, cy-8), (cx, cy-20)], fill=shade(VC, 0.65)); save(im, "VC-B01_hq")
    im, d, cx, cy, c, a = base(46, 42, FC, FC, 0.9); d.rectangle([cx-7, cy-7, cx+7, cy+7], fill=(16, 18, 24)); d.polygon([(cx-8, cy-8), (cx+8, cy-8), (cx, cy-20)], fill=shade(FC, 0.65)); save(im, "FC-B01_hq")
    # Economy / factories
    im, d, cx, cy, c, a = base(48, 40, VC, VC, 0.8); d.line([cx-16, cy-4, cx+16, cy-4], fill=shade(VC, 0.45), width=2); d.line([cx-16, cy+4, cx+16, cy+4], fill=shade(VC, 0.45), width=2); vent(d, cx-4, cy+2, VC); save(im, "VC-B02_fab")
    im, d, cx, cy, c, a = base(48, 40, VC, VC, 0.75); d.line([cx-15, cy-3, cx+15, cy-3], fill=shade(VC, 0.45), width=2); d.line([cx-15, cy+6, cx+15, cy+6], fill=shade(VC, 0.45), width=2); vent(d, cx-3, cy, VC); save(im, "VC-B07_maker")
    im, d, cx, cy, c, a = base(48, 40, FC, FC, 0.75); d.line([cx-15, cy-3, cx+15, cy-3], fill=shade(FC, 0.45), width=2); d.line([cx-15, cy+6, cx+15, cy+6], fill=shade(FC, 0.45), width=2); vent(d, cx-3, cy, FC); save(im, "FC-B04_barracks")
    im, d, cx, cy, c, a = base(48, 40, FC, FC, 0.7); d.line([cx-16, cy-2, cx+16, cy-2], fill=shade(FC, 0.4), width=2)
    for ex in (cx-8, cx+2):
        d.ellipse([ex, cy+6, ex+6, cy+12], fill=(22, 24, 30))
    save(im, "FC-B05_motorpool")
    im, d, cx, cy, c, a = base(48, 40, VC, VC, 0.7); d.line([cx-16, cy-2, cx+16, cy-2], fill=shade(VC, 0.4), width=2)
    for ex in (cx-8, cx+2):
        d.ellipse([ex, cy+6, ex+6, cy+12], fill=(22, 24, 30))
    save(im, "VC-B08_robotshop")
    # Power
    im, d, cx, cy, c, a = base(38, 36, VC, VC, 0.6); d.ellipse([cx-11, cy-11, cx+11, cy+11], fill=(64, 68, 76), outline=(14, 16, 20), width=2); d.ellipse([cx-5, cy-5, cx+5, cy+5], fill=(14, 16, 20)); save(im, "VC-B03_gen")
    im, d, cx, cy, c, a = base(38, 36, FC, FC, 0.6); d.ellipse([cx-11, cy-11, cx+11, cy+11], fill=(64, 68, 76), outline=(14, 16, 20), width=2); d.ellipse([cx-5, cy-5, cx+5, cy+5], fill=(14, 16, 20)); save(im, "FC-B03_gen")
    # Compute / cooling
    im, d, cx, cy, c, a = base(42, 38, VC, VC, 0.65); d.rectangle([cx-11, cy-11, cx+11, cy+11], fill=(12, 14, 20))
    for ly in (-6, 0, 6):
        d.line([cx-9, cy+ly, cx+9, cy+ly], fill=VC, width=2)
    save(im, "VC-B05_servers")
    im, d, cx, cy, c, a = base(42, 38, VC, VC, 0.7); d.rounded_rectangle([cx-13, cy-11, cx+13, cy+11], radius=6, fill=(28, 78, 96), outline=shade(VC, 0.6), width=2); save(im, "VC-B06_cluster")
    im, d, cx, cy, c, a = base(36, 34, VC, VC, 0.8); d.line([cx-14, cy+12, cx+14, cy+12], fill=(150, 190, 210), width=3); d.line([cx-14, cy+8, cx+14, cy+8], fill=(110, 150, 170), width=2); save(im, "VC-B04_cooling")
    # Tech / support
    im, d, cx, cy, c, a = base(42, 38, FC, FC, 0.75); d.rounded_rectangle([cx-12, cy-11, cx+12, cy+11], radius=5, fill=shade(FC, 0.5), outline=shade(FC, 0.85), width=2); d.ellipse([cx-5, cy-5, cx+5, cy+5], fill=(18, 20, 26)); save(im, "FC-B09_command")
    im, d, cx, cy, c, a = base(40, 36, FC, FC, 0.7); d.rounded_rectangle([cx-16, cy-6, cx+16, cy+8], radius=4, fill=(40, 44, 50), outline=shade(FC, 0.6), width=2); d.rounded_rectangle([cx-16, cy-12, cx+16, cy-6], radius=4, fill=(60, 64, 70)); save(im, "FC-B10_repair")
    im, d, cx, cy, c, a = base(40, 36, VC, VC, 0.7); d.rounded_rectangle([cx-16, cy-6, cx+16, cy+8], radius=4, fill=(40, 44, 50), outline=shade(VC, 0.6), width=2); d.rounded_rectangle([cx-16, cy-12, cx+16, cy-6], radius=4, fill=(60, 64, 70)); save(im, "VC-B10_repair")
    # Defense / wall
    im, d = canvas(64); shadow(d, 32, 33, 52, 16, 2); outline_rect(d, [6, 22, 58, 42], 5, shade(FC, 0.45), shade(FC, 0.75), 2); d.line([6, 30, 58, 30], fill=shade(FC, 0.4), width=2); d.line([6, 38, 58, 38], fill=shade(FC, 0.35), width=2); save(im, "FC-D01_wall")
    im, d = canvas(64); shadow(d, 32, 32, 16, 50, 2); outline_rect(d, [24, 6, 40, 58], 5, shade(FC, 0.5), shade(FC, 0.8), 2); outline_rect(d, [28, 14, 36, 26], 2, (16, 18, 24), shade(FC, 0.6), 1); d.rounded_rectangle([26, 30, 38, 34], radius=2, fill=shade(FC, 0.7)); save(im, "FC-D02_guard")
    im, d = canvas(64); shadow(d, 32, 33, 26, 22, 2); outline_rect(d, [20, 34, 44, 50], 6, shade(VC, 0.5), shade(VC, 0.8), 2); outline_rect(d, [27, 16, 37, 36], 2, (14, 16, 22), shade(VC, 0.6), 1); d.rounded_rectangle([16, 10, 48, 16], radius=3, fill=shade(VC, 0.75)); save(im, "VC-D02_turret")

def gen_support():
    im, d = canvas(52); shadow(d, 26, 27, 28, 22, 2); tracked(d, 26, 27, 28, 20, (96, 104, 84), NEUTRAL, barrel=0, turret=(20, 18)); d.rounded_rectangle([32, 12, 42, 22], radius=3, fill=(120, 128, 108), outline=shade(NEUTRAL, 0.5), width=2); save(im, "SRV_harvester")

gen_vehicles()
gen_drones_bots()
gen_structures()
gen_support()
gen_human_characters()

M = {
 "FC-U01":"characters/soldier", "FC-U02":"characters/hitman", "FC-U03":"characters/survivor",
 "VC-U01":"characters/manblue", "VC-U05":"VC-U05_botdog", "VC-U06":"VC-U06_sentry",
 "FC-U05":"FC-U05_humvee","FC-U06":"FC-U06_ifv","FC-U07":"FC-U07_mbt",
 "FC-U08":"FC-U08_aa","FC-U09":"FC-U09_arty","VC-U02":"VC-U02_scout",
 "VC-U03":"VC-U03_drone","VC-U04":"VC-U04_technical","VC-U07":"VC-U07_hackvan",
 "VC-U08":"VC-U08_crawler","VC-U10":"VC-U10_atlas",
 "VC-B01":"VC-B01_hq","FC-B01":"FC-B01_hq","VC-B02":"VC-B02_fab",
 "VC-B07":"VC-B07_maker","FC-B04":"FC-B04_barracks","FC-B05":"FC-B05_motorpool",
 "VC-B08":"VC-B08_robotshop","VC-B03":"VC-B03_gen","FC-B03":"FC-B03_gen",
 "VC-B05":"VC-B05_servers","VC-B06":"VC-B06_cluster","VC-B04":"VC-B04_cooling",
 "FC-B09":"FC-B09_command","FC-B10":"FC-B10_repair","VC-B10":"VC-B10_repair",
 "FC-D01":"FC-D01_wall","FC-D02":"FC-D02_guard","VC-D02":"VC-D02_turret",
 "SRV":"SRV_harvester",
}
with open(os.path.join(OUT, "manifest.json"), "w") as f:
    json.dump({k: (v + ".png") for k, v in M.items()}, f, indent=2)
print("Total sprite files:", len([x for x in os.listdir(OUT) if x.endswith('.png')]))
print("Manifest entries:", len(M))
