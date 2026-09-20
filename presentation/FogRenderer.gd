extends Node2D
class_name FogRenderer
## FogRenderer — draws the player faction's fog of war as a world-space overlay.
## Unexplored cells are fully black, explored/fogged cells are dimmed, visible cells
## are clear. Reads the same FogOfWarSystem state the sim owns (single authority).
## Sits above the map but below entities so only visible units appear.
##
## V2: the fog grid is packed into a grid-sized Image (one texel per cell), uploaded
## to an ImageTexture and drawn scaled over the world with LINEAR filtering. The
## visibility edge feathers across one cell instead of stepping. `texture` is shared
## with the minimap so both read one authority.

var fog_sys: FogOfWarSystem
var player_faction: String = "VC"
var texture: ImageTexture

var _image: Image
var _data: PackedByteArray
var _last_states: PackedByteArray

# RGBA per state. Explored is blue-black so fogged terrain reads cooled and
# desaturated, not just darker.
const RGBA_UNEXPLORED: PackedByteArray = [0, 0, 0, 255]
const RGBA_EXPLORED: PackedByteArray = [6, 9, 16, 165]
const RGBA_VISIBLE: PackedByteArray = [0, 0, 0, 0]

func _init(fog: FogOfWarSystem, faction: String) -> void:
	fog_sys = fog
	player_faction = faction
	z_index = 5   # above map(z=0) below entities(z=6)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var w := fog_sys.grid_width()
	var h := fog_sys.grid_height()
	_data.resize(w * h * 4)
	_data.fill(0)
	_image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	texture = ImageTexture.create_from_image(_image)

func _draw() -> void:
	if fog_sys == null:
		return
	_refresh_texture()
	var cell := fog_sys.cell_size()
	draw_texture_rect(texture, Rect2(0, 0, fog_sys.grid_width() * cell, fog_sys.grid_height() * cell), false)

## Re-pack the grid only when a cell actually changed state.
func _refresh_texture() -> void:
	var states := fog_sys.state_bytes(player_faction)
	if states == _last_states:
		return
	_last_states = states
	for i in range(states.size()):
		var rgba: PackedByteArray
		match states[i]:
			0: rgba = RGBA_UNEXPLORED
			1: rgba = RGBA_EXPLORED
			_: rgba = RGBA_VISIBLE
		var o := i * 4
		_data[o] = rgba[0]
		_data[o + 1] = rgba[1]
		_data[o + 2] = rgba[2]
		_data[o + 3] = rgba[3]
	_image.set_data(fog_sys.grid_width(), fog_sys.grid_height(), false, Image.FORMAT_RGBA8, _data)
	texture.update(_image)
