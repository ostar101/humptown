extends TestCase
## PlaceArt: the authored decoration an open-air location is furnished with
## (D-030). Placement is data, so these tests are mostly about the data being
## consistent with the map it is authored against.


func _world() -> WorldState:
	var data := DataRegistry.new()
	data.load_all()
	var world := WorldState.new()
	world.build_from(data)
	return world


func _map() -> DistrictMap:
	return _world().map_for("harbourside")


## Every district's map: places are furnished in all of them (D-072).
func _maps() -> Array[DistrictMap]:
	var out: Array[DistrictMap] = []
	var world := _world()
	for region_id: String in world.maps:
		out.append(world.map_for(region_id))
	return out


func test_a_location_with_nothing_authored_gets_nothing() -> void:
	var map := _map()
	for location_id in ["loc_dock_street", "loc_harbour", "loc_not_a_place", ""]:
		assert_eq(PlaceArt.decorations_for(map, location_id).size(), 0, location_id)


func test_every_authored_place_is_actually_on_a_map() -> void:
	var maps := _maps()
	var found := 0
	for location_id in PlaceArt.DECORATIONS:
		var on_some_map := false
		for map in maps:
			on_some_map = on_some_map or map.places.has(location_id)
		assert_true(on_some_map, "%s is furnished but has no place on any map" % location_id)
	for map in maps:
		found += PlaceArt.decorated_places(map).size()
	assert_eq(found, PlaceArt.DECORATIONS.size())


## The reason this is worth a test: an offset is authored by hand against a
## rect authored by hand in another file, and nothing else would notice a
## tree hanging off the end of its park.
func test_no_decoration_hangs_outside_its_own_place() -> void:
	var checked := 0
	for map in _maps():
		for location_id in PlaceArt.decorated_places(map):
			var rect: Rect2i = map.places[location_id]["rects"][0]
			for piece: Dictionary in PlaceArt.decorations_for(map, location_id):
				var texture: Texture2D = load(piece["file"])
				var cells := Vector2i(texture.get_size()) / RegionTiles.TILE
				var covered := Rect2i(piece["cell"], cells)
				assert_true(rect.encloses(covered),
					"%s: %s covers %s, outside its place %s" % [location_id, piece["file"], covered, rect])
				checked += 1
	if checked == 0:
		assert_true(true, "art not installed on this machine; nothing to check")


## D-073: a tree stands on grass, never on paving. Where a tree is wanted on a
## paved square the map lays a patch of grass under it.
func test_trees_stand_on_grass_not_paving() -> void:
	var checked := 0
	for map in _maps():
		for location_id in PlaceArt.decorated_places(map):
			for piece: Dictionary in PlaceArt.decorations_for(map, location_id):
				if not str(piece["file"]).get_file().begins_with("tree_"):
					continue
				var texture: Texture2D = load(piece["file"])
				var cells := Vector2i(texture.get_size()) / RegionTiles.TILE
				for y in range(cells.y):
					for x in range(cells.x):
						var cell: Vector2i = (piece["cell"] as Vector2i) + Vector2i(x, y)
						assert_eq(map.ground_at(cell), DistrictMap.Terrain.GRASS,
							"%s: a tree at %s stands on %s" % [location_id, piece["cell"], cell])
						checked += 1
	if checked == 0:
		assert_true(true, "art not installed on this machine; nothing to check")


func test_the_court_is_flat_ground_and_a_tree_is_not() -> void:
	var map := _map()
	var court := PlaceArt.decorations_for(map, "loc_court")
	if court.is_empty():
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	assert_true(bool(court[0]["flat"]), "a painted court surface is ground, not an object")
	for piece: Dictionary in PlaceArt.decorations_for(map, "loc_harbour_park"):
		assert_false(bool(piece["flat"]), "a tree is an object people walk behind")


func test_a_decorated_place_stays_walkable() -> void:
	for map in _maps():
		for location_id in PlaceArt.decorated_places(map):
			var rect: Rect2i = map.places[location_id]["rects"][0]
			assert_false(map.is_blocked(rect.get_center()),
				"%s is decoration, not a building — it must stay walkable" % location_id)


func test_region_view_draws_the_authored_pieces() -> void:
	var map := _map()
	var view := RegionView.new()
	view.show_map(map)
	var expected := 0
	for location_id in PlaceArt.decorated_places(map):
		expected += PlaceArt.decorations_for(map, location_id).size()
	var drawn := 0
	for sprite in view._overlays:
		if str(sprite.name).begins_with("Place_"):
			drawn += 1
	assert_eq(drawn, expected)
	view.clear()
	view.free()
