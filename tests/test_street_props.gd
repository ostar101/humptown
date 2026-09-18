extends TestCase
## StreetProps: where decorative lamps, trash cans and hydrants are allowed to
## stand (D-022). Purely deterministic placement logic; the sprites
## themselves are checked visually, not by these tests.

const T := DistrictMap.Terrain


func _map() -> DistrictMap:
	var built := DistrictMap.from_data({
		"id": "test_props_map",
		"region": "harbourside",
		"width": 20,
		"height": 20,
		"fill": "grass",
		"spawn": [1, 1],
		"areas": [
			{"terrain": "road", "rect": [0, 8, 20, 2]},
			{"terrain": "pavement", "rect": [0, 10, 20, 2]},
		],
		"buildings": [
			{"location": "loc_corner_shop", "rect": [4, 4, 6, 6], "door": [6, 9]},
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


func test_props_only_stand_on_pavement_next_to_a_road_and_off_any_structure() -> void:
	if not StreetProps.available():
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	var map := _map()
	var props := StreetProps.props_in(map, Rect2i(Vector2i.ZERO, map.size))
	assert_gt(float(props.size()), 0.0, "20 cells of road-side pavement should show at least one prop")
	for prop: Dictionary in props:
		var cell: Vector2i = prop["cell"]
		assert_eq(map.ground_at(cell), T.PAVEMENT, "%s stands on pavement" % cell)
		assert_eq(map.structure_at(cell), T.NONE, "%s does not overlap a building" % cell)
		assert_true(FileAccess.file_exists(str(prop["file"])) or ResourceLoader.exists(prop["file"]), prop["file"])


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
