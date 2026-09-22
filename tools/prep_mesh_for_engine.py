"""prep_mesh_for_engine.py — turn one tools/image_to_3d.py output into an engine-ready GLB.

    ~/Dev/tools/blender-4.5.13-linux-x64/blender -b -P tools/prep_mesh_for_engine.py -- <id> \
        [--image <path relative to repo root>] [--max-tris N]

Hunyuan3D meshes are ~500k verts, no UVs, colour only as a per-vertex layer after
render_sprites.project_portrait(). This script, for one id:
  1. Imports ~/Dev/assets/generated3d/<id>.glb, drops loose debris (render_sprites.
     drop_loose_debris), joins whatever survives into one mesh, and normalises scale so
     the largest extent equals the sim footprint (structures: footprint * NavGrid.CELL from
     content/data/structures.json; units: render_sprites.FIT_BY_ARMOR * 40 / 3, i.e. the same
     world units the 2D sprite rig fits units to, in engine px). Sits it on Blender z=0
     (Blender is Z-up here, same convention as render_sprites.py and kit_generated(); the
     glTF exporter's default +Y-up conversion makes that height axis Y in the exported file,
     which is what Godot expects).
  2. Paints it from the SAME image used to generate the mesh via render_sprites.
     project_portrait() (per-vertex "portrait" + "glow" colour attributes).
  3. Decimates to <= --max-tris (default 8000) triangles.
  4. Smart-UV-projects it, then bakes the per-vertex colour into a 1024x1024 diffuse image
     (Cycles DIFFUSE/COLOR bake; falls back to an EMIT bake if that fails).
  5. Assigns a Principled material with the baked image as Base Color and exports
     assets/models/<id>.glb with the texture embedded.

Prints "PREPPED <id> tris=<n>" on success.
"""
import json
import math
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
    max_tris = int(argv[argv.index("--max-tris") + 1]) if "--max-tris" in argv else 8000

    src = os.path.join(GENERATED, f"{uid}.glb")
    if not os.path.exists(src):
        raise SystemExit(f"no generated mesh at {src}")
    if not os.path.exists(image):
        raise SystemExit(f"no source image at {image}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene

    # 1. Import, drop debris, collapse to one mesh, normalise scale + position.
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
    s = length / max(ext.x, ext.y, ext.z, 1e-6)
    centre = (mn + mx) * 0.5
    holder = bpy.data.objects.new(uid + "_holder", None)
    sc.collection.objects.link(holder)
    holder.scale = (s, s, s)
    holder.location = (-centre.x * s, -centre.y * s, -mn.z * s)
    mesh_obj.parent = holder

    # 2. Paint from the source image (per-vertex "portrait" + "glow" colour attributes).
    mesh_obj.data.materials.clear()
    if not rs.project_portrait(mesh_obj, image):
        raise SystemExit(f"project_portrait failed for {uid} ({image})")

    # 3. Decimate to <= max_tris triangles.
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

    # 4. Smart UV Project, then bake the per-vertex colour into a 1024x1024 diffuse image.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    img = bpy.data.images.new(f"{uid}_diffuse", 1024, 1024, alpha=False)
    bake_mat = rs.vertex_color_material(uid + "_bake")
    tex_node = bake_mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex_node.image = img
    bake_mat.node_tree.nodes.active = tex_node
    mesh_obj.data.materials.clear()
    mesh_obj.data.materials.append(bake_mat)

    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 8
    try:
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, save_mode="INTERNAL")
    except RuntimeError as e:
        print(f"Cycles DIFFUSE bake failed ({e}); falling back to EMIT")
        bpy.ops.object.bake(type="EMIT", save_mode="INTERNAL")

    # 5. Principled material with the baked image as Base Color; export.
    final_mat = bpy.data.materials.new(f"{uid}_final")
    final_mat.use_nodes = True
    bsdf = final_mat.node_tree.nodes["Principled BSDF"]
    tex = final_mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    final_mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.75
    mesh_obj.data.materials.clear()
    mesh_obj.data.materials.append(final_mat)

    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, f"{uid}.glb")
    bpy.ops.object.select_all(action="DESELECT")
    holder.select_set(True)
    mesh_obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out_path, use_selection=True, export_format="GLB",
                               export_image_format="AUTO")
    size_mb = os.path.getsize(out_path) / 1e6
    print(f"PREPPED {uid} tris={tris} size={size_mb:.2f}MB -> {out_path}")


if __name__ == "__main__":
    main()
