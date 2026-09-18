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
## and die with a chunk (props, ambient sound, NPC body pooling).

signal chunk_shown(chunk: Vector2i)
signal chunk_hidden(chunk: Vector2i)

const TILE := RegionTiles.TILE

## Chunks kept resident in each direction around the focus chunk. Two covers
## a 1280x720 view at any sensible zoom with a chunk of margin for movement.
@export var load_radius: int = 2

var map: DistrictMap = null

var _streamer := ChunkStreamer.new()
var _chunks: Dictionary = {}        # Vector2i -> Node2D
var _bounds: StaticBody2D = null


## Switches to a new map, releasing everything from the previous one. Nothing
## is drawn until the first focus_on().
func show_map(new_map: DistrictMap) -> void:
	clear()
	map = new_map
	if map == null:
		return
	_streamer.configure(map.chunk_grid(), load_radius)
	_build_bounds()


func clear() -> void:
	for chunk in _streamer.reset():
		_release(chunk)
	if _bounds != null:
		remove_child(_bounds)
		_bounds.queue_free()
		_bounds = null
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
			ground.set_cell(cell, RegionTiles.SOURCE_ID, RegionTiles.coords_for(map, cell, false))
			var top := RegionTiles.coords_for(map, cell, true)
			if top.x >= 0:
				structures.set_cell(cell, RegionTiles.SOURCE_ID, top)

	add_child(root)
	_chunks[chunk] = root
	chunk_shown.emit(chunk)


func _release(chunk: Vector2i) -> void:
	var root: Node2D = _chunks.get(chunk)
	if root == null:
		return
	_chunks.erase(chunk)
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
