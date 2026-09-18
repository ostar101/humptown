extends TestCase
## RegionTiles: which (terrain, variant, theme) cells use a real LimeZu tile,
## and that the atlas builds correctly whether or not the art is installed
## (D-019/D-021/D-022). `test_region_map.gd` covers the atlas's collision and
## drawing contract; this file covers the real-art seam and theming.

const T := DistrictMap.Terrain


func test_curated_terrains_have_a_real_file_for_every_variant() -> void:
	var curated: Array[DistrictMap.Terrain] = [
		T.PAVEMENT, T.ROAD, T.ROAD_LINE, T.FLOOR, T.WALL, T.ROOF, T.GRASS, T.SAND, T.DOCK,
	]
	for terrain in curated:
		for v in RegionTiles.VARIANTS:
			var path: String = RegionTiles._real_file(terrain, v)
			assert_ne(path, "", "%s variant %d has a real tile" % [terrain, v])
			assert_true(path.begins_with(RegionTiles.REAL_DIR) or path.begins_with(RegionTiles.TERRAIN_DIR),
				"%s comes from one of the two import folders: %s" % [terrain, path])


func test_uncurated_terrains_have_no_real_file() -> void:
	# Interior objects are still code-painted (D-021). Water is not listed here
	# because it has no plain tile at all: every water cell comes from an edge
	# set instead, which is what lets it meet a shore and animate (D-031).
	for terrain in [T.WATER, T.DOOR, T.COUNTER, T.SHELF, T.BED, T.TABLE, T.SIGN]:
		for v in RegionTiles.VARIANTS:
			assert_eq(RegionTiles._real_file(terrain, v), "", "%s has no plain real tile" % terrain)


func test_wall_variants_share_one_file_per_theme() -> void:
	for theme in ["", "shop", "bar", "civic"]:
		var upper: String = RegionTiles._real_file(T.WALL, RegionTiles.WALL_UPPER, theme)
		var window: String = RegionTiles._real_file(T.WALL, RegionTiles.WALL_UPPER_WINDOW, theme)
		var lower: String = RegionTiles._real_file(T.WALL, RegionTiles.WALL_LOWER, theme)
		var top: String = RegionTiles._real_file(T.WALL, RegionTiles.WALL_TOP, theme)
		assert_eq(upper, window, "the window is composited onto the wall, not a separate file")
		assert_eq(upper, lower, "the plinth is the wall tile, darkened in place")
		assert_eq(upper, top, "top-down is the wall tile, darkened in place")


func test_wall_and_roof_themes_are_distinct_files() -> void:
	var themes := ["", "shop", "bar", "civic"]
	var wall_files := {}
	var roof_files := {}
	for theme in themes:
		wall_files[theme] = RegionTiles._real_file(T.WALL, RegionTiles.WALL_UPPER, theme)
		roof_files[theme] = RegionTiles._real_file(T.ROOF, 0, theme)
	var distinct_walls := {}
	for f in wall_files.values():
		distinct_walls[f] = true
	assert_eq(distinct_walls.size(), themes.size(), "each theme's wall is a different file")
	# "bar" reuses "home"'s roof on purpose (D-022); every other pair differs.
	assert_eq(roof_files[""], roof_files["bar"], "bar reuses the home roof colour")
	assert_ne(roof_files[""], roof_files["shop"])
	assert_ne(roof_files[""], roof_files["civic"])
	assert_ne(roof_files["shop"], roof_files["civic"])


func test_unknown_kind_falls_back_to_the_plain_row() -> void:
	assert_eq(RegionTiles._row_for(T.WALL, ""), int(T.WALL))
	assert_eq(RegionTiles._row_for(T.ROOF, ""), int(T.ROOF))


func test_themed_rows_round_trip_terrain_and_theme() -> void:
	for entry in RegionTiles.THEMED_ROWS:
		var terrain: DistrictMap.Terrain = entry[0]
		var theme: String = entry[1]
		var row := RegionTiles._row_for(terrain, theme)
		assert_gt(float(row), float(DistrictMap.Terrain.size() - 2), "themed rows come after the plain ones")
		assert_eq(RegionTiles._terrain_for_row(row), terrain)
		assert_eq(RegionTiles._theme_for_row(row), theme)


func test_door_variant_differs_by_theme_and_home_is_variant_zero() -> void:
	assert_eq(RegionTiles.DOOR_VARIANT_BY_THEME.get("", 0), 0, "home has no entry; the default is 0")
	var seen := {0: true}
	for theme in RegionTiles.DOOR_VARIANT_BY_THEME:
		var v: int = RegionTiles.DOOR_VARIANT_BY_THEME[theme]
		assert_false(seen.has(v), "variant %d used twice" % v)
		seen[v] = true


func test_roof_eave_points_at_the_eave_file() -> void:
	for theme in ["", "shop", "bar", "civic"]:
		var eave: String = RegionTiles._real_file(T.ROOF, RegionTiles.ROOF_EAVE, theme)
		assert_true(eave.ends_with("_eave.png"), eave)
		for v in RegionTiles.VARIANTS:
			if v != RegionTiles.ROOF_EAVE:
				assert_false(RegionTiles._real_file(T.ROOF, v, theme).ends_with("_eave.png"))


func test_darken_only_lowers_brightness() -> void:
	var img := Image.create(RegionTiles.TILE, RegionTiles.TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color("d9cdb4"))
	var before := img.get_pixel(4, 4)
	RegionTiles._darken(img, Vector2i.ZERO, 0.55)
	var after := img.get_pixel(4, 4)
	assert_lt(after.v, before.v, "darkened lowers value")
	assert_almost(after.a, before.a, 0.001, "alpha is unchanged")


func test_atlas_has_a_row_per_plain_terrain_plus_one_per_themed_pair() -> void:
	# The seam only changes which pixels a cell gets, never that a cell exists
	# — test_region_map.gd exercises the drawing/collision contract itself.
	var source: TileSetAtlasSource = RegionTiles.tile_set().get_source(RegionTiles.SOURCE_ID)
	var expected_rows := DistrictMap.Terrain.size() - 1 + RegionTiles.THEMED_ROWS.size()
	assert_eq(expected_rows, RegionTiles._total_rows())
	# Plus the trailing transparent-but-solid row a whole-building sprite
	# covers its own cells with (D-028).
	assert_eq(source.get_atlas_grid_size(), Vector2i(RegionTiles.VARIANTS, expected_rows + 1))
	assert_eq(RegionTiles.hidden_coords(), Vector2i(0, expected_rows))


func test_a_themed_buildings_wall_and_door_differ_from_a_plain_one() -> void:
	# Deliberately not the authored map: every building there is exactly the
	# size of a whole-building sprite, and a covered building draws no per-cell
	# tiles at all (D-028). Theming is what a building of any *other* size
	# still gets — and what every building gets without the art installed.
	var built := DistrictMap.from_data({
		"id": "themed", "region": "harbourside", "width": 20, "height": 12,
		"fill": "grass", "spawn": [1, 11],
		"buildings": [
			{"location": "loc_shop", "rect": [2, 2, 4, 6], "door": [3, 7]},
			{"location": "loc_home", "rect": [10, 2, 4, 6], "door": [11, 7]},
		],
	})
	assert_ok(built)
	var map: DistrictMap = built.value
	map.building_kind = {"loc_shop": "shop", "loc_home": "home"}
	var shop_door: Vector2i = map.buildings["loc_shop"]["door"]
	var home_door: Vector2i = map.buildings["loc_home"]["door"]
	assert_false(BuildingArt.covers(map, shop_door), "this building is the wrong size for whole art")
	assert_eq(map.kind_at(shop_door), "shop")
	assert_eq(map.kind_at(home_door), "home")
	var shop_wall := RegionTiles.coords_for(map, shop_door + Vector2i.UP, true)
	var home_wall := RegionTiles.coords_for(map, home_door + Vector2i.UP, true)
	assert_ne(shop_wall.y, home_wall.y, "different themes land on different atlas rows")
	var shop_door_coords := RegionTiles.coords_for(map, shop_door, true)
	var home_door_coords := RegionTiles.coords_for(map, home_door, true)
	assert_eq(home_door_coords.x, 0, "an unthemed kind still draws the default door")
	assert_ne(shop_door_coords.x, home_door_coords.x, "a themed kind draws a different door variant")


# --- edge sets (D-031) -------------------------------------------------------

func _coast() -> DistrictMap:
	# Sand along the top, the sea below it, and a road with pavement either
	# side: both edge sets on one small map.
	var built := DistrictMap.from_data({
		"id": "coast", "region": "harbourside", "width": 12, "height": 14,
		"fill": "grass", "spawn": [1, 1],
		"areas": [
			{"terrain": "pavement", "rect": [0, 2, 12, 1]},
			{"terrain": "road", "rect": [0, 3, 12, 3]},
			{"terrain": "road_line", "rect": [0, 4, 12, 1]},
			{"terrain": "pavement", "rect": [0, 6, 12, 1]},
			{"terrain": "sand", "rect": [0, 8, 12, 2]},
			{"terrain": "water", "rect": [0, 10, 12, 4]},
			{"terrain": "dock", "rect": [8, 8, 4, 2]},
		],
	})
	assert_ok(built)
	return built.value


func test_every_edge_set_is_a_four_by_four_block() -> void:
	for entry in RegionTiles.EDGE_SETS:
		var path: String = RegionTiles.TERRAIN_DIR + str(entry["file"])
		if not ResourceLoader.exists(path):
			continue
		var texture: Texture2D = load(path)
		var cells := Vector2i(texture.get_size()) / RegionTiles.TILE
		assert_eq(cells.y, RegionTiles.EDGE_BLOCK, "%s is not four rows tall" % entry["id"])
		assert_eq(cells.x, RegionTiles.EDGE_BLOCK * int(entry["frames"]),
			"%s does not hold %s blocks side by side" % [entry["id"], entry["frames"]])


func test_a_shore_cell_draws_its_edge_and_open_water_does_not() -> void:
	var map := _coast()
	if RegionTiles.edge_set_for(map, Vector2i(2, 10), T.WATER) < 0:
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	# Row 10 is the first row of sea: sand above it, water below.
	assert_eq(RegionTiles.edge_coords(map, Vector2i(2, 10), T.WATER).y, 0, "the shore is the block's top row")
	# Row 12 has water on every side, so it is open sea.
	var open := RegionTiles.edge_coords(map, Vector2i(2, 12), T.WATER)
	assert_true(open.y == 1 or open.y == 2, "open water uses an interior row, got %s" % open)
	assert_true(open.x == 1 or open.x == 2, "open water uses an interior column, got %s" % open)


func test_the_sea_runs_off_the_edge_of_the_world_rather_than_ending() -> void:
	var map := _coast()
	if RegionTiles.edge_set_for(map, Vector2i(0, 13), T.WATER) < 0:
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	# Bottom-left corner: out of bounds on two sides, water on the others.
	var corner := RegionTiles.edge_coords(map, Vector2i(0, 13), T.WATER)
	assert_true(corner.x == 1 or corner.x == 2, "no shore against the map's west edge")
	assert_true(corner.y == 1 or corner.y == 2, "no shore against the map's south edge")


func test_water_picks_the_quay_set_where_it_meets_the_dock() -> void:
	var map := _coast()
	var beside_sand := RegionTiles.edge_set_for(map, Vector2i(2, 10), T.WATER)
	var beside_dock := RegionTiles.edge_set_for(map, Vector2i(9, 10), T.WATER)
	if beside_sand < 0:
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	assert_ne(beside_sand, beside_dock, "the sea meets a beach and a quay differently")
	assert_eq(str(RegionTiles.EDGE_SETS[beside_dock]["id"]), "water_dock")


func test_a_road_gets_a_kerb_where_the_pavement_is_and_not_in_its_middle() -> void:
	var map := _coast()
	if RegionTiles.edge_set_for(map, Vector2i(5, 3), T.ROAD) < 0:
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	assert_eq(RegionTiles.edge_coords(map, Vector2i(5, 3), T.ROAD).y, 0, "kerb along the road's north side")
	assert_eq(RegionTiles.edge_coords(map, Vector2i(5, 5), T.ROAD).y, 3, "kerb along the road's south side")
	# Row 4 is the centre line: still road as far as the kerb is concerned, so
	# the rows either side of it must read as interior, not as another edge.
	var middle := RegionTiles.edge_coords(map, Vector2i(5, 4), T.ROAD)
	assert_true(middle.y == 1 or middle.y == 2, "the middle of a road has no kerb, got %s" % middle)


func test_ground_tile_names_the_edge_source_for_water_and_the_atlas_otherwise() -> void:
	var map := _coast()
	var pavement := RegionTiles.ground_tile(map, Vector2i(5, 2))
	assert_eq(pavement.x, RegionTiles.SOURCE_ID, "pavement comes from the procedural atlas")
	var sea := RegionTiles.ground_tile(map, Vector2i(5, 12))
	if RegionTiles.edge_set_for(map, Vector2i(5, 12), T.WATER) < 0:
		assert_eq(sea.x, RegionTiles.SOURCE_ID, "art not installed; water falls back to the atlas")
		return
	assert_gt(float(sea.x), float(RegionTiles.SOURCE_ID), "water comes from its own source")
	var source: TileSetAtlasSource = RegionTiles.tile_set().get_source(sea.x)
	assert_true(source.has_tile(Vector2i(sea.y, sea.z)), "the tile that cell asks for exists")


func test_the_sea_is_animated_and_the_kerb_is_not() -> void:
	var tiles := RegionTiles.tile_set()
	for i in RegionTiles.EDGE_SETS.size():
		var entry: Dictionary = RegionTiles.EDGE_SETS[i]
		var id := RegionTiles.EDGE_SOURCE_FIRST + i
		if not tiles.has_source(id):
			continue
		var source: TileSetAtlasSource = tiles.get_source(id)
		var frames := int(entry["frames"])
		assert_eq(source.get_tile_animation_frames_count(Vector2i.ZERO), frames,
			"%s animation frames" % entry["id"])
		if frames > 1:
			assert_almost(source.get_tile_animation_total_duration(Vector2i.ZERO),
				frames * RegionTiles.EDGE_FRAME_SECONDS, 0.001, "%s runs for a full loop" % entry["id"])
			assert_eq(source.get_tile_animation_separation(Vector2i.ZERO),
				Vector2i(RegionTiles.EDGE_BLOCK - 1, 0), "frames sit one block apart in the sheet")


func test_water_still_blocks_whichever_source_draws_it() -> void:
	var map := _coast()
	assert_true(map.is_blocked(Vector2i(5, 12)), "the sea is not walkable")
	var sea := RegionTiles.ground_tile(map, Vector2i(5, 12))
	var source: TileSetAtlasSource = RegionTiles.tile_set().get_source(sea.x)
	var data := source.get_tile_data(Vector2i(sea.y, sea.z), 0)
	assert_gt(float(data.get_collision_polygons_count(0)), 0.0, "water tiles carry collision")
