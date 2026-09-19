class_name InventoryWindow
extends CanvasLayer
## What the player carries (D-041): each thing, how many, what it weighs,
## and a Use for what can be eaten, drunk or put on a wound. Using goes
## through `Game.use_item()`, which decides; a refusal is shown in plain
## words. Time stands still while it is open; using something takes the
## minutes it takes.

signal closed()

var _time_was_paused := false

@onready var _root: Control = $Root
@onready var _condition: Label = %Condition
@onready var _rows: VBoxContainer = %Rows
@onready var _message: Label = %Message
@onready var _carrying: Label = %Carrying
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
	_focus_first()


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	Game.pause_time(_time_was_paused)
	closed.emit()


func is_open() -> bool:
	return _root.visible


func use(item_id: String) -> Result:
	var used := Game.use_item(item_id)
	var item := Game.data.get_entry("items", item_id)
	var item_name := Localization.t(str(item.get("name_key", item_id)))
	if used.is_ok():
		_message.text = Localization.t("ui.bag.used." + str(item.get("kind", "food")), {"item": item_name})
	else:
		var key := "ui.bag.refused." + used.code
		_message.text = Localization.t(key) if Localization.t(key) != key else Localization.t("ui.bag.refused.other")
	_render()
	return used


## The rows as shown, "name|count|weight", for tests and for reading.
func row_texts() -> Array[String]:
	var out: Array[String] = []
	for row in _rows.get_children():
		var parts: Array[String] = []
		for child in row.get_children():
			if child is Label:
				parts.append((child as Label).text)
		out.append("|".join(parts))
	return out


func message() -> String:
	return _message.text


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory")):
		get_viewport().set_input_as_handled()
		close()


func _render() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var inventory := Game.player.inventory
	for item_id in inventory.item_ids():
		_rows.add_child(_row(item_id, inventory.count_of(item_id)))
	if inventory.item_ids().is_empty():
		var holder := HBoxContainer.new()
		var none := Label.new()
		none.theme_type_variation = &"MutedLabel"
		none.text = Localization.t("ui.bag.empty")
		holder.add_child(none)
		_rows.add_child(holder)
	_condition.text = StatusText.condition()
	_carrying.text = Localization.t("ui.bag.carrying", {
		"weight": "%.1f" % inventory.total_weight(), "capacity": "%.0f" % inventory.capacity(),
		"cash": Game.player.wallet.cash,
	})


func _row(item_id: String, count: int) -> HBoxContainer:
	var item := Game.data.get_entry("items", item_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var item_name := Label.new()
	item_name.text = Localization.t(str(item.get("name_key", item_id)))
	item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var how_many := Label.new()
	how_many.text = "× %d" % count
	how_many.custom_minimum_size = Vector2(60, 0)
	var weight := Label.new()
	weight.theme_type_variation = &"MutedLabel"
	weight.text = "%.1f kg" % (float(item.get("weight", 0.0)) * count)
	weight.custom_minimum_size = Vector2(80, 0)
	weight.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for child: Control in [item_name, how_many, weight]:
		row.add_child(child)
	if not ItemRules.effects_of(item).is_empty() and ItemRules.USABLE_KINDS.has(str(item.get("kind", ""))):
		var action := Button.new()
		action.theme_type_variation = &"SmallButton"
		action.custom_minimum_size = Vector2(90, 0)
		action.text = Localization.t("ui.bag.use")
		action.pressed.connect(func() -> void: use(item_id))
		row.add_child(action)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(90, 0)
		row.add_child(spacer)
	return row


func _focus_first() -> void:
	for row in _rows.get_children():
		for child in row.get_children():
			if child is Button:
				(child as Button).grab_focus()
				return
	_close.grab_focus()
