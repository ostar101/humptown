class_name RegionView
extends Node2D
## Draws the region the player is in, one chunk at a time.
##
## Presentation only: it reads a DistrictMap and never changes it. Chunks are
## streamed around a focus point (the camera, once there is one) by a
## ChunkStreamer, and each resident chunk is its own node, so releasing a
## chunk frees its tiles, its collision and — later — anything else parked
## under it, in one call.
##
## `chunk_shown` / `chunk_hidden` are the hooks for systems that want to live
## and die with a chunk (ambient sound, NPC body pooling). Street props
## (StreetProps, D-022) are decorative and cheap enough to just place inline
## in `_populate()`, parented under the same y-sort root as the tiles, rather
## than needing their own listener.

signal chunk_shown(chunk: Vector2i)
signal chunk_hidden(chunk: Vector2i)

const TILE := RegionTiles.TILE

## A street lamp's pool of light (D-032). Warm, about seven cells across, and
## centred on the ground below the lamp's head — the head is on an arm a cell
## to the right of the pole, and in this view the ground under it is on the
## pole's own row.
const LAMP_LIGHT_COLOR := Color(1.0, 0.85, 0.56)
const LAMP_LIGHT_ENERGY := 0.85
const LAMP_LIGHT_RADIUS_CELLS := 3.5
const LAMP_LIGHT_OFFSET := Vector2(36.0, 0.0)
## The beam (D-074): a soft cone from the lamp's head down to the ground, so a
## lit lamp is seen to shine rather than only to leave a pool. Its apex is at the
## head, `LAMP_BEAM_APEX` above the pool's centre, and it widens as it falls.
const LAMP_BEAM_SIZE := Vector2i(176, 132)
const LAMP_BEAM_APEX := 96.0
const LAMP_BEAM_ENERGY := 0.55

## Chunks kept resident in each direction around the focus chunk. Two covers
## a 1280x720 view at any sensible zoom with a chunk of margin for movement.
@export var load_radius: int = 2

## How brightly the street lamps burn, 0-1 (DayNight.lamp_energy_for()).
## Kept here rather than asked for, so a chunk streamed in at midnight is lit
## the moment it appears.
var lamp_energy: float = 0.0

static var _lamp_texture: GradientTexture2D = null
static var _beam_texture: ImageTexture = null

var map: DistrictMap = null

var _streamer := ChunkStreamer.new()
var _chunks: Dictionary = {}        # Vector2i -> Node2D
var _lamp_lights: Dictionary = {}   # Vector2i -> Array[PointLight2D]
var _bounds: StaticBody2D = null
## Whole-building sprites (BuildingArt, D-024) and open-air place decoration
## (PlaceArt, D-030). Few enough per map — a couple dozen buildings and a
## park's worth of trees — to just keep them all resident, unlike chunks.
var _overlays: Array[Node2D] = []


## Y-sort must be enabled here, not just on the nested chunk roots: a building
## sprite and a Chunk_X_Y root are SIBLINGS under this node, and Godot only
## compares siblings by position when their shared parent is itself y-sorted
## (nested y-sort composes; it does not start partway down the tree). Without
## this, a chunk streamed in after `show_map()` built the building sprites
## simply draws on top of them in child order regardless of position, and the
## building's own plain WALL/ROOF/DOOR cells (kept for collision) show
## through where the whole-building art should be. This used to be set only
## by the embedding scene (`world.tscn` did; `region_preview.tscn` forgot to,
## which is exactly what made buildings there look unfinished) — setting it
## here means every scene that instances RegionView gets it right (D-027).
func _init() -> void:
	y_sort_enabled = true


## Switches to a new map, releasing everything from the previous one. Nothing
## is drawn until the first focus_on().
func show_map(new_map: DistrictMap) -> void:
	clear()
	map = new_map
	if map == null:
		return
	_streamer.configure(map.chunk_grid(), load_radius)
	_build_bounds()
	_build_place_art()
	_build_building_art()


func clear() -> void:
	for chunk in _streamer.reset():
		_release(chunk)
	if _bounds != null:
		remove_child(_bounds)
		_bounds.queue_free()
		_bounds = null
	for sprite in _overlays:
		remove_child(sprite)
		sprite.queue_free()
	_overlays.clear()
	if map != null:
		map.open_cells.clear()
	map = null


## Streams chunks around a world position. Cheap to call every frame: when the
## focus has not left its chunk the streamer returns an empty diff at once.
func focus_on(world_position: Vector2) -> void:
	if map == null:
		return
	var diff := _streamer.update(DistrictMap.chunk_of(world_to_cell(world_position)))
	for chunk: Vector2i in diff["unload"]:
		_release(chunk)
	for chunk: Vector2i in diff["load"]:
		_populate(chunk)


func is_chunk_resident(chunk: Vector2i) -> bool:
	return _chunks.has(chunk)


func resident_chunk_count() -> int:
	return _chunks.size()


func chunk_node(chunk: Vector2i) -> Node2D:
	return _chunks.get(chunk)


## Sets how brightly every street lamp burns, now and in every chunk streamed
## in afterwards. A lamp at zero is disabled rather than merely dark, so the
## daytime town pays nothing for lights nobody can see.
func set_lamp_energy(energy: float) -> void:
	lamp_energy = clampf(energy, 0.0, 1.0)
	for lights: Array in _lamp_lights.values():
		for light: PointLight2D in lights:
			_apply_lamp_energy(light)


## Every lamp light in the resident chunks. For tests and debugging.
func lamp_lights() -> Array[PointLight2D]:
	var out: Array[PointLight2D] = []
	for lights: Array in _lamp_lights.values():
		for light: PointLight2D in lights:
			out.append(light)
	return out


static func cell_to_world(cell: Vector2i) -> Vector2:
	return DistrictMap.cell_to_world(cell)


static func world_to_cell(world_position: Vector2) -> Vector2i:
	return DistrictMap.world_to_cell(world_position)


## Map extent in pixels, for camera limits.
func pixel_rect() -> Rect2:
	if map == null:
		return Rect2()
	return Rect2(Vector2.ZERO, Vector2(map.size * TILE))


# --- internals --------------------------------------------------------------

func _populate(chunk: Vector2i) -> void:
	var tiles := RegionTiles.tile_set()
	var root := Node2D.new()
	root.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
	root.y_sort_enabled = true
	# Ground is always underneath; structures y-sort with the bodies walking
	# among them, which is why the two are separate layers.
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = tiles
	ground.z_index = -1
	var structures := TileMapLayer.new()
	structures.name = "Structures"
	structures.tile_set = tiles
	structures.y_sort_enabled = true
	root.add_child(ground)
	root.add_child(structures)

	var rect := map.chunk_rect(chunk)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var floor_tile := RegionTiles.ground_tile(map, cell)
			ground.set_cell(cell, floor_tile.x, Vector2i(floor_tile.y, floor_tile.z))
			var top := RegionTiles.coords_for(map, cell, true)
			if top.x >= 0:
				structures.set_cell(cell, RegionTiles.SOURCE_ID, top)

	var lights: Array[PointLight2D] = []
	for prop in StreetProps.props_in(map, rect):
		var sprite := _prop_sprite(prop)
		if prop["kind"] == "lamp":
			var light := _lamp_light()
			if bool(prop["flip"]):
				light.position.x = -light.position.x
			sprite.add_child(light)
			lights.append(light)
			sprite.add_child(_lamp_foot(prop["cell"], sprite.position))
		else:
			var foot: Rect2i = StreetProps.KINDS[prop["kind"]].get("foot", Rect2i())
			var body := ArtShape.body(str(prop["file"]), foot, sprite.offset, RegionTiles.COLLISION_LAYER)
			if body != null:
				sprite.add_child(body)
		root.add_child(sprite)

	add_child(root)
	_chunks[chunk] = root
	_lamp_lights[chunk] = lights
	chunk_shown.emit(chunk)


## A lamp/trash-can/hydrant sprite standing on its cell. The sprite's
## bottom-left cell is its footing, because that is where these props are
## drawn from: the street lamp is two cells wide and four tall, with the pole
## in its left column and the arm reaching right, so centring the texture put
## the pole half a cell into the neighbouring tile and the light out over the
## carriageway (D-029). Its y-sort key stays on the cell itself, the way
## CharacterFigure anchors a person, so someone walking past sorts against the
## lamp's base rather than its head.
func _prop_sprite(prop: Dictionary) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = load(prop["file"])
	sprite.centered = false
	var cell: Vector2i = prop["cell"]
	var feet := DistrictMap.cell_to_world(cell)
	var size := sprite.texture.get_size()
	var top_left := Vector2(cell) * float(TILE) - Vector2(0.0, size.y - TILE)
	if bool(prop.get("flip", false)):
		# Mirrored, the pole is in the image's right column: the image starts a cell earlier.
		sprite.flip_h = true
		top_left.x -= size.x - TILE
	sprite.position = feet
	sprite.offset = top_left - feet
	return sprite


## The lamp pole's foot, as a body the player cannot walk through (D-066). A
## child of the lamp's sprite, so it streams and goes with its chunk.
func _lamp_foot(cell: Vector2i, feet: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Foot"
	body.collision_layer = RegionTiles.COLLISION_LAYER
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = StreetProps.LAMP_FOOT.size
	shape.shape = box
	shape.position = Vector2(cell) * float(TILE) + StreetProps.LAMP_FOOT.get_center() - feet
	body.add_child(shape)
	return body


## The pool of light under a street lamp, a child of the lamp's sprite so it
## is freed with its chunk. The sprite's origin is the cell the pole stands on.
func _lamp_light() -> PointLight2D:
	var light := PointLight2D.new()
	light.name = "Light"
	light.texture = _lamp_light_texture()
	light.texture_scale = LAMP_LIGHT_RADIUS_CELLS * 2.0 * TILE / float(light.texture.get_width())
	light.color = LAMP_LIGHT_COLOR
	light.position = LAMP_LIGHT_OFFSET
	var beam := PointLight2D.new()
	beam.name = "Beam"
	beam.texture = _lamp_beam_texture()
	beam.color = LAMP_LIGHT_COLOR
	# centred so the cone's tip is at the lamp's head and its foot on the ground
	beam.position = Vector2(0.0, float(LAMP_BEAM_SIZE.y) * 0.5 - LAMP_BEAM_APEX)
	light.add_child(beam)
	_apply_lamp_energy(light)
	return light


func _apply_lamp_energy(light: PointLight2D) -> void:
	light.energy = lamp_energy * LAMP_LIGHT_ENERGY
	light.enabled = lamp_energy > 0.001
	var beam := light.get_node_or_null("Beam") as PointLight2D
	if beam != null:
		beam.energy = lamp_energy * LAMP_BEAM_ENERGY
		beam.enabled = light.enabled


## One soft cone shared by every lamp, built once: narrow at the top, wide and
## faint at the bottom, feathered along both edges.
static func _lamp_beam_texture() -> ImageTexture:
	if _beam_texture == null:
		var size := LAMP_BEAM_SIZE
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		for y in size.y:
			var t := float(y) / float(size.y - 1)
			var half := lerpf(5.0, float(size.x) * 0.5 - 2.0, t)
			var along := (0.85 - 0.5 * t) * (1.0 - smoothstep(0.78, 1.0, t))
			for x in size.x:
				var d := absf(float(x) + 0.5 - float(size.x) * 0.5)
				var edge := 1.0 - smoothstep(half * 0.35, half, d)
				image.set_pixel(x, y, Color(1, 1, 1, clampf(edge * along, 0.0, 1.0)))
		_beam_texture = ImageTexture.create_from_image(image)
	return _beam_texture


## One soft radial falloff shared by every lamp, built once.
static func _lamp_light_texture() -> GradientTexture2D:
	if _lamp_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.45, Color(1, 1, 1, 0.55))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 128
		texture.height = 128
		_lamp_texture = texture
	return _lamp_texture


## One overlay sprite per building whose rect matches a whole-building art
## size (BuildingArt); every other building keeps its per-cell tiles as is.
## Sits over the map for its whole lifetime — buildings do not stream with
## chunks. Its y-sort key is placed just past the building's own bottom row,
## not at that row's centre: a `TileMapLayer` cell's own sort key can reach
## the bottom of its cell, and this building's WALL/DOOR cells (still drawn,
## for their collision) must never win that comparison and show through the
## art meant to cover them. The cost is one imprecise cell of layering at the
## doorway itself — someone standing exactly on the door tile draws behind
## the building rather than in front of it — traded for never showing the
## plain tiles peeking out from under a real, hand-drawn house.
func _build_building_art() -> void:
	for loc_id in map.buildings:
		var rect: Rect2i = map.buildings[loc_id]["rect"]
		var kind := map.kind_of(loc_id)
		var file := BuildingArt.sprite_for(kind, loc_id, rect.size)
		if file == "":
			continue
		var sprite := Sprite2D.new()
		sprite.name = "Building_%s" % loc_id
		sprite.texture = load(file)
		sprite.centered = false
		var top_left := Vector2(rect.position) * float(TILE)
		var sort_y := float(rect.end.y) * TILE + 1.0
		sprite.position = Vector2(top_left.x, sort_y)
		sprite.offset = Vector2(0, top_left.y - sort_y)
		add_child(sprite)
		_overlays.append(sprite)
		_build_building_body(loc_id, rect, kind)


## The building collides as the art is drawn (D-065): the outline of its opaque
## pixels, so the body meets the roof's outer edge rather than the grid
## rectangle behind it. Cells the art fills only partly are told to the map, so
## the movement rule lets the body stand in the clear part of them.
func _build_building_body(loc_id: String, rect: Rect2i, kind: String) -> void:
	var body := StaticBody2D.new()
	body.name = "Body_%s" % loc_id
	body.collision_layer = RegionTiles.COLLISION_LAYER
	body.collision_mask = 0
	body.position = Vector2(rect.position) * float(TILE)
	for outline in BuildingArt.outline(kind, loc_id, rect.size):
		var shape := CollisionPolygon2D.new()
		shape.polygon = outline
		body.add_child(shape)
	add_child(body)
	_overlays.append(body)
	for cell in BuildingArt.open_cells(kind, loc_id, rect.size):
		map.open_cells[rect.position + cell] = true


## The park's trees, the court's surface, the worksite's frame (PlaceArt,
## D-030). Like the building sprites these are few and never stream; unlike
## them they hide nothing, and only their feet block (D-067), so they are simply drawn where
## the place says. A `flat` piece is painted ground and sorts from its top
## edge, so walking onto the court puts you on it rather than under it.
func _build_place_art() -> void:
	for location_id in PlaceArt.decorated_places(map):
		for piece: Dictionary in PlaceArt.decorations_for(map, location_id):
			var sprite := Sprite2D.new()
			sprite.name = "Place_%s_%d" % [location_id, _overlays.size()]
			sprite.texture = load(piece["file"])
			sprite.centered = false
			var cell: Vector2i = piece["cell"]
			var top_left := Vector2(cell) * float(TILE)
			var rows := sprite.texture.get_height() / TILE
			var sort_y: float = top_left.y if piece["flat"] else float(cell.y + rows) * TILE
			sprite.position = Vector2(top_left.x, sort_y)
			sprite.offset = Vector2(0.0, top_left.y - sort_y)
			add_child(sprite)
			_overlays.append(sprite)
			if int(piece["foot"]) > 0:
				# What stands on the ground stops the body: the bottom of the art, by its outline.
				var size := Vector2i(sprite.texture.get_size())
				var foot := int(piece["foot"])
				var body := ArtShape.body(str(piece["file"]), Rect2i(0, size.y - foot, size.x, foot),
					sprite.offset, RegionTiles.COLLISION_LAYER)
				if body != null:
					sprite.add_child(body)


func _release(chunk: Vector2i) -> void:
	var root: Node2D = _chunks.get(chunk)
	if root == null:
		return
	_chunks.erase(chunk)
	_lamp_lights.erase(chunk)
	remove_child(root)
	root.queue_free()
	chunk_hidden.emit(chunk)


## Invisible walls around the map edge. The grid already treats out-of-bounds
## as blocked; this makes physics agree.
func _build_bounds() -> void:
	_bounds = StaticBody2D.new()
	_bounds.name = "Bounds"
	_bounds.collision_layer = RegionTiles.COLLISION_LAYER
	_bounds.collision_mask = 0
	var extent := Vector2(map.size * TILE)
	var thickness := float(TILE)
	var walls := [
		Rect2(-thickness, -thickness, extent.x + thickness * 2.0, thickness),
		Rect2(-thickness, extent.y, extent.x + thickness * 2.0, thickness),
		Rect2(-thickness, 0.0, thickness, extent.y),
		Rect2(extent.x, 0.0, thickness, extent.y),
	]
	for wall: Rect2 in walls:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = wall.size
		shape.shape = box
		shape.position = wall.get_center()
		_bounds.add_child(shape)
	add_child(_bounds)
