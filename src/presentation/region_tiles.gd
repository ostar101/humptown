class_name RegionTiles
extends RefCounted
## The tile set every region is drawn with, and the rule for which tile a map
## cell shows.
##
## Atlas layout: one row per DistrictMap.Terrain, VARIANTS columns per row,
## then the themed rows, then one transparent-but-solid row (`_hidden_row()`)
## for cells a whole-building sprite draws over.
## Each (terrain, variant) cell is either a real LimeZu tile (D-019/D-021) or,
## where none was curated, code-painted (D-014). `_real_file()` is the whole
## seam: it says which file a cell wants; `_build()` blits it in when present
## and falls back to `_paint()` otherwise, so the game and the tests run
## identically with or without the art installed. `coords_for()` (which cell a
## map position shows) does not change either way.
##
## Ground terrain (grass, water, sand, dock) has no real tiles yet: LimeZu's
## packs draw them as edge-aware autotiles (paths cutting through grass,
## shorelines), which this per-cell-random-variant atlas cannot place
## correctly without a neighbour-aware tiling pass. See DECISIONS.md D-021.
##
## A building's WALL, ROOF and DOOR cells look different by the location's
## `kind` (D-022): `THEME_BY_KIND` maps it to a theme name, and WALL/ROOF get
## extra atlas rows — one per (terrain, theme) pair, appended after the
## ordinary per-Terrain rows — holding that theme's tile at the same four
## columns (upper/window/plinth/top, body/body/body/eave). DOOR instead reuses
## its own row's otherwise-unused variants 1-3, since a door is always drawn
## at variant 0 today. A kind absent from `THEME_BY_KIND` (home, and anything
## unset) draws the plain row, so most homes need no extra art at all.

const TILE := DistrictMap.CELL_PIXELS
const VARIANTS := 4
const SOURCE_ID := 0
const COLLISION_LAYER := 1
const REAL_DIR := "res://art/vendor/limezu/tiles/"
const TERRAIN_DIR := "res://art/vendor/limezu/terrain/"

## Edge sets (D-031): a terrain's sixteen ways of meeting a different one, each
## in its own `TileSetAtlasSource` as a 4x4 block — column 0 its western edge,
## column 3 its eastern, row 0 its northern, row 3 its southern, and the four
## middle cells its open interior. `coords_for()`'s per-cell hash cannot do
## this: which tile a cell wants depends on its neighbours, not on itself.
##
## They live in their own sources rather than in the procedural atlas because
## of the sea: sixteen tiles times eight animation frames is 128 columns, and
## widening the shared atlas to 4096 px to hold them would push the texture to
## the limit of the hardware D-002 targets for the sake of one terrain.
##
## `frames` is LimeZu's own animation, whose frames sit one block apart in the
## sheet — `EDGE_BLOCK - 1` columns of separation, which is all Godot needs to
## play them. The order of this list fixes each set's source id: append, never
## reorder.
const EDGE_BLOCK := 4
const EDGE_SOURCE_FIRST := 1
const EDGE_FRAME_SECONDS := 0.4
const EDGE_SETS: Array[Dictionary] = [
	{"id": "water_sand", "file": "edge_water_sand.png", "frames": 8},
	{"id": "water_dock", "file": "edge_water_dock.png", "frames": 8},
	{"id": "road", "file": "edge_road.png", "frames": 1},
]

const NEIGHBOURS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

## location `kind` -> theme name. Kinds not listed draw the plain row.
const THEME_BY_KIND := {
	"shop": "shop",
	"bar": "bar",
	"civic": "civic",
	"work": "civic",   # the one "work" building is a warehouse; civic's grey fits
}
## (terrain, theme) pairs that get an extra atlas row, in the order they are
## appended. Order matters: it fixes each pair's row number.
const THEMED_ROWS: Array[Array] = [
	[DistrictMap.Terrain.WALL, "shop"], [DistrictMap.Terrain.WALL, "bar"], [DistrictMap.Terrain.WALL, "civic"],
	[DistrictMap.Terrain.ROOF, "shop"], [DistrictMap.Terrain.ROOF, "civic"],
]
## DOOR variant per theme, reusing that row's variants 1-3 (variant 0 stays
## the default/home door). A theme with no entry here still gets a themed
## wall and roof; a plain door is not worth a fourth variant slot per theme.
const DOOR_VARIANT_BY_THEME := {"shop": 1, "bar": 2, "civic": 3}

const SOLID := [
	DistrictMap.Terrain.WATER,
	DistrictMap.Terrain.ROOF,
	DistrictMap.Terrain.WALL,
	DistrictMap.Terrain.DOOR,
	DistrictMap.Terrain.COUNTER,
	DistrictMap.Terrain.SHELF,
	DistrictMap.Terrain.BED,
	DistrictMap.Terrain.TABLE,
	DistrictMap.Terrain.SIGN,
]

## Wall variants: the facade's upper row carries windows, the lower row a
## plinth. Chosen from the cell's neighbours in coords_for().
const WALL_UPPER := 0
const WALL_UPPER_WINDOW := 1
const WALL_LOWER := 2
## Indoors, the side and front walls are seen from above: just their tops.
const WALL_TOP := 3
## Roof variant for the eave row, which casts a shadow onto the facade.
const ROOF_EAVE := 3

static var _shared: TileSet = null


## Built once per run and shared by every RegionView.
static func tile_set() -> TileSet:
	if _shared == null:
		_shared = _build()
	return _shared


## Atlas coordinates for a layer of a cell. (-1, -1) means leave it empty.
static func coords_for(map: DistrictMap, cell: Vector2i, structure_layer: bool) -> Vector2i:
	var terrain := map.structure_at(cell) if structure_layer else map.ground_at(cell)
	if terrain == DistrictMap.Terrain.NONE:
		return Vector2i(-1, -1)
	if structure_layer and BuildingArt.covers(map, cell):
		return hidden_coords()
	var variant := _hash(cell) % VARIANTS
	# Interiors have no `buildings` entry for themselves, so kind_at() (and
	# therefore theme) is always "" there: an interior never themes its own
	# walls, with no special case needed for it here.
	var theme: String = THEME_BY_KIND.get(map.kind_at(cell), "")
	match terrain:
		DistrictMap.Terrain.ROOF:
			var below := map.structure_at(cell + Vector2i.DOWN)
			variant = ROOF_EAVE if below == DistrictMap.Terrain.WALL or below == DistrictMap.Terrain.DOOR 				else _hash(cell) % 3
			return Vector2i(variant, _row_for(terrain, theme))
		DistrictMap.Terrain.WALL:
			if map.is_interior():
				if cell.y >= DistrictMap.INTERIOR_TOP_WALL or cell.x == 0 or cell.x == map.size.x - 1:
					variant = WALL_TOP
				else:
					variant = WALL_UPPER_WINDOW if cell.y == 0 and cell.x % 3 == 1 else 						(WALL_UPPER if cell.y == 0 else WALL_LOWER)
			elif map.structure_at(cell + Vector2i.UP) == DistrictMap.Terrain.ROOF:
				variant = WALL_UPPER_WINDOW if cell.x % 2 == 1 else WALL_UPPER
			else:
				variant = WALL_LOWER
			return Vector2i(variant, _row_for(terrain, theme))
		DistrictMap.Terrain.DOOR:
			variant = DOOR_VARIANT_BY_THEME.get(theme, 0)
		DistrictMap.Terrain.COUNTER, DistrictMap.Terrain.BED, DistrictMap.Terrain.SIGN:
			variant = 0
	return Vector2i(variant, int(terrain))


## The atlas row for (terrain, theme); "" is always the plain per-Terrain row.
## The inverse, `_terrain_for_row()`/`_theme_for_row()`, lets `_build()` paint
## every row -- plain and themed -- through the same loop.
static func _row_for(terrain: DistrictMap.Terrain, theme: String) -> int:
	if theme != "":
		for i in THEMED_ROWS.size():
			if THEMED_ROWS[i][0] == terrain and THEMED_ROWS[i][1] == theme:
				return DistrictMap.Terrain.size() - 1 + i
	return int(terrain)


static func _terrain_for_row(row: int) -> DistrictMap.Terrain:
	var base_rows := DistrictMap.Terrain.size() - 1
	if row < base_rows:
		return row as DistrictMap.Terrain
	return THEMED_ROWS[row - base_rows][0] as DistrictMap.Terrain


static func _theme_for_row(row: int) -> String:
	var base_rows := DistrictMap.Terrain.size() - 1
	return "" if row < base_rows else str(THEMED_ROWS[row - base_rows][1])


static func _total_rows() -> int:
	return DistrictMap.Terrain.size() - 1 + THEMED_ROWS.size()


## One extra row after every terrain and themed row: fully transparent, but
## solid exactly like the wall it stands in for. A building drawn as one whole
## sprite (`BuildingArt`) uses it for its own roof/wall/door cells, because the
## art's silhouette is not a rectangle — a pitched roof leaves its top corners
## clear — and the generic tiles underneath showed through as stray brickwork
## around a finished house (D-028). Those cells still block, still path and
## still collide; they simply draw nothing.
static func _hidden_row() -> int:
	return _total_rows()


static func hidden_coords() -> Vector2i:
	return Vector2i(0, _hidden_row())


static func is_solid(terrain: DistrictMap.Terrain) -> bool:
	return SOLID.has(terrain)


# --- edge sets ---------------------------------------------------------------

## Which atlas source and tile a cell's ground draws, packed as
## (source, column, row) so one call answers both halves of `set_cell()`.
## Most terrain comes from the procedural atlas; a terrain with an installed
## edge set uses that instead, so it meets its neighbours properly and — for
## the sea — moves.
static func ground_tile(map: DistrictMap, cell: Vector2i) -> Vector3i:
	var terrain := map.ground_at(cell)
	var index := edge_set_for(map, cell, terrain)
	if index >= 0:
		var edge := edge_coords(map, cell, terrain)
		return Vector3i(EDGE_SOURCE_FIRST + index, edge.x, edge.y)
	var plain := coords_for(map, cell, false)
	return Vector3i(SOURCE_ID, plain.x, plain.y)


## The edge set a cell uses, or -1 for the procedural atlas. The sea picks its
## set by what it washes against: a beach on one side of the district, the
## quay's planking on the other.
static func edge_set_for(map: DistrictMap, cell: Vector2i, terrain: DistrictMap.Terrain) -> int:
	match terrain:
		DistrictMap.Terrain.WATER:
			for dir in NEIGHBOURS:
				if map.ground_at(cell + dir) == DistrictMap.Terrain.DOCK:
					return _installed_set("water_dock")
			return _installed_set("water_sand")
		DistrictMap.Terrain.ROAD:
			return _installed_set("road")
	return -1


## The cell within a 4x4 edge block. Out of bounds counts as the same terrain,
## so the sea runs off the edge of the world instead of washing up against it.
## A one-cell-wide channel (no neighbour on either side) draws its western
## edge; nothing in this district is that thin, and a wrong tile there is
## better than a branch nobody can see.
##
## The four interior cells are chosen by parity, not by the usual per-cell
## hash: they are drawn as one 2x2 block whose waves run from tile to tile, so
## laying them out as the artist arranged them keeps the sea continuous where
## a hash would chop it up.
static func edge_coords(map: DistrictMap, cell: Vector2i, terrain: DistrictMap.Terrain) -> Vector2i:
	var col := 0
	if _edge_same(map, cell + Vector2i.LEFT, terrain):
		col = 3 if not _edge_same(map, cell + Vector2i.RIGHT, terrain) else 1 + posmod(cell.x, 2)
	var row := 0
	if _edge_same(map, cell + Vector2i.UP, terrain):
		row = 3 if not _edge_same(map, cell + Vector2i.DOWN, terrain) else 1 + posmod(cell.y, 2)
	return Vector2i(col, row)


static func _edge_same(map: DistrictMap, cell: Vector2i, terrain: DistrictMap.Terrain) -> bool:
	if not map.in_bounds(cell):
		return true
	var other := map.ground_at(cell)
	if other == terrain:
		return true
	# The dashes down the middle of a road are still road to its kerb.
	return terrain == DistrictMap.Terrain.ROAD and other == DistrictMap.Terrain.ROAD_LINE


## The index of an edge set if its art is installed, else -1. Indices are
## fixed by EDGE_SETS' order whether or not a set is installed, so a missing
## file never shifts another set's source id.
static func _installed_set(id: String) -> int:
	for i in EDGE_SETS.size():
		if str(EDGE_SETS[i]["id"]) != id:
			continue
		return i if ResourceLoader.exists(TERRAIN_DIR + str(EDGE_SETS[i]["file"])) else -1
	return -1


## Cheap, stable per-cell hash so the same cell always shows the same variant.
static func _hash(cell: Vector2i) -> int:
	var h := (cell.x * 73856093) ^ (cell.y * 19349663)
	return absi(h)


# --- real art ----------------------------------------------------------------

## The curated LimeZu file for a (terrain, variant, theme) cell, or "" for
## none — the one place that says which real tiles exist. WALL's four
## variants share one file per theme: the window, the plinth shade and the
## top-down darkening are composited onto it in `_blit_real()`, not stored as
## separate files, so that drawing exists once, not once per theme.
static func _real_file(terrain: DistrictMap.Terrain, v: int, theme: String = "") -> String:
	var themed := theme if theme != "" else "home"
	match terrain:
		DistrictMap.Terrain.GRASS:
			return TERRAIN_DIR + "grass_%d.png" % v
		DistrictMap.Terrain.SAND:
			return TERRAIN_DIR + "sand.png"
		DistrictMap.Terrain.DOCK:
			return TERRAIN_DIR + "dock_%d.png" % v
		DistrictMap.Terrain.PAVEMENT:
			return REAL_DIR + "pavement_%d.png" % v
		DistrictMap.Terrain.ROAD:
			return REAL_DIR + "road_%d.png" % v
		DistrictMap.Terrain.ROAD_LINE:
			return REAL_DIR + "road_line.png"
		DistrictMap.Terrain.FLOOR:
			return REAL_DIR + "floor.png"
		DistrictMap.Terrain.WALL:
			return REAL_DIR + "wall_%s.png" % themed
		DistrictMap.Terrain.ROOF:
			# "bar" has no roof file of its own: the home roof's red suits it too.
			var roof_theme := "home" if themed == "bar" else themed
			return REAL_DIR + ("roof_%s_eave.png" % roof_theme if v == ROOF_EAVE else "roof_%s_%d.png" % [roof_theme, v])
	return ""


## Blits a real tile into the atlas, then adds whatever `_paint()` would have
## drawn on top for this specific variant (a window, the plinth and top-down
## darkening — WALL's four variants are one real file, not four).
static func _blit_real(img: Image, path: String, terrain: DistrictMap.Terrain, v: int, o: Vector2i) -> void:
	var tile_image := (load(path) as Texture2D).get_image()
	if tile_image.get_format() != img.get_format():
		tile_image = tile_image.duplicate()
		tile_image.convert(img.get_format())
	img.blit_rect(tile_image, Rect2i(Vector2i.ZERO, Vector2i(TILE, TILE)), o)
	if terrain != DistrictMap.Terrain.WALL:
		return
	if v == WALL_UPPER_WINDOW:
		_paint_window(img, o)
	elif v == WALL_LOWER:
		_darken(img, o, 0.22)
	elif v == WALL_TOP:
		_darken(img, o, 0.55)


## Darkens an already-blitted tile in place, for the interior top-down wall.
static func _darken(img: Image, o: Vector2i, amount: float) -> void:
	for y in TILE:
		for x in TILE:
			var p := o + Vector2i(x, y)
			img.set_pixelv(p, img.get_pixelv(p).darkened(amount))


# --- atlas painting ---------------------------------------------------------

static func _build() -> TileSet:
	var rows := _total_rows() + 1   # the last one is _hidden_row(), left transparent
	var image := Image.create(TILE * VARIANTS, TILE * rows, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	for row in _total_rows():
		var terrain := _terrain_for_row(row)
		var theme := _theme_for_row(row)
		for v in VARIANTS:
			rng.seed = row * 97 + v * 13 + 1
			var offset := Vector2i(v * TILE, row * TILE)
			var real_path := _real_file(terrain, v, theme)
			if real_path != "" and ResourceLoader.exists(real_path):
				_blit_real(image, real_path, terrain, v, offset)
			else:
				_paint(image, terrain, v, offset, rng, theme)

	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(TILE, TILE)
	tiles.add_physics_layer()
	tiles.set_physics_layer_collision_layer(0, COLLISION_LAYER)
	tiles.set_physics_layer_collision_mask(0, 0)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE, TILE)
	tiles.add_source(source, SOURCE_ID)

	var half := TILE / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	for row in rows:
		for v in VARIANTS:
			var coords := Vector2i(v, row)
			source.create_tile(coords)
			if row == _hidden_row() or is_solid(_terrain_for_row(row)):
				var data := source.get_tile_data(coords, 0)
				data.add_collision_polygon(0)
				data.set_collision_polygon_points(0, 0, square)

	for i in EDGE_SETS.size():
		_add_edge_source(tiles, i, square)
	return tiles


## One atlas source per installed edge set. Water still blocks, so its tiles
## carry the same collision box they had in the procedural atlas; the road's
## do not. Animation frames sit one block apart in LimeZu's sheet, which is
## what `set_tile_animation_separation` describes.
static func _add_edge_source(tiles: TileSet, index: int, square: PackedVector2Array) -> void:
	var entry: Dictionary = EDGE_SETS[index]
	var path: String = TERRAIN_DIR + str(entry["file"])
	if not ResourceLoader.exists(path):
		return
	var source := TileSetAtlasSource.new()
	source.texture = load(path)
	source.texture_region_size = Vector2i(TILE, TILE)
	# Added before its tiles are configured: a TileData's physics layers come
	# from the TileSet the source belongs to, so collision cannot be set on a
	# source that is still loose.
	tiles.add_source(source, EDGE_SOURCE_FIRST + index)
	var frames: int = entry["frames"]
	var solid: bool = str(entry["id"]).begins_with("water")
	for row in EDGE_BLOCK:
		for col in EDGE_BLOCK:
			var coords := Vector2i(col, row)
			source.create_tile(coords)
			if frames > 1:
				source.set_tile_animation_separation(coords, Vector2i(EDGE_BLOCK - 1, 0))
				source.set_tile_animation_frames_count(coords, frames)
				for f in frames:
					source.set_tile_animation_frame_duration(coords, f, EDGE_FRAME_SECONDS)
			if solid:
				var data := source.get_tile_data(coords, 0)
				data.add_collision_polygon(0)
				data.set_collision_polygon_points(0, 0, square)


## The window a wall-with-a-window shows, drawn onto whatever is already at
## `o` — a painted wall (fallback) or a real one (`_blit_real()`), so this
## drawing exists in exactly one place either way.
static func _paint_window(img: Image, o: Vector2i) -> void:
	img.fill_rect(Rect2i(o + Vector2i(8, 8), Vector2i(16, 18)), Color("6b5a44"))
	img.fill_rect(Rect2i(o + Vector2i(10, 10), Vector2i(12, 14)), Color("7fb2d6"))
	img.fill_rect(Rect2i(o + Vector2i(10, 10), Vector2i(5, 5)), Color("b5d6ea"))
	img.fill_rect(Rect2i(o + Vector2i(15, 10), Vector2i(2, 14)), Color("6b5a44"))


## Base colours for the code-painted fallback, by theme ("" = home/default) —
## kept alongside THEME_BY_KIND so the fallback looks themed too, not just
## the real art. DOOR is keyed by variant directly: it stays on its own
## Terrain row (see DOOR_VARIANT_BY_THEME), never a themed one.
const THEME_WALL_COLOR := {
	"": Color("d9cdb4"), "shop": Color("3a6ea8"), "bar": Color("a13c3c"), "civic": Color("7d7686"),
}
const THEME_ROOF_COLOR := {
	"": Color("8e3b2f"), "shop": Color("5a7a3a"), "bar": Color("8e3b2f"), "civic": Color("3a4a6a"),
}
const DOOR_COLOR_BY_VARIANT := {
	0: Color("7a5334"), 1: Color("2a4a70"), 2: Color("5a1f1f"), 3: Color("454550"),
}


static func _paint(img: Image, terrain: DistrictMap.Terrain, v: int, o: Vector2i, rng: RandomNumberGenerator, theme: String = "") -> void:
	match terrain:
		DistrictMap.Terrain.GRASS:
			_noise(img, o, Color("5d8c3e"), 0.05, rng)
			for i in 14:
				var p := o + Vector2i(rng.randi_range(0, TILE - 1), rng.randi_range(1, TILE - 1))
				img.set_pixelv(p, Color("4a7431"))
				img.set_pixelv(p + Vector2i.UP, Color("6f9f4a"))
			if v == 3:
				for i in 3:
					var f := o + Vector2i(rng.randi_range(2, TILE - 3), rng.randi_range(2, TILE - 3))
					img.set_pixelv(f, Color("f2e27a"))
		DistrictMap.Terrain.PAVEMENT:
			_noise(img, o, Color("b8b2a6"), 0.03, rng)
			var seam := Color("9d978b")
			for i in TILE:
				img.set_pixelv(o + Vector2i(i, 0), seam)
				img.set_pixelv(o + Vector2i(i, TILE / 2), seam)
				img.set_pixelv(o + Vector2i(0 if i < TILE / 2 else TILE / 2, i), seam)
			if v == 2:
				img.set_pixelv(o + Vector2i(rng.randi_range(3, 28), rng.randi_range(3, 28)), Color("8e887d"))
		DistrictMap.Terrain.ROAD, DistrictMap.Terrain.ROAD_LINE:
			_noise(img, o, Color("46474e"), 0.035, rng)
			for i in 10:
				img.set_pixelv(o + Vector2i(rng.randi_range(0, TILE - 1), rng.randi_range(0, TILE - 1)), Color("5a5b62"))
			if terrain == DistrictMap.Terrain.ROAD_LINE:
				img.fill_rect(Rect2i(o + Vector2i(6, 0), Vector2i(20, 2)), Color("e8dfb8"))
		DistrictMap.Terrain.WATER:
			for y in TILE:
				var base := Color("2d5d88").lerp(Color("24507a"), float(y) / TILE)
				for x in TILE:
					img.set_pixelv(o + Vector2i(x, y), base.lightened(rng.randf_range(0.0, 0.03)))
			for x in TILE:
				var y := int(8 + v * 5 + sin((x + v * 7) * TAU / TILE) * 2.0) % TILE
				img.set_pixelv(o + Vector2i(x, y), Color("5f8fb8"))
		DistrictMap.Terrain.DOCK:
			_noise(img, o, Color("8a6440"), 0.04, rng)
			for plank in 4:
				var y := plank * 8
				for x in TILE:
					img.set_pixelv(o + Vector2i(x, y), Color("5e4128"))
				var seam_x := (plank * 11 + v * 7) % TILE
				for dy in range(1, 8):
					img.set_pixelv(o + Vector2i(seam_x, y + dy), Color("6b4a2e"))
		DistrictMap.Terrain.SAND:
			_noise(img, o, Color("d8c48e"), 0.04, rng)
			for i in 8:
				img.set_pixelv(o + Vector2i(rng.randi_range(0, TILE - 1), rng.randi_range(0, TILE - 1)), Color("c2ad78"))
		DistrictMap.Terrain.ROOF:
			var roof_base: Color = THEME_ROOF_COLOR.get(theme, THEME_ROOF_COLOR[""])
			_noise(img, o, roof_base, 0.03, rng)
			for course in 4:
				var y := course * 8 + 7
				for x in TILE:
					img.set_pixelv(o + Vector2i(x, y), roof_base.darkened(0.25))
				var shift := 0 if course % 2 == 0 else 8
				for tab in range(shift, TILE, 16):
					for dy in 7:
						img.set_pixelv(o + Vector2i(tab, course * 8 + dy), roof_base.darkened(0.12))
			if v == ROOF_EAVE:
				img.fill_rect(Rect2i(o + Vector2i(0, TILE - 4), Vector2i(TILE, 4)), roof_base.darkened(0.45))
		DistrictMap.Terrain.WALL:
			var wall_base: Color = THEME_WALL_COLOR.get(theme, THEME_WALL_COLOR[""])
			_noise(img, o, wall_base, 0.02, rng)
			if v == WALL_UPPER or v == WALL_UPPER_WINDOW:
				img.fill_rect(Rect2i(o, Vector2i(TILE, 3)), wall_base.darkened(0.1))   # eave shadow
			if v == WALL_UPPER_WINDOW:
				_paint_window(img, o)
			if v == WALL_LOWER:
				img.fill_rect(Rect2i(o + Vector2i(0, TILE - 6), Vector2i(TILE, 6)), wall_base.darkened(0.22))
			if v == WALL_TOP:
				_noise(img, o, wall_base.darkened(0.55), 0.03, rng)
				img.fill_rect(Rect2i(o + Vector2i(2, 2), Vector2i(TILE - 4, TILE - 4)), wall_base.darkened(0.45))
		DistrictMap.Terrain.DOOR:
			var door_color: Color = DOOR_COLOR_BY_VARIANT.get(v, DOOR_COLOR_BY_VARIANT[0])
			_noise(img, o, Color("d9cdb4"), 0.02, rng)
			img.fill_rect(Rect2i(o + Vector2i(0, TILE - 6), Vector2i(TILE, 6)), Color("8b8172"))
			img.fill_rect(Rect2i(o + Vector2i(6, 2), Vector2i(20, 30)), door_color.darkened(0.3))
			img.fill_rect(Rect2i(o + Vector2i(8, 4), Vector2i(16, 28)), door_color)
			img.fill_rect(Rect2i(o + Vector2i(20, 17), Vector2i(2, 2)), Color("e0c060"))
		DistrictMap.Terrain.FLOOR:
			_noise(img, o, Color("a57b4f"), 0.03, rng)
			for plank in 4:
				var y := plank * 8
				for x in TILE:
					img.set_pixelv(o + Vector2i(x, y), Color("7d5a38"))
				var seam_x := (plank * 13 + v * 5) % TILE
				for dy in range(1, 8):
					img.set_pixelv(o + Vector2i(seam_x, y + dy), Color("8a6440"))
		DistrictMap.Terrain.COUNTER:
			_noise(img, o, Color("8a5a3a"), 0.02, rng)
			img.fill_rect(Rect2i(o, Vector2i(TILE, 3)), Color("a8744c"))
			img.fill_rect(Rect2i(o + Vector2i(0, 20), Vector2i(TILE, 12)), Color("5e3d26"))
			img.fill_rect(Rect2i(o + Vector2i(0, 20), Vector2i(TILE, 1)), Color("3e281a"))
		DistrictMap.Terrain.SHELF:
			_noise(img, o, Color("5a3c24"), 0.02, rng)
			for row in 3:
				var y := 3 + row * 10
				img.fill_rect(Rect2i(o + Vector2i(1, y + 7), Vector2i(TILE - 2, 2)), Color("3e281a"))
				var x := 2
				while x < TILE - 4:
					var w := rng.randi_range(3, 6)
					var goods := Color.from_hsv(rng.randf(), 0.5, 0.8)
					img.fill_rect(Rect2i(o + Vector2i(x, y + rng.randi_range(0, 2)), Vector2i(w, 7 - rng.randi_range(0, 2))), goods)
					x += w + 1
		DistrictMap.Terrain.BED:
			img.fill_rect(Rect2i(o + Vector2i(0, 2), Vector2i(TILE, 28)), Color("6b4a2e"))
			img.fill_rect(Rect2i(o + Vector2i(1, 4), Vector2i(TILE - 2, 24)), Color("e8e2d4"))
			img.fill_rect(Rect2i(o + Vector2i(1, 12), Vector2i(TILE - 2, 16)), Color("4a6a8c"))
			img.fill_rect(Rect2i(o + Vector2i(1, 12), Vector2i(TILE - 2, 2)), Color("6a8aac"))
		DistrictMap.Terrain.TABLE:
			img.fill_rect(Rect2i(o + Vector2i(3, 6), Vector2i(TILE - 6, 18)), Color("8a5a3a"))
			img.fill_rect(Rect2i(o + Vector2i(3, 6), Vector2i(TILE - 6, 2)), Color("a8744c"))
			img.fill_rect(Rect2i(o + Vector2i(5, 24), Vector2i(3, 6)), Color("5e3d26"))
			img.fill_rect(Rect2i(o + Vector2i(TILE - 8, 24), Vector2i(3, 6)), Color("5e3d26"))
		DistrictMap.Terrain.SIGN:
			img.fill_rect(Rect2i(o + Vector2i(14, 14), Vector2i(4, 17)), Color("4a4a4a"))
			img.fill_rect(Rect2i(o + Vector2i(4, 2), Vector2i(24, 14)), Color("2f5f7a"))
			img.fill_rect(Rect2i(o + Vector2i(6, 4), Vector2i(20, 10)), Color("e8e8e0"))
			for line in 3:
				img.fill_rect(Rect2i(o + Vector2i(8, 6 + line * 3), Vector2i(10 + (line * 5) % 7, 1)), Color("6a6a6a"))


## Fills a tile with a colour and per-pixel brightness jitter.
static func _noise(img: Image, o: Vector2i, base: Color, amount: float, rng: RandomNumberGenerator) -> void:
	for y in TILE:
		for x in TILE:
			var jitter := rng.randf_range(-amount, amount)
			var c := base.lightened(jitter) if jitter > 0.0 else base.darkened(-jitter)
			img.set_pixelv(o + Vector2i(x, y), c)
