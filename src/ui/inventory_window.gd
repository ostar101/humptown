class_name InventoryWindow
extends GameWindow
## What the player carries (D-041): each thing, how many, what it weighs,
## and a Use for what can be eaten, drunk or put on a wound. Using goes
## through `Game.use_item()`, which decides; a refusal is shown in plain
## words. Time stands still while it is open; using something takes the
## minutes it takes.

@onready var _condition: Label = %Condition
@onready var _rows: VBoxContainer = %Rows
@onready var _message: Label = %Message
@onready var _carrying: Label = %Carrying
@onready var _job: Label = %Job


func _ready() -> void:
	super._ready()
	toggle_action = "inventory"


func use(item_id: String) -> Result:
	var used := Game.use_item(item_id)
	var item := Game.data.get_entry("items", item_id)
	var item_name := Localization.t(str(item.get("name_key", item_id)))
	if used.is_ok():
		_message.text = Localization.t("ui.bag.used." + str(item.get("kind", "food")), {"item": item_name})
	else:
		_message.text = _refusal_text("ui.bag", used.code)
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


func _before_show() -> void:
	_message.text = ""
	_render()


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
	_job.text = StatusText.job()
	_job.visible = _job.text != ""
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
	var total := float(item.get("weight", 0.0)) * count
	weight.text = ("%.2f kg" if total < 0.1 else "%.1f kg") % total   # a paper weighs grams, and says so
	weight.custom_minimum_size = Vector2(80, 0)
	weight.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(ItemIcons.tile(item_id, 40))
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
