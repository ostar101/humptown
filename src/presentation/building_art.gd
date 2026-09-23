class_name BuildingArt
extends RefCounted
## Whole-building overlay sprites (D-024): LimeZu's actual house art, used as
## one piece, for a building whose *rect exactly matches the art's fixed
## size* — not stretched to fit, because stretching pixel art distorts it.
## A building of any other size keeps `RegionTiles`' generic per-cell wall
## and roof; that is a real building, just a plainer one, never broken.
##
## The art also dictates geometry the map must agree with (D-028):
##
## - `door_column` is the column the art draws its own front door in, so the
##   map's interactive door cell lands *on* the drawn door rather than near it.
## - `porch_rows` are rows the art draws below the building's front wall —
##   the villa's porch decking — which people walk on to reach that door. They
##   are drawn by the sprite but are **not** part of the building's rect, so
##   they stay ordinary walkable ground. `footprint()` is therefore shorter
##   than `draw_cells()` by exactly those rows.
##
## `tools/import_limezu_buildings.py` prepares the files this points to, in
## git-ignored `art/vendor/limezu/buildings/`; without them `sprite_for()`
## returns "" and every building falls back the same way.

const REAL_DIR := "res://art/vendor/limezu/buildings/"

## kind -> the one building drawn for it. `home` has five colour variants of
## the villa; `shop`/`bar`/`civic`/`work` share one flat-roofed storefront,
## each with its own sign colour repainted at import time rather than a
## different building — nothing generic-looking enough to be a *different*
## building per kind was found; see DECISIONS.md D-026.
##
## `cells` is the whole image; `porch_rows` how many of its bottom rows are
## walkable porch rather than building; `door_column` where its door is drawn.
const BUILDINGS := {
	"home": {"prefix": "home_", "count": 5, "cells": Vector2i(8, 13), "porch_rows": 2, "door_column": 2},
	"shop": {"prefix": "shop_", "count": 1, "cells": Vector2i(8, 13), "porch_rows": 0, "door_column": 4},
	"bar": {"prefix": "bar_", "count": 1, "cells": Vector2i(8, 13), "porch_rows": 0, "door_column": 4},
	"civic": {"prefix": "civic_", "count": 1, "cells": Vector2i(8, 13), "porch_rows": 0, "door_column": 4},
	"work": {"prefix": "work_", "count": 1, "cells": Vector2i(8, 13), "porch_rows": 0, "door_column": 4},
	# LimeZu's own police station ("Small", 7x13, badge and POLICE sign drawn in), D-060.
	"police": {"prefix": "police_", "count": 1, "cells": Vector2i(7, 13), "porch_rows": 0, "door_column": 3},
	# Downtown's towers (D-091): tools/import_limezu_downtown.py stacks a ground
	# cap, N repeats of a window-band middle floor and a flat roof cap, all 7
	# cells wide, into one fixed-size image per height so this reads like any
	# other whole-building sprite — no runtime compositing. The suffix names
	# how many storeys are walkable (ground floor + N-1 upper floors, reached
	# by stairs); flush to the sidewalk like the storefronts, no porch.
	"downtown_2": {"prefix": "downtown_2_", "count": 1, "cells": Vector2i(7, 13), "porch_rows": 0, "door_column": 3},
	"downtown_4": {"prefix": "downtown_4_", "count": 1, "cells": Vector2i(7, 21), "porch_rows": 0, "door_column": 3},
	"downtown_6": {"prefix": "downtown_6_", "count": 1, "cells": Vector2i(7, 29), "porch_rows": 0, "door_column": 3},
}

## Buildings whose art is their own rather than their kind's: `civic` covers
## the clinic, the police post and others, but only the post has a building
## with POLICE across it. Downtown's four towers all share the "home"/"work"
## kind but need one of three heights each (D-091/D-092) — `kind` alone
## cannot express that, so each building names its own art here. Location id
## -> a key of BUILDINGS.
const BY_LOCATION := {
	"loc_police_post": "police",
	"loc_downtown_flats_a": "downtown_2",
	"loc_downtown_flats_b": "downtown_4",
	"loc_downtown_tower_a": "downtown_4",
	"loc_downtown_tower_b": "downtown_6",
}

## Resolved once per path: `sprite_for()` is called per cell by
## `RegionTiles.coords_for()` through `covers()`, and hitting the filesystem
## that often would be silly for nine files that never change during a run.
static var _installed_cache: Dictionary = {}



## The whole image's size in cells, porch included. Vector2i.ZERO for a kind
## with no art.
static func draw_cells(kind: String) -> Vector2i:
	var entry: Dictionary = BUILDINGS.get(kind, {})
	return entry["cells"] if not entry.is_empty() else Vector2i.ZERO


## The rect a map must author for a building of this kind to get the art: the
## solid part only, without the porch rows the sprite draws below it.
static func footprint(kind: String) -> Vector2i:
	var entry: Dictionary = BUILDINGS.get(kind, {})
	if entry.is_empty():
		return Vector2i.ZERO
	return entry["cells"] - Vector2i(0, entry["porch_rows"])


## Column within the rect where the art draws its door, or -1 for a kind with
## no art. `test_content` checks every authored building agrees with this.
static func door_column(kind: String) -> int:
	var entry: Dictionary = BUILDINGS.get(kind, {})
	return int(entry["door_column"]) if not entry.is_empty() else -1


## The BUILDINGS key a location is drawn with: its own art if it has any
## (`BY_LOCATION`), otherwise its kind's. Geometry checks must ask this, not the
## bare kind, or they measure the wrong building.
static func art_kind(kind: String, loc_id: String) -> String:
	return str(BY_LOCATION.get(loc_id, kind))


## The overlay file for this building, or "" if its kind has no whole-building
## art, its rect is the wrong shape for the art available, or the file simply
## is not installed. `loc_id` only picks *which* variant, for a little
## street-to-street variety; the same building always gets the same one.
static func sprite_for(kind: String, loc_id: String, rect_size: Vector2i) -> String:
	kind = art_kind(kind, loc_id)
	var entry: Dictionary = BUILDINGS.get(kind, {})
	if entry.is_empty() or rect_size != footprint(kind):
		return ""
	var count: int = entry["count"]
	var n := posmod(loc_id.hash(), count) + 1
	var path := REAL_DIR + "%s%d.png" % [entry["prefix"], n]
	return path if _installed(path) else ""


## True when a cell is inside a building drawn as one whole sprite, so its own
## per-cell roof/wall/door must not be drawn underneath the art (D-028). The
## sprite's silhouette is not a rectangle — a pitched roof leaves its top
## corners clear — and those tiles showed through as stray brickwork around
## the house.
static func covers(map: DistrictMap, cell: Vector2i) -> bool:
	for loc_id in map.buildings:
		var rect: Rect2i = map.buildings[loc_id]["rect"]
		if rect.has_point(cell):
			return sprite_for(map.kind_of(loc_id), loc_id, rect.size) != ""
	return false


## What the art's opaque pixels outline, for collision (D-065): polygons in
## pixels from the building's top-left, covering only the solid part (the
## porch rows below are walkable). A pitched roof's bare top corners are not in
## it, so the body walks up to the roof's outer edge, not to the edge of the
## grid rectangle behind it. Empty when the art is not installed.
static func outline(kind: String, loc_id: String, rect_size: Vector2i) -> Array[PackedVector2Array]:
	var solid := _silhouette(kind, loc_id, rect_size)
	return solid["polygons"] if not solid.is_empty() else ([] as Array[PackedVector2Array])


## Cells (relative to the building's rect) the art does not fill completely:
## the body may stand in them where the outline lets it, so the movement rule
## must not refuse them (D-065). Empty when the art is not installed.
static func open_cells(kind: String, loc_id: String, rect_size: Vector2i) -> Array[Vector2i]:
	var solid := _silhouette(kind, loc_id, rect_size)
	return solid["open"] if not solid.is_empty() else ([] as Array[Vector2i])


static var _silhouettes: Dictionary = {}


static func _silhouette(kind: String, loc_id: String, rect_size: Vector2i) -> Dictionary:
	var file := sprite_for(kind, loc_id, rect_size)
	if file == "":
		return {}
	var key := "%s@%s" % [file, rect_size]
	if _silhouettes.has(key):
		return _silhouettes[key]
	var pixels := rect_size * DistrictMap.CELL_PIXELS
	var bitmap := ArtShape.bitmap(file)
	var polygons := ArtShape.outline(file, Rect2i(Vector2i.ZERO, pixels))
	var open: Array[Vector2i] = []
	for y in rect_size.y:
		for x in rect_size.x:
			if not _cell_full(bitmap, Vector2i(x, y) * DistrictMap.CELL_PIXELS):
				open.append(Vector2i(x, y))
	var made := {"polygons": polygons, "open": open}
	_silhouettes[key] = made
	return made


static func _cell_full(bitmap: BitMap, origin: Vector2i) -> bool:
	for y in DistrictMap.CELL_PIXELS:
		for x in DistrictMap.CELL_PIXELS:
			if not bitmap.get_bitv(origin + Vector2i(x, y)):
				return false
	return true


static func _installed(path: String) -> bool:
	if not _installed_cache.has(path):
		_installed_cache[path] = ResourceLoader.exists(path)
	return bool(_installed_cache[path])
