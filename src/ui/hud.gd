class_name Hud
extends CanvasLayer
## The layer over the world: when and where you are and how you are, what
## you can do right here, and what just happened. It shows; it decides
## nothing and knows no rules — the status words come from `StatusText`.

const MESSAGE_SECONDS := 4.0

@onready var _prompt: PanelContainer = $Bottom/Prompt
@onready var _prompt_label: Label = $Bottom/Prompt/Label
@onready var _message: PanelContainer = $Bottom/Message
@onready var _message_label: Label = $Bottom/Message/Label
@onready var _status_line: Label = $Status/Lines/Line
@onready var _condition: Label = $Status/Lines/Condition

var _message_left := 0.0


func _ready() -> void:
	_prompt.visible = false
	_message.visible = false
	set_process(false)
	for changed: Signal in [Events.minute_passed, Events.time_skipped, Events.money_changed,
			Events.condition_changed, Events.location_entered, Events.game_loaded, Events.locale_changed,
			Events.phone_message, Events.phone_read]:
		changed.connect(_on_status_changed)
	refresh_status()


## Rewrites the status corner from the world as it is now.
func refresh_status() -> void:
	_status_line.text = StatusText.line()
	var condition := StatusText.condition()
	_condition.text = condition
	_condition.visible = condition != ""


func status_text() -> String:
	return _status_line.text + ("\n" + _condition.text if _condition.visible else "")


## Any of the signals it listens to, whatever they carry.
func _on_status_changed(_a: Variant = null, _b: Variant = null) -> void:
	refresh_status()


## Empty hides the prompt.
func set_prompt(text: String) -> void:
	_prompt.visible = not text.is_empty()
	_prompt_label.text = "" if text.is_empty() else "[%s]  %s" % [key_hint("interact"), text]


## Shows a line for a few seconds. Empty is ignored.
func show_message(text: String) -> void:
	if text.is_empty():
		return
	_message_label.text = text
	_message.visible = true
	_message_left = MESSAGE_SECONDS
	set_process(true)


func prompt_text() -> String:
	return _prompt_label.text if _prompt.visible else ""


func message_text() -> String:
	return _message_label.text if _message.visible else ""


func _process(delta: float) -> void:
	_message_left -= delta
	if _message_left <= 0.0:
		_message.visible = false
		set_process(false)


## The key bound to an action, for prompts: "E" rather than "interact".
static func key_hint(action: String) -> String:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			return OS.get_keycode_string(key.keycode if key.keycode != KEY_NONE else key.physical_keycode)
	return action
