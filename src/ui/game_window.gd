class_name GameWindow
extends CanvasLayer
## Shared shape for every modal game window (M8 step 2, D-078): pauses the
## clock while open, restores it on close, closes on Esc and its own toggle
## key, and looks up a refusal message the same way everywhere. Owns none of
## a window's rendering, data or focus — only the ~25 lines every window had
## copied.

signal closed()

## The input action that also closes this window besides "ui_cancel" — its
## own open key, "inventory" or "craft" for example. "" if it has none.
var toggle_action := ""

var _time_was_paused := false

@onready var _root: Control = $Root
@onready var _close: Button = %Close


func _ready() -> void:
	_root.visible = false
	_close.pressed.connect(close)


func open() -> void:
	if _root.visible or not Game.is_running():
		return
	_time_was_paused = Game.clock.paused
	Game.pause_time(true)
	_before_show()
	_root.visible = true
	_focus_first()


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	Game.pause_time(_time_was_paused)
	closed.emit()


func is_open() -> bool:
	return _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event.is_action_pressed("ui_cancel") or (toggle_action != "" and event.is_action_pressed(toggle_action)):
		get_viewport().set_input_as_handled()
		close()


## Renders and resets whatever the window shows, called just before it
## becomes visible. Subclasses override; the base does nothing.
func _before_show() -> void:
	pass


## Focuses the first sensible control. Subclasses override; the base falls
## back to the close button.
func _focus_first() -> void:
	_close.grab_focus()


## `"<prefix>.refused." + code`, falling back to `"<prefix>.refused.other"`
## when nothing specific is authored for that refusal.
func _refusal_text(prefix: String, code: String) -> String:
	var key := prefix + ".refused." + code
	return Localization.t(key) if Localization.t(key) != key else Localization.t(prefix + ".refused.other")
