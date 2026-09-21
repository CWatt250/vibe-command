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


def kit_generated(uid, length=3.0, material="paint", yaw_deg=0.0):
    """A Hunyuan3D-2 mesh from tools/image_to_3d.py: import, normalise so the longest
    horizontal extent is `length`, sit it on z=0, give it one flat material (the
    native nodes produce shape only, no texture)."""
    from mathutils import Vector
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
    s = length / max(ext.x, ext.y, 1e-6)
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
    w, h = img.size
    px = list(img.pixels)  # RGBA floats, bottom-up rows
    me = obj.data
    view = Vector((-0.55, -1.0, 0.75)).normalized()      # from camera toward object
    up = Vector((0, 0, 1))
    right = view.cross(up).normalized()
    up2 = right.cross(view).normalized()
    coords = [obj.matrix_world @ v.co for v in me.vertices]
    us = [c.dot(right) for c in coords]
    vs = [c.dot(up2) for c in coords]
    u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
    # Fit the mesh's projected bbox to the portrait's opaque bbox.
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            if px[(y * w + x) * 4 + 3] > 0.5:
                xs.append(x); ys.append(y)
    if not xs:
        return False
    bx0, bx1, by0, by1 = min(xs), max(xs), min(ys), max(ys)
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
        k = (y * w + x) * 4
        layer.data[i].color = (px[k], px[k + 1], px[k + 2], 1.0)
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


KITS = {
    "VC-U04": kit_technical_kenney,
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
    sun.energy = 7.0
    sun.angle = math.radians(2.0)
    so = bpy.data.objects.new("sun", sun)
    sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(50), 0.0, math.radians(-135))
    # Fill light from the opposite side, weak, so shadowed faces still show material.
    fill = bpy.data.lights.new("fill", "SUN")
    fill.energy = 1.5
    fo = bpy.data.objects.new("fill", fill)
    sc.collection.objects.link(fo)
    fo.rotation_euler = (math.radians(35), 0.0, math.radians(45))
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.6, 0.7, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
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
    os.makedirs(out_dir, exist_ok=True)
    sc = build_scene(px)
    materials()
    if uid in KITS:
        root = KITS[uid]()
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
