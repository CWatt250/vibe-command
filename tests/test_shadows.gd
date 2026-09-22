extends SceneTree
## test_shadows.gd — p3-01: EntityRenderer cast-shadow geometry (pure math, no drawing).
## Headless: `godot-4 --headless --path . --script tests/test_shadows.gd`

var failures: int = 0

func _init() -> void:
	var registry := ContentRegistry.new("res://content/data/")
	registry.load_all()
	var events := GameEvents.new()
	var sim := Simulation.new(registry, events, 50, 50)
	sim.add_player("VC")
	var r := EntityRenderer.new(sim, null)

	var inf: Entity = sim.entities[sim.spawn_unit("VC-U01", "VC", Vector2(1000, 1000))]
	var heavy: Entity = sim.entities[sim.spawn_unit("VC-U12", "VC", Vector2(1100, 1000))]
	var air: Entity = sim.entities[sim.spawn_unit("VC-U02", "VC", Vector2(1200, 1000))]
	var bld: Entity = sim.entities[sim.spawn_structure("VC-B03", "VC", Vector2(1000, 1200), true)]
	_check(inf.def_data.get("armorClass") == "Infantry" and heavy.def_data.get("armorClass") == "Heavy",
		"premise: VC-U01 Infantry, VC-U12 Heavy")
	_check(air.is_airborne and not inf.is_airborne, "premise: VC-U02 airborne, VC-U01 not")

	var g: Dictionary = EntityRenderer.SHADOW["ground"]
	var a: Dictionary = EntityRenderer.SHADOW["air"]

	# --- infantry: ellipse centred at position + ground offset, sized from UNIT_PX × atlas scale ---
	var inf_px: float = EntityRenderer.UNIT_PX["Infantry"] * SpriteAtlas.scale("VC-U01")
	var ri := r.shadow_rect(inf)
	_check(ri.get_center().is_equal_approx(inf.position + g["offset"]), "infantry shadow centre = position + ground offset")
	_check(is_equal_approx(ri.size.x, 2.0 * g["rx"] * inf_px) and is_equal_approx(ri.size.y, 2.0 * g["ry"] * inf_px),
		"infantry shadow size derives from UNIT_PX (%s)" % ri.size)
	_check(ri.size.y < ri.size.x, "ground shadow is a flattened ellipse")
	_check(g["offset"].x > 0.0 and g["offset"].y > 0.0, "ground shadow falls down-right")

	# --- Heavy vehicle: same rule, bigger sprite -> bigger shadow ---
	var heavy_px: float = EntityRenderer.UNIT_PX["Heavy"] * SpriteAtlas.scale("VC-U12")
	var rh := r.shadow_rect(heavy)
	_check(is_equal_approx(rh.size.x, 2.0 * g["rx"] * heavy_px), "heavy shadow width from UNIT_PX Heavy")
	_check(rh.size.x > ri.size.x, "heavy shadow wider than infantry shadow")

	# --- airborne: smaller, lighter, further offset ---
	var air_px: float = EntityRenderer.UNIT_PX["AirLight"] * SpriteAtlas.scale("VC-U02")
	var ra := r.shadow_rect(air)
	_check(ra.get_center().is_equal_approx(air.position + a["offset"]), "air shadow centre uses the air offset")
	_check(a["offset"].length() > g["offset"].length(), "air offset is further than ground offset")
	_check(ra.size.x < 2.0 * g["rx"] * air_px, "air shadow smaller than the ground rule would give")
	_check(a["alpha"] < g["alpha"], "air shadow lighter than ground shadow")

	# --- 2x2 structure: sheared footprint quad, down-right only ---
	var fp := r._footprint_rect(bld)
	_check(fp.size == Vector2(80, 80), "premise: VC-B03 footprint is 2x2 cells (%s)" % fp.size)
	var s: Dictionary = EntityRenderer.SHADOW["structure"]
	var off: Vector2 = s["offset"] * fp.size.y
	var q := r.structure_shadow_quad(bld)
	_check(q.size() == 4, "structure shadow is a quad")
	_check(q[3].is_equal_approx(Vector2(fp.position.x, fp.end.y) + off), "quad bottom-left = pad bottom-left + offset")
	_check(q[2].is_equal_approx(fp.end + off), "quad bottom-right = pad bottom-right + offset")
	_check(is_equal_approx(q[0].x - q[3].x, s["shear"] * fp.size.y), "top edge sheared right by shear × pad height")
	_check(is_equal_approx(q[0].y - fp.position.y, off.y), "top edge sits offset.y below the pad top")
	var rb := r.shadow_rect(bld)
	_check(rb.position.x >= fp.position.x and rb.position.y >= fp.position.y, "structure shadow never extends up/left of the pad")
	_check(is_equal_approx(rb.size.y, fp.size.y), "structure shadow height = pad height")

	r.free()   # Node2D never entered the tree; free it so quit() doesn't report a leaked CanvasItem
	if failures == 0:
		print("SHADOWS_RESULT: ALL PASS")
	else:
		print("SHADOWS_RESULT: %d FAILURE(S)" % failures)
	quit()

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: " + msg)
	else:
		_fail(msg)

func _fail(msg: String) -> void:
	failures += 1
	push_error("FAIL: " + msg)
	print("FAIL: " + msg)
