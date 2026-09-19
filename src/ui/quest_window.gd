class_name QuestWindow
extends CanvasLayer
## The quest log (D-044): what is under way, who it is for, what the goal is
## and how long is left — and what is behind you. It states goals; it does
## not draw routes. It reads and never writes. Time stands still while it
## is open.

signal closed()

var _time_was_paused := false

@onready var _root: Control = $Root
@onready var _entries: VBoxContainer = %Entries
@onready var _close: Button = %Close


func _ready() -> void:
	_root.visible = false
	_close.pressed.connect(close)


func open() -> void:
	if _root.visible or not Game.is_running():
		return
	_time_was_paused = Game.clock.paused
	Game.pause_time(true)
	_render()
	_root.visible = true
	_close.grab_focus()


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	Game.pause_time(_time_was_paused)
	closed.emit()


func is_open() -> bool:
	return _root.visible


## Each entry as "title|from · when|goal", for tests and reading.
func entry_texts() -> Array[String]:
	var out: Array[String] = []
	for entry in _entries.get_children():
		var parts: Array[String] = []
		for child in entry.get_children():
			if child is Label and (child as Label).visible:
				parts.append((child as Label).text)
		out.append("|".join(parts))
	return out


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("quests")):
		get_viewport().set_input_as_handled()
		close()


func _render() -> void:
	for child in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()
	var entries := QuestText.entries()
	var behind := false
	for entry in entries:
		var finished := str(entry["status"]) in ["done", "failed"]
		if finished and not behind:
			behind = true
			var header := Label.new()
			header.theme_type_variation = &"MutedLabel"
			header.text = Localization.t("ui.quests.finished")
			var holder := VBoxContainer.new()
			holder.add_child(header)
			_entries.add_child(holder)
		_entries.add_child(_entry(entry, finished))
	if entries.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"MutedLabel"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.text = Localization.t("ui.quests.empty")
		var holder := VBoxContainer.new()
		holder.add_child(none)
		_entries.add_child(holder)


func _entry(entry: Dictionary, finished: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = str(entry["title"])
	title.add_theme_font_size_override("font_size", 20)
	if finished:
		title.theme_type_variation = &"MutedLabel"
	var meta := Label.new()
	meta.theme_type_variation = &"MutedLabel"
	var bits: Array[String] = []
	for key in ["from", "when"]:
		if str(entry[key]) != "":
			bits.append(str(entry[key]))
	meta.text = " · ".join(bits)
	meta.visible = not bits.is_empty()
	var goal := Label.new()
	goal.text = str(entry["goal"])
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if finished:
		goal.theme_type_variation = &"MutedLabel"
	for child: Control in [title, meta, goal]:
		box.add_child(child)
	return box
