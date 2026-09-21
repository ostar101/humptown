extends TestCase
## StreetProps: where decorative lamps, trash cans and hydrants are allowed to
## stand (D-022, D-029). Purely deterministic placement logic; the sprites
## themselves are checked visually, not by these tests.

const T := DistrictMap.Terrain


func _map() -> DistrictMap:
	var built := DistrictMap.from_data({
		"id": "test_props_map",
		"region": "harbourside",
		"width": 40,
		"height": 20,
		"fill": "grass",
		"spawn": [1, 15],
		# A street the way the district builds one: a shop fronting a pavement,
		# the carriageway, and a second pavement opposite.
		"areas": [
			{"terrain": "pavement", "rect": [0, 6, 40, 2]},
			{"terrain": "road", "rect": [0, 8, 40, 2]},
			{"terrain": "pavement", "rect": [0, 10, 40, 2]},
		],
		"buildings": [
			{"location": "loc_corner_shop", "rect": [4, 0, 6, 6], "door": [6, 5]},
		],
	})
	assert_ok(built)
	return built.value


func test_without_the_art_nothing_is_placed() -> void:
	if StreetProps.available():
		assert_true(true, "art is installed on this machine; covered by the placement tests below")
		return
	var map := _map()
	assert_eq(StreetProps.props_in(map, Rect2i(Vector2i.ZERO, map.size)).size(), 0)


func test_props_only_stand_on_pavement_and_off_any_structure() -> void:
	if not StreetProps.available():
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	var map := _map()
	var props := StreetProps.props_in(map, Rect2i(Vector2i.ZERO, map.size))
	assert_gt(float(props.size()), 0.0, "a lit street should show at least one prop")
	for prop: Dictionary in props:
		var cell: Vector2i = prop["cell"]
		assert_eq(map.ground_at(cell), T.PAVEMENT, "%s stands on pavement" % cell)
		assert_eq(map.structure_at(cell), T.NONE, "%s does not overlap a building" % cell)
		assert_true(ResourceLoader.exists(prop["file"]), prop["file"])


## D-066: a lamp stands on the pavement cell next to the road, and hydrants
## keep to the back of the pavement, off the pavement below a carriageway.
func test_a_lamp_stands_at_the_kerb_and_a_hydrant_at_the_back() -> void:
	var map := _map()
	var lamps := 0
	for y in map.size.y:
		for x in map.size.x:
			var cell := Vector2i(x, y)
			var kind := StreetProps.kind_at(map, cell)
			if kind == "lamp":
				lamps += 1
				assert_true(StreetProps.touches_road(map, cell), "%s is the pavement cell by the road" % cell)
			if kind == "hydrant":
				assert_true(StreetProps.is_back_of_pavement(map, cell), "%s" % cell)
				assert_true(StreetProps.has_headroom(map, cell, "hydrant"))
	assert_gt(float(lamps), 0.0)


func test_lamps_stand_on_both_sides_of_a_street() -> void:
	var map := _map()
	var near := 0
	var far := 0
	for x in map.size.x:
		near += 1 if StreetProps.kind_at(map, Vector2i(x, 7)) == "lamp" else 0
		far += 1 if StreetProps.kind_at(map, Vector2i(x, 10)) == "lamp" else 0
	assert_gt(float(near), 0.0, "the pavement above the road")
	assert_gt(float(far), 0.0, "the pavement below it")
	assert_eq(StreetProps.kind_at(map, Vector2i(9, 11)), "", "the back of the pavement gets no lamp")


## The art draws the head to the right of the pole, so with the road on its left
## a lamp is mirrored: the head is always on the road's side.
func test_a_lamp_beside_a_road_that_runs_down_the_screen_faces_the_road() -> void:
	var built := DistrictMap.from_data({
		"id": "test_props_vertical", "region": "harbourside", "width": 30, "height": 40,
		"fill": "grass", "spawn": [1, 1],
		"areas": [
			{"terrain": "pavement", "rect": [10, 0, 2, 40]},
			{"terrain": "road", "rect": [12, 0, 4, 40]},
			{"terrain": "pavement", "rect": [16, 0, 2, 40]},
		],
	})
	assert_ok(built)
	var map: DistrictMap = built.value
	assert_false(StreetProps.lamp_faces_left(map, Vector2i(11, 5)), "road on its right: head on the right")
	assert_true(StreetProps.lamp_faces_left(map, Vector2i(16, 5)), "road on its left: mirrored")
	if not StreetProps.available():
		return
	var west := 0
	var east := 0
	for prop: Dictionary in StreetProps.props_in(map, Rect2i(Vector2i.ZERO, map.size)):
		if prop["kind"] != "lamp":
			continue
		var cell: Vector2i = prop["cell"]
		assert_eq(prop["flip"], cell.x == 16, "%s" % cell)
		west += 1 if cell.x == 11 else 0
		east += 1 if cell.x == 16 else 0
	assert_gt(float(west), 0.0)
	assert_gt(float(east), 0.0)


func test_no_lamp_at_a_crossing_or_in_front_of_a_door() -> void:
	var built := DistrictMap.from_data({
		"id": "test_props_crossing", "region": "harbourside", "width": 40, "height": 40, "fill": "grass", "spawn": [1, 1],
		"areas": [
			{"terrain": "pavement", "rect": [0, 20, 40, 2]}, {"terrain": "road", "rect": [0, 22, 40, 2]},
			{"terrain": "pavement", "rect": [10, 0, 2, 20]}, {"terrain": "road", "rect": [12, 0, 4, 20]},
		],
		"buildings": [{"location": "loc_corner_shop", "rect": [20, 8, 6, 12], "door": [22, 19]}],
	})
	assert_ok(built)
	var map: DistrictMap = built.value
	for y in map.size.y:
		for x in map.size.x:
			var cell := Vector2i(x, y)
			if StreetProps.kind_at(map, cell) != "lamp":
				continue
			for dy in range(-StreetProps.CORNER_CLEARANCE, StreetProps.CORNER_CLEARANCE + 1):
				for dx in range(-StreetProps.CORNER_CLEARANCE, StreetProps.CORNER_CLEARANCE + 1):
					assert_false(StreetProps._is_corner(map, cell + Vector2i(dx, dy)), "lamp %s is at a crossing" % cell)
			assert_ne(cell.x, 22, "not straight in front of the door: %s" % cell)


## The pole's foot is a body the player cannot walk through; the rest of the
## lamp is drawn over the walker, as before.
func test_a_lamps_foot_collides() -> void:
	if not StreetProps.available():
		return
	var map := _map()
	var view := RegionView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	view.show_map(map)
	view.focus_on(DistrictMap.cell_to_world(Vector2i(20, 8)))
	var feet := 0
	for chunk_root: Node in view.get_children():
		for child in chunk_root.get_children():
			if child is Sprite2D and str((child as Sprite2D).texture.resource_path).ends_with("lamp.png"):
				var foot := child.get_node_or_null("Foot") as StaticBody2D
				assert_not_null(foot, "every lamp has a foot")
				if foot != null:
					feet += 1
					assert_eq(foot.collision_layer, RegionTiles.COLLISION_LAYER)
					var box := (foot.get_child(0) as CollisionShape2D).shape as RectangleShape2D
					assert_eq(box.size, StreetProps.LAMP_FOOT.size)
	assert_gt(float(feet), 0.0)
	view.free()


func test_lamps_repeat_at_a_regular_interval_along_a_street() -> void:
	var map := _map()
	var lit: Array[int] = []
	for x in map.size.x:
		if StreetProps.kind_at(map, Vector2i(x, 7)) == "lamp":
			lit.append(x)
	assert_gt(float(lit.size()), 2.0, "one street, several lamps")
	for i in range(1, lit.size()):
		assert_eq(lit[i] - lit[i - 1], StreetProps.LAMP_SPACING,
			"lamps at x=%d and x=%d are not one interval apart" % [lit[i - 1], lit[i]])


## D-068: a building's bin stands at the front corner away from its door.
func test_a_bin_stands_at_the_corner_away_from_the_door() -> void:
	var map := _map()
	var rect: Rect2i = map.buildings["loc_corner_shop"]["rect"]
	var door: Vector2i = map.buildings["loc_corner_shop"]["door"]
	var corner := StreetFurniture.bin_cell(map, "loc_corner_shop")
	assert_eq(corner, Vector2i(rect.end.x - 1, rect.end.y), "the door is in the left half, so the right corner")
	assert_eq(StreetProps.kind_at(map, corner), "trash")
	assert_true(map.furniture.has(corner))
	assert_gt(float(absi(corner.x - door.x)), 1.0, "well to one side of the door")
	assert_eq(StreetProps.kind_at(map, map.anchor_of("loc_corner_shop")), "",
		"the cell someone must stand on to use the door stays clear")


func test_bins_and_hydrants_block_their_cell() -> void:
	var map := _map()
	assert_false(map.furniture.is_empty())
	for cell: Vector2i in map.furniture:
		assert_true(map.is_blocked(cell), "%s" % cell)
		assert_eq(map.ground_at(cell), T.PAVEMENT)


## The real town: every building with pavement in front of it has its bin,
## none stands in front of a door, and no hydrant is near a door or a bin.
func test_the_real_streets_keep_doors_clear() -> void:
	var data := DataRegistry.new()
	data.load_all()
	var world := WorldState.new()
	world.build_from(data)
	var map := world.map_for("harbourside")
	var bins := 0
	for cell: Vector2i in map.furniture:
		var kind := str(map.furniture[cell]["kind"])
		for loc_id in map.buildings:
			var door: Vector2i = map.buildings[loc_id]["door"]
			assert_false(absi(cell.x - door.x) <= 1 and cell.y > door.y and cell.y <= door.y + 3,
				"%s at %s is in front of the door of %s" % [kind, cell, loc_id])
			if kind == "hydrant":
				assert_false(absi(cell.x - door.x) <= StreetFurniture.DOOR_CLEARANCE and cell.y > door.y and cell.y <= door.y + 4,
					"a hydrant at %s is near the door of %s" % [cell, loc_id])
		bins += 1 if kind == "trash" else 0
	for loc_id in map.buildings:
		assert_ne(StreetFurniture.bin_cell(map, loc_id), Vector2i(-1, -1), "%s has a bin" % loc_id)
	assert_eq(bins, map.buildings.size(), "one bin a building")


func test_placement_is_deterministic_across_calls() -> void:
	if not StreetProps.available():
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	var map := _map()
	var rect := Rect2i(Vector2i.ZERO, map.size)
	assert_eq(StreetProps.props_in(map, rect), StreetProps.props_in(map, rect), "same map, same result")


func test_pavement_away_from_any_road_gets_nothing() -> void:
	if not StreetProps.available():
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	var built := DistrictMap.from_data({
		"id": "test_props_no_road", "region": "harbourside", "width": 20, "height": 20,
		"fill": "grass", "spawn": [1, 1],
		"areas": [{"terrain": "pavement", "rect": [0, 10, 20, 2]}],
	})
	assert_ok(built)
	assert_eq(StreetProps.props_in(built.value, Rect2i(Vector2i.ZERO, built.value.size)).size(), 0)
