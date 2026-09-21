class_name PlaceArt
extends RefCounted
## What an open-air location is furnished with (D-030): the park's trees and
## benches, the basketball court's surface, the worksite's frame and digger.
##
## The counterpart to `BuildingArt`, and deliberately a much smaller idea. A
## building's art has to agree with the map about where its door and its walls
## are; a place is walkable ground either way, so this is pure decoration —
## authored per location id, drawn over the place's first rect, blocking
## nothing. That matches `StreetProps`: scenery a missing art install can
## simply leave out.
##
## `at` is a cell offset from the place's rect, of the piece's **top-left**
## corner, which is how one reads it off a map. `RegionView` turns that into
## a y-sort key at the piece's base, so someone walks in front of a tree they
## are below and behind one they are above.
##
## `foot` is how many pixel rows at the bottom of the art collide, by its own
## outline (D-067): a tree's base, a bench, the frame of the worksite. Zero
## (the default) is ground, or nothing worth bumping into.
##
## `flat` marks a piece that is ground rather than an object — the court's
## painted surface. It sorts from its top edge instead of its base, so a
## player standing anywhere on it is drawn on top of it rather than under it.

const REAL_DIR := "res://art/vendor/limezu/places/"

const DECORATIONS := {
	"loc_court": [
		{"file": "court.png", "at": Vector2i(0, 0), "flat": true},
	],
	"loc_harbour_park": [
		{"file": "tree_2.png", "at": Vector2i(1, 0), "foot": 32},
		{"file": "tree_1.png", "at": Vector2i(6, 1), "foot": 32},
		{"file": "tree_3.png", "at": Vector2i(12, 0), "foot": 32},
		{"file": "bench.png", "at": Vector2i(6, 6), "foot": 24},
		{"file": "bench.png", "at": Vector2i(11, 6), "foot": 24},
		{"file": "tree_4.png", "at": Vector2i(0, 8), "foot": 32},
		{"file": "tree_1.png", "at": Vector2i(8, 9), "foot": 32},
		{"file": "tree_2.png", "at": Vector2i(13, 8), "foot": 32},
	],
	"loc_worksite": [
		{"file": "skeleton.png", "at": Vector2i(1, 1), "foot": 64},
		{"file": "excavator.png", "at": Vector2i(10, 2), "foot": 64},
		{"file": "cone.png", "at": Vector2i(9, 10), "foot": 24},
		{"file": "cone.png", "at": Vector2i(13, 9), "foot": 24},
	],
}


## Every piece to draw on a location, as {"file": path, "cell": top-left cell
## on the map, "flat": bool, "foot": int}. Empty for a location with nothing authored, and
## for every location when the art is not installed.
static func decorations_for(map: DistrictMap, location_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pieces: Array = DECORATIONS.get(location_id, [])
	if pieces.is_empty() or not map.places.has(location_id):
		return out
	var rect: Rect2i = map.places[location_id]["rects"][0]
	for piece: Dictionary in pieces:
		var path: String = REAL_DIR + str(piece["file"])
		if not ResourceLoader.exists(path):
			continue
		out.append({
			"file": path,
			"cell": rect.position + (piece["at"] as Vector2i),
			"flat": bool(piece.get("flat", false)),
			"foot": int(piece.get("foot", 0)),
		})
	return out


## Every decorated place on a map, in authored order.
static func decorated_places(map: DistrictMap) -> Array[String]:
	var out: Array[String] = []
	for location_id in DECORATIONS:
		if map.places.has(location_id):
			out.append(location_id)
	return out
