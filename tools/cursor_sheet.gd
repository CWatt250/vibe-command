extends SceneTree
## Renders the five p4-05 cursors 4x (nearest) into docs/cursors_sheet.png for review.
## Run: godot-4 --headless --path . --script tools/cursor_sheet.gd

const SCALE := 4
const GUTTER := 8

func _init() -> void:
	var n := Cursors.NAMES.size()
	var tile := Cursors.SIZE * SCALE
	var sheet := Image.create_empty(n * tile + (n - 1) * GUTTER, tile, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.30, 0.32, 0.28, 1.0))   # MapRenderer-ish ground so white ink reads
	for i in range(n):
		var name: String = Cursors.NAMES[i]
		var img := Cursors.build(name)
		img.resize(tile, tile, Image.INTERPOLATE_NEAREST)
		var at := Vector2i(i * (tile + GUTTER), 0)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
		var hs: Vector2 = Cursors.HOTSPOT[name]
		sheet.fill_rect(Rect2i(at + Vector2i(int(hs.x), int(hs.y)) * SCALE, Vector2i(SCALE, SCALE)), Color(1, 0, 1))
	var err := sheet.save_png("res://docs/cursors_sheet.png")
	print("CURSOR_SHEET: docs/cursors_sheet.png size=%s err=%d" % [sheet.get_size(), err])
	quit()
