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
}

## Buildings whose art is their own rather than their kind's: `civic` covers
## the clinic, the police post and others, but only the post has a building
## with POLICE across it. Location id -> a key of BUILDINGS.
const BY_LOCATION := {"loc_police_post": "police"}

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


static func _installed(path: String) -> bool:
	if not _installed_cache.has(path):
		_installed_cache[path] = ResourceLoader.exists(path)
	return bool(_installed_cache[path])
