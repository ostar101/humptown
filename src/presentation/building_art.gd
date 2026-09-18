class_name BuildingArt
extends RefCounted
## Whole-building overlay sprites (D-024): LimeZu's actual house art, used as
## one piece, for a building whose *rect exactly matches the art's fixed
## size* — not stretched to fit, because stretching pixel art distorts it.
## A building of any other size keeps `RegionTiles`' generic per-cell wall
## and roof; that is a real building, just a plainer one, never broken.
##
## `tools/import_limezu_buildings.py` prepares the files this points to, in
## git-ignored `art/vendor/limezu/buildings/`; without them `sprite_for()`
## returns "" and every building falls back the same way.

const REAL_DIR := "res://art/vendor/limezu/buildings/"

## kind -> (file name pattern, count). One choice per kind for now; more
## kinds or more variety per kind both just extend this table.
const FILES_BY_KIND := {
	"home": {"prefix": "home_", "count": 5},
}

## Cell size the art was drawn at — the one building shape this covers. The
## interactive door is the cell at the *bottom* of the porch, not where the
## art draws the doorway itself — see `tools/import_limezu_buildings.py`.
const SPRITE_SIZE := Vector2i(8, 13)


## The overlay file for this building, or "" if its kind has no whole-building
## art, its rect is the wrong shape for the art available, or the file simply
## is not installed. `loc_id` only picks *which* variant, for a little
## street-to-street variety; the same building always gets the same one.
static func sprite_for(kind: String, loc_id: String, rect_size: Vector2i) -> String:
	if rect_size != SPRITE_SIZE:
		return ""
	var choice: Dictionary = FILES_BY_KIND.get(kind, {})
	if choice.is_empty():
		return ""
	var count: int = choice["count"]
	var n := posmod(loc_id.hash(), count) + 1
	var path := REAL_DIR + "%s%d.png" % [choice["prefix"], n]
	return path if ResourceLoader.exists(path) else ""
