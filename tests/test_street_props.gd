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


## The complaint that started D-029: lamps stood at the kerb, and a lamp is
## four cells tall with an arm over the carriageway, so every light hung in
## the middle of the road.
func test_no_lamp_or_hydrant_ever_stands_at_the_kerb() -> void:
	var map := _map()
	for y in map.size.y:
		for x in map.size.x:
			var cell := Vector2i(x, y)
			var kind := StreetProps.kind_at(map, cell)
			if kind == "lamp" or kind == "hydrant":
				assert_false(StreetProps.touches_road(map, cell),
					"%s is at the kerb, not the back of the pavement" % cell)
				assert_true(StreetProps.is_back_of_pavement(map, cell), "%s" % cell)
			if kind != "":
				assert_true(StreetProps.has_headroom(map, cell, kind),
					"a %s at %s reaches out over the road" % [kind, cell])


## A lamp is four cells tall and drawn rising up the screen, so the pavement
## on the near side of a carriageway cannot hold one wherever it stands.
func test_a_lamp_never_leans_over_the_carriageway() -> void:
	var map := _map()
	assert_true(StreetProps.is_back_of_pavement(map, Vector2i(9, 11)), "row 11 is the far pavement")
	assert_false(StreetProps.has_headroom(map, Vector2i(9, 11), "lamp"),
		"a lamp here would stand in the road it is meant to light")
	assert_ne(StreetProps.kind_at(map, Vector2i(9, 11)), "lamp")
	assert_true(StreetProps.has_headroom(map, Vector2i(9, 11), "hydrant"),
		"a hydrant is short enough to stand there")


func test_lamps_repeat_at_a_regular_interval_along_a_street() -> void:
	var map := _map()
	var lit: Array[int] = []
	for x in map.size.x:
		if StreetProps.kind_at(map, Vector2i(x, 6)) == "lamp":
			lit.append(x)
	assert_gt(float(lit.size()), 2.0, "one street, several lamps")
	for i in range(1, lit.size()):
		assert_eq(lit[i] - lit[i - 1], StreetProps.LAMP_SPACING,
			"lamps at x=%d and x=%d are not one interval apart" % [lit[i - 1], lit[i]])


func test_a_bin_stands_beside_a_door_and_never_in_front_of_it() -> void:
	var map := _map()
	var door: Vector2i = map.buildings["loc_corner_shop"]["door"]
	var beside := door + Vector2i(StreetProps.TRASH_OFFSET, 1)
	assert_eq(StreetProps.kind_at(map, beside), "trash", "a bin stands along the pavement from the door")
	assert_eq(StreetProps.kind_at(map, map.anchor_of("loc_corner_shop")), "",
		"the cell someone must stand on to use the door stays clear")


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
