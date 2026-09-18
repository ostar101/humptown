extends TestCase
## RegionTiles: which (terrain, variant, theme) cells use a real LimeZu tile,
## and that the atlas builds correctly whether or not the art is installed
## (D-019/D-021/D-022). `test_region_map.gd` covers the atlas's collision and
## drawing contract; this file covers the real-art seam and theming.

const T := DistrictMap.Terrain


func test_curated_terrains_have_a_real_file_for_every_variant() -> void:
	var curated: Array[DistrictMap.Terrain] = [
		T.PAVEMENT, T.ROAD, T.ROAD_LINE, T.FLOOR, T.WALL, T.ROOF,
	]
	for terrain in curated:
		for v in RegionTiles.VARIANTS:
			var path: String = RegionTiles._real_file(terrain, v)
			assert_ne(path, "", "%s variant %d has a real tile" % [terrain, v])
			assert_true(path.begins_with(RegionTiles.REAL_DIR), path)


func test_uncurated_terrains_have_no_real_file() -> void:
	# Ground terrain LimeZu draws as edge-aware autotiles doesn't fit this
	# atlas's per-cell-random-variant model; see DECISIONS.md D-021.
	for terrain in [T.GRASS, T.WATER, T.SAND, T.DOCK, T.DOOR, T.COUNTER, T.SHELF, T.BED, T.TABLE, T.SIGN]:
		for v in RegionTiles.VARIANTS:
			assert_eq(RegionTiles._real_file(terrain, v), "", "%s stays code-painted" % terrain)


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
