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

## VC-B01's engine-ready mesh (tools/prep_mesh_for_engine.py output). Any other structure
## gets a faction-coloured box sized by its footprint, so the base still reads.
static func structure(def_id: String, faction: String, footprint: Array) -> Node3D:
	var path := GLB_DIR + def_id + ".glb"
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		var inst: Node3D = scene.instantiate()
		_enable_shadows(inst)
		return inst
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

## Everything else in the sandbox: a faction-coloured box sized by armor class, so nothing
## in the roster is invisible while only four exemplars have real models.
static func fallback(e: Entity) -> Node3D:
	var armor: String = e.def_data.get("armorClass", "")
	var size: float = FALLBACK_SIZE.get(armor, 24.0)
	var y: float = 24.0 if e.is_airborne else size * 0.5
	return _box(Vector3(size, size, size), FC_COLORS.get(e.faction_id, Color.WHITE), Vector3(0, y, 0))

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
