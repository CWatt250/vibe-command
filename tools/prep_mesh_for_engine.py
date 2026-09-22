"""prep_mesh_for_engine.py — turn one tools/image_to_3d.py output into an engine-ready GLB.

    ~/Dev/tools/blender-4.5.13-linux-x64/blender -b -P tools/prep_mesh_for_engine.py -- <id> \
        [--image <path relative to repo root>] [--max-tris N]

Hunyuan3D meshes are ~500k verts, no UVs, no usable material. This script, for one id:
  1. Imports ~/Dev/assets/generated3d/<id>.glb, drops loose debris (render_sprites.
     drop_loose_debris), joins whatever survives into one mesh, Voxel Remeshes it (the
     surface-net output is non-manifold and Decimate's edge-collapse stalls on it
     untouched), and normalises scale so the largest extent equals the sim footprint
     (structures: footprint * NavGrid.CELL from content/data/structures.json; units:
     render_sprites.FIT_BY_ARMOR * 40 / 3, the same world units the 2D sprite rig fits
     units to, in engine px). Sits it on Blender z=0 (Blender is Z-up here, same convention
     as render_sprites.py; the glTF exporter's +Y-up conversion makes that height axis Y in
     the exported file, which is what Godot expects).
  2. Decimates to <= --max-tris (default 30000) triangles. Runs BEFORE painting: colour is
     computed once, directly on the vertices we actually ship, instead of being computed on
     ~350k vertices and then blurred/averaged by the collapse.
  3. Paints the decimated mesh from the SAME image used to generate the mesh, via
     render_sprites.project_portrait() (per-vertex "portrait" + "glow" colour attributes;
     no UVs needed).
  4. Assigns render_sprites.vertex_color_material() — Base Color from "portrait", Emission
     from "glow" — the same material recipe the 2D sprite rig bakes from, so an engine model
     and its 2D portrait read as the same paint job.
  5. Exports assets/models/<id>.glb with vertex colours embedded (glTF COLOR_0; Blender's
     default export_vertex_color="MATERIAL" ships whatever colour attribute(s) the assigned
     material's shader nodes reference, which is exactly "portrait" — no bake, no image file).

Prints "PREPPED <id> tris=<n> verts=<n> color=COLOR_0" on success.
"""
import json
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import render_sprites as rs  # noqa: E402  (needs sys.path set first)

GENERATED = os.path.expanduser("~/Dev/assets/generated3d")
OUT_DIR = os.path.join(ROOT, "assets", "models")
STRUCTURES_JSON = os.path.join(ROOT, "content", "data", "structures.json")
CELL = 40.0  # NavGrid.CELL — world units per sim grid cell.


def _structure_def(sid: str) -> dict:
    for d in json.load(open(STRUCTURES_JSON))["structures"]:
        if d["id"] == sid:
            return d
    return {}


def target_extent(uid: str) -> float:
    """World-space size the mesh's largest bound-box extent should be scaled to."""
    sdef = _structure_def(uid)
    if sdef:
        fp = sdef.get("footprint", [1, 1])
        return max(fp) * CELL
    # Units: FIT_BY_ARMOR is in the 2D sprite rig's own world scale (ortho=3.4 frame);
    # x40/3 puts it in the same engine px the 3D scene uses (Blueprint coordinate contract).
    return rs.fit_for(uid) * CELL / 3.0


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not argv:
        raise SystemExit("usage: -- <id> [--image <path>] [--max-tris N]")
    uid = argv[0]
    image = (os.path.join(ROOT, argv[argv.index("--image") + 1]) if "--image" in argv
              else os.path.join(ROOT, "assets", "portraits", f"{uid}.png"))
    max_tris = int(argv[argv.index("--max-tris") + 1]) if "--max-tris" in argv else 30000

    src = os.path.join(GENERATED, f"{uid}.glb")
    if not os.path.exists(src):
        raise SystemExit(f"no generated mesh at {src}")
    if not os.path.exists(image):
        raise SystemExit(f"no source image at {image}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene

    # 1. Import, drop debris, collapse to one mesh, remesh to clean topology, normalise
    #    scale + position.
    before = set(sc.objects)
    bpy.ops.import_scene.gltf(filepath=src)
    new = rs.drop_loose_debris([o for o in sc.objects if o not in before])
    meshes = [o for o in new if o.type == "MESH"]
    if not meshes:
        raise SystemExit(f"no mesh geometry survived import for {uid}")
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[-1]
    if len(meshes) > 1:
        bpy.ops.object.join()
    mesh_obj = bpy.context.view_layer.objects.active
    if mesh_obj.parent is not None:
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")

    # The VAEDecodeHunyuan3D/VoxelToMesh (surface-net) output is riddled with non-manifold
    # geometry (doubled shells, T-junctions) that Decimate's edge-collapse can't cross — a
    # direct decimate pass stalls two orders of magnitude above target no matter how
    # aggressive the ratio. A Voxel Remesh rebuilds clean 2-manifold topology (at a voxel
    # size fine enough to keep the original silhouette) that Decimate can then simplify
    # all the way down.
    bpy.context.view_layer.objects.active = mesh_obj
    voxel_size = max(mesh_obj.dimensions) / 180.0
    remesh_mod = mesh_obj.modifiers.new("remesh", "REMESH")
    remesh_mod.mode = "VOXEL"
    remesh_mod.voxel_size = voxel_size
    remesh_mod.use_smooth_shade = False
    bpy.ops.object.modifier_apply(modifier=remesh_mod.name)

    bpy.context.view_layer.update()
    pts = [mesh_obj.matrix_world @ Vector(c) for c in mesh_obj.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    ext = mx - mn
    length = target_extent(uid)
    is_structure = bool(_structure_def(uid))
    if is_structure:
        # Footprint (x/y) is pinned exactly to the sim footprint -- gameplay-accuracy, and
        # what a structure's ground pad is sized from. Height is capped independently
        # rather than uniform-scaled 1:1 with the footprint: VC-B01's raw reconstruction
        # (a two-story building + roof antenna, single-view) comes out about as tall as its
        # footprint is wide, a far taller silhouette than this game's art direction uses
        # anywhere else, and it visibly parallax-shifted off its own ground pad at the
        # camera's 40 degree tilt (confirmed with tilt=0, where the offset vanished
        # completely -- real perspective displacement from excess height, not a lighting or
        # geometry bug). The cap only ever COMPRESSES height, never stretches it beyond
        # what uniform scaling would already give.
        s_xy = length / max(ext.x, ext.y, 1e-6)
        height_cap = length * 0.65
        s_z = min(s_xy, height_cap / max(ext.z, 1e-6))
        s = Vector((s_xy, s_xy, s_z))
    else:
        su = length / max(ext.x, ext.y, ext.z, 1e-6)
        s = Vector((su, su, su))
    centre = (mn + mx) * 0.5
    holder = bpy.data.objects.new(uid + "_holder", None)
    sc.collection.objects.link(holder)
    holder.scale = s
    holder.location = (-centre.x * s.x, -centre.y * s.y, -mn.z * s.z)
    mesh_obj.parent = holder

    # 2. Decimate to <= max_tris triangles, BEFORE painting (see module docstring).
    bpy.context.view_layer.objects.active = mesh_obj
    bpy.ops.object.select_all(action="DESELECT")
    mesh_obj.select_set(True)
    # A single aggressive Decimate pass on a surface-net mesh hits a topology floor well
    # above the target ratio (non-manifold/high-genus voxel geometry the algorithm won't
    # collapse past in one go); repeated passes at the *current* count push it the rest
    # of the way, same as running the modifier from the UI more than once.
    for _ in range(6):
        mesh_obj.data.calc_loop_triangles()
        current_tris = len(mesh_obj.data.loop_triangles)
        if current_tris <= max_tris:
            break
        ratio = max_tris / current_tris
        mod = mesh_obj.modifiers.new("decimate", "DECIMATE")
        mod.ratio = ratio
        bpy.ops.object.modifier_apply(modifier=mod.name)
        mesh_obj.data.calc_loop_triangles()
        new_tris = len(mesh_obj.data.loop_triangles)
        print(f"decimate pass: {current_tris} -> {new_tris} (ratio {ratio:.4f})")
        if new_tris >= current_tris:
            break  # no further progress possible
    tris = len(mesh_obj.data.loop_triangles)
    verts = len(mesh_obj.data.vertices)

    # 2b. Recalculate normals. The old pipeline baked colour with Cycles DIFFUSE+COLOR,
    # which extracts flat albedo independent of lighting/orientation — invisible normals
    # bugs stayed invisible. Vertex colour is lit in real time by the engine, so a face
    # with an inverted normal now renders unlit (black) regardless of its colour. Found by
    # isolating this exact mesh with a flat grey material: the bottom half rendered solid
    # black with a crisp seam, present with or without vertex colour, so the base geometry
    # itself has an inside-out patch (voxel remesh occasionally mis-signs an SDF pocket on
    # complex single-view reconstructions). This is a one-shot, well-understood fix for
    # exactly that class of bug — outward-consistent recalculation on a closed manifold.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")

    # 3. Paint the FINAL (already-decimated) mesh from the source image: per-vertex
    #    "portrait" + "glow" colour attributes, no UVs needed.
    mesh_obj.data.materials.clear()
    if not rs.project_portrait(mesh_obj, image):
        raise SystemExit(f"project_portrait failed for {uid} ({image})")

    # 4. Material: Base Color from "portrait", Emission from "glow" — the same recipe the
    #    2D sprite rig uses, so the engine model and the unit's portrait/sprite match.
    mesh_obj.data.materials.append(rs.vertex_color_material(uid))

    # 5. Export with vertex colours embedded. Blender's default export_vertex_color=
    #    "MATERIAL" ships whichever colour attribute(s) the assigned material's shader
    #    nodes reference — exactly "portrait" (and "glow") here. No bake, no image file.
    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, f"{uid}.glb")
    bpy.ops.object.select_all(action="DESELECT")
    holder.select_set(True)
    mesh_obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out_path, use_selection=True, export_format="GLB")
    size_mb = os.path.getsize(out_path) / 1e6
    print(f"PREPPED {uid} tris={tris} verts={verts} color=COLOR_0 size={size_mb:.2f}MB -> {out_path}")


if __name__ == "__main__":
    main()
