extends RefCounted
class_name SpriteAtlas
## Loads the generated CC0 sprite set (assets/sprites/) and exposes a texture per
## game content ID, plus a faction-colour tint. Presentation-only.

const MANIFEST_PATH := "res://assets/sprites/manifest.json"
const SPRITE_DIR := "res://assets/sprites"

static var _textures: Dictionary = {}
static var _regions: Dictionary = {}    # id -> Rect2 of opaque pixels (canvases carry ~30% margin)
static var _meta: Dictionary = {}       # id -> manifest dict for entries that carry options
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
		# Entry is either "file.png" or {"file": ..., "scale": 1.3, "tint": 0.0}.
		# scale: draw width as a multiple of the footprint (3/4-view art overhangs its pad).
		# tint:  faction-colour wash strength (painted art wants 0; flat generator art 0.22).
		var entry: Variant = data[key]
		var file: String = String(entry["file"]) if entry is Dictionary else String(entry)
		if entry is Dictionary:
			_meta[key] = entry
		var tex := load(SPRITE_DIR + "/" + file)
		if tex is Texture2D:
			_textures[key] = tex
			var img: Image = tex.get_image()
			var used: Rect2i = img.get_used_rect() if img != null else Rect2i()
			if used.size.x <= 0 or used.size.y <= 0:
				used = Rect2i(Vector2i.ZERO, Vector2i(tex.get_size()))
			_regions[key] = Rect2(used)

static func has(id: String) -> bool:
	_load()
	return id in _textures

static func texture(id: String) -> Texture2D:
	_load()
	return _textures.get(id)

## Opaque region of the sprite in texture pixels — draw this, not the full canvas,
## so size targets are the art's size and not the art plus its padding.
static func region(id: String) -> Rect2:
	_load()
	return _regions.get(id, Rect2(Vector2.ZERO, px_size(id)))

## HUD portraits (assets/portraits/, Pipeline B unit renders). Separate manifest so the
## battlefield sprite and the cameo can differ. Null if the unit has no portrait yet.
const PORTRAIT_MANIFEST := "res://assets/portraits/manifest.json"
const PORTRAIT_DIR := "res://assets/portraits"
static var _portraits: Dictionary = {}
static var _portraits_loaded := false

static func portrait(id: String) -> Texture2D:
	if not _portraits_loaded:
		_portraits_loaded = true
		var mf := FileAccess.open(PORTRAIT_MANIFEST, FileAccess.READ)
		if mf != null:
			var data: Variant = JSON.parse_string(mf.get_as_text())
			if data is Dictionary:
				for key in data.keys():
					var tex := load(PORTRAIT_DIR + "/" + String(data[key]))
					if tex is Texture2D:
						_portraits[key] = tex
	return _portraits.get(id)

## Draw-width multiple of the footprint for structures (1.0 = fill the pad).
static func scale(id: String) -> float:
	_load()
	return float(_meta.get(id, {}).get("scale", 1.0))

## Faction-colour wash strength, 0..1. Default matches the flat generator art.
static func tint(id: String, default: float) -> float:
	_load()
	return float(_meta.get(id, {}).get("tint", default))

## Pixel size of a given content-id sprite (or Vector2.ZERO if missing).
static func px_size(id: String) -> Vector2:
	var t := texture(id)
	if t == null:
		return Vector2.ZERO
	return t.get_size()

## Is this content id a humanoid character (faction-tint should be subtle)?
static func is_humanoid(id: String) -> bool:
	return id == "FC-U01" or id == "FC-U02" or id == "FC-U03" or id == "VC-U01"
