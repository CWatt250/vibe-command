extends SceneTree
## test_cursors.gd — p4-05: Cursors.cursor_for() priority table + procedural cursor images.
## Headless: `godot-4 --headless --path . --script tests/test_cursors.gd`

var failures: int = 0

func _init() -> void:
	# --- rules: one context per row of the ticket's priority table ---
	var base := {"ui": false, "armed": "", "has_selection": true, "hover_own": false,
		"hover_enemy": false, "fog": 2, "walkable": true}
	_rule(base, "move", "selection over walkable visible ground -> move")
	_rule(_with(base, {"has_selection": false}), "arrow", "no selection over ground -> arrow")
	_rule(_with(base, {"hover_own": true}), "select", "own unit -> select")
	_rule(_with(base, {"hover_own": true, "has_selection": false}), "select", "own unit, nothing selected -> select")
	_rule(_with(base, {"hover_enemy": true}), "attack", "visible enemy with a selection -> attack")
	_rule(_with(base, {"hover_enemy": true, "has_selection": false}), "arrow", "enemy but nothing selected -> arrow")
	_rule(_with(base, {"walkable": false}), "invalid", "blocked cell -> invalid")
	_rule(_with(base, {"fog": 0}), "invalid", "unexplored fog -> invalid")
	_rule(_with(base, {"fog": 1}), "move", "explored (dim) fog is still orderable -> move")
	_rule(_with(base, {"armed": "attack", "walkable": false, "fog": 0}), "attack", "A armed -> attack anywhere")
	_rule(_with(base, {"armed": "attack", "hover_own": true}), "attack", "A armed beats own-unit select")
	_rule(_with(base, {"ui": true, "hover_enemy": true, "armed": "attack"}), "arrow", "over HUD/minimap -> arrow beats everything")
	_rule({}, "arrow", "empty context -> arrow")

	# --- images: 32x32, opaque centre and hotspot, drawn but not a blob, distinct shape slots ---
	var slots := {}
	for n in Cursors.NAMES:
		var img: Image = Cursors.build(n)
		_check(img.get_size() == Vector2i(32, 32), "%s is 32x32" % n)
		_check(img.get_pixel(16, 16).a > 0.99, "%s centre pixel is opaque" % n)
		var hs: Vector2 = Cursors.HOTSPOT[n]
		_check(img.get_pixel(int(hs.x), int(hs.y)).a > 0.99, "%s hotspot pixel is opaque" % n)
		var opaque := 0
		for y in range(32):
			for x in range(32):
				if img.get_pixel(x, y).a > 0.5:
					opaque += 1
		_check(opaque >= 60 and opaque <= 700, "%s draws a shape, not a blob (%d opaque px)" % [n, opaque])
		slots[Cursors.SHAPE[n]] = true
	_check(slots.size() == Cursors.NAMES.size(), "each cursor owns its own Input.CursorShape slot")
	var arrow := Cursors.build("arrow")
	_check(arrow.get_pixel(2, 2).a < 0.01, "nothing above-left of the arrow tip (hotspot is the tip)")

	# --- apply() is idempotent state; Input calls are no-ops headless ---
	var c := Cursors.new()
	c.install()
	_check(c.current() == "arrow", "install() starts on arrow")
	c.apply("attack")
	_check(c.current() == "attack", "apply() switches")
	c.apply("attack")
	_check(c.current() == "attack", "apply() with the same name is a no-op")

	if failures == 0:
		print("CURSORS_RESULT: ALL PASS")
	else:
		print("CURSORS_RESULT: %d FAILURE(S)" % failures)
	quit()

func _rule(ctx: Dictionary, expected: String, msg: String) -> void:
	var got := Cursors.cursor_for(ctx)
	_check(got == expected, "%s (got %s)" % [msg, got])

func _with(base: Dictionary, over: Dictionary) -> Dictionary:
	var d := base.duplicate()
	for k in over:
		d[k] = over[k]
	return d

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: " + msg)
	else:
		_fail(msg)

func _fail(msg: String) -> void:
	failures += 1
	push_error("FAIL: " + msg)
	print("FAIL: " + msg)
