class_name StashWindow
extends CanvasLayer
## The cupboard at home (D-043): what you carry on one side, what you keep
## on the other, and a button to move a thing across. `Game.store()` and
## `Game.take()` decide; a refusal is shown in plain words. Time stands still
## while it is open.
##
## The same window is a street bin's (D-069) when `use_as_bin()` has been called:
## the other side is what is in the bin, and `Game.bin_put()` / `bin_take()` decide.

signal closed()

var _time_was_paused := false
## "stash" or "bin": which words to use and which of Game's rules decide.
var kind := "stash"

@onready var _root: Control = $Root
@onready var _carried: VBoxContainer = %CarriedRows
@onready var _stored: VBoxContainer = %StoredRows
@onready var _message: Label = %Message
@onready var _weights: Label = %Weights
@onready var _close: Button = %Close


func _ready() -> void:
	_root.visible = false
	_close.pressed.connect(close)


## Makes this window the one for bins.
func use_as_bin() -> void:
	kind = "bin"


func open() -> void:
	if _root.visible or not Game.is_running():
		return
	if kind == "bin" and Game.bin_contents() == null:
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
	if kind == "bin":
		Game.close_bin()
	Game.pause_time(_time_was_paused)
	closed.emit()


func is_open() -> bool:
	return _root.visible


func store(item_id: String) -> Result:
	var stored := Game.bin_put(item_id, 1) if kind == "bin" else Game.store(item_id, 1)
	_report(stored)
	return stored


func take(item_id: String) -> Result:
	var taken := Game.bin_take(item_id, 1) if kind == "bin" else Game.take(item_id, 1)
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
		var key := "ui.%s.refused.%s" % [kind, result.code]
		_message.text = Localization.t(key) if Localization.t(key) != key else Localization.t("ui.bag.refused.other")
	_render()


func _render() -> void:
	var other: Inventory = Game.bin_contents() if kind == "bin" else Game.player.stash
	if other == null:
		return
	($Root/Frame/Layout/Title as Label).text = Localization.t("ui.%s.title" % kind)
	($Root/Frame/Layout/Columns/Stored/StoredTitle as Label).text = Localization.t("ui.%s.stored" % kind)
	_fill(_carried, Game.player.inventory, "ui.%s.put" % kind, store, "ui.bag.empty")
	_fill(_stored, other, "ui.%s.take" % kind, take, "ui.%s.empty" % kind)
	_weights.text = Localization.t("ui.%s.weights" % kind, {
		"carried": "%.1f" % Game.player.inventory.total_weight(),
		"capacity": "%.0f" % Game.player.inventory.capacity(),
		"stored": "%.1f" % other.total_weight(),
		"room": "%.0f" % other.capacity(),
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
		row.add_child(ItemIcons.tile(item_id, 36))
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
