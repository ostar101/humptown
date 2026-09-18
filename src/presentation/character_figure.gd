class_name CharacterFigure
extends Node2D
## A person, drawn. Used for the player now and for NPC bodies next.
##
## Painted with draw calls for the same reason the tiles are (D-014): no art
## has been chosen. The contract a sprite replacement must keep is small —
## `palette`, `facing`, `moving`, `running` — and the origin is at the feet,
## which is what y-sorting keys on.

## Keys: skin, hair, shirt, trousers, shoes. Missing keys use the defaults.
@export var palette: Dictionary = {}:
	set(value):
		palette = value
		queue_redraw()

var facing := Vector2i.DOWN:
	set(value):
		if value != facing:
			facing = value
			queue_redraw()
var moving := false:
	set(value):
		if value != moving:
			moving = value
			_phase = 0.0
			queue_redraw()
var running := false

const DEFAULTS := {
	"skin": Color("e0b48c"),
	"hair": Color("4a3326"),
	"shirt": Color("3f6e8c"),
	"trousers": Color("2f3440"),
	"shoes": Color("1f1d1c"),
}

var _phase := 0.0


func _process(delta: float) -> void:
	if not moving:
		return
	_phase = fmod(_phase + delta * (13.0 if running else 9.0), TAU)
	queue_redraw()


func _draw() -> void:
	var skin := _colour("skin")
	var hair := _colour("hair")
	var shirt := _colour("shirt")
	var trousers := _colour("trousers")
	var shoes := _colour("shoes")
	var stride := sin(_phase) * 2.5 if moving else 0.0
	var bob := absf(sin(_phase)) * -1.0 if moving else 0.0
	var side := facing.x != 0

	# Shadow: flattened circle at the feet.
	draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2(0, bob))

	# Legs and shoes. Seen from the side they scissor; from the front they
	# lift alternately.
	if side:
		draw_rect(Rect2(-3 + stride, -10, 4, 9), trousers)
		draw_rect(Rect2(-2 - stride, -10, 4, 9), trousers.darkened(0.15))
		draw_rect(Rect2(-3 + stride + facing.x, -2, 5, 2), shoes)
		draw_rect(Rect2(-2 - stride + facing.x, -2, 5, 2), shoes)
	else:
		draw_rect(Rect2(-5, -10 - maxf(stride, 0.0), 4, 9), trousers)
		draw_rect(Rect2(1, -10 - maxf(-stride, 0.0), 4, 9), trousers)
		draw_rect(Rect2(-5, -2 - maxf(stride, 0.0), 4, 2), shoes)
		draw_rect(Rect2(1, -2 - maxf(-stride, 0.0), 4, 2), shoes)

	# Torso and arms.
	var torso_w := 10.0 if side else 14.0
	draw_rect(Rect2(-torso_w / 2.0, -22, torso_w, 13), shirt)
	draw_rect(Rect2(-torso_w / 2.0, -11, torso_w, 2), shirt.darkened(0.2))
	if side:
		draw_rect(Rect2(-2 - stride * 0.8, -21, 4, 10), shirt.darkened(0.12))
		draw_rect(Rect2(-2 - stride * 0.8, -12, 4, 3), skin)
	else:
		draw_rect(Rect2(-torso_w / 2.0 - 3, -21 + stride * 0.5, 3, 10), shirt.darkened(0.12))
		draw_rect(Rect2(torso_w / 2.0, -21 - stride * 0.5, 3, 10), shirt.darkened(0.12))
		draw_rect(Rect2(-torso_w / 2.0 - 3, -12 + stride * 0.5, 3, 3), skin)
		draw_rect(Rect2(torso_w / 2.0, -12 - stride * 0.5, 3, 3), skin)

	# Head, then hair and face depending on which way they look.
	draw_rect(Rect2(-2, -24, 4, 3), skin.darkened(0.1))
	draw_circle(Vector2(0, -30), 7.0, skin)
	match facing:
		Vector2i.UP:
			draw_circle(Vector2(0, -31), 7.0, hair)
		Vector2i.DOWN:
			draw_rect(Rect2(-7, -38, 14, 5), hair)
			draw_rect(Rect2(-7, -35, 2, 5), hair)
			draw_rect(Rect2(5, -35, 2, 5), hair)
			draw_rect(Rect2(-3, -30, 2, 2), Color("1c1a1a"))
			draw_rect(Rect2(1, -30, 2, 2), Color("1c1a1a"))
		_:
			var back := -facing.x
			draw_rect(Rect2(-7, -38, 14, 5), hair)
			draw_rect(Rect2(back * 3 - 4, -35, 8, 7), hair)
			draw_rect(Rect2(facing.x * 3 - 1, -30, 2, 2), Color("1c1a1a"))
	draw_set_transform(Vector2.ZERO)


func _colour(key: String) -> Color:
	var value: Variant = palette.get(key, DEFAULTS[key])
	if value is Color:
		return value
	return Color(str(value))
