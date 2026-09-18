class_name Hud
extends CanvasLayer
## The layer over the world: what you can do right here, and what just
## happened. Shows text it is given; it decides nothing and knows no rules.

const MESSAGE_SECONDS := 4.0

@onready var _prompt: PanelContainer = $Bottom/Prompt
@onready var _prompt_label: Label = $Bottom/Prompt/Label
@onready var _message: PanelContainer = $Bottom/Message
@onready var _message_label: Label = $Bottom/Message/Label

var _message_left := 0.0


func _ready() -> void:
	_prompt.visible = false
	_message.visible = false
	set_process(false)


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
