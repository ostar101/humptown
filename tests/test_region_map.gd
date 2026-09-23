extends TestCase
## DistrictMap, ChunkStreamer and RegionView: the region you can see.

const T := DistrictMap.Terrain


func _small_map(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "test_map",
		"region": "harbourside",
		"width": 40,
		"height": 20,
		"fill": "grass",
		"spawn": [1, 1],
		"areas": [
			{"terrain": "water", "rect": [0, 16, 40, 4]},
			{"terrain": "pavement", "rect": [0, 10, 40, 2]},
		],
		"buildings": [
			{"location": "loc_corner_shop", "rect": [4, 4, 6, 6], "door": [6, 9]},
		],
		"places": [
			{"location": "loc_dock_street", "rects": [[0, 10, 40, 2]]},
		],
		"exits": [{"to": "old_town", "rect": [39, 10, 1, 2]}],
	}
	d.merge(overrides, true)
	return d


func _build(overrides: Dictionary = {}) -> DistrictMap:
	var built := DistrictMap.from_data(_small_map(overrides))
	assert_ok(built)
	return built.value if built.ok else null


## A minimal interior, for mechanics (floors, objects) that only make sense
## inside a building. Mirrors test_interaction.gd's own _interior() helper.
func _small_interior(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "test_interior", "interior_of": "loc_t", "width": 6, "height": 6,
		"fill": "floor", "door": [3, 5],
	}
	d.merge(overrides, true)
	return d


# --- DistrictMap ------------------------------------------------------------

func test_areas_are_rasterised_in_order() -> void:
	var m := _build()
	assert_eq(m.ground_at(Vector2i(0, 0)), T.GRASS)
	assert_eq(m.ground_at(Vector2i(20, 10)), T.PAVEMENT)
	assert_eq(m.ground_at(Vector2i(20, 18)), T.WATER)


func test_building_is_roof_then_facade_with_a_door() -> void:
	var m := _build()
	assert_eq(m.structure_at(Vector2i(4, 4)), T.ROOF)
	assert_eq(m.structure_at(Vector2i(4, 7)), T.ROOF)
	assert_eq(m.structure_at(Vector2i(4, 8)), T.WALL)
	assert_eq(m.structure_at(Vector2i(4, 9)), T.WALL)
	assert_eq(m.structure_at(Vector2i(6, 9)), T.DOOR)
	assert_eq(m.structure_at(Vector2i(3, 4)), T.NONE)


func test_blocking_follows_water_structures_and_bounds() -> void:
	var m := _build()
	assert_false(m.is_blocked(Vector2i(1, 1)))
	assert_true(m.is_blocked(Vector2i(20, 18)), "water")
	assert_true(m.is_blocked(Vector2i(6, 9)), "door is solid until interaction exists")
	assert_true(m.is_blocked(Vector2i(-1, 0)), "out of bounds")
	assert_true(m.is_blocked(Vector2i(40, 0)), "out of bounds")


func test_location_lookup_prefers_the_building() -> void:
	var m := _build({"places": [{"location": "loc_dock_street", "rects": [[0, 0, 40, 12]]}]})
	assert_eq(m.location_at(Vector2i(5, 5)), "loc_corner_shop")
	assert_eq(m.location_at(Vector2i(20, 5)), "loc_dock_street")
	assert_eq(m.location_at(Vector2i(20, 14)), "")


func test_anchors_stand_in_front_of_doors_and_inside_places() -> void:
	var m := _build()
	assert_eq(m.anchor_of("loc_corner_shop"), Vector2i(6, 10))
	assert_false(m.is_blocked(m.anchor_of("loc_corner_shop")))
	assert_eq(m.location_at(m.anchor_of("loc_dock_street")), "loc_dock_street")
	assert_eq(m.anchor_of("loc_nowhere"), Vector2i(-1, -1))


func test_exits_are_found_by_cell() -> void:
	var m := _build()
	assert_eq(m.exit_at(Vector2i(39, 11)), "old_town")
	assert_eq(m.exit_at(Vector2i(38, 11)), "")


func test_reachability_stops_at_water_and_walls() -> void:
	var m := _build({"areas": [{"terrain": "water", "rect": [20, 0, 1, 20]}]})
	var reach := m.reachable_from(Vector2i(1, 1))
	assert_true(reach.has(Vector2i(19, 5)))
	assert_false(reach.has(Vector2i(21, 5)), "the channel cuts the map in two")
	assert_false(reach.has(Vector2i(5, 5)), "inside a building")


func test_chunk_grid_and_rects_clip_to_the_map() -> void:
	var m := _build()
	assert_eq(m.chunk_grid(), Vector2i(3, 2))
	assert_eq(m.chunk_rect(Vector2i(0, 0)), Rect2i(0, 0, 16, 16))
	assert_eq(m.chunk_rect(Vector2i(2, 1)), Rect2i(32, 16, 8, 4))
	assert_eq(DistrictMap.chunk_of(Vector2i(17, 3)), Vector2i(1, 0))
	assert_eq(DistrictMap.chunk_of(Vector2i(-1, 0)), Vector2i(-1, 0))


func test_refuses_a_door_that_is_not_on_the_front_row() -> void:
	var d := _small_map({"buildings": [
		{"location": "loc_corner_shop", "rect": [4, 4, 6, 6], "door": [6, 5]}]})
	assert_err(DistrictMap.from_data(d), "map_invalid")


func test_refuses_geometry_outside_the_map() -> void:
	assert_err(DistrictMap.from_data(_small_map({"areas": [
		{"terrain": "road", "rect": [30, 0, 20, 2]}]})), "map_invalid")
	assert_err(DistrictMap.from_data(_small_map({"buildings": [
		{"location": "x", "rect": [38, 4, 6, 6], "door": [40, 9]}]})), "map_invalid")


func test_refuses_unknown_terrain_and_a_blocked_spawn() -> void:
	assert_err(DistrictMap.from_data(_small_map({"areas": [
		{"terrain": "lava", "rect": [0, 0, 2, 2]}]})), "map_invalid")
	assert_err(DistrictMap.from_data(_small_map({"spawn": [5, 5]})), "map_invalid")
	assert_err(DistrictMap.from_data(_small_map({"width": 0})), "map_invalid")


func test_reports_every_problem_at_once() -> void:
	var result := DistrictMap.from_data(_small_map({
		"areas": [{"terrain": "lava", "rect": [0, 0, 2, 2]}],
		"spawn": [5, 5],
	}))
	assert_err(result, "map_invalid")
	assert_true(result.message.contains("lava"), result.message)
	assert_true(result.message.contains("spawn"), result.message)


func test_interior_floor_defaults_to_one_and_round_trips() -> void:
	var ground := DistrictMap.from_data(_small_interior())
	assert_ok(ground)
	assert_eq(ground.value.storey, 1)
	var upper := DistrictMap.from_data(_small_interior({"floor": 2}))
	assert_ok(upper)
	assert_eq(upper.value.storey, 2)
	assert_err(DistrictMap.from_data(_small_interior({"floor": 0})), "map_invalid")


func test_stairs_object_validates_like_an_atm() -> void:
	var solids := [{"kind": "table", "rect": [1, 2, 1, 1]}]
	assert_err(DistrictMap.from_data(_small_interior({
		"objects": [{"id": "o", "kind": "stairs", "cell": [2, 3]}],
	})), "map_invalid", "stairs need furniture under them, same as an atm")
	var built := DistrictMap.from_data(_small_interior({
		"solids": solids, "objects": [{"id": "obj_up", "kind": "stairs", "cell": [1, 2]}],
	}))
	assert_ok(built)
	assert_eq(built.value.object_at(Vector2i(1, 2))["kind"], "stairs")


# --- ChunkStreamer ----------------------------------------------------------

func test_streamer_loads_the_neighbourhood_nearest_first() -> void:
	var s := ChunkStreamer.new()
	s.configure(Vector2i(5, 5), 1)
	var diff := s.update(Vector2i(2, 2))
	var loaded: Array = diff["load"]
	assert_eq(loaded.size(), 9)
	assert_eq(loaded[0], Vector2i(2, 2), "focus chunk first")
	assert_eq((diff["unload"] as Array).size(), 0)


func test_streamer_clips_at_the_map_edge() -> void:
	var s := ChunkStreamer.new()
	s.configure(Vector2i(5, 5), 1)
	assert_eq((s.update(Vector2i(0, 0))["load"] as Array).size(), 4)


func test_streamer_same_chunk_is_a_no_op() -> void:
	var s := ChunkStreamer.new()
	s.configure(Vector2i(5, 5), 1)
	s.update(Vector2i(2, 2))
	var again := s.update(Vector2i(2, 2))
	assert_eq((again["load"] as Array).size(), 0)
	assert_eq((again["unload"] as Array).size(), 0)


func test_streamer_hysteresis_keeps_chunks_just_behind_you() -> void:
	var s := ChunkStreamer.new()
	s.configure(Vector2i(8, 8), 1, 1)
	s.update(Vector2i(2, 2))
	var step := s.update(Vector2i(3, 2))
	assert_eq((step["load"] as Array).size(), 3, "a new column ahead")
	assert_eq((step["unload"] as Array).size(), 0, "the column behind stays within the margin")
	assert_true(s.is_loaded(Vector2i(1, 2)))
	# Stepping back again loads nothing: it never left.
	assert_eq((s.update(Vector2i(2, 2))["load"] as Array).size(), 0)


func test_streamer_releases_chunks_beyond_the_margin() -> void:
	var s := ChunkStreamer.new()
	s.configure(Vector2i(8, 8), 1, 1)
	s.update(Vector2i(1, 1))
	var jump := s.update(Vector2i(5, 5))
	assert_eq((jump["unload"] as Array).size(), 9)
	assert_false(s.is_loaded(Vector2i(1, 1)))
	assert_eq(s.loaded_count(), 9)


func test_streamer_reset_hands_back_everything() -> void:
	var s := ChunkStreamer.new()
	s.configure(Vector2i(5, 5), 1)
	s.update(Vector2i(2, 2))
	assert_eq(s.reset().size(), 9)
	assert_eq(s.loaded_count(), 0)


# --- RegionView -------------------------------------------------------------

func test_view_populates_and_releases_chunk_nodes() -> void:
	var view := RegionView.new()
	view.load_radius = 1
	var shown: Array[Vector2i] = []
	var hidden: Array[Vector2i] = []
	view.chunk_shown.connect(func(c: Vector2i) -> void: shown.append(c))
	view.chunk_hidden.connect(func(c: Vector2i) -> void: hidden.append(c))

	var m := _build({"width": 80, "height": 20})
	view.show_map(m)
	assert_eq(view.resident_chunk_count(), 0, "nothing drawn before a focus")

	view.focus_on(RegionView.cell_to_world(Vector2i(1, 1)))
	assert_eq(view.resident_chunk_count(), 4)
	assert_eq(shown.size(), 4)
	var ground: TileMapLayer = view.chunk_node(Vector2i(0, 0)).get_node("Ground")
	var structures: TileMapLayer = view.chunk_node(Vector2i(0, 0)).get_node("Structures")
	assert_eq(ground.get_used_cells().size(), 256)
	assert_eq(structures.get_cell_atlas_coords(Vector2i(6, 9)).y, int(T.DOOR))
	assert_eq(structures.get_cell_source_id(Vector2i(1, 1)), -1, "no structure on open ground")

	view.focus_on(RegionView.cell_to_world(Vector2i(79, 1)))
	assert_false(view.is_chunk_resident(Vector2i(0, 0)))
	assert_eq(hidden.size(), 4)

	view.clear()
	assert_eq(view.resident_chunk_count(), 0)
	view.free()


func test_view_world_cell_conversion_round_trips() -> void:
	var cell := Vector2i(12, 7)
	assert_eq(RegionView.world_to_cell(RegionView.cell_to_world(cell)), cell)
	assert_eq(RegionView.world_to_cell(Vector2(-1.0, 5.0)), Vector2i(-1, 0))


func test_solid_tiles_carry_collision_and_open_ground_does_not() -> void:
	var source: TileSetAtlasSource = RegionTiles.tile_set().get_source(RegionTiles.SOURCE_ID)
	var wall := source.get_tile_data(Vector2i(0, int(T.WALL)), 0)
	var water := source.get_tile_data(Vector2i(1, int(T.WATER)), 0)
	var grass := source.get_tile_data(Vector2i(0, int(T.GRASS)), 0)
	assert_eq(wall.get_collision_polygons_count(0), 1)
	assert_eq(water.get_collision_polygons_count(0), 1)
	assert_eq(grass.get_collision_polygons_count(0), 0)


# --- authored content -------------------------------------------------------

func test_every_authored_map_builds() -> void:
	var data := DataRegistry.new()
	data.load_all()
	for id in data.ids("maps"):
		var built := DistrictMap.from_data(data.get_entry("maps", id))
		assert_ok(built, "map %s" % id)


func test_mapped_regions_place_every_location_and_reach_every_door() -> void:
	var data := DataRegistry.new()
	data.load_all()
	var world := WorldState.new()
	world.build_from(data)
	assert_not_null(world.map_for("harbourside"))
	for region_id in world.maps:
		var m := world.map_for(region_id)
		var reach := m.reachable_from(m.spawn)
		for loc_id in world.locations_in(region_id):
			assert_true(m.has_location(loc_id), "%s is not on the %s map" % [loc_id, region_id])
			assert_true(reach.has(m.anchor_of(loc_id)),
				"%s cannot be walked to from the spawn" % loc_id)
		for e in m.exits:
			var rect: Rect2i = e["rect"]
			assert_true(reach.has(rect.position), "exit to %s is unreachable" % e["to"])


func test_registry_refuses_a_map_placing_another_regions_location() -> void:
	var data := DataRegistry.new()
	data.load_all()
	var bad := _small_map({"id": "bad", "buildings": [
		{"location": "loc_pawn_shop", "rect": [4, 4, 6, 6], "door": [6, 9]}]})
	data.tables["maps"]["bad"] = bad
	var problems := data.validate_references()
	assert_eq(problems.size(), 1, "; ".join(problems))
	assert_true(problems[0].contains("another region"))


func test_registry_refuses_an_exit_to_nowhere() -> void:
	var data := DataRegistry.new()
	data.load_all()
	data.tables["maps"]["bad"] = _small_map({"id": "bad", "exits": [{"to": "atlantis", "rect": [0, 0, 1, 1]}]})
	var problems := data.validate_references()
	assert_eq(problems.size(), 1, "; ".join(problems))
