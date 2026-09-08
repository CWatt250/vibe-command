extends RefCounted
class_name SpriteAtlas
## Loads the generated CC0 sprite set (assets/sprites/) and exposes a texture per
## game content ID, plus a faction-colour tint. Presentation-only.

const MANIFEST_PATH := "res://assets/sprites/manifest.json"
const SPRITE_DIR := "res://assets/sprites"

static var _textures: Dictionary = {}
static var _loaded := false

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var mf := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if mf == null:
		push_error("SpriteAtlas: manifest missing %s" % MANIFEST_PATH)
		return
	var data: Variant = JSON.parse_string(mf.get_as_text())
	if data == null or not (data is Dictionary):
		push_error("SpriteAtlas: manifest parse failed")
		return
	for key in data.keys():
		var tex := load(SPRITE_DIR + "/" + String(data[key]))
		if tex is Texture2D:
			_textures[key] = tex

static func has(id: String) -> bool:
	_load()
	return id in _textures

static func texture(id: String) -> Texture2D:
	_load()
	return _textures.get(id)

## Pixel size of a given content-id sprite (or Vector2.ZERO if missing).
static func px_size(id: String) -> Vector2:
	var t := texture(id)
	if t == null:
		return Vector2.ZERO
	return t.get_size()

## Is this content id a humanoid character (faction-tint should be subtle)?
static func is_humanoid(id: String) -> bool:
	return id == "FC-U01" or id == "FC-U02" or id == "FC-U03" or id == "VC-U01"
