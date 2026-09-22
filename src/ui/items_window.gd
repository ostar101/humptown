class_name ItemsWindow
extends GameWindow
## Everything the player carries and can put together, in one window (M8
## step 3, D-079): the bag, the bench, and the recipes you know, as three
## tabs. `I` opens on the bag, `C` opens on the bench; if the window is
## already open the key switches tab instead of closing it.
##
## It shows and proposes. Using goes through `Game.use_item()` and crafting
## through `Game.craft()`, both deciding; a refusal is shown in plain words.
## Time stands still while it is open.

enum Tab { BAG, BENCH, RECIPES }

const SLOTS := 9
const GRID_SLOT := 60.0
const OUTPUT_SLOT := 84.0
const BAG_SLOT := 56.0

var _tab: Tab = Tab.BAG
## What lies on each bench slot, "" for nothing.
var _placed: Array[String] = []
var _grid_slots: Array[ItemSlot] = []
var _output: ItemSlot = null

@onready var _condition: Label = %Condition
@onready var _job: Label = %Job
@onready var _message: Label = %Message
@onready var _carrying: Label = %Carrying
@onready var _bag_tab: Button = %BagTab
@onready var _bench_tab: Button = %BenchTab
@onready var _recipes_tab: Button = %RecipesTab
@onready var _bag_body: Control = %BagBody
@onready var _bench_body: Control = %BenchBody
@onready var _recipes_body: Control = %RecipesBody
@onready var _rows: VBoxContainer = %Rows
@onready var _grid: GridContainer = %Grid
@onready var _output_holder: VBoxContainer = %OutputHolder
@onready var _result: Label = %Result
@onready var _make: Button = %Make
@onready var _clear: Button = %Clear
@onready var _bag_grid: GridContainer = %BagGrid
@onready var _book_rows: VBoxContainer = %BookRows


func _ready() -> void:
	super._ready()
	_bag_tab.pressed.connect(func() -> void: show_tab(Tab.BAG))
	_bench_tab.pressed.connect(func() -> void: show_tab(Tab.BENCH))
	_recipes_tab.pressed.connect(func() -> void: show_tab(Tab.RECIPES))
	_make.pressed.connect(make)
	_clear.pressed.connect(clear)
	for i in SLOTS:
		_placed.append("")
		var slot := ItemSlot.new(GRID_SLOT)
		slot.pressed.connect(func() -> void: take_off(i))
		_grid.add_child(slot)
		_grid_slots.append(slot)
	_output = ItemSlot.new(OUTPUT_SLOT)
	_output.pressed.connect(make)
	_output_holder.add_child(_output)


## Opens on a given tab, or switches to it if already open — it never closes
## the window, which is what makes `I`/`C` behave as tab keys once merged.
func open_on(tab: Tab) -> void:
	if is_open():
		show_tab(tab)
		return
	_tab = tab
	open()


func current_tab() -> Tab:
	return _tab


func show_tab(tab: Tab) -> void:
	_tab = tab
	_bag_tab.button_pressed = tab == Tab.BAG
	_bench_tab.button_pressed = tab == Tab.BENCH
	_recipes_tab.button_pressed = tab == Tab.RECIPES
	_bag_body.visible = tab == Tab.BAG
	_bench_body.visible = tab == Tab.BENCH
	_recipes_body.visible = tab == Tab.RECIPES
	_message.text = ""
	_render()
	_focus_first()


func _before_show() -> void:
	Game.refresh_recipes()
	_placed.fill("")
	_message.text = ""
	show_tab(_tab)


# --- the bag --------------------------------------------------------------------

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


## The bag rows as shown, "name|count|weight", for tests and for reading.
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


# --- the bench --------------------------------------------------------------------

## Lays one of a thing from the bag on the first empty slot. Refused
## `not_owned` (all of it is already on the grid) and `grid_full`.
func place(item_id: String) -> Result:
	var owned := Game.player.inventory.count_of(item_id)
	if owned - _placed.count(item_id) < 1:
		return _refuse("not_owned")
	var free := _placed.find("")
	if free < 0:
		return _refuse("grid_full")
	_placed[free] = item_id
	_message.text = ""
	_render()
	return Result.success(free)


func take_off(slot: int) -> void:
	if slot < 0 or slot >= SLOTS or _placed[slot] == "":
		return
	_placed[slot] = ""
	_message.text = ""
	_render()


func clear() -> void:
	_placed.fill("")
	_message.text = ""
	_render()


## Clears the grid and lays out a known recipe from what the bag holds. Refused
## `unknown_recipe`, and `missing` when the bag lacks something for it — the part
## it has is still laid out, so the gap can be seen.
func fill_recipe(recipe_id: String) -> Result:
	var recipe := Game.data.get_entry("recipes", recipe_id)
	if recipe.is_empty() or not Game.player.known_recipes.has(recipe_id):
		return _refuse("unknown_recipe")
	_placed.fill("")
	var short := false
	var inputs := CraftRules.inputs_of(recipe)
	if bool(recipe.get("fire", false)):
		# whichever light the bag has, the lighter first
		var light := CraftRules.FIRE[0] if Game.player.inventory.has(CraftRules.FIRE[0]) else CraftRules.FIRE[1]
		inputs[light] = 1
	for item_id: String in inputs:
		for n in int(inputs[item_id]):
			var free := _placed.find("")
			if free < 0 or Game.player.inventory.count_of(item_id) - _placed.count(item_id) < 1:
				short = true
				break
			_placed[free] = item_id
	_message.text = Localization.t("ui.craft.refused.missing") if short else ""
	_render()
	return Result.failure("missing") if short else Result.success()


## Makes what the grid makes. Refused as `Game.craft()` refuses (`no_recipe`,
## `not_owned`, `too_heavy`, `busy`).
func make() -> Result:
	var made := Game.craft(_placed)
	if made.is_err():
		return _refuse(made.code)
	var info: Dictionary = made.value
	_message.text = Localization.t("ui.craft.made", {
		"what": _things(info["outputs"]), "minutes": info["minutes"]})
	if bool(info["learned"]):
		_message.text += " " + Localization.t("ui.craft.learned")
	_trim_to_bag()
	_render()
	return made


# --- what tests and reading ask ------------------------------------------------

## What lies on the grid, slot by slot; "" for an empty one.
func grid_ids() -> Array[String]:
	return _placed.duplicate()


## The first thing the grid would make, or "".
func output_id() -> String:
	return _output.item_id if _output != null else ""


func can_make() -> bool:
	return not _make.disabled


func result_text() -> String:
	return _result.text


## The bag's slots as "item_id|left": how many of each are not yet on the grid.
func bag_texts() -> Array[String]:
	var out: Array[String] = []
	for slot in _bag_grid.get_children():
		if slot is ItemSlot:
			var item_slot := slot as ItemSlot
			out.append("%s|%d" % [item_slot.item_id, item_slot.count])
	return out


## The recipe book's names, in order.
func book_texts() -> Array[String]:
	var out: Array[String] = []
	for row in _book_rows.get_children():
		for child in row.get_children():
			if child is Button:
				out.append((child as Button).text)
	return out


# --- internals ---------------------------------------------------------------------

func _refuse(code: String) -> Result:
	_message.text = _refusal_text("ui.craft", code)
	_render()
	return Result.failure(code)


## After a make, takes off the grid whatever the bag no longer has, so the same
## thing can be made again while the ingredients last.
func _trim_to_bag() -> void:
	var used := {}
	for i in SLOTS:
		var item_id := _placed[i]
		if item_id == "":
			continue
		used[item_id] = int(used.get(item_id, 0)) + 1
		if int(used[item_id]) > Game.player.inventory.count_of(item_id):
			_placed[i] = ""


func _things(counts: Dictionary) -> String:
	var parts: Array[String] = []
	for item_id: String in counts:
		var n := int(counts[item_id])
		parts.append(ItemIcons.name_of(item_id) + (" ×%d" % n if n > 1 else ""))
	return ", ".join(parts)


func _render() -> void:
	_render_bag_rows()
	_render_bench()
	_render_book()
	_condition.text = StatusText.condition()
	_job.text = StatusText.job()
	_job.visible = _job.text != ""
	var inventory := Game.player.inventory
	_carrying.text = Localization.t("ui.bag.carrying", {
		"weight": "%.1f" % inventory.total_weight(), "capacity": "%.0f" % inventory.capacity(),
		"cash": Game.player.wallet.cash,
	})


func _render_bag_rows() -> void:
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


func _render_bench() -> void:
	for i in SLOTS:
		_grid_slots[i].show_item(_placed[i], 1)
	_render_bag_grid()
	_render_output()


func _render_bag_grid() -> void:
	for child in _bag_grid.get_children():
		_bag_grid.remove_child(child)
		child.queue_free()
	var inventory := Game.player.inventory
	for item_id in inventory.item_ids():
		var left := inventory.count_of(item_id) - _placed.count(item_id)
		var slot := ItemSlot.new(BAG_SLOT)
		slot.show_item(item_id, left)
		slot.disabled = left < 1
		slot.modulate = Color(1, 1, 1, 0.4) if left < 1 else Color.WHITE
		slot.pressed.connect(func() -> void: place(item_id))
		_bag_grid.add_child(slot)


func _render_output() -> void:
	var recipe := CraftRules.find(Game.data.table("recipes"), _placed)
	if recipe.is_empty():
		_output.show_item("")
		_make.disabled = true
		_result.text = Localization.t("ui.craft.nothing") if _placed.any(func(id: String) -> bool: return id != "") \
			else Localization.t("ui.craft.empty")
		return
	var outputs := CraftRules.outputs_of(recipe)
	var first: String = str(outputs.keys()[0])
	_output.show_item(first, int(outputs[first]))
	var judged := CraftRules.judge(recipe, _bag_counts(), _placed)
	_make.disabled = judged.is_err()
	_result.text = Localization.t("ui.craft.makes", {
		"what": _things(outputs), "minutes": int(recipe.get("minutes", 1))})


func _bag_counts() -> Dictionary:
	var out := {}
	for item_id in Game.player.inventory.item_ids():
		out[item_id] = Game.player.inventory.count_of(item_id)
	return out


func _render_book() -> void:
	for child in _book_rows.get_children():
		_book_rows.remove_child(child)
		child.queue_free()
	var recipes := Game.data.table("recipes")
	for recipe_id: String in recipes:
		if not Game.player.known_recipes.has(recipe_id):
			continue
		var recipe: Dictionary = recipes[recipe_id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var outputs := CraftRules.outputs_of(recipe)
		row.add_child(ItemIcons.tile(str(outputs.keys()[0]), 36))
		var pick := Button.new()
		pick.theme_type_variation = &"SmallButton"
		pick.text = Localization.t(str(recipe.get("name_key", recipe_id)))
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.clip_text = true
		pick.pressed.connect(func() -> void: fill_recipe(recipe_id))
		row.add_child(pick)
		for item_id: String in CraftRules.ingredients_of(recipe):
			row.add_child(ItemIcons.tile(item_id, 24))
		_book_rows.add_child(row)
	if _book_rows.get_child_count() == 0:
		var none := Label.new()
		none.theme_type_variation = &"MutedLabel"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.text = Localization.t("ui.craft.book_empty")
		_book_rows.add_child(none)


func _focus_first() -> void:
	match _tab:
		Tab.BAG:
			for row in _rows.get_children():
				for child in row.get_children():
					if child is Button:
						(child as Button).grab_focus()
						return
		Tab.BENCH:
			for slot in _bag_grid.get_children():
				if slot is ItemSlot and not (slot as ItemSlot).disabled:
					(slot as ItemSlot).grab_focus()
					return
		Tab.RECIPES:
			for row in _book_rows.get_children():
				for child in row.get_children():
					if child is Button:
						(child as Button).grab_focus()
						return
	_close.grab_focus()
