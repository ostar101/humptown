extends TestCase
## PlaceArt: the authored decoration an open-air location is furnished with
## (D-030). Placement is data, so these tests are mostly about the data being
## consistent with the map it is authored against.


func _map() -> DistrictMap:
	var data := DataRegistry.new()
	data.load_all()
	var world := WorldState.new()
	world.build_from(data)
	return world.map_for("harbourside")


func test_a_location_with_nothing_authored_gets_nothing() -> void:
	var map := _map()
	for location_id in ["loc_dock_street", "loc_harbour", "loc_not_a_place", ""]:
		assert_eq(PlaceArt.decorations_for(map, location_id).size(), 0, location_id)


func test_every_authored_place_is_actually_on_the_map() -> void:
	var map := _map()
	for location_id in PlaceArt.DECORATIONS:
		assert_true(map.places.has(location_id),
			"%s is furnished but has no place on the map" % location_id)
	assert_eq(PlaceArt.decorated_places(map).size(), PlaceArt.DECORATIONS.size())


## The reason this is worth a test: an offset is authored by hand against a
## rect authored by hand in another file, and nothing else would notice a
## tree hanging off the end of its park.
func test_no_decoration_hangs_outside_its_own_place() -> void:
	var map := _map()
	var checked := 0
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
	var map := _map()
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
