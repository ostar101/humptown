class_name TimeSkipOverlay
extends CanvasLayer
## Time passing (D-076): when a night's sleep or a whole shift goes by in one
## step, the screen should say so instead of jumping. The old picture dims to
## black, a line says what is happening while the clock runs from when it
## started to when it ended, and the new picture is uncovered.
##
## Pure presentation: the world has already moved on by the time this plays,
## which is why the old frame is kept as a picture and faded rather than the
## world being faded (it would show the morning going dark). Any key or click
## skips it. It never decides or changes anything.

signal finished()

const FADE_TO_BLACK := 0.5
const FADE_FROM_BLACK := 0.55
const HOLD_MIN := 0.9
const HOLD_MAX := 2.2
## Real seconds of holding per game hour that pass, past the minimum.
const HOLD_PER_HOUR := 0.12

var _tween: Tween = null
var _playing := false
var _from := 0
var _to := 0

@onready var _root: Control = $Root
@onready var _picture: TextureRect = %Picture
@onready var _black: ColorRect = %Black
@onready var _words: VBoxContainer = %Words
@onready var _title: Label = %Title
@onready var _clock: Label = %Clock


func _ready() -> void:
	_root.visible = false


func is_playing() -> bool:
	return _playing


## The clock as it reads now, for tests and reading.
func shown_time() -> String:
	return _clock.text


func shown_title() -> String:
	return _title.text


## Plays it. `title` is already in the player's language. From and to are
## absolute game minutes; equal, and no clock is shown. `snapshot` is the frame
## from before the jump, or null to start from black.
func play(title: String, from_minute: int, to_minute: int, snapshot: Texture2D = null) -> void:
	if _tween != null:
		_tween.kill()
	_playing = true
	_from = from_minute
	_to = to_minute
	_title.text = title
	_clock.visible = to_minute != from_minute
	_clock.text = _format(from_minute)
	_picture.texture = snapshot
	_picture.visible = snapshot != null
	_black.modulate.a = 0.0 if snapshot != null else 1.0
	_words.modulate.a = 0.0
	_root.visible = true
	var hold := clampf(HOLD_MIN + float(absi(to_minute - from_minute)) / 60.0 * HOLD_PER_HOUR, HOLD_MIN, HOLD_MAX)
	_tween = create_tween()
	if snapshot != null:
		_tween.tween_property(_black, "modulate:a", 1.0, FADE_TO_BLACK)
	_tween.tween_property(_words, "modulate:a", 1.0, 0.25)
	if to_minute != from_minute:
		_tween.tween_method(_set_progress, 0.0, 1.0, hold)
	else:
		_tween.tween_interval(hold * 0.6)
	_tween.tween_property(_words, "modulate:a", 0.0, 0.2)
	_tween.tween_callback(_picture.hide)
	_tween.tween_property(_black, "modulate:a", 0.0, FADE_FROM_BLACK)
	_tween.tween_callback(_done)


## Ends it now.
func skip() -> void:
	if not _playing:
		return
	if _tween != null:
		_tween.kill()
	_done()


func _done() -> void:
	_playing = false
	_root.visible = false
	finished.emit()


func _input(event: InputEvent) -> void:
	if _playing and ((event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed)):
		get_viewport().set_input_as_handled()
		skip()


func _set_progress(progress: float) -> void:
	_clock.text = _format(int(round(lerpf(float(_from), float(_to), progress))))


static func _format(total_minutes: int) -> String:
	var minute_of_day := posmod(total_minutes, GameClock.MINUTES_PER_DAY)
	return "%02d:%02d" % [minute_of_day / 60, minute_of_day % 60]
