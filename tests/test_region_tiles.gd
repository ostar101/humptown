extends TestCase
## RegionTiles: which (terrain, variant) cells use a real LimeZu tile, and
## that the atlas builds correctly whether or not the art is installed
## (D-019/D-021). `test_region_map.gd` covers the atlas's collision and
## drawing contract; this file covers the real-art seam specifically.

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


func test_wall_variants_point_at_the_right_file() -> void:
	var upper: String = RegionTiles._real_file(T.WALL, RegionTiles.WALL_UPPER)
	var window: String = RegionTiles._real_file(T.WALL, RegionTiles.WALL_UPPER_WINDOW)
	var top: String = RegionTiles._real_file(T.WALL, RegionTiles.WALL_TOP)
	var lower: String = RegionTiles._real_file(T.WALL, RegionTiles.WALL_LOWER)
	assert_eq(upper, window, "the window is composited onto the upper wall, not a separate file")
	assert_eq(upper, top, "top-down is the upper wall, darkened in place")
	assert_ne(upper, lower, "the plinth is a different tile from the wall body")


func test_roof_eave_points_at_the_eave_file() -> void:
	var eave: String = RegionTiles._real_file(T.ROOF, RegionTiles.ROOF_EAVE)
	assert_true(eave.ends_with("roof_eave.png"))
	for v in RegionTiles.VARIANTS:
		if v != RegionTiles.ROOF_EAVE:
			assert_false(RegionTiles._real_file(T.ROOF, v).ends_with("eave.png"))


func test_darken_only_lowers_brightness() -> void:
	var img := Image.create(RegionTiles.TILE, RegionTiles.TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color("d9cdb4"))
	var before := img.get_pixel(4, 4)
	RegionTiles._darken(img, Vector2i.ZERO, 0.55)
	var after := img.get_pixel(4, 4)
	assert_lt(after.v, before.v, "darkened lowers value")
	assert_almost(after.a, before.a, 0.001, "alpha is unchanged")


func test_atlas_builds_the_same_shape_with_or_without_the_art() -> void:
	# The seam only changes which pixels a cell gets, never the atlas's shape
	# or which cells carry collision — RegionTiles.tile_set() is cached
	# per-run either way, so this just checks the contract test_region_map.gd
	# already exercises still holds when real files exist.
	var source: TileSetAtlasSource = RegionTiles.tile_set().get_source(RegionTiles.SOURCE_ID)
	var rows := DistrictMap.Terrain.size() - 1
	assert_eq(source.get_atlas_grid_size(), Vector2i(RegionTiles.VARIANTS, rows))
