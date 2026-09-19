class_name MapView
extends Control
## The map (D-049): the district as the player has come to know it. Places
## they have been to are solid, places they have only heard of are outlined,
## everything else is blank — and no one but the player is on it. It draws;
## what is known is the player's (`PlayerState.known_places`).

const WIDTH := 460.0
const BACKDROP := Color(0.13, 0.14, 0.19)
const OUTLINE := Color(0.05, 0.05, 0.09)
const YOU := Color(0.98, 0.72, 0.16)
const KIND_COLOURS := {
	"home": Color(0.55, 0.62, 0.78), "shop": Color(0.86, 0.62, 0.42), "bar": Color(0.72, 0.46, 0.62),
	"work": Color(0.62, 0.66, 0.5), "civic": Color(0.5, 0.72, 0.74), "park": Color(0.44, 0.72, 0.46),
	"street": Color(0.62, 0.62, 0.68),
}

var _map: DistrictMap = null
var _marks: Array[Dictionary] = []
var _you := Vector2(-1.0, -1.0)
var _scale := 1.0


## Lays out what is known of one district. `kinds` maps a location id to its
## kind for colour, `numbers` to the number it is marked with (the legend
## below the map says which is which); `you` is the player's cell on this
## district, or (-1, -1).
func show_district(map: DistrictMap, known: Dictionary, kinds: Dictionary, numbers: Dictionary, you: Vector2i) -> void:
	_map = map
	_scale = WIDTH / float(map.size.x)
	custom_minimum_size = Vector2(WIDTH, float(map.size.y) * _scale)
	_marks = []
	for location_id: String in known:
		var rects: Array[Rect2i] = []
		if map.buildings.has(location_id):
			rects.append(map.buildings[location_id]["rect"])
		elif map.places.has(location_id):
			for rect: Rect2i in map.places[location_id]["rects"]:
				rects.append(rect)
		if rects.is_empty():
			continue
		_marks.append({"id": location_id, "state": str(known[location_id]), "kind": str(kinds.get(location_id, "")),
			"rects": rects, "number": int(numbers.get(location_id, 0))})
	_you = Vector2(you.x, you.y) if you.x >= 0 else Vector2(-1.0, -1.0)
	queue_redraw()


## What is drawn: {"id", "state", "kind", "rects", "number"} per known place
## on this district. For tests and reading.
func marks() -> Array[Dictionary]:
	return _marks


func has_you() -> bool:
	return _you.x >= 0.0


func you_cell() -> Vector2i:
	return Vector2i(int(_you.x), int(_you.y))


func _draw() -> void:
	if _map == null:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(_map.size) * _scale), BACKDROP)
	var font := ThemeDB.fallback_font
	for mark in _marks:
		var solid: bool = mark["state"] == "visited"
		var colour: Color = KIND_COLOURS.get(mark["kind"], Color(0.7, 0.7, 0.75))
		var first := true
		for rect: Rect2i in mark["rects"]:
			var area := Rect2(Vector2(rect.position) * _scale, Vector2(rect.size) * _scale)
			draw_rect(area, Color(colour, 0.85 if solid else 0.22))
			draw_rect(area, colour if not solid else OUTLINE, false, 1.5)
			if first:
				first = false
				var label := str(mark["number"])
				var extent := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
				var at := area.get_center() + Vector2(-extent.x * 0.5, extent.y * 0.3)
				draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, OUTLINE if solid else colour.lightened(0.35))
	if has_you():
		var at := (_you + Vector2(0.5, 0.5)) * _scale
		draw_circle(at, 6.0, OUTLINE)
		draw_circle(at, 4.0, YOU)
