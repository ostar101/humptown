class_name RegionTiles
extends RefCounted
## The tile set every region is drawn with, and the rule for which tile a map
## cell shows.
##
## Atlas layout: one row per DistrictMap.Terrain, VARIANTS columns per row.
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

const TILE := DistrictMap.CELL_PIXELS
const VARIANTS := 4
const SOURCE_ID := 0
const COLLISION_LAYER := 1
const REAL_DIR := "res://art/vendor/limezu/tiles/"

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
	var variant := _hash(cell) % VARIANTS
	match terrain:
		DistrictMap.Terrain.ROOF:
			var below := map.structure_at(cell + Vector2i.DOWN)
			variant = ROOF_EAVE if below == DistrictMap.Terrain.WALL or below == DistrictMap.Terrain.DOOR \
				else _hash(cell) % 3
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
		DistrictMap.Terrain.DOOR, DistrictMap.Terrain.COUNTER, DistrictMap.Terrain.BED, DistrictMap.Terrain.SIGN:
			variant = 0
	return Vector2i(variant, int(terrain))


static func is_solid(terrain: DistrictMap.Terrain) -> bool:
	return SOLID.has(terrain)


## Cheap, stable per-cell hash so the same cell always shows the same variant.
static func _hash(cell: Vector2i) -> int:
	var h := (cell.x * 73856093) ^ (cell.y * 19349663)
	return absi(h)


# --- real art ----------------------------------------------------------------

## The curated LimeZu file for a (terrain, variant) cell, or "" for none —
## the one place that says which real tiles exist. WALL and ROOF variants
## are not interchangeable (see WALL_UPPER etc. above): the window and the
## top-down darkening are composited onto the plain tile in `_blit_real()`,
## not stored as separate files, so that drawing exists only once.
static func _real_file(terrain: DistrictMap.Terrain, v: int) -> String:
	match terrain:
		DistrictMap.Terrain.PAVEMENT:
			return REAL_DIR + "pavement_%d.png" % v
		DistrictMap.Terrain.ROAD:
			return REAL_DIR + "road_%d.png" % v
		DistrictMap.Terrain.ROAD_LINE:
			return REAL_DIR + "road_line.png"
		DistrictMap.Terrain.FLOOR:
			return REAL_DIR + "floor.png"
		DistrictMap.Terrain.WALL:
			match v:
				WALL_UPPER, WALL_UPPER_WINDOW, WALL_TOP:
					return REAL_DIR + "wall_upper.png"
				WALL_LOWER:
					return REAL_DIR + "wall_lower.png"
		DistrictMap.Terrain.ROOF:
			return REAL_DIR + ("roof_eave.png" if v == ROOF_EAVE else "roof_%d.png" % v)
	return ""


## Blits a real tile into the atlas, then adds whatever `_paint()` would have
## drawn on top for this specific variant (a window, the top-down darkening).
static func _blit_real(img: Image, path: String, terrain: DistrictMap.Terrain, v: int, o: Vector2i) -> void:
	var tile_image := (load(path) as Texture2D).get_image()
	if tile_image.get_format() != img.get_format():
		tile_image = tile_image.duplicate()
		tile_image.convert(img.get_format())
	img.blit_rect(tile_image, Rect2i(Vector2i.ZERO, Vector2i(TILE, TILE)), o)
	if terrain == DistrictMap.Terrain.WALL and v == WALL_UPPER_WINDOW:
		_paint_window(img, o)
	elif terrain == DistrictMap.Terrain.WALL and v == WALL_TOP:
		_darken(img, o, 0.55)


## Darkens an already-blitted tile in place, for the interior top-down wall.
static func _darken(img: Image, o: Vector2i, amount: float) -> void:
	for y in TILE:
		for x in TILE:
			var p := o + Vector2i(x, y)
			img.set_pixelv(p, img.get_pixelv(p).darkened(amount))


# --- atlas painting ---------------------------------------------------------

static func _build() -> TileSet:
	var rows := DistrictMap.Terrain.size() - 1   # NONE has no row
	var image := Image.create(TILE * VARIANTS, TILE * rows, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	for row in rows:
		var terrain := row as DistrictMap.Terrain
		for v in VARIANTS:
			rng.seed = row * 97 + v * 13 + 1
			var offset := Vector2i(v * TILE, row * TILE)
			var real_path := _real_file(terrain, v)
			if real_path != "" and ResourceLoader.exists(real_path):
				_blit_real(image, real_path, terrain, v, offset)
			else:
				_paint(image, terrain, v, offset, rng)

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
			if is_solid(row as DistrictMap.Terrain):
				var data := source.get_tile_data(coords, 0)
				data.add_collision_polygon(0)
				data.set_collision_polygon_points(0, 0, square)
	return tiles


## The window a wall-with-a-window shows, drawn onto whatever is already at
## `o` — a painted wall (fallback) or a real one (`_blit_real()`), so this
## drawing exists in exactly one place either way.
static func _paint_window(img: Image, o: Vector2i) -> void:
	img.fill_rect(Rect2i(o + Vector2i(8, 8), Vector2i(16, 18)), Color("6b5a44"))
	img.fill_rect(Rect2i(o + Vector2i(10, 10), Vector2i(12, 14)), Color("7fb2d6"))
	img.fill_rect(Rect2i(o + Vector2i(10, 10), Vector2i(5, 5)), Color("b5d6ea"))
	img.fill_rect(Rect2i(o + Vector2i(15, 10), Vector2i(2, 14)), Color("6b5a44"))


static func _paint(img: Image, terrain: DistrictMap.Terrain, v: int, o: Vector2i, rng: RandomNumberGenerator) -> void:
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
			_noise(img, o, Color("8e3b2f"), 0.03, rng)
			for course in 4:
				var y := course * 8 + 7
				for x in TILE:
					img.set_pixelv(o + Vector2i(x, y), Color("6c2a21"))
				var shift := 0 if course % 2 == 0 else 8
				for tab in range(shift, TILE, 16):
					for dy in 7:
						img.set_pixelv(o + Vector2i(tab, course * 8 + dy), Color("772f25"))
			if v == ROOF_EAVE:
				img.fill_rect(Rect2i(o + Vector2i(0, TILE - 4), Vector2i(TILE, 4)), Color("4d1d17"))
		DistrictMap.Terrain.WALL:
			_noise(img, o, Color("d9cdb4"), 0.02, rng)
			if v == WALL_UPPER or v == WALL_UPPER_WINDOW:
				img.fill_rect(Rect2i(o, Vector2i(TILE, 3)), Color("a89a80"))   # eave shadow
			if v == WALL_UPPER_WINDOW:
				_paint_window(img, o)
			if v == WALL_LOWER:
				img.fill_rect(Rect2i(o + Vector2i(0, TILE - 6), Vector2i(TILE, 6)), Color("8b8172"))
			if v == WALL_TOP:
				_noise(img, o, Color("4a4038"), 0.03, rng)
				img.fill_rect(Rect2i(o + Vector2i(2, 2), Vector2i(TILE - 4, TILE - 4)), Color("5a4e44"))
		DistrictMap.Terrain.DOOR:
			_noise(img, o, Color("d9cdb4"), 0.02, rng)
			img.fill_rect(Rect2i(o + Vector2i(0, TILE - 6), Vector2i(TILE, 6)), Color("8b8172"))
			img.fill_rect(Rect2i(o + Vector2i(6, 2), Vector2i(20, 30)), Color("4f3421"))
			img.fill_rect(Rect2i(o + Vector2i(8, 4), Vector2i(16, 28)), Color("7a5334"))
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
