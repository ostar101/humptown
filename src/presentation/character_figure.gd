class_name CharacterFigure
extends Node2D
## A person, drawn. Used for the player and for NPC bodies.
##
## Drawn from LimeZu's layered sheets when a `look` is set and the art is
## present (D-019, CharacterSprites); otherwise painted with draw calls as
## before (D-014), so the game runs without the art. Either way the contract is
## `palette`, `facing`, `moving`, `running`, and the origin is at the feet,
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
			if moving and _pose != "":
				_end_pose()   # setting off ends whatever they were doing
			queue_redraw()
var running := false
## Layer files from CharacterSprites.look_for. Empty means code-painted.
var look: Dictionary = {}:
	set(value):
		look = value
		_layers = CharacterSprites.textures_for(value)
		queue_redraw()

const DEFAULTS := {
	"skin": Color("e0b48c"),
	"hair": Color("4a3326"),
	"shirt": Color("3f6e8c"),
	"trousers": Color("2f3440"),
	"shoes": Color("1f1d1c"),
}

## Walk frames per second of the sprite sheet.
const SPRITE_FPS := 10.0
const SPRITE_RUN_FPS := 15.0
## Frames per second of the other animations (D-058); anything unlisted plays at POSE_FPS.
const POSE_FPS := 8.0
const POSE_SPEEDS := {"idle": 5.0}
## An action that can be held: {first frame of the loop, last frame of the
## loop}. It plays up to the loop, repeats it until `end_pose()`, then plays
## out the rest — a phone is lifted, talked into, and put away.
const POSE_LOOPS := {"phone": Vector2i(4, 9)}

## An action played to its end (or to `end_pose()`) has finished.
signal pose_finished(action: String)

var _phase := 0.0
var _pose := ""
var _pose_frame := 0.0
var _pose_holding := false
var _layers: Array[Texture2D] = []


func _process(delta: float) -> void:
	if _pose != "":
		_advance_pose(delta)
		return
	if not moving:
		return
	if _layers.is_empty():
		_phase = fmod(_phase + delta * (13.0 if running else 9.0), TAU)
	else:
		_phase = fmod(_phase + delta * (SPRITE_RUN_FPS if running else SPRITE_FPS),
			maxi(CharacterSprites.action_frames("walk"), 1))
	queue_redraw()


func _draw() -> void:
	if not _layers.is_empty():
		_draw_sprite()
		return
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


func _draw_sprite() -> void:
	draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO)
	var source := CharacterSprites.frame_rect(facing, true, int(_phase)) if moving 		else CharacterSprites.frame_rect_for(_pose if _pose != "" else "stand", facing, int(_pose_frame))
	var size := Vector2(CharacterSprites.FRAME)
	var target := Rect2(Vector2(-size.x / 2.0, -size.y), size)   # feet on the origin
	for layer in _layers:
		draw_texture_rect_region(layer, target, source)


## Starts an action from the art (idle, phone, gift, …). Returns false, and does
## nothing, when there is no art or it has no such animation — the code-painted
## figure has nothing to play. `hold` keeps a loopable action repeating until
## `end_pose()`. Presentation only: what the world does never waits for this.
func play(action: String, hold: bool = false) -> bool:
	if _layers.is_empty() or moving or not CharacterSprites.has_action(action):
		return false
	_pose = action
	_pose_frame = 0.0
	_pose_holding = hold and POSE_LOOPS.has(action)
	queue_redraw()
	return true


## Lets a held action finish: it plays out its last frames and is done.
func end_pose() -> void:
	_pose_holding = false
	if _pose != "" and not POSE_LOOPS.has(_pose):
		_end_pose()


func is_posing() -> bool:
	return _pose != ""


func pose() -> String:
	return _pose


func _advance_pose(delta: float) -> void:
	_pose_frame += delta * float(POSE_SPEEDS.get(_pose, POSE_FPS))
	if _pose_holding and POSE_LOOPS.has(_pose):
		var loop: Vector2i = POSE_LOOPS[_pose]
		if _pose_frame >= float(loop.y + 1):
			_pose_frame = float(loop.x) + fmod(_pose_frame - float(loop.x), float(loop.y + 1 - loop.x))
	if _pose_frame >= float(CharacterSprites.action_frames(_pose)):
		_end_pose()
		return
	queue_redraw()


func _end_pose() -> void:
	var finished := _pose
	_pose = ""
	_pose_frame = 0.0
	_pose_holding = false
	queue_redraw()
	pose_finished.emit(finished)


## Four-way facing from any direction. Horizontal wins ties so diagonal walking
## shows the profile, which reads better than the back of a head.
static func facing_for(direction: Vector2) -> Vector2i:
	if absf(direction.x) >= absf(direction.y):
		return Vector2i.RIGHT if direction.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if direction.y > 0.0 else Vector2i.UP


func _colour(key: String) -> Color:
	var value: Variant = palette.get(key, DEFAULTS[key])
	if value is Color:
		return value
	return Color(str(value))
