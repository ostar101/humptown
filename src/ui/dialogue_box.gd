class_name DialogueBox
extends CanvasLayer
## Talking to someone (D-035), laid out the way the design plan describes it:
## who is speaking in the upper left, their words appearing a letter at a
## time, and the player's own words typed freely at the bottom. The quick
## replies are shortcuts for a few common things to say; they never replace
## the text field, which is always there.
##
## Presentation only: it hands what the player typed to `Game.say_to_npc()`
## and shows what comes back. Whether a conversation can start at all, and
## what is said in reply, are Game's.

signal closed()

## How fast a line appears. Quick enough not to drag, slow enough to read as
## someone speaking. Any key or click shows the rest at once.
const CHARS_PER_SECOND := 55.0
## After a goodbye, how long the last line stays before the box closes.
const LINGER_AFTER_GOODBYE := 1.6

@onready var _name: Label = %Name
@onready var _line: RichTextLabel = %Line
@onready var _portrait: CharacterFigure = %Portrait
@onready var _entry: LineEdit = %Entry
@onready var _send: Button = %Send
@onready var _leave: Button = %Leave
@onready var _quick: HBoxContainer = %Quick

var _npc_id := ""
var _reveal: Tween = null
var _leaving := false


func _ready() -> void:
	visible = false
	_line.bbcode_enabled = false   # what people say is shown as said, never as markup
	_entry.text_submitted.connect(func(text: String) -> void: submit(text))
	_send.pressed.connect(func() -> void: submit(_entry.text))
	_leave.pressed.connect(close)
	for button: Button in _quick.get_children():
		var topic := str(button.name)
		button.pressed.connect(func() -> void: submit(Localization.t("ui.dialogue.quick." + topic)))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and is_revealing():
		finish_reveal()


## Starts talking to someone. Refused (and left closed) when Game says they
## cannot be talked to; the caller shows why.
func open(npc_id: String) -> Result:
	var started := Game.start_conversation(npc_id)
	if started.is_err():
		return started
	_npc_id = npc_id
	_leaving = false
	var npc := Game.npcs.get_npc(npc_id)
	var palette := NpcLook.palette_for(npc)
	_portrait.palette = palette
	_portrait.look = CharacterSprites.look_for(npc_id, palette)
	_portrait.facing = Vector2i.DOWN
	_name.text = Game.dialogue.display_name(npc_id, Game.data)
	_set_input_enabled(true)
	visible = true
	_entry.text = ""
	_show_line(str((started.value as Dictionary)["text"]))
	_entry.grab_focus()
	return started


## Says something. Empty or refused input is ignored and nothing is shown.
func submit(text: String) -> Result:
	if not visible or _leaving:
		return Result.failure("not_talking")
	var said := Game.say_to_npc(text)
	if said.is_err():
		return said
	var reply: Dictionary = said.value
	_entry.text = ""
	# Asking who someone is can be how you learn their name.
	_name.text = Game.dialogue.display_name(_npc_id, Game.data)
	_show_line(str(reply["text"]))
	if reply["ends"]:
		_leaving = true
		_set_input_enabled(false)
		var linger := str(reply["text"]).length() / CHARS_PER_SECOND + LINGER_AFTER_GOODBYE
		get_tree().create_timer(linger).timeout.connect(close)
	else:
		_entry.grab_focus()
	return said


func close() -> void:
	if not visible:
		return
	if Game.dialogue.is_talking():
		Game.end_conversation()
	if _reveal != null:
		_reveal.kill()
	visible = false
	_leaving = false
	closed.emit()


func is_open() -> bool:
	return visible


func is_revealing() -> bool:
	return _reveal != null and _reveal.is_running()


func finish_reveal() -> void:
	if is_revealing():
		_reveal.kill()
	_line.visible_ratio = 1.0


## What the person is saying now, all of it, whether or not it has finished
## appearing. For tests.
func line_text() -> String:
	return _line.text


func speaker_name() -> String:
	return _name.text


func _show_line(text: String) -> void:
	_line.text = text
	_line.visible_ratio = 0.0
	if _reveal != null:
		_reveal.kill()
	_reveal = create_tween()
	_reveal.tween_property(_line, "visible_ratio", 1.0, maxf(text.length() / CHARS_PER_SECOND, 0.05))


func _set_input_enabled(enabled: bool) -> void:
	_entry.editable = enabled
	_send.disabled = not enabled
	for button: Button in _quick.get_children():
		button.disabled = not enabled
