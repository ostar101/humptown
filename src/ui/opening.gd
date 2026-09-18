class_name Opening
extends Node
## The short opening (D-034): a few lines about the life the player chose,
## one at a time, at their own pace, and then the world — waking up at home.
##
## Every background has its own lines (`opening.<background>.<n>`, as many as
## the locale defines) and they all end on the same one. The text is authored,
## not generated: this is the first thing anyone reads, and it has to be right
## offline and on the first run.
##
## Any key or click shows the next line, or finishes the one fading in; after
## the last it fades out into the world. Escape skips straight there.

const WORLD := "res://scenes/world/world.tscn"
const FADE_SECONDS := 0.9
const MAX_LINES := 6
const FALLBACK := "fallback"
const LAST_LINE := "opening.common.last"

@onready var _lines: VBoxContainer = %Lines
@onready var _template: Label = %LineTemplate
@onready var _hint: Label = %Hint
@onready var _fade: ColorRect = %Fade

var _keys: Array[String] = []
var _shown := 0
var _tween: Tween = null
var _leaving := false


## The locale keys an opening shows for a background, in order: its own lines,
## or the fallback's for a life started without one, then the shared last line.
static func lines_for(background_id: String) -> Array[String]:
	var out := _numbered("opening.%s." % background_id)
	if out.is_empty():
		out = _numbered("opening.%s." % FALLBACK)
	out.append(LAST_LINE)
	return out


static func _numbered(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for n in range(1, MAX_LINES + 1):
		var key := prefix + str(n)
		if String(TranslationServer.translate(key)) == key:
			break
		out.append(key)
	return out


func _ready() -> void:
	if not Game.is_running():
		var started := Game.new_game()
		if started.is_err():
			Log.error("opening", "Could not start a world", {"reason": started.message})
	_keys = lines_for(Game.player.background_id)
	_template.visible = false
	_fade.color.a = 0.0
	reveal_next()
	DevCapture.maybe_capture(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		finish()
		return
	var key := event as InputEventKey
	var click := event as InputEventMouseButton
	if (key != null and key.pressed and not key.echo) or (click != null and click.pressed):
		get_viewport().set_input_as_handled()
		advance()


## What a key press does: finish the line that is fading in, else show the
## next one, else leave for the world.
func advance() -> void:
	if _tween != null and _tween.is_running():
		_tween.custom_step(FADE_SECONDS)
	elif _shown < _keys.size():
		reveal_next()
	else:
		finish()


func reveal_next() -> void:
	if _shown >= _keys.size():
		return
	var line: Label = _template.duplicate()
	line.visible = true
	line.text = Localization.t(_keys[_shown])
	line.modulate.a = 0.0
	_lines.add_child(line)
	_shown += 1
	_tween = create_tween()
	_tween.tween_property(line, "modulate:a", 1.0, FADE_SECONDS)
	_hint.visible = true


func finish() -> void:
	if _leaving:
		return
	_leaving = true
	_hint.visible = false
	var out := create_tween()
	out.tween_property(_fade, "color:a", 1.0, FADE_SECONDS)
	out.tween_callback(func() -> void: _go(WORLD))


func shown_keys() -> Array[String]:
	return _keys.slice(0, _shown)


## Where this screen goes next. Tests set `scene_changer` to see where it would
## go without replacing the test runner's own scene.
var scene_changer: Callable = Callable()


func _go(path: String) -> void:
	if scene_changer.is_valid():
		scene_changer.call(path)
	else:
		get_tree().change_scene_to_file(path)
