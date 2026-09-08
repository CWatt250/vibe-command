extends RefCounted
class_name ContentRegistry
## ContentRegistry — loads ALL content JSON into typed dictionaries keyed by stable ID.
## Single source of truth for unit/weapon/structure/moveprofile/faction defs (Blueprint §4).
## Pure data + lookup; no logic, no presentation.

var _units: Dictionary = {}
var _weapons: Dictionary = {}
var _structures: Dictionary = {}
var _moveprofiles: Dictionary = {}
var _factions: Dictionary = {}
var _armormatrix: Dictionary = {}
var content_path: String

func _init(root_path: String) -> void:
	content_path = root_path

func load_all() -> void:
	_units = _load_array("units.json", "units")
	_weapons = _load_array("weapons.json", "weapons")
	_structures = _load_array("structures.json", "structures")
	_moveprofiles = _load_array("moveprofiles.json", "profiles")
	_factions = _load_array("factions.json", "factions")
	var ap = content_path.path_join("armormatrix.json")
	if FileAccess.file_exists(ap):
		var af = FileAccess.open(ap, FileAccess.READ)
		var at = af.get_as_text()
		af.close()
		var parsed_a = JSON.parse_string(at)
		if parsed_a != null:
			_armormatrix = parsed_a.get("armorMatrix", {})
		else:
			push_error("ContentRegistry: bad JSON in armormatrix.json")

## Read a content file and key its array items by their "id" field.
func _load_array(fname: String, key: String) -> Dictionary:
	var result: Dictionary = {}
	var p = content_path.path_join(fname)
	if not FileAccess.file_exists(p):
		push_error("ContentRegistry: missing content file " + p)
		return result
	var f = FileAccess.open(p, FileAccess.READ)
	var text = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("ContentRegistry: bad JSON in " + p)
		return result
	for item in parsed.get(key, []):
		if item.has("id"):
			result[item["id"]] = item
	return result

func get_unit(id: String) -> Dictionary:
	return _units.get(id, {})

func get_weapon(id: String) -> Dictionary:
	return _weapons.get(id, {})

func get_structure(id: String) -> Dictionary:
	return _structures.get(id, {})

func get_moveprofile(id: String) -> Dictionary:
	return _moveprofiles.get(id, {})

func get_faction(id: String) -> Dictionary:
	return _factions.get(id, {})

func armor_multiplier(damage_type: String, armor_class: String) -> float:
	if _armormatrix.has(damage_type):
		return _armormatrix[damage_type].get(armor_class, 1.0)
	return 1.0

func all_units() -> Dictionary:
	return _units

func all_structures() -> Dictionary:
	return _structures

func all_weapons() -> Dictionary:
	return _weapons

func has_unit(id: String) -> bool:
	return _units.has(id)

func has_structure(id: String) -> bool:
	return _structures.has(id)
