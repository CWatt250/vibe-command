#!/usr/bin/env python3
"""Build a labelled contact sheet for one faction's unit sprites.

usage: python3 tools/make_faction_sheet.py TS
       (reads content/data/units.json + assets/sprites/manifest.json)
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPR = os.path.join(BASE, "assets/sprites")

PALETTE = {
    "VC": ((34, 28, 22), (232, 176, 64), "VIBE CODER - THE GARAGE"),
    "FC": ((24, 26, 24), (190, 166, 106), "FEDERAL COMMAND - CONTINUITY COMMAND"),
    "TS": ((22, 23, 26), (232, 176, 64), "TITAN SYSTEMS - PREMIUM CORPORATE WAR MACHINE"),
    "SG": ((16, 16, 18), (192, 80, 16), "THE SIGNAL - ASSIMILATION INTELLIGENCE"),
}


def font(sz):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def main():
    pre = sys.argv[1].upper()
    bg, accent, title = PALETTE[pre]
    units = [u for u in json.load(open(os.path.join(BASE, "content/data/units.json")))["units"]
             if u["id"].startswith(pre + "-")]
    man = json.load(open(os.path.join(SPR, "manifest.json")))
    units.sort(key=lambda u: u["id"])

    cols, cw, ch, pad, top = 5, 210, 210, 18, 96
    rows = (len(units) + cols - 1) // cols
    W = cols * cw + pad * (cols + 1)
    H = top + rows * (ch + 58) + pad
    im = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(im)
    d.text((pad, 26), title, font=font(30), fill=accent)
    d.text((pad, 62), "%d units - sprite pass" % len(units), font=font(17), fill=(150, 150, 150))

    for i, u in enumerate(units):
        c, r = i % cols, i // cols
        x = pad + c * (cw + pad)
        y = top + r * (ch + 58)
        d.rounded_rectangle([x, y, x + cw, y + ch], radius=10,
                            fill=(bg[0] + 12, bg[1] + 12, bg[2] + 12),
                            outline=(bg[0] + 40, bg[1] + 40, bg[2] + 40), width=1)
        rel = man.get(u["id"])
        if rel and os.path.exists(os.path.join(SPR, rel)):
            s = Image.open(os.path.join(SPR, rel)).convert("RGBA")
            k = min((cw - 40) / s.width, (ch - 40) / s.height, 4.0)
            s = s.resize((max(1, int(s.width * k)), max(1, int(s.height * k))), Image.NEAREST)
            im.paste(s, (x + (cw - s.width) // 2, y + (ch - s.height) // 2), s)
        d.text((x + 10, y + ch + 8), u["id"], font=font(19), fill=accent)
        d.text((x + 10, y + ch + 32), u["displayName"][:26], font=font(15), fill=(200, 200, 200))

    out = os.path.join(BASE, "docs/%s_units.png" % pre)
    im.save(out)
    print("wrote", out, im.size, "units:", len(units))


if __name__ == "__main__":
    main()
