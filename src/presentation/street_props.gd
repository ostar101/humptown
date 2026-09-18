class_name StreetProps
extends RefCounted
## Purely decorative street furniture — lamps, trash cans, hydrants — placed
## on pavement next to a road, chosen deterministically from the cell so a
## given map always looks the same (D-022).
##
## Visual only: no collision, no interaction, nothing saved. There is no
## code-painted fallback either, unlike the tiles in RegionTiles — a missing
## sprite here just means no decoration, which is a legitimate look, not a
## broken one, so `props_in()` returns nothing until the art is installed.

const REAL_DIR := "res://art/vendor/limezu/props/"

## kind -> {file, spacing}. `spacing` is how many candidate cells apart one
## of that kind appears on average; kinds are tried in this order; the first
## a cell's hash matches wins, so smaller spacings are effectively rarer once
## a bigger one has already claimed a cell.
const KINDS := {
	"lamp": {"file": "lamp.png", "spacing": 6},
	"trash": {"file": "trash.png", "spacing": 9},
	"hydrant": {"file": "hydrant.png", "spacing": 17},
}


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
			var kind := _kind_at(map, cell)
			if kind == "":
				continue
			var file: String = REAL_DIR + str(KINDS[kind]["file"])
			if ResourceLoader.exists(file):
				out.append({"cell": cell, "file": file})
	return out


static func _kind_at(map: DistrictMap, cell: Vector2i) -> String:
	if map.ground_at(cell) != DistrictMap.Terrain.PAVEMENT:
		return ""
	if map.structure_at(cell) != DistrictMap.Terrain.NONE:
		return ""   # never stand a lamp in a doorway or on a sign
	if not _touches_road(map, cell):
		return ""
	for kind in KINDS:
		if posmod(_hash(cell), int(KINDS[kind]["spacing"])) == 0:
			return kind
	return ""


static func _touches_road(map: DistrictMap, cell: Vector2i) -> bool:
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var ground := map.ground_at(cell + dir)
		if ground == DistrictMap.Terrain.ROAD or ground == DistrictMap.Terrain.ROAD_LINE:
			return true
	return false


## A different mix from RegionTiles._hash() (different primes) so props do
## not fall on the same cells the tile variant hash would pick out.
static func _hash(cell: Vector2i) -> int:
	return absi((cell.x * 60493 + cell.y * 43781))
