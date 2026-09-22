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
## V2b (p3-02): the world overlay draws `soft_texture` — alpha eroded one cell and
## 3×3 box-blurred so the edge is a 3-cell gradient; `texture` stays crisp for the minimap.

var fog_sys: FogOfWarSystem
var player_faction: String = "VC"
var texture: ImageTexture

var _image: Image
var _data: PackedByteArray
var _last_states: PackedByteArray

## World-space overlay: fog alpha eroded by one cell then 3x3 box-blurred, visible cells
## pinned clear. `texture` above stays crisp (one texel per cell) for the minimap.
var soft_texture: ImageTexture

var _soft_image: Image
var _soft_data: PackedByteArray
var _alpha: PackedByteArray
var _tmp: PackedByteArray

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
	_soft_data.resize(w * h * 4)
	_soft_data.fill(0)
	_alpha.resize(w * h)
	_tmp.resize(w * h)
	_soft_image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	soft_texture = ImageTexture.create_from_image(_soft_image)

func _draw() -> void:
	if fog_sys == null:
		return
	_refresh_texture()
	var cell := fog_sys.cell_size()
	draw_texture_rect(soft_texture, Rect2(0, 0, fog_sys.grid_width() * cell, fog_sys.grid_height() * cell), false)

## Re-pack the grid only when a cell actually changed state.
func _refresh_texture() -> void:
	var states := fog_sys.state_bytes(player_faction)
	if states == _last_states:
		return
	_last_states = states
	var w := fog_sys.grid_width()
	var h := fog_sys.grid_height()
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
		_soft_data[o] = rgba[0]
		_soft_data[o + 1] = rgba[1]
		_soft_data[o + 2] = rgba[2]
		_alpha[i] = rgba[3]
	_soften(states, w, h)
	for i in range(states.size()):
		_soft_data[i * 4 + 3] = _alpha[i]
	_image.set_data(w, h, false, Image.FORMAT_RGBA8, _data)
	texture.update(_image)
	_soft_image.set_data(w, h, false, Image.FORMAT_RGBA8, _soft_data)
	soft_texture.update(_soft_image)

## Erode fog by one cell (3x3 min), then 3x3 box blur, both separable with clamped edges;
## cells the sim reports visible are pinned fully clear. Operates on _alpha in place.
func _soften(states: PackedByteArray, w: int, h: int) -> void:
	for y in range(h):
		var r := y * w
		for x in range(w):
			_tmp[r + x] = mini(_alpha[r + maxi(x - 1, 0)], mini(_alpha[r + x], _alpha[r + mini(x + 1, w - 1)]))
	for y in range(h):
		for x in range(w):
			_alpha[y * w + x] = mini(_tmp[maxi(y - 1, 0) * w + x], mini(_tmp[y * w + x], _tmp[mini(y + 1, h - 1) * w + x]))
	for y in range(h):
		var r := y * w
		for x in range(w):
			_tmp[r + x] = (_alpha[r + maxi(x - 1, 0)] + _alpha[r + x] + _alpha[r + mini(x + 1, w - 1)]) / 3
	for y in range(h):
		for x in range(w):
			_alpha[y * w + x] = (_tmp[maxi(y - 1, 0) * w + x] + _tmp[y * w + x] + _tmp[mini(y + 1, h - 1) * w + x]) / 3
	for i in range(w * h):
		if states[i] == 2:
			_alpha[i] = 0

## Softened overlay alpha (0 clear .. 255 opaque) for a grid cell. Test hook.
func soft_alpha_at(cx: int, cy: int) -> int:
	return _soft_data[(cy * fog_sys.grid_width() + cx) * 4 + 3]
