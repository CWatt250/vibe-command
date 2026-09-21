#!/usr/bin/env python3
"""Contact sheet of a faction's structure sprites for review.

    python3 tools/make_structure_sheet.py VC   -> docs/concepts/vc_structures_sheet.png
"""
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACCENT = {"VC": (0, 209, 255), "FC": (232, 178, 26), "TS": (47, 168, 160), "SG": (214, 83, 46)}


def main(fac: str) -> None:
    man = json.load(open(os.path.join(ROOT, "assets/sprites/manifest.json")))
    defs = {d["id"]: d for d in json.load(open(os.path.join(ROOT, "content/data/structures.json")))["structures"]
            if d["factionId"] == fac}
    fname = json.load(open(os.path.join(ROOT, "content/data/factions.json")))["factions"]
    title = next((f["displayName"] for f in fname if f["id"] == fac), fac)
    ids = sorted(defs)
    cols, cw, ch, pad, top = 5, 230, 250, 12, 40
    rows = (len(ids) + cols - 1) // cols
    im = Image.new("RGB", (cols * cw + pad * (cols + 1), top + rows * (ch + pad) + pad), (34, 36, 40))
    d = ImageDraw.Draw(im)
    d.text((pad, 12), f"{title} structures - Pipeline B (Qwen-Image-2.1), keyed sprites", fill=ACCENT.get(fac, (230, 230, 230)))
    for i, sid in enumerate(ids):
        e = man.get(sid)
        f = e["file"] if isinstance(e, dict) else e
        x = pad + (i % cols) * (cw + pad)
        y = top + (i // cols) * (ch + pad)
        d.rectangle([x, y, x + cw, y + ch], fill=(60, 62, 66))
        p = os.path.join(ROOT, "assets/sprites", f) if f else ""
        if f and os.path.exists(p):
            s = Image.open(p).convert("RGBA")
            sc = min((cw - 20) / s.width, (ch - 40) / s.height)
            s = s.resize((int(s.width * sc), int(s.height * sc)), Image.LANCZOS)
            im.paste(s, (x + (cw - s.width) // 2, y + 10 + (ch - 40 - s.height) // 2), s)
        else:
            d.text((x + 10, y + 100), "missing", fill=(255, 80, 80))
        d.text((x + 8, y + ch - 24), f"{sid}  {defs[sid]['displayName']}  {defs[sid].get('footprint')}", fill=(230, 230, 230))
    out = os.path.join(ROOT, "docs", "concepts", f"{fac.lower()}_structures_sheet.png")
    im.save(out)
    print(out, im.size)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "VC")
