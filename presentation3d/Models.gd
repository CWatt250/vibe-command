extends RefCounted
class_name Models3D
## Static model builders for the p2-01 3D prototype: one real exemplar per unit type
## (Garage Core structure, Technical truck, Maker Crew soldier, Scout Quad drone) plus a
## faction-coloured box fallback so every entity in the sandbox appears.

const KENNEY_DIR := "res://assets/models/kenney/"
const GLB_DIR := "res://assets/models/"

# Reuse the 2D sprite rig's faction palette (presentation/EntityRenderer.gd FC_COLORS).
const FC_COLORS := {
	"VC": Color(0.0, 0.82, 1.0),
	"FC": Color(0.95, 0.75, 0.15),
}

const FALLBACK_SIZE := {
	"Infantry": 14.0, "HeavyInfantry": 14.0, "Light": 24.0, "Medium": 32.0,
	"Heavy": 40.0, "AirLight": 24.0, "AirHeavy": 24.0,
}

## VC-B01's engine-ready mesh (tools/prep_mesh_for_engine.py output): painted with
## per-vertex colour (glTF COLOR_0), no texture. Any other structure with no GLB falls
## back to a billboard of its existing AI-rendered 3/4-view sprite (see `_structure_sprite`).
static func structure(def_id: String, faction: String, footprint: Array) -> Node3D:
	var path := GLB_DIR + def_id + ".glb"
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		var inst: Node3D = scene.instantiate()
		_use_vertex_colors(inst)
		_enable_shadows(inst)
		return inst
	var sprite := _structure_sprite(def_id, footprint)
	if sprite != null:
		return sprite
	var fw: float = float(footprint[0]) * 40.0 if footprint.size() > 0 else 40.0
	var fd: float = float(footprint[1]) * 40.0 if footprint.size() > 1 else fw
	return _box(Vector3(fw, 60.0, fd), FC_COLORS.get(faction, Color.WHITE), Vector3(0, 30.0, 0))

## VC-U04 Technical: the Kenney car-kit truck, faded and armed only visually (no turret —
## this ticket is about motion, not the roster). Scaled so its front-to-back length is 52.
static func truck() -> Node3D:
	var scene: PackedScene = load(KENNEY_DIR + "truck.glb")
	var inst: Node3D = scene.instantiate()
	inst.set_script(load("res://presentation3d/Truck3D.gd"))
	# Native bounds (Godot/glTF Y-up, no Blender re-import): z -1.475..1.475 (front/back).
	var native_length := 2.95
	var s := 52.0 / native_length
	inst.scale = Vector3(s, s, s)
	_recolor(inst, "body", Color(0.47, 0.42, 0.33))
	_recolor(inst, "wheel", Color(0.08, 0.08, 0.09))
	_enable_shadows(inst)
	inst.setup(0.3 * s)  # native wheel radius ~0.3, scaled with the body
	return inst

## VC-U01 Maker Crew: the Kenney blocky-characters kit, scaled to stand 40 units tall.
static func soldier() -> Node3D:
	var scene: PackedScene = load(KENNEY_DIR + "character-c.glb")
	var inst: Node3D = scene.instantiate()
	inst.set_script(load("res://presentation3d/Soldier3D.gd"))
	# Native height (feet to crown, measured off character-c.glb): 2.7.
	var native_height := 2.7
	var s := 40.0 / native_height
	inst.scale = Vector3(s, s, s)
	_recolor(inst, "torso", Color(0.69, 0.54, 0.32))
	_recolor(inst, "arm", Color(0.16, 0.16, 0.18))
	_recolor(inst, "leg", Color(0.16, 0.16, 0.18))
	_recolor(inst, "head", Color(0.80, 0.62, 0.48))
	_enable_shadows(inst)
	inst.setup()
	return inst

## VC-U02 Scout Quad: no kit mesh, built entirely from primitives (Drone3D).
static func drone() -> Node3D:
	return Drone3D.new()

## Everything else in the roster: a billboard of the unit's existing AI portrait, so the
## sandbox reads as the game's actual art instead of anonymous boxes while only four
## exemplars have real animated models. This is a comparison aid for the 3D-vs-2D decision,
## not the destination — the real fix is porting more units through Pipeline A/prep_mesh.
## Falls back to a faction-coloured box only if the unit has no portrait at all.
static func fallback(e: Entity) -> Node3D:
	var armor: String = e.def_data.get("armorClass", "")
	var size: float = FALLBACK_SIZE.get(armor, 24.0)
	var y: float = 24.0 if e.is_airborne else 0.0
	var tex := SpriteAtlas.portrait(e.def_id)
	if tex == null:
		var by: float = 24.0 if e.is_airborne else size * 0.5
		return _box(Vector3(size, size, size), FC_COLORS.get(e.faction_id, Color.WHITE), Vector3(0, by, 0))
	var region := SpriteAtlas.region(e.def_id)
	var target_px: float = EntityRenderer.UNIT_PX.get(armor, EntityRenderer.UNIT_PX_DEFAULT)
	var aspect: float = region.size.y / maxf(region.size.x, 1.0)
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.region_enabled = true
	sp.region_rect = region
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.shaded = true
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.pixel_size = target_px / region.size.x
	# Sprite3D's local origin is the sprite's centre; lift so the feet sit on the ground.
	sp.offset = Vector2(0.0, -target_px * aspect * 0.5)
	sp.position = Vector3(0.0, y, 0.0)
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return sp

## A structure with no engine mesh: a standing (non-billboard) sprite of its existing
## 3/4-view AI render, sized to its footprint and the sprite's own manifest scale
## (presentation/EntityRenderer.gd does the same STRUCTURE_FILL * scale math for the 2D
## game). Faces -Z (toward the camera's forward projection) since the sprite art is
## painted from one fixed 3/4 angle, not meant to rotate.
static func _structure_sprite(def_id: String, footprint: Array) -> Node3D:
	var tex := SpriteAtlas.texture(def_id)
	if tex == null:
		return null
	var region := SpriteAtlas.region(def_id)
	var fw: float = float(footprint[0]) * 40.0 if footprint.size() > 0 else 40.0
	var target_w: float = fw * 0.94 * SpriteAtlas.scale(def_id)
	var aspect: float = region.size.y / maxf(region.size.x, 1.0)
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.region_enabled = true
	sp.region_rect = region
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sp.shaded = true
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.pixel_size = target_w / region.size.x
	var height := target_w * aspect
	sp.offset = Vector2(0.0, -height * 0.5)
	sp.rotation.y = PI  # sprite art faces the viewer at yaw 0; scene "forward" is -Z
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return sp

static func _box(size: Vector3, color: Color, local_pos: Vector3) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.material_override = m
	mi.position = local_pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

static func _recolor(root: Node, name_substr: String, color: Color) -> void:
	for c in root.find_children("*", "MeshInstance3D", true, false):
		if name_substr in String(c.name):
			var m := StandardMaterial3D.new()
			m.albedo_color = color
			(c as MeshInstance3D).material_override = m

static func _enable_shadows(root: Node) -> void:
	for c in root.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## tools/prep_mesh_for_engine.py ships meshes with per-vertex colour (glTF COLOR_0) and no
## texture. Godot's glTF importer reads COLOR_0 into the mesh's vertex colour channel, but
## StandardMaterial3D still needs `vertex_color_use_as_albedo` explicitly turned on per
## surface, or it renders using the material's flat (default white/grey) albedo — the grey
## blob the p2-01 capture showed, from a *different* cause (a bad UV bake) but the same
## symptom. Any glow/emission from a second vertex-colour layer does not survive glTF
## import as a separate channel Godot can read, so emission is simply left at whatever the
## imported material set (usually none) — the ticket's own documented fallback.
static func _use_vertex_colors(root: Node) -> void:
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in range(mi.mesh.get_surface_count()):
			var src: Material = mi.mesh.surface_get_material(i)
			var mat: StandardMaterial3D = (src as StandardMaterial3D).duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mat.roughness = 0.85
			# Minimum-brightness floor. This mesh's reconstructed geometry has a deep recess
			# (the open garage door) whose normals face away from every light source AND
			# away from the sky-facing direction Environment.ambient_light weights toward —
			# raising ambient_light_energy 4x moved it only a few RGB values (29 -> 38 of
			# 255), and disabling SSAO didn't move it further, so this is not occlusion or
			# ambient strength, it is the hemisphere-weighted ambient model simply not
			# reaching a sideways/downward-facing cavity. A small flat self-emission is the
			# standard stylized-render fix for exactly this: guarantees every surface reads
			# as "in shadow", never "a hole", independent of normal direction or renderer.
			mat.emission_enabled = true
			mat.emission = Color(0.16, 0.14, 0.12)
			mat.emission_energy_multiplier = 1.0
			mi.set_surface_override_material(i, mat)
