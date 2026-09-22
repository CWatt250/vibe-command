"""Pipeline A render rig — Blender headless, one unit -> N facing frames.

    ~/Dev/tools/blender-4.5.13-linux-x64/blender -b -P tools/render_sprites.py -- VC-U04 <out_dir> [--facings 16] [--px 256]

Scene contract (the C&C recipe): orthographic camera pitched 40 deg from straight-down, looking
toward +Y; model "front" = +Y (screen-up in frame 0); hard sun from the screen's upper-left with a
dark ambient so facets read; Freestyle 1px outline; transparent film. Frame k rotates the model
by -k * (360 / facings) deg about Z, i.e. clockwise on screen, matching Godot's y-down angle.

Models come from KITS[id]: a function that builds the unit from primitives + materials. The
Technical is the proof of concept; kitbashing CC0 meshes drops in the same slot (append the .glb,
return the parent object). Frames land as <out_dir>/<id>_<k>.png; tools/pack_facings.py packs them.
"""
import math
import os
import sys

import bpy

# ---- materials ---------------------------------------------------------------
def mat(name, rgb, rough=0.7, metal=0.0, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 6.0
    return m


def srgb(r, g, b):
    return tuple(((c / 255.0) / 12.92) if c / 255.0 <= 0.04045 else (((c / 255.0) + 0.055) / 1.055) ** 2.4 for c in (r, g, b))


M = {}


def materials():
    M["osb"] = mat("osb", srgb(176, 138, 82), 0.9)
    M["ply"] = mat("ply", srgb(214, 180, 122), 0.85)
    M["paint"] = mat("paint", srgb(120, 108, 84), 0.6)       # faded truck paint
    M["metal"] = mat("metal", srgb(86, 92, 100), 0.5, 0.6)
    M["dark"] = mat("dark", srgb(30, 32, 36), 0.6, 0.2)
    M["tire"] = mat("tire", srgb(24, 24, 26), 0.95)
    M["glass"] = mat("glass", srgb(58, 78, 96), 0.2, 0.3)
    M["tape"] = mat("tape", srgb(158, 164, 172), 0.8)
    M["led"] = mat("led", srgb(0, 190, 255), 0.4, 0.0, emit=srgb(0, 190, 255))
    M["skin"] = mat("skin", srgb(198, 150, 112), 0.85)
    M["amber"] = mat("amber", srgb(232, 178, 26), 0.5, 0.0, emit=srgb(232, 178, 26))
    M["teal"] = mat("teal", srgb(47, 208, 196), 0.4, 0.0, emit=srgb(47, 208, 196))
    M["orange"] = mat("orange", srgb(255, 96, 32), 0.4, 0.0, emit=srgb(255, 96, 32))
    M["white"] = mat("white", srgb(226, 228, 232), 0.55)
    M["tan"] = mat("tan", srgb(168, 146, 104), 0.8)


# ---- primitives --------------------------------------------------------------
def box(name, size, loc, material, rot=(0, 0, 0), parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.data.materials.append(M[material])
    if parent:
        o.parent = parent
    return o


def cyl(name, r, depth, loc, material, rot=(0, 0, 0), parent=None, verts=24):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=verts)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(M[material])
    if parent:
        o.parent = parent
    return o


# ---- kits --------------------------------------------------------------------
def kit_technical():
    """VC-U04 Technical: pickup with plywood door/bed armor and a bed-mounted autocannon."""
    root = bpy.data.objects.new("VC-U04", None)
    bpy.context.scene.collection.objects.link(root)
    # chassis + bed (front = +Y)
    box("chassis", (1.3, 2.6, 0.45), (0, 0, 0.55), "paint", parent=root)
    box("cab", (1.25, 1.0, 0.55), (0, 0.55, 1.05), "paint", parent=root)
    box("windshield", (1.1, 0.06, 0.4), (0, 1.02, 1.1), "glass", parent=root)
    box("hood", (1.2, 0.5, 0.12), (0, 1.3, 0.83), "paint", parent=root)
    box("bed_floor", (1.2, 1.3, 0.06), (0, -0.55, 0.8), "dark", parent=root)
    # plywood armor: doors, bed sides, tailgate, a hood plate
    box("door_l", (0.06, 0.9, 0.5), (-0.66, 0.5, 1.05), "osb", parent=root)
    box("door_r", (0.06, 0.9, 0.5), (0.66, 0.5, 1.05), "osb", parent=root)
    box("bed_l", (0.06, 1.3, 0.55), (-0.66, -0.55, 1.05), "ply", parent=root)
    box("bed_r", (0.06, 1.3, 0.55), (0.66, -0.55, 1.05), "ply", parent=root)
    box("tailgate", (1.3, 0.06, 0.5), (0, -1.22, 1.02), "osb", parent=root)
    box("hood_plate", (0.9, 0.4, 0.05), (0, 1.3, 0.92), "osb", parent=root)
    # duct tape strips on the doors
    for y in (0.25, 0.75):
        box("tape_l%.0f" % (y * 10), (0.08, 0.1, 0.52), (-0.67, y, 1.05), "tape", parent=root)
        box("tape_r%.0f" % (y * 10), (0.08, 0.1, 0.52), (0.67, y, 1.05), "tape", parent=root)
    # wheels
    for x in (-0.72, 0.72):
        for y in (0.85, -0.85):
            cyl("wheel", 0.36, 0.3, (x, y, 0.36), "tire", rot=(0, math.pi / 2, 0), parent=root)
            cyl("hub", 0.14, 0.32, (x, y, 0.36), "metal", rot=(0, math.pi / 2, 0), parent=root)
    # bed gun: post, pintle, autocannon barrel, ammo box
    cyl("post", 0.06, 0.7, (0, -0.5, 1.15), "metal", parent=root)
    box("pintle", (0.3, 0.35, 0.22), (0, -0.5, 1.55), "dark", parent=root)
    cyl("barrel", 0.05, 1.3, (0, 0.2, 1.6), "dark", rot=(math.pi / 2, 0, 0), parent=root, verts=12)
    box("ammo", (0.25, 0.3, 0.22), (0.3, -0.85, 0.95), "dark", parent=root)
    # batteries strapped in the bed, laptop on the dash, antenna, LED
    box("battery1", (0.22, 0.4, 0.18), (-0.35, -0.7, 0.92), "led" if False else "dark", parent=root)
    box("battery2", (0.22, 0.4, 0.18), (-0.35, -0.25, 0.92), "metal", parent=root)
    box("laptop", (0.3, 0.2, 0.03), (-0.3, 0.75, 1.12), "metal", parent=root)
    cyl("antenna", 0.02, 1.2, (0.5, -0.1, 1.9), "metal", parent=root, verts=8)
    box("led_front", (0.3, 0.05, 0.08), (0, 1.56, 0.7), "led", parent=root)
    box("led_ant", (0.06, 0.06, 0.06), (0.5, -0.1, 2.5), "led", parent=root)
    return root


KENNEY = os.path.expanduser("~/Dev/assets/kenney")


def kenney(pack, name, parent, rot_z_deg=0.0, scale=1.0, recolor=None):
    """Append a Kenney CC0 GLB (Y-forward after glTF import) under `parent`.
    recolor: {mesh_name_substring: material_key} — Kenney ships one 'colormap'
    material per kit, so faction colours are applied per mesh here."""
    path = os.path.join(KENNEY, pack, "Models", "GLB format", f"{name}.glb")
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.context.scene.objects if o not in before]
    roots = [o for o in new if o.parent is None or o.parent not in new]
    for o in roots:
        o.parent = parent
        o.rotation_euler = (0.0, 0.0, math.radians(rot_z_deg))
        o.scale = (scale, scale, scale)
    if recolor:
        for o in new:
            if o.type != "MESH":
                continue
            for sub, key in recolor.items():
                if sub in o.name:
                    o.data.materials.clear()
                    o.data.materials.append(M[key])
    return new


def kit_technical_kenney():
    """VC-U04 Technical from the Kenney Car Kit truck + garage parts bolted on.
    Truck bounds after import: x ±0.75, y −1.45..1.5 (front +Y), z 0..1.3."""
    root = bpy.data.objects.new("VC-U04", None)
    bpy.context.scene.collection.objects.link(root)
    kenney("car-kit", "truck", root, recolor={"body": "paint", "wheel": "tire"})
    # plywood door + bed armor, duct tape, tailgate plate
    box("door_l", (0.06, 0.8, 0.5), (-0.78, 0.55, 0.85), "osb", parent=root)
    box("door_r", (0.06, 0.8, 0.5), (0.78, 0.55, 0.85), "osb", parent=root)
    box("bed_l", (0.06, 1.1, 0.5), (-0.78, -0.75, 0.9), "ply", parent=root)
    box("bed_r", (0.06, 1.1, 0.5), (0.78, -0.75, 0.9), "ply", parent=root)
    box("tailgate", (1.5, 0.06, 0.45), (0, -1.48, 0.9), "osb", parent=root)
    box("hood_plate", (1.0, 0.5, 0.05), (0, 1.1, 0.98), "osb", parent=root)
    for y in (0.3, 0.8):
        box("tape_l", (0.08, 0.1, 0.52), (-0.79, y, 0.85), "tape", parent=root)
        box("tape_r", (0.08, 0.1, 0.52), (0.79, y, 0.85), "tape", parent=root)
    # bed autocannon on a post, ammo, batteries, laptop, antenna, LEDs
    cyl("post", 0.06, 0.7, (0, -0.7, 1.15), "metal", parent=root)
    box("pintle", (0.3, 0.35, 0.22), (0, -0.7, 1.55), "dark", parent=root)
    cyl("barrel", 0.05, 1.4, (0, 0.05, 1.6), "dark", rot=(math.pi / 2, 0, 0), parent=root, verts=12)
    box("ammo", (0.25, 0.3, 0.22), (0.35, -1.1, 0.95), "dark", parent=root)
    box("battery1", (0.22, 0.4, 0.18), (-0.4, -1.0, 0.92), "dark", parent=root)
    box("battery2", (0.22, 0.4, 0.18), (-0.4, -0.5, 0.92), "metal", parent=root)
    cyl("antenna", 0.02, 1.2, (0.55, -0.3, 1.9), "metal", parent=root, verts=8)
    box("led_front", (0.3, 0.05, 0.08), (0, 1.52, 0.65), "led", parent=root)
    box("led_ant", (0.06, 0.06, 0.06), (0.55, -0.3, 2.5), "led", parent=root)
    return root


GENERATED = os.path.expanduser("~/Dev/assets/generated3d")


UNITS_JSON = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          "content", "data", "units.json")
# World size (largest extent, any axis) per armor class. Infantry stands ~2 units tall;
# vehicles run ~3 long; heavies a bit more. Keeps every mesh inside the 3.4 ortho frame.
FIT_BY_ARMOR = {"Infantry": 2.0, "HeavyInfantry": 2.3, "Light": 2.8, "Medium": 3.0,
                "Heavy": 3.2, "AirLight": 2.4, "AirHeavy": 3.2}


# Camera tilt per armor class, measured FROM STRAIGHT DOWN: 0 = pure top-down,
# 90 = pure side view. A standing figure at 40 is mostly the top of a helmet — an
# unreadable lump at 40 px. Every classic RTS cheats this: infantry are drawn nearly
# side-on while vehicles stay top-down. Same cheat here.
TILT_BY_ARMOR = {"Infantry": 58.0, "HeavyInfantry": 55.0}
DEFAULT_TILT = 40.0

# Per-faction infantry palette (body / webbing / accent light).
INFANTRY_STYLE = {
    "VC": {"body": "osb", "gear": "dark", "accent": "led"},      # garage: OSB + cyan
    "FC": {"body": "tan", "gear": "dark", "accent": "amber"},    # federal: tan + amber
    "TS": {"body": "white", "gear": "metal", "accent": "teal"},  # corporate: white + teal
    "SG": {"body": "dark", "gear": "metal", "accent": "orange"}, # signal: black + orange
}


def _unit_def(uid):
    try:
        import json
        for d in json.load(open(UNITS_JSON))["units"]:
            if d["id"] == uid.split("-hy3d")[0]:
                return d
    except Exception:
        pass
    return {}


def tilt_for(uid):
    return TILT_BY_ARMOR.get(_unit_def(uid).get("armorClass", ""), DEFAULT_TILT)


def fit_for(uid):
    try:
        import json
        for d in json.load(open(UNITS_JSON))["units"]:
            if d["id"] == uid:
                return FIT_BY_ARMOR.get(d.get("armorClass", ""), 3.0)
    except Exception:
        pass
    return 3.0


def kit_generated(uid, length=None, material="paint", yaw_deg=0.0):
    """A Hunyuan3D-2 mesh from tools/image_to_3d.py: import, normalise so the LARGEST
    extent on any axis is `length` (default from the unit's armor class), sit it on
    z=0, paint it from its portrait (or one flat material if that fails)."""
    from mathutils import Vector
    if length is None:
        length = fit_for(uid)
    root = bpy.data.objects.new(uid, None)
    bpy.context.scene.collection.objects.link(root)
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(GENERATED, f"{uid}.glb"))
    new = [o for o in bpy.context.scene.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    ext = mx - mn
    s = length / max(ext.x, ext.y, ext.z, 1e-6)
    holder = bpy.data.objects.new(uid + "_mesh", None)
    bpy.context.scene.collection.objects.link(holder)
    holder.parent = root
    holder.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    holder.scale = (s, s, s)
    centre = (mn + mx) * 0.5
    holder.location = (-centre.x * s, -centre.y * s, -mn.z * s)
    for o in new:
        if o.parent is None or o.parent not in new:
            o.parent = holder
    portrait = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                            "assets", "portraits", f"{uid}.png")
    for o in meshes:
        o.data.materials.clear()
        if os.path.exists(portrait) and project_portrait(o, portrait):
            o.data.materials.append(vertex_color_material(uid))
        else:
            o.data.materials.append(M[material])
    return root


def project_portrait(obj, image_path):
    """Paint the mesh with the portrait it was generated from: orthographic projection
    along the portrait's view (front-left-above in the mesh's own frame, front = -Y),
    sampled into a vertex colour layer. Faces the portrait couldn't see get the colour
    of the nearest visible edge — a smear that is invisible at sprite size and far better
    than flat clay. Returns False if the image can't be read."""
    from mathutils import Vector
    try:
        img = bpy.data.images.load(image_path)
    except Exception:
        return False
    import numpy as np
    w, h = img.size
    px = list(img.pixels)  # RGBA floats, bottom-up rows
    # Blur the albedo hard before sampling. Per-vertex sampling of a sharp portrait
    # paints high-frequency detail onto the mesh, which at 40 px reads as camouflage
    # speckle and destroys the form. A 30 px unit is read through LIGHTING; the
    # portrait's job is only to say "this region is tan / this one is cyan".
    rgba = np.array(px, dtype=np.float32).reshape(h, w, 4)
    radius = max(2, int(min(w, h) * 0.05))
    ker = np.ones(radius * 2 + 1, dtype=np.float32)
    ker /= ker.sum()
    a_mask = rgba[..., 3:4]
    prem = rgba[..., :3] * a_mask            # blur premultiplied so transparent pixels
    for axis in (0, 1):                      # don't bleed black into the silhouette
        prem = np.apply_along_axis(lambda m: np.convolve(m, ker, mode="same"), axis, prem)
        a_mask = np.apply_along_axis(lambda m: np.convolve(m, ker, mode="same"), axis, a_mask)
    rgba[..., :3] = prem / np.maximum(a_mask, 1e-4)
    px = rgba.reshape(-1).tolist()
    me = obj.data
    coords = np.array([obj.matrix_world @ v.co for v in me.vertices], dtype=np.float32)
    alpha = np.array(px[3::4], dtype=np.float32).reshape(h, w) > 0.5
    ys_, xs_ = np.nonzero(alpha)
    if xs_.size == 0:
        return False
    bx0, bx1, by0, by1 = int(xs_.min()), int(xs_.max()), int(ys_.min()), int(ys_.max())
    # The generator's canonical frame vs the portrait's camera isn't documented, so
    # search: which view direction makes the mesh's silhouette match the portrait's?
    G = 48
    pm = alpha[by0:by1 + 1, bx0:bx1 + 1]
    pr = np.zeros((G, G), dtype=bool)
    ph, pw = pm.shape
    for gy in range(G):
        for gx in range(G):
            y0_, y1_ = gy * ph // G, max((gy + 1) * ph // G, gy * ph // G + 1)
            x0_, x1_ = gx * pw // G, max((gx + 1) * pw // G, gx * pw // G + 1)
            pr[gy, gx] = pm[y0_:y1_, x0_:x1_].any()
    best, best_basis = -1.0, None
    for az_deg in range(180 - 90, 180 + 91, 15):      # camera azimuth around the -Y front
        for el_deg in (15, 25, 35, 45, 55):
            az, el = math.radians(az_deg), math.radians(el_deg)
            cam = np.array([math.cos(el) * math.sin(az), -math.cos(el) * math.cos(az), math.sin(el)], dtype=np.float32)
            view = -cam / np.linalg.norm(cam)
            up = np.array([0, 0, 1], dtype=np.float32)
            right = np.cross(view, up); right /= np.linalg.norm(right)
            up2 = np.cross(right, view)
            u = coords @ right; v = coords @ up2
            gu = ((u - u.min()) / max(u.max() - u.min(), 1e-6) * (G - 1)).astype(int)
            gv = ((v - v.min()) / max(v.max() - v.min(), 1e-6) * (G - 1)).astype(int)
            mm = np.zeros((G, G), dtype=bool)
            mm[gv, gu] = True
            # dilate once so sparse vertex hits become a silhouette
            mm = mm | np.roll(mm, 1, 0) | np.roll(mm, -1, 0) | np.roll(mm, 1, 1) | np.roll(mm, -1, 1)
            iou = float((mm & pr).sum()) / max(float((mm | pr).sum()), 1.0)
            if iou > best:
                best, best_basis = iou, (right, up2)
    right, up2 = best_basis
    print(f"PROJECT {obj.name}: best silhouette IoU {best:.2f}")
    us = coords @ right
    vs = coords @ up2
    u0, u1, v0, v1 = float(us.min()), float(us.max()), float(vs.min()), float(vs.max())
    layer = me.color_attributes.new(name="portrait", type="BYTE_COLOR", domain="POINT")
    for i, v in enumerate(me.vertices):
        fx = (us[i] - u0) / max(u1 - u0, 1e-6)
        fy = (vs[i] - v0) / max(v1 - v0, 1e-6)
        x = min(max(int(bx0 + fx * (bx1 - bx0)), 0), w - 1)
        y = min(max(int(by0 + fy * (by1 - by0)), 0), h - 1)
        # Walk toward the centre until we hit an opaque pixel (edge smear for hidden faces).
        cx, cy = (bx0 + bx1) // 2, (by0 + by1) // 2
        for _ in range(64):
            k = (y * w + x) * 4
            if px[k + 3] > 0.5:
                break
            x += (1 if cx > x else -1) if cx != x else 0
            y += (1 if cy > y else -1) if cy != y else 0
        # Average an opaque 5x5 window: per-vertex single pixels read as static on a
        # dense mesh; a small box gives painted-looking colour at sprite size.
        r = g = b = 0.0
        n = 0
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                xx, yy = x + dx, y + dy
                if 0 <= xx < w and 0 <= yy < h:
                    kk = (yy * w + xx) * 4
                    if px[kk + 3] > 0.5:
                        r += px[kk]; g += px[kk + 1]; b += px[kk + 2]; n += 1
        if n == 0:
            kk = (y * w + x) * 4
            r, g, b, n = px[kk], px[kk + 1], px[kk + 2], 1
        # Averaging desaturates and flattens; push saturation up and expand value
        # around mid-grey so albedo has real light/dark separation before lighting.
        import colorsys
        hh, ss, vv = colorsys.rgb_to_hsv(r / n, g / n, b / n)
        # Blurring already smoothed value; keep albedo mid-range and let the lighting
        # rig make the light/dark separation, or the two stack into mud.
        vv = min(max(0.45 + (vv - 0.5) * 0.8, 0.12), 0.85)
        rr, gg, bb = colorsys.hsv_to_rgb(hh, min(ss * 1.3, 1.0), vv)
        layer.data[i].color = (rr, gg, bb, 1.0)
    return True


def vertex_color_material(uid):
    m = bpy.data.materials.new(f"{uid}_portrait")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "portrait"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.75
    return m


# Per-unit infantry loadout, so a Rifle Squad and a Javelin Team aren't the same
# silhouette. `base` picks one of Kenney's 18 characters; `role` swaps the weapon.
INFANTRY_ROLE = {
    "VC-U01": ("character-c", "tools"), "VC-U10": ("character-p", "heavy"),
    "FC-U01": ("character-a", "rifle"), "FC-U02": ("character-c", "tools"),
    "FC-U03": ("character-d", "launcher"), "FC-U04": ("character-e", "mg"),
    "FC-U14": ("character-f", "rifle"),
    "TS-U01": ("character-g", "rifle"), "TS-U02": ("character-h", "tools"),
    "TS-U06": ("character-i", "heavy"), "TS-U12": ("character-p", "heavy"),
    "SG-U04": ("character-l", "rifle"), "SG-U14": ("character-m", "heavy"),
}


def infantry_weapon(role, gear, accent, root):
    """The held object is the main thing distinguishing one infantry sprite from
    another at 40 px — make each one a different silhouette, not a different texture."""
    if role == "launcher":                      # tube over the shoulder, points back
        cyl("tube", 0.17, 1.7, (0.28, 0.1, 1.95), gear,
            rot=(math.radians(68), 0, math.radians(14)), parent=root, verts=10)
        box("sight", (0.16, 0.3, 0.16), (0.12, 0.5, 1.92), accent, parent=root)
    elif role == "mg":                          # long barrel + drum, low and wide
        cyl("barrel", 0.09, 1.9, (0.05, 0.75, 1.36), gear,
            rot=(math.radians(84), 0, math.radians(8)), parent=root, verts=8)
        cyl("drum", 0.26, 0.2, (0.22, 0.12, 1.36), gear,
            rot=(0, math.radians(90), 0), parent=root, verts=12)
    elif role == "tools":                       # no rifle: toolpack + drill
        box("toolpack", (0.5, 0.34, 0.5), (-0.5, -0.3, 1.5), gear, parent=root)
        box("drill", (0.2, 0.42, 0.22), (0.42, 0.42, 1.3), gear, parent=root)
        box("drill_led", (0.08, 0.08, 0.08), (0.42, 0.64, 1.3), accent, parent=root)
    elif role == "heavy":                       # exo frame: cannon arm + wide shoulders
        cyl("cannon", 0.16, 1.4, (0.5, 0.55, 1.5), gear,
            rot=(math.radians(78), 0, math.radians(10)), parent=root, verts=10)
        box("core", (0.3, 0.2, 0.3), (0, 0.42, 1.62), accent, parent=root)
    else:                                       # rifle across the chest
        cyl("weapon", 0.09, 1.5, (0.1, 0.5, 1.5), gear,
            rot=(math.radians(74), 0, math.radians(20)), parent=root, verts=8)


def kit_infantry(uid, body="metal", gear="dark", accent="led"):
    """Infantry from a Kenney Blocky Character (CC0) with faction kit bolted on.

    Hunyuan3D reconstructs vehicles well but fails on humanoids from a single view —
    legs come back missing or fused and the result is an unreadable lump at 40 px. A
    real humanoid mesh has correct anatomy, which is the whole reason infantry read.
    Faction identity comes from materials + gear, same idea as the structures.
    """
    root = bpy.data.objects.new(uid, None)
    bpy.context.scene.collection.objects.link(root)
    # Kenney character-a: 1.6 wide x 2.7 tall, +Z up, facing -Y (our front is +Y).
    # Parts: leg-* 0.0-1.0, torso 1.0-1.9, arm-* 0.8-1.9, head 1.9-2.7.
    base, role = INFANTRY_ROLE.get(uid, ("character-a", "rifle"))
    kenney("blocky-characters", base, root, rot_z_deg=180.0,
           recolor={"torso": body, "arm": gear, "leg": gear, "head": "skin"})
    heavy = _unit_def(uid).get("armorClass") == "HeavyInfantry"
    # Helmet over the head, plate carrier over the torso, pack on the back. Chunky on
    # purpose: from 40 deg above, head and shoulders are most of what the player sees.
    # Value banding is what makes this read from above: dark helmet, light faction
    # torso, dark legs. One tone head-to-toe collapses into a single block.
    box("helmet", (0.86, 0.84, 0.3), (0, 0.02, 2.62), gear, parent=root)
    box("visor", (0.6, 0.1, 0.13), (0, 0.4, 2.5), accent, parent=root)
    box("vest", (1.16, 0.8, 0.62), (0, 0.0, 1.52), body, parent=root)
    box("belt", (1.18, 0.82, 0.14), (0, 0.0, 1.12), gear, parent=root)
    box("pack", (0.86, 0.4, 0.66), (0, -0.54, 1.54), gear, parent=root)
    box("led", (0.14, 0.1, 0.1), (0.34, -0.52, 1.86), accent, parent=root)
    infantry_weapon(role, gear, accent, root)
    if heavy:
        box("pauldron_l", (0.34, 0.6, 0.46), (-0.72, 0.0, 1.78), gear, parent=root)
        box("pauldron_r", (0.34, 0.6, 0.46), (0.72, 0.0, 1.78), gear, parent=root)
        box("backtank", (0.5, 0.3, 0.6), (0, -0.62, 2.0), body, parent=root)
    return root


# Hand-built kits, kept for reference / props. Plain unit ids resolve to the generated
# Hunyuan3D mesh (see main); these need the suffixed id to render.
KITS = {
    "VC-U04-kenney": kit_technical_kenney,
    "VC-U04-primitive": kit_technical,
    # Hunyuan3D meshes come out facing -Y (the portrait's "toward the viewer"); yaw 180.
    "VC-U04-hy3d": lambda: kit_generated("VC-U04", yaw_deg=180.0),
}


# ---- scene ----------------------------------------------------------------------
def build_scene(px, tilt_deg=40.0, ortho=3.4):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.resolution_x = px
    sc.render.resolution_y = px
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    # Camera: ortho, pitched `tilt` from straight-down, looking toward +Y.
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = ortho
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    t = math.radians(tilt_deg)
    co.location = (0.0, -10.0 * math.sin(t), 10.0 * math.cos(t) + 0.6)
    co.rotation_euler = (t, 0.0, 0.0)
    sc.camera = co
    # Sun from the screen's upper-left; dark ambient so facets separate.
    sun = bpy.data.lights.new("sun", "SUN")
    # Three-point rig tuned for READABILITY AT 30 px, not for a pretty hero render:
    # a hot key so lit planes go bright, a dim fill so shadow keeps hue without
    # going to mud, and a rim from behind-above that draws a bright edge along the
    # silhouette — the single biggest help in separating a unit from the terrain.
    sun.energy = 9.0
    sun.angle = math.radians(2.0)
    so = bpy.data.objects.new("sun", sun)
    sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(50), 0.0, math.radians(-135))
    fill = bpy.data.lights.new("fill", "SUN")
    fill.energy = 1.2
    fo = bpy.data.objects.new("fill", fill)
    sc.collection.objects.link(fo)
    fo.rotation_euler = (math.radians(35), 0.0, math.radians(45))
    rim = bpy.data.lights.new("rim", "SUN")
    rim.energy = 5.0
    rim.color = (0.85, 0.92, 1.0)
    ro = bpy.data.objects.new("rim", rim)
    sc.collection.objects.link(ro)
    ro.rotation_euler = (math.radians(20), 0.0, math.radians(35))
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.6, 0.7, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.35
    # Filmic crushes the value range we just built; Standard + a contrast look keeps it.
    sc.view_settings.look = "High Contrast"
    sc.world = world
    # Outline.
    sc.render.use_freestyle = True
    sc.render.line_thickness = 1.6
    fs = sc.view_layers[0].freestyle_settings
    ls = fs.linesets.new("outline") if not fs.linesets else fs.linesets[0]
    ls.select_silhouette = True
    ls.select_border = True
    ls.select_crease = True
    if ls.linestyle is None:
        ls.linestyle = bpy.data.linestyles.new("outline")
    ls.linestyle.color = (0.05, 0.05, 0.06)
    ls.linestyle.thickness = 1.6
    return sc


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(argv) < 2:
        raise SystemExit("usage: -- <unit_id> <out_dir> [--facings N] [--px N]")
    uid, out_dir = argv[0], argv[1]
    facings = int(argv[argv.index("--facings") + 1]) if "--facings" in argv else 16
    px = int(argv[argv.index("--px") + 1]) if "--px" in argv else 256
    tilt = float(argv[argv.index("--tilt") + 1]) if "--tilt" in argv else tilt_for(uid)
    os.makedirs(out_dir, exist_ok=True)
    sc = build_scene(px, tilt_deg=tilt)
    materials()
    armor = _unit_def(uid).get("armorClass", "")
    if uid in KITS:
        root = KITS[uid]()
    elif armor in ("Infantry", "HeavyInfantry"):
        root = kit_infantry(uid, **INFANTRY_STYLE.get(uid.split("-")[0], {}))
    elif os.path.exists(os.path.join(GENERATED, f"{uid}.glb")):
        # Any unit with a Hunyuan3D mesh renders through the generic kit.
        root = kit_generated(uid, yaw_deg=180.0)
    else:
        raise SystemExit(f"no kit and no generated mesh for {uid}")
    for k in range(facings):
        root.rotation_euler = (0.0, 0.0, math.radians(-k * 360.0 / facings))
        sc.render.filepath = os.path.join(out_dir, f"{uid}_{k:02d}.png")
        bpy.ops.render.render(write_still=True)
    print(f"RENDERED {uid} {facings} facings @ {px}px -> {out_dir}")


if __name__ == "__main__":
    main()
