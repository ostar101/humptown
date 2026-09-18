class_name StreetProps
extends RefCounted
## Purely decorative street furniture — lamps, trash cans, hydrants — placed
## by what a cell *is*, not by a hash over every candidate (D-022, D-029).
##
## Where each kind goes, and why:
##
## - **lamp**: the back edge of a pavement strip, the side away from the road,
##   at a regular interval. A lamp is four cells tall with an arm that reaches
##   out over the carriageway, so standing one at the kerb puts the light in
##   the middle of the road — which is where they all were.
## - **hydrant**: the same back edge, far rarer, on its own offset so it never
##   lands on a lamp.
## - **trash**: beside a building's entrance, where a bin is actually wanted,
##   rather than anywhere a road happens to be near.
##
## Visual only: no collision, no interaction, nothing saved. There is no
## code-painted fallback either, unlike the tiles in RegionTiles — a missing
## sprite here just means no decoration, which is a legitimate look, not a
## broken one, so `props_in()` returns nothing until the art is installed.

const REAL_DIR := "res://art/vendor/limezu/props/"

## `cells_tall` mirrors the art: a prop is drawn standing on its cell and
## reaching *up* the screen, so this is how far above itself it covers. The
## placement rules use it to keep a prop from leaning over a carriageway,
## which no amount of choosing the right pavement cell can fix on its own.
const KINDS := {
	"lamp": {"file": "lamp.png", "cells_tall": 4},
	"trash": {"file": "trash.png", "cells_tall": 2},
	"hydrant": {"file": "hydrant.png", "cells_tall": 2},
}

## Cells between one lamp and the next along a street. Regular rather than
## hashed: a street lit at even intervals reads as a street, and a hashed
## interval clumps.
const LAMP_SPACING := 10
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


## Every decoration in this cell range: {"cell": Vector2i, "file": String}.
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
				out.append({"cell": cell, "file": file})
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
	if not is_back_of_pavement(map, cell):
		return ""
	if posmod(cell.x + cell.y, LAMP_SPACING) == 0 and has_headroom(map, cell, "lamp"):
		return "lamp"
	if posmod(cell.x + cell.y, HYDRANT_SPACING) == HYDRANT_OFFSET and has_headroom(map, cell, "hydrant"):
		return "hydrant"
	return ""


## Whether a prop this tall fits above its own cell without covering road.
## A lamp is four cells tall, so on the pavement *below* a carriageway its
## pole and light land squarely in the middle of it however far back from the
## kerb it stands — the town is lit from the side of each street that has the
## room, the way plenty of real ones are (D-029).
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
