extends RefCounted
class_name Cursors
## p4-05 — contextual mouse cursor. Five 32x32 cursors drawn procedurally at startup (the repo
## ships no cursor art), each registered once into its own Input.CursorShape slot; switching is
## one set_default_cursor_shape() call, made only when the name changes. cursor_for() is pure so
## the headless test pins the rules without a window.

const NAMES: Array[String] = ["arrow", "move", "attack", "invalid", "select"]
const SIZE := 32

# Hotspot = the pixel that "is" the pointer. Arrow points from its tip; the rest from the centre.
const HOTSPOT := {
	"arrow": Vector2(4, 4), "move": Vector2(16, 16), "attack": Vector2(16, 16),
	"invalid": Vector2(16, 16), "select": Vector2(16, 16),
}
# One shape slot per cursor. set_custom_mouse_cursor() replaces the image of a shape;
# set_default_cursor_shape() then switches between them with no re-upload.
const SHAPE := {
	"arrow": Input.CURSOR_ARROW, "move": Input.CURSOR_MOVE, "attack": Input.CURSOR_CROSS,
	"invalid": Input.CURSOR_FORBIDDEN, "select": Input.CURSOR_POINTING_HAND,
}
const INK := {
	"arrow": Color(1.0, 1.0, 1.0), "move": Color(1.0, 1.0, 1.0), "attack": Color(1.0, 0.45, 0.25),
	"invalid": Color(0.95, 0.22, 0.20), "select": Color(0.35, 0.95, 1.0),
}
const OUTLINE := Color(0.05, 0.05, 0.08)

var _current: String = ""

## Pure rule table (see the ticket). Keys, all optional:
##   ui: bool           mouse over a Control / the minimap / placement ghost active
##   armed: String      "" | "attack"   (p4-04 armed ATTACK_MOVE)
##   has_selection: bool
##   hover_own: bool    own unit or structure under the mouse
##   hover_enemy: bool  visible enemy under the mouse
##   fog: int           FogOfWarSystem.state_at: 0 unexplored, 1 explored, 2 visible
##   walkable: bool     not NavGrid.is_blocked for the selection's path layer
static func cursor_for(ctx: Dictionary) -> String:
	if ctx.get("ui", false):
		return "arrow"
	var armed: String = str(ctx.get("armed", ""))
	if armed == "attack":
		return "attack"
	if ctx.get("hover_own", false):
		return "select"
	if not ctx.get("has_selection", false):
		return "arrow"
	if ctx.get("hover_enemy", false):
		return "attack"
	if int(ctx.get("fog", 2)) == 0 or not ctx.get("walkable", true):
		return "invalid"
	return "move"

## Register all five images once (Game._ready). Headless this is a silent no-op.
## The bare Image goes in — wrapping it in an ImageTexture leaks GL textures at exit.
func install() -> void:
	for n in NAMES:
		Input.set_custom_mouse_cursor(build(n), SHAPE[n], HOTSPOT[n])
	_current = ""
	apply("arrow")

## Switch only on change — called once per sim tick, so most calls return here.
func apply(name: String) -> void:
	if name == _current:
		return
	_current = name
	Input.set_default_cursor_shape(SHAPE[name])

func current() -> String:
	return _current

## 32x32 RGBA image for one cursor: the ink pixels with a 1-px dark outline underneath.
static func build(name: String) -> Image:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := _pixels(name)
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_stamp(img, ink, off, OUTLINE)
	_stamp(img, ink, Vector2i.ZERO, INK[name])
	return img

static func _stamp(img: Image, px: Array[Vector2i], off: Vector2i, col: Color) -> void:
	for p in px:
		var q := p + off
		if q.x >= 0 and q.y >= 0 and q.x < SIZE and q.y < SIZE:
			img.set_pixelv(q, col)

## Ink pixels per cursor. Duplicates are harmless.
static func _pixels(name: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match name:
		"arrow":
			# Diagonal arrow: head = triangle x+y<=22 from the (4,4) tip; 3-px shaft down the
			# diagonal to (26,26). The centre (16,16) sits on the shaft.
			for y in range(4, 19):
				for x in range(4, 19):
					if x + y <= 22:
						out.append(Vector2i(x, y))
			for i in range(11, 27):
				out.append(Vector2i(i, i))
				out.append(Vector2i(i + 1, i))
				out.append(Vector2i(i, i + 1))
		"move":
			# Four outward chevrons on the axes (2 px thick, 5 px arms) + 2x2 centre dot.
			for k in range(5):
				for t in range(2):
					out.append(Vector2i(16 - k, 4 + k + t));  out.append(Vector2i(16 + k, 4 + k + t))    # N
					out.append(Vector2i(16 - k, 27 - k - t)); out.append(Vector2i(16 + k, 27 - k - t))   # S
					out.append(Vector2i(4 + k + t, 16 - k));  out.append(Vector2i(4 + k + t, 16 + k))    # W
					out.append(Vector2i(27 - k - t, 16 - k)); out.append(Vector2i(27 - k - t, 16 + k))   # E
			out.append_array(_dot())
		"attack":
			# Crosshair: ring r 9..10.5, four axis ticks r 3..7, 2x2 centre dot.
			out.append_array(_ring(9.0, 10.5))
			for r in range(3, 8):
				out.append(Vector2i(16 + r, 16)); out.append(Vector2i(16 - r, 16))
				out.append(Vector2i(16, 16 + r)); out.append(Vector2i(16, 16 - r))
			out.append_array(_dot())
		"invalid":
			# Circle-slash: ring r 9.5..11.5 and a 2-px diagonal bar through the centre.
			out.append_array(_ring(9.5, 11.5))
			for i in range(8, 25):
				out.append(Vector2i(i, i))
				out.append(Vector2i(i + 1, i))
		"select":
			# Bracket corners of the 22-px box (5..26), 6 px long, 2 px thick, + 2x2 centre dot.
			for c in [Vector2i(5, 5), Vector2i(26, 5), Vector2i(5, 26), Vector2i(26, 26)]:
				var sx := 1 if c.x == 5 else -1
				var sy := 1 if c.y == 5 else -1
				for i in range(6):
					for t in range(2):
						out.append(Vector2i(c.x + sx * i, c.y + sy * t))
						out.append(Vector2i(c.x + sx * t, c.y + sy * i))
			out.append_array(_dot())
	return out

static func _ring(r0: float, r1: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(SIZE):
		for x in range(SIZE):
			var d := Vector2(x - 16, y - 16).length()
			if d >= r0 and d <= r1:
				out.append(Vector2i(x, y))
	return out

static func _dot() -> Array[Vector2i]:
	var out: Array[Vector2i] = [Vector2i(15, 15), Vector2i(16, 15), Vector2i(15, 16), Vector2i(16, 16)]
	return out
