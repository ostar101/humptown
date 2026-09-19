class_name ShopWindow
extends CanvasLayer
## A shop's counter (D-039): what is for sale and at what price, what the
## shop would buy from you, and your money — a JRPG shop, in the house style.
##
## It shows and asks; `Game` decides. Every purchase and sale goes through
## `Game.buy()` / `Game.sell()`, and a refusal is shown in the counter's own
## words. Time stands still while the window is open.

signal closed()

var _selling := false

@onready var _root: Control = $Root
@onready var _title: Label = %Title
@onready var _serving: Label = %Serving
@onready var _buy_tab: Button = %BuyTab
@onready var _sell_tab: Button = %SellTab
@onready var _rows: VBoxContainer = %Rows
@onready var _message: Label = %Message
@onready var _money: Label = %Money
@onready var _leave: Button = %Leave


func _ready() -> void:
	_root.visible = false
	_buy_tab.pressed.connect(func() -> void: show_selling(false))
	_sell_tab.pressed.connect(func() -> void: show_selling(true))
	_leave.pressed.connect(close)


## Steps up to the counter of the shop the player is in. A refusal
## (`nobody_serving`, `not_a_shop`) comes back and nothing opens.
func open() -> Result:
	var opened := Game.open_shop()
	if opened.is_err():
		return opened
	_selling = false
	_buy_tab.button_pressed = true
	_message.text = ""
	_render()
	_root.visible = true
	_focus_first()
	return opened


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	Game.close_shop()
	closed.emit()


func is_open() -> bool:
	return _root.visible


func show_selling(selling: bool) -> void:
	_selling = selling
	_sell_tab.button_pressed = selling
	_buy_tab.button_pressed = not selling
	_message.text = ""
	_render()
	_focus_first()


func buy(item_id: String) -> Result:
	var bought := Game.buy(item_id, 1)
	_report(bought, "ui.shop.bought")
	return bought


## Tries to walk off with it (D-051). The counter says only what the player
## can tell: their hand was stopped, or it was not — never who saw.
func steal(item_id: String) -> Result:
	var tried := Game.steal(item_id)
	if tried.is_ok():
		var outcome: Dictionary = tried.value
		var item := Game.data.get_entry("items", item_id)
		_message.text = Localization.t("ui.shop.stole_caught" if outcome["caught"] else "ui.shop.stole_taken", {
			"name": Game.dialogue.display_name(str(outcome["staff"]), Game.data),
			"item": Localization.t(str(item.get("name_key", item_id))),
		})
		_render()
	else:
		_report(tried, "")
	return tried


## Tries to talk the price down (D-040); the counter says how it went.
func haggle(item_id: String) -> Result:
	var tried := Game.haggle(item_id)
	if tried.is_ok():
		var outcome: Dictionary = tried.value
		var item := Game.data.get_entry("items", item_id)
		var args := {
			"name": Game.dialogue.display_name(str(outcome["staff"]), Game.data),
			"item": Localization.t(str(item.get("name_key", item_id))),
			"percent": int(round(float(outcome["discount"]) * 100.0)),
		}
		_message.text = Localization.t("ui.shop.haggle_won" if outcome["won"] else "ui.shop.haggle_lost", args)
		_render()
	else:
		_report(tried, "")
	return tried


func sell(item_id: String) -> Result:
	var sold := Game.sell(item_id, 1)
	_report(sold, "ui.shop.sold")
	return sold


## The rows as shown, "name|price|detail", for tests and for reading.
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
	if _root.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _report(result: Result, done_key: String) -> void:
	if result.is_ok():
		var outcome: Dictionary = result.value
		var item := Game.data.get_entry("items", str(outcome["item"]))
		_message.text = Localization.t(done_key, {
			"item": Localization.t(str(item.get("name_key", outcome["item"]))), "total": outcome["total"]})
	else:
		var key := "ui.shop.refused." + result.code
		_message.text = Localization.t(key) if Localization.t(key) != key else Localization.t("ui.shop.refused.other")
	_render()


func _render() -> void:
	var view := Game.shop_view()
	if view.is_empty():
		return
	_title.text = InteractionText.place_name(str(view["location"]))
	var staff := str(view["staff"])
	_serving.text = Localization.t("ui.shop.serving", {"name": Game.dialogue.display_name(staff, Game.data)}) \
		if staff != "" else ""
	_money.text = Localization.t("ui.shop.money", {"cash": view["cash"], "bank": view["bank"]})

	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var entries: Array = view["will_buy"] if _selling else view["for_sale"]
	for entry: Dictionary in entries:
		_rows.add_child(_row(entry))
	if entries.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"MutedLabel"
		none.text = Localization.t("ui.shop.nothing_to_sell" if _selling else "ui.shop.nothing_for_sale")
		var holder := HBoxContainer.new()
		holder.add_child(none)
		_rows.add_child(holder)


func _row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var item_name := Label.new()
	item_name.text = Localization.t(str(entry["name_key"]))
	item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var price := Label.new()
	price.text = Localization.t("ui.shop.price", {"price": entry["price"]})
	price.custom_minimum_size = Vector2(80, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var detail := Label.new()
	detail.theme_type_variation = &"MutedLabel"
	detail.custom_minimum_size = Vector2(130, 0)
	var action := Button.new()
	action.theme_type_variation = &"SmallButton"
	action.custom_minimum_size = Vector2(90, 0)
	var item_id := str(entry["item"])
	if _selling:
		detail.text = Localization.t("ui.shop.owned", {"count": entry["owned"]})
		action.text = Localization.t("ui.shop.sell")
		action.pressed.connect(func() -> void: sell(item_id))
	else:
		var off := int(round(float(entry.get("discount", 0.0)) * 100.0))
		if off > 0:
			detail.text = Localization.t("ui.shop.stock_discounted", {"count": entry["stock"], "percent": off})
		else:
			detail.text = Localization.t("ui.shop.stock", {"count": entry["stock"]})
		action.text = Localization.t("ui.shop.buy")
		action.disabled = int(entry["stock"]) <= 0
		action.pressed.connect(func() -> void: buy(item_id))
		var bargain := Button.new()
		bargain.theme_type_variation = &"SmallButton"
		bargain.custom_minimum_size = Vector2(90, 0)
		bargain.text = Localization.t("ui.shop.haggle")
		bargain.disabled = bool(entry.get("haggled", false))
		bargain.pressed.connect(func() -> void: haggle(item_id))
		var pocket := Button.new()
		pocket.theme_type_variation = &"SmallButton"
		pocket.custom_minimum_size = Vector2(90, 0)
		pocket.text = Localization.t("ui.shop.pocket")
		pocket.disabled = int(entry["stock"]) <= 0
		pocket.pressed.connect(func() -> void: steal(item_id))
		for child: Control in [item_name, price, detail, pocket, bargain, action]:
			row.add_child(child)
		return row
	for child: Control in [item_name, price, detail, action]:
		row.add_child(child)
	return row


## Focus on the first row's main action — Buy or Sell, the last button in a
## row — so the keyboard's first press is the plain one, not a haggle.
func _focus_first() -> void:
	for row in _rows.get_children():
		var buttons := row.get_children().filter(func(c: Node) -> bool: return c is Button and not (c as Button).disabled)
		if not buttons.is_empty():
			(buttons[-1] as Button).grab_focus()
			return
	_leave.grab_focus()
