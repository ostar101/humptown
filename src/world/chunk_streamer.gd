class_name ChunkStreamer
extends RefCounted
## Decides which chunks of a region should be resident around a focus point.
##
## Pure bookkeeping: it knows nothing about tiles, nodes or rendering, so the
## rule is unit-tested headless and the same streamer can later drive NPC
## body pooling or prop spawning. The caller applies the diff it returns.
##
## Hysteresis: a chunk loads within `load_radius` of the focus but only
## unloads once it is further than `load_radius + unload_margin`. Walking back
## and forth over a chunk border therefore never thrashes.

var load_radius: int = 1
var unload_margin: int = 1

var _grid := Vector2i.ZERO
var _loaded: Dictionary = {}   # Vector2i -> true
var _focus := Vector2i(-9999, -9999)


func configure(chunk_grid: Vector2i, radius: int = 1, margin: int = 1) -> void:
	_grid = chunk_grid
	load_radius = maxi(radius, 0)
	unload_margin = maxi(margin, 0)
	_loaded.clear()
	_focus = Vector2i(-9999, -9999)


## Moves the focus to `chunk` and returns what changed:
## {"load": Array[Vector2i] nearest first, "unload": Array[Vector2i]}.
## Calling it again with the same chunk is free and returns an empty diff.
func update(chunk: Vector2i) -> Dictionary:
	var to_load: Array[Vector2i] = []
	var to_unload: Array[Vector2i] = []
	if chunk == _focus:
		return {"load": to_load, "unload": to_unload}
	_focus = chunk

	for loaded: Vector2i in _loaded.keys():
		if _distance(loaded, chunk) > load_radius + unload_margin:
			to_unload.append(loaded)
	for gone in to_unload:
		_loaded.erase(gone)

	for y in range(chunk.y - load_radius, chunk.y + load_radius + 1):
		for x in range(chunk.x - load_radius, chunk.x + load_radius + 1):
			var candidate := Vector2i(x, y)
			if _in_grid(candidate) and not _loaded.has(candidate):
				_loaded[candidate] = true
				to_load.append(candidate)
	to_load.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _distance(a, chunk) < _distance(b, chunk))
	return {"load": to_load, "unload": to_unload}


## Forgets everything and returns the chunks that were resident, so the
## caller can release them (on region change, for instance).
func reset() -> Array[Vector2i]:
	var released: Array[Vector2i] = []
	for c: Vector2i in _loaded.keys():
		released.append(c)
	_loaded.clear()
	_focus = Vector2i(-9999, -9999)
	return released


func is_loaded(chunk: Vector2i) -> bool:
	return _loaded.has(chunk)


func loaded_count() -> int:
	return _loaded.size()


func _in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _grid.x and c.y < _grid.y


## Chebyshev distance: a square neighbourhood matches a rectangular screen
## better than a diamond does.
static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
