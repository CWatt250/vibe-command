#!/usr/bin/env python3
"""Contact sheet of a faction's rendered facing strips: frame 0 (up), 4 (right), 6 (down-right)
per unit, at 2x, next to the portrait for comparison.

    python3 tools/make_unit_sheet.py VC   -> docs/concepts/vc_units_sheet.png
"""
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACCENT = {"VC": (0, 209, 255), "FC": (232, 178, 26), "TS": (47, 168, 160), "SG": (214, 83, 46)}


def main(fac: str) -> None:
    man = json.load(open(os.path.join(ROOT, "assets/sprites/manifest.json")))
    defs = {d["id"]: d for d in json.load(open(os.path.join(ROOT, "content/data/units.json")))["units"]
            if d["factionId"] == fac}
    ids = sorted(defs)
    cw, ch, pad, top = 560, 150, 10, 40
    im = Image.new("RGB", (cw + pad * 2, top + len(ids) * (ch + pad) + pad), (34, 36, 40))
    d = ImageDraw.Draw(im)
    d.text((pad, 12), f"{fac} battlefield sprites — Pipeline A (Hunyuan3D-2 mesh -> 16 facings); portrait | up | right | down-right", fill=ACCENT.get(fac, (230, 230, 230)))
    for i, uid in enumerate(ids):
        y = top + i * (ch + pad)
        d.rectangle([pad, y, pad + cw, y + ch], fill=(60, 62, 66))
        e = man.get(uid)
        p = os.path.join(ROOT, "assets/portraits", f"{uid}.png")
        if os.path.exists(p):
            s = Image.open(p).convert("RGBA")
            sc = min(120 / s.width, 120 / s.height)
            s = s.resize((int(s.width * sc), int(s.height * sc)), Image.LANCZOS)
            im.paste(s, (pad + 8 + (120 - s.width) // 2, y + 8 + (120 - s.height) // 2), s)
        if isinstance(e, dict) and e.get("facings"):
            strip = Image.open(os.path.join(ROOT, "assets/sprites", e["file"])).convert("RGBA")
            fw, fh = e["frame"]
            for j, k in enumerate((0, 4, 6)):
                f = strip.crop((k * fw, 0, (k + 1) * fw, fh))
                sc = min(120 / fw, 120 / fh)
                f = f.resize((int(fw * sc), int(fh * sc)), Image.LANCZOS)
                x = pad + 150 + j * 135
                im.paste(f, (x + (120 - f.width) // 2, y + 8 + (120 - f.height) // 2), f)
        else:
            d.text((pad + 160, y + 60), "no facing strip yet", fill=(255, 120, 100))
        d.text((pad + 8, y + ch - 18), f"{uid}  {defs[uid]['displayName']}  {defs[uid].get('armorClass')}", fill=(230, 230, 230))
    out = os.path.join(ROOT, "docs", "concepts", f"{fac.lower()}_units_sheet.png")
    im.save(out)
    print(out, im.size)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "VC")
