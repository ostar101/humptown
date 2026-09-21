class_name ArtShape
extends RefCounted
## Collision taken from an art file's own pixels (D-065, D-067): the outline of
## what is opaque, so a body meets a roof, a hydrant or a bench where it is
## drawn rather than at the edge of the grid cell behind it.
##
## Presentation only, and only with the art installed. Without a file there is
## no shape, and whatever it belonged to simply does not collide.

## A pixel at least this opaque is part of the shape.
const OPAQUE := 0.5
## How closely the outline follows the pixels, in pixels.
const OUTLINE_EPSILON := 1.5

static var _bitmaps: Dictionary = {}
static var _outlines: Dictionary = {}


## The file's opaque pixels, cached per path. Null when it does not load.
static func bitmap(path: String) -> BitMap:
	if _bitmaps.has(path):
		return _bitmaps[path]
	var made: BitMap = null
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	if texture != null:
		made = BitMap.new()
		made.create_from_image_alpha(texture.get_image(), OPAQUE)
	_bitmaps[path] = made
	return made


## Polygons (pixels from the file's top-left) around the opaque pixels inside
## `clip`, itself in pixels of the file. Empty when the file is missing or
## nothing in `clip` is opaque.
static func outline(path: String, clip: Rect2i) -> Array[PackedVector2Array]:
	var key := "%s@%s" % [path, clip]
	if _outlines.has(key):
		return _outlines[key]
	var polygons: Array[PackedVector2Array] = []
	var opaque := bitmap(path)
	if opaque != null:
		for polygon in opaque.opaque_to_polygons(clip, OUTLINE_EPSILON):
			polygons.append(polygon)
	_outlines[key] = polygons
	return polygons


## A static body the player collides with, made of those polygons and placed
## with the file's top-left at `top_left` (in the parent's space). Null when
## there is nothing to collide with.
static func body(path: String, clip: Rect2i, top_left: Vector2, layer: int) -> StaticBody2D:
	var shapes := outline(path, clip)
	if shapes.is_empty():
		return null
	var made := StaticBody2D.new()
	made.name = "Body"
	made.collision_layer = layer
	made.collision_mask = 0
	# The outline's points count from the corner of the clipped part, not of the file.
	made.position = top_left + Vector2(clip.position)
	for polygon in shapes:
		var shape := CollisionPolygon2D.new()
		shape.polygon = polygon
		made.add_child(shape)
	return made
