class_name StashWindow
extends CanvasLayer
## The cupboard at home (D-043): what you carry on one side, what you keep
## on the other, and a button to move a thing across. `Game.store()` and
## `Game.take()` decide; a refusal is shown in plain words. Time stands still
## while it is open.

signal closed()

var _time_was_paused := false

@onready var _root: Control = $Root
@onready var _carried: VBoxContainer = %CarriedRows
@onready var _stored: VBoxContainer = %StoredRows
@onready var _message: Label = %Message
@onready var _weights: Label = %Weights
@onready var _close: Button = %Close


func _ready() -> void:
	_root.visible = false
	_close.pressed.connect(close)


func open() -> void:
	if _root.visible or not Game.is_running():
		return
	_time_was_paused = Game.clock.paused
	Game.pause_time(true)
	_message.text = ""
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


func store(item_id: String) -> Result:
	var stored := Game.store(item_id, 1)
	_report(stored)
	return stored


func take(item_id: String) -> Result:
	var taken := Game.take(item_id, 1)
	_report(taken)
	return taken


## "name|count" per row, carried first then stored, for tests and reading.
func carried_texts() -> Array[String]:
	return _texts(_carried)


func stored_texts() -> Array[String]:
	return _texts(_stored)


func message() -> String:
	return _message.text


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _report(result: Result) -> void:
	if result.is_ok():
		_message.text = ""
	else:
		var key := "ui.stash.refused." + result.code
		_message.text = Localization.t(key) if Localization.t(key) != key else Localization.t("ui.bag.refused.other")
	_render()


func _render() -> void:
	_fill(_carried, Game.player.inventory, "ui.stash.put", store, "ui.bag.empty")
	_fill(_stored, Game.player.stash, "ui.stash.take", take, "ui.stash.empty")
	_weights.text = Localization.t("ui.stash.weights", {
		"carried": "%.1f" % Game.player.inventory.total_weight(),
		"capacity": "%.0f" % Game.player.inventory.capacity(),
		"stored": "%.1f" % Game.player.stash.total_weight(),
		"room": "%.0f" % Game.player.stash.capacity(),
	})


func _fill(rows: VBoxContainer, inventory: Inventory, action_key: String, action: Callable, empty_key: String) -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for item_id in inventory.item_ids():
		var item := Game.data.get_entry("items", item_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var item_name := Label.new()
		item_name.text = Localization.t(str(item.get("name_key", item_id)))
		item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var count := Label.new()
		count.text = "× %d" % inventory.count_of(item_id)
		count.custom_minimum_size = Vector2(56, 0)
		var button := Button.new()
		button.theme_type_variation = &"SmallButton"
		button.custom_minimum_size = Vector2(110, 0)
		button.text = Localization.t(action_key)
		button.pressed.connect(func() -> void: action.call(item_id))
		for child: Control in [item_name, count, button]:
			row.add_child(child)
		rows.add_child(row)
	if inventory.item_ids().is_empty():
		var holder := HBoxContainer.new()
		var none := Label.new()
		none.theme_type_variation = &"MutedLabel"
		none.text = Localization.t(empty_key)
		holder.add_child(none)
		rows.add_child(holder)


static func _texts(rows: VBoxContainer) -> Array[String]:
	var out: Array[String] = []
	for row in rows.get_children():
		var parts: Array[String] = []
		for child in row.get_children():
			if child is Label:
				parts.append((child as Label).text)
		out.append("|".join(parts))
	return out
