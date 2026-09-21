class_name StreetProps
extends RefCounted
## Draws the street's furniture — lamps, bins, hydrants (D-022, D-029, D-066,
## D-067, D-068). *Where* each stands is `StreetFurniture`'s business, in the
## world, because a bin can be searched and a hydrant is in the way whatever
## is drawn; this is the art: which file, which way round, which part collides.
##
## Visual, except that each one's foot collides. There is no code-painted
## fallback, unlike the tiles in RegionTiles — a missing sprite here just means
## no decoration, which is a legitimate look, not a broken one, so `props_in()`
## returns nothing until the art is installed.

const REAL_DIR := "res://art/vendor/limezu/props/"

## `cells_tall` mirrors the art: a prop is drawn standing on its cell and
## reaching *up* the screen. `foot` is the part of the art, in pixels from its
## top-left, that collides: the bottom cell of a bin or hydrant, by its own
## outline (D-067). The lamp collides through `LAMP_FOOT` instead.
const KINDS := {
	"lamp": {"file": "lamp.png", "cells_tall": 4},
	"trash": {"file": "trash.png", "cells_tall": 2, "foot": Rect2i(0, 32, 32, 32)},
	"hydrant": {"file": "hydrant.png", "cells_tall": 2, "foot": Rect2i(0, 32, 32, 32)},
}

## The pole's foot in the lamp's cell, in pixels from the cell's top-left: what
## the body cannot walk through (D-066). Raised from where the art draws the
## base to where the body's own feet are, and centred in the cell, so a mirrored
## lamp needs no other one.
const LAMP_FOOT := Rect2(8.0, 12.0, 16.0, 14.0)

## Placement lives in `StreetFurniture`; these keep the names the drawing and
## the tests use.
const LAMP_SPACING := StreetFurniture.LAMP_SPACING
const CORNER_CLEARANCE := StreetFurniture.CORNER_CLEARANCE


## True once at least one prop's art is installed; RegionView skips the
## whole pass otherwise rather than asking per cell for nothing.
static func available() -> bool:
	for kind in KINDS:
		if ResourceLoader.exists(REAL_DIR + str(KINDS[kind]["file"])):
			return true
	return false


## Every decoration in this cell range: {"cell": Vector2i, "file": String,
## "kind": String, "flip": bool}. The kind is how RegionView knows which ones
## to light; `flip` mirrors a lamp so its head is on the road's side.
static func props_in(map: DistrictMap, rect: Rect2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not available():
		return out
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var kind := kind_at(map, cell)
			if kind == "":
				continue
			var file: String = REAL_DIR + str(KINDS[kind]["file"])
			if ResourceLoader.exists(file):
				out.append({"cell": cell, "file": file, "kind": kind, "flip": kind == "lamp" and lamp_faces_left(map, cell)})
	return out


## Which prop stands on a cell, or "": a bin or hydrant the map placed, or a lamp.
static func kind_at(map: DistrictMap, cell: Vector2i) -> String:
	if map.furniture.has(cell):
		return str(map.furniture[cell]["kind"])
	return "lamp" if StreetFurniture.lamp_at(map, cell) else ""


static func has_headroom(map: DistrictMap, cell: Vector2i, kind: String) -> bool:
	return StreetFurniture.has_headroom(map, cell, int(KINDS.get(kind, {}).get("cells_tall", 1)))


static func is_back_of_pavement(map: DistrictMap, cell: Vector2i) -> bool:
	return StreetFurniture.is_back_of_pavement(map, cell)


static func touches_road(map: DistrictMap, cell: Vector2i) -> bool:
	return StreetFurniture.touches_road(map, cell)


static func lamp_faces_left(map: DistrictMap, cell: Vector2i) -> bool:
	return StreetFurniture.lamp_faces_left(map, cell)


static func _is_corner(map: DistrictMap, cell: Vector2i) -> bool:
	return StreetFurniture.is_corner(map, cell)
