class_name Hud
extends CanvasLayer
## The layer over the world: when and where you are and how you are, what
## you can do right here, and what just happened. It shows; it decides
## nothing and knows no rules — the status words come from `StatusText`.

const MESSAGE_SECONDS := 4.0
## The event feed (D-059): the last few things that happened to the player,
## kept on screen a while, newest at the bottom.
const FEED_MAX := 6
const FEED_SECONDS := 14.0
const FEED_FADE := 2.0

@onready var _prompt: PanelContainer = $Bottom/Prompt
@onready var _prompt_label: Label = $Bottom/Prompt/Label
@onready var _message: PanelContainer = $Bottom/Message
@onready var _message_label: Label = $Bottom/Message/Label
@onready var _status_line: Label = $Status/Lines/Line
@onready var _condition: Label = $Status/Lines/Condition

var _message_left := 0.0
## [{"text": String, "left": float}], oldest first.
var _feed: Array[Dictionary] = []
var _feed_box: VBoxContainer = null


func _ready() -> void:
	_prompt.visible = false
	_message.visible = false
	_feed_box = VBoxContainer.new()
	_feed_box.name = "Feed"
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed_box.offset_left = -440.0
	_feed_box.offset_right = -16.0
	_feed_box.offset_top = 16.0
	_feed_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed_box.add_theme_constant_override("separation", 4)
	add_child(_feed_box)
	Events.money_moved.connect(_on_money_moved)
	Events.item_moved.connect(_on_item_moved)
	Events.skill_level_up.connect(_on_skill_up)
	Events.follow_changed.connect(_on_follow_changed)
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


## Tells the player something worth keeping: shown as the message and added to
## the feed, so it is still there a few moments later.
func notify(text: String) -> void:
	show_message(text)
	log_event(text)


## Adds a line to the event feed. Empty is ignored.
func log_event(text: String) -> void:
	if text.is_empty():
		return
	_feed.append({"text": text, "left": FEED_SECONDS})
	while _feed.size() > FEED_MAX:
		_feed.remove_at(0)
	_rebuild_feed()
	set_process(true)


## The feed's lines, oldest first.
func feed_lines() -> Array[String]:
	var out: Array[String] = []
	for entry in _feed:
		out.append(str(entry["text"]))
	return out


func _on_money_moved(amount: int, kind: String, reason: String) -> void:
	if Game.is_running():
		log_event(FeedText.money(amount, kind, reason))


func _on_item_moved(item_id: String, delta: int) -> void:
	if Game.is_running():
		log_event(FeedText.item(item_id, delta))


func _on_skill_up(skill_id: String, level: int) -> void:
	if Game.is_running():
		log_event(FeedText.skill_up(skill_id, level))


func _on_follow_changed(npc_id: String, following: bool, _why: String) -> void:
	if Game.is_running():
		log_event(FeedText.follow(npc_id, following))


func _rebuild_feed() -> void:
	for child in _feed_box.get_children():
		_feed_box.remove_child(child)
		child.queue_free()
	for entry in _feed:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.size_flags_horizontal = Control.SIZE_SHRINK_END
		var label := Label.new()
		label.text = str(entry["text"])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 16)
		panel.add_child(label)
		_feed_box.add_child(panel)


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
	var expired := false
	for i in range(_feed.size() - 1, -1, -1):
		_feed[i]["left"] = float(_feed[i]["left"]) - delta
		if float(_feed[i]["left"]) <= 0.0:
			_feed.remove_at(i)
			expired = true
	if expired:
		_rebuild_feed()
	var children := _feed_box.get_children()
	for i in mini(children.size(), _feed.size()):
		(children[i] as Control).modulate.a = clampf(float(_feed[i]["left"]) / FEED_FADE, 0.0, 1.0)
	if _message_left <= 0.0 and _feed.is_empty():
		set_process(false)


## The key bound to an action, for prompts: "E" rather than "interact".
static func key_hint(action: String) -> String:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			return OS.get_keycode_string(key.keycode if key.keycode != KEY_NONE else key.physical_keycode)
	return action
