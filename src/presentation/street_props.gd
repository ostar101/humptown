class_name StreetProps
extends RefCounted
## Purely decorative street furniture — lamps, trash cans, hydrants — placed
## by what a cell *is*, not by a hash over every candidate (D-022, D-029).
##
## Where each kind goes, and why:
##
## - **lamp**: the pavement cell next to the road (D-066), at a regular
##   interval, turned so the lamp head is on the road's side: the art has the
##   pole in its left column and the head on an arm to the right, so a lamp with
##   the road on its left is mirrored. Beside a road that runs across the
##   screen the arm cannot point at the road (it would point at the viewer), so
##   it is left along the street. The pole's foot collides (`LAMP_FOOT`).
## - **hydrant**: the same back edge, far rarer, on its own offset so it never
##   lands on a lamp.
## - **trash**: beside a building's entrance, where a bin is actually wanted,
##   rather than anywhere a road happens to be near.
##
## Visual, except that each one's foot collides (D-066, D-067): nothing saved. There is no
## code-painted fallback either, unlike the tiles in RegionTiles — a missing
## sprite here just means no decoration, which is a legitimate look, not a
## broken one, so `props_in()` returns nothing until the art is installed.

const REAL_DIR := "res://art/vendor/limezu/props/"

## `cells_tall` mirrors the art: a prop is drawn standing on its cell and
## reaching *up* the screen, so this is how far above itself it covers. The
## placement rules use it to keep a prop from leaning over a carriageway,
## which no amount of choosing the right pavement cell can fix on its own.
## `foot` is the part of the art, in pixels from its top-left, that collides:
## the bottom cell of a bin or hydrant, by its own outline (D-067). The lamp
## collides through `LAMP_FOOT` instead.
const KINDS := {
	"lamp": {"file": "lamp.png", "cells_tall": 4},
	"trash": {"file": "trash.png", "cells_tall": 2, "foot": Rect2i(0, 32, 32, 32)},
	"hydrant": {"file": "hydrant.png", "cells_tall": 2, "foot": Rect2i(0, 32, 32, 32)},
}

## Cells between one lamp and the next along a street. Regular rather than
## hashed: a street lit at even intervals reads as a street, and a hashed
## interval clumps.
const LAMP_SPACING := 10
## No lamp this close (in cells) to a corner where two roads meet.
const CORNER_CLEARANCE := 2
## The pole's foot in the lamp's cell, in pixels from the cell's top-left: what
## the body cannot walk through (D-066). Raised from where the art draws the
## base to where the body's own feet are, and centred in the cell, so a mirrored
## lamp needs no other one.
const LAMP_FOOT := Rect2(8.0, 12.0, 16.0, 14.0)
const HYDRANT_SPACING := 31
const HYDRANT_OFFSET := 5
## Cells to the right of a door's approach where its bin stands.
const TRASH_OFFSET := 2

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


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


## Which prop stands on a cell, or "". Public so the placement rules can be
## tested directly rather than through a chunk's worth of sprites.
static func kind_at(map: DistrictMap, cell: Vector2i) -> String:
	if map.ground_at(cell) != DistrictMap.Terrain.PAVEMENT:
		return ""
	if map.structure_at(cell) != DistrictMap.Terrain.NONE:
		return ""   # never stand a lamp in a doorway or on a sign
	if _beside_a_door(map, cell) and has_headroom(map, cell, "trash"):
		return "trash"
	if touches_road(map, cell):
		if posmod(cell.x + cell.y, LAMP_SPACING) == 0 and _lamp_fits(map, cell):
			return "lamp"
		return ""
	if not is_back_of_pavement(map, cell):
		return ""
	if posmod(cell.x + cell.y, HYDRANT_SPACING) == HYDRANT_OFFSET and has_headroom(map, cell, "hydrant"):
		return "hydrant"
	return ""


## Whether a prop this tall fits above its own cell without covering road.
## A hydrant is kept off the pavement below a carriageway; lamps are not asked
## (D-066): they stand at the kerb, and a pole at the kerb does rise over it.
static func has_headroom(map: DistrictMap, cell: Vector2i, kind: String) -> bool:
	var cells_tall: int = KINDS.get(kind, {}).get("cells_tall", 1)
	for up in range(1, cells_tall):
		var above := cell + Vector2i(0, -up)
		if map.ground_at(above) == DistrictMap.Terrain.ROAD or map.ground_at(above) == DistrictMap.Terrain.ROAD_LINE:
			return false
	return true


## The row of a pavement strip furthest from the road: pavement that does not
## itself touch a road but neighbours pavement that does. On the two-cell
## sidewalks this map is built from, that is exactly the far kerb — the grass
## or shopfront side — which is where a lamp post belongs.
static func is_back_of_pavement(map: DistrictMap, cell: Vector2i) -> bool:
	if touches_road(map, cell):
		return false
	for dir in DIRECTIONS:
		var next := cell + dir
		if map.ground_at(next) == DistrictMap.Terrain.PAVEMENT and touches_road(map, next):
			return true
	return false


## A lamp is not put where it would be in someone's way or double up: not on a
## corner where two roads meet (each would light it from its own side), and not
## on the walk from a door to the street.
static func _lamp_fits(map: DistrictMap, cell: Vector2i) -> bool:
	for dy in range(-CORNER_CLEARANCE, CORNER_CLEARANCE + 1):
		for dx in range(-CORNER_CLEARANCE, CORNER_CLEARANCE + 1):
			if _is_corner(map, cell + Vector2i(dx, dy)):
				return false
	for dx in range(-1, 2):
		for up in range(1, 4):
			if map.structure_at(cell + Vector2i(dx, -up)) == DistrictMap.Terrain.DOOR:
				return false
	return true


## A pavement cell with road beside it on both axes: where two streets meet.
static func _is_corner(map: DistrictMap, cell: Vector2i) -> bool:
	if map.ground_at(cell) != DistrictMap.Terrain.PAVEMENT:
		return false
	var across := _is_road(map, cell + Vector2i.LEFT) or _is_road(map, cell + Vector2i.RIGHT)
	var along := _is_road(map, cell + Vector2i.UP) or _is_road(map, cell + Vector2i.DOWN)
	return across and along


## Whether a lamp here is mirrored: the road is on its left and not its right, so
## the head, which the art draws to the right, would point away from it.
static func lamp_faces_left(map: DistrictMap, cell: Vector2i) -> bool:
	return _is_road(map, cell + Vector2i.LEFT) and not _is_road(map, cell + Vector2i.RIGHT)


static func _is_road(map: DistrictMap, cell: Vector2i) -> bool:
	var ground := map.ground_at(cell)
	return ground == DistrictMap.Terrain.ROAD or ground == DistrictMap.Terrain.ROAD_LINE


static func touches_road(map: DistrictMap, cell: Vector2i) -> bool:
	for dir in DIRECTIONS:
		var ground := map.ground_at(cell + dir)
		if ground == DistrictMap.Terrain.ROAD or ground == DistrictMap.Terrain.ROAD_LINE:
			return true
	return false


## A bin stands a couple of cells along the pavement from a door, on the cell
## someone leaving the building would walk past — never in front of it.
static func _beside_a_door(map: DistrictMap, cell: Vector2i) -> bool:
	return map.structure_at(cell + Vector2i(-TRASH_OFFSET, -1)) == DistrictMap.Terrain.DOOR
