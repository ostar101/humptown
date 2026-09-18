class_name CharacterCreation
extends Node
## Who the player was, who they are, and a last look before it begins
## (D-034): `Choose Background -> Customise -> Confirm`, as the design plan
## orders it.
##
## The screen only ever edits a `CharacterDraft` through the draft's own
## rules (`lower`, `raise`, `PlayerLook.cycle`), so it cannot show a choice
## Game would refuse — only an unfinished one, which Next will not pass. The
## world is built once, by `Game.new_game_from()`, when the player presses
## Begin; backing out before that leaves nothing behind.
##
## Layout lives in the scene. Repeated rows (a card per background, a row per
## choice and per attribute) are copied from hidden templates there and
## filled in from content, so adding a background or an attribute needs no
## change here.

const TITLE := "res://scenes/ui/title_screen.tscn"
const OPENING := "res://scenes/ui/opening.tscn"

enum Step { BACKGROUND, LOOK, CONFIRM }
const STEP_KEYS := ["ui.create.step.background", "ui.create.step.look", "ui.create.step.confirm"]

const LOOK_CHOICES: Array[String] = ["skin", "hair_style", "hair", "outfit_style", "shirt", "trousers"]
const ATTRIBUTES: Array[String] = ["strength", "agility", "endurance", "wits", "charisma", "resolve"]
const PREVIEW_FACINGS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]

var draft := CharacterDraft.new()
var step: Step = Step.BACKGROUND

var _data := DataRegistry.new()
var _cards: Dictionary = {}            # background id -> Button
var _choice_rows: Dictionary = {}      # look key -> HBoxContainer
var _attribute_rows: Dictionary = {}   # attribute -> HBoxContainer
var _facing_index := 0

@onready var _step_title: Label = %StepTitle
@onready var _step_count: Label = %StepCount
@onready var _pages: Array[Control] = [%BackgroundPage, %LookPage, %ConfirmPage]
@onready var _cards_grid: GridContainer = %Cards
@onready var _choices: VBoxContainer = %Choices
@onready var _figure: CharacterFigure = %Figure
@onready var _portrait: CharacterFigure = %Portrait
@onready var _name_edit: LineEdit = %NameEdit
@onready var _pronouns: HBoxContainer = %Pronouns
@onready var _attributes_hint: Label = %AttributesHint
@onready var _attributes: VBoxContainer = %Attributes
@onready var _summary: RichTextLabel = %Summary
@onready var _back: Button = %Back
@onready var _next: Button = %Next
@onready var _refusal: Label = %Refusal


func _ready() -> void:
	_data.load_all()
	draft.appearance = PlayerLook.default_appearance()
	_build_cards()
	_build_choices()
	_build_attributes()
	_name_edit.text_changed.connect(func(text: String) -> void:
		draft.display_name = text
		_refresh())
	for button: Button in _pronouns.get_children():
		var pronoun := str(button.name)
		button.pressed.connect(func() -> void: choose_pronouns(pronoun))
	_back.pressed.connect(back)
	_next.pressed.connect(next)
	$TurnTimer.timeout.connect(_turn_preview)
	_figure.moving = true
	show_step(Step.BACKGROUND)
	DevCapture.maybe_capture(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back()


# --- what the buttons do -------------------------------------------------------

func choose_background(background_id: String) -> void:
	if draft.background_id != background_id:
		draft.background_id = background_id
		draft.attribute_shifts = {}   # a reshuffle belongs to the life it was made for
	var card: Button = _cards.get(background_id)
	if card != null:
		card.set_pressed_no_signal(true)
	_refresh()


func choose_pronouns(pronouns: String) -> void:
	draft.pronouns = pronouns
	_refresh()


func cycle_look(key: String, direction: int) -> void:
	draft.appearance = PlayerLook.cycle(draft.appearance, key, direction)
	_refresh()


func lower_attribute(attribute: String) -> void:
	draft.lower(_background(), attribute)
	_refresh()


func raise_attribute(attribute: String) -> void:
	draft.raise(_background(), attribute)
	_refresh()


func back() -> void:
	if step == Step.BACKGROUND:
		_go(TITLE)
	else:
		show_step((step - 1) as Step)


## Forward a page, or — on the last — start the life. Returns the result of
## starting it on the last page, so a test can see a refusal.
func next() -> Result:
	if not can_advance():
		return Result.failure("not_ready")
	if step != Step.CONFIRM:
		show_step((step + 1) as Step)
		return Result.success()
	var started := Game.new_game_from(draft)
	if started.is_err():
		_refusal.text = Localization.t("ui.create.refusal." + started.code)
		return started
	_go(OPENING)
	return started


func show_step(new_step: Step) -> void:
	step = new_step
	for i in _pages.size():
		_pages[i].visible = i == int(step)
	_step_title.text = Localization.t(STEP_KEYS[step])
	_step_count.text = Localization.t("ui.create.step_count", {"n": int(step) + 1, "total": _pages.size()})
	_next.text = Localization.t("ui.create.begin" if step == Step.CONFIRM else "ui.create.next")
	if step == Step.CONFIRM:
		_summary.text = _summary_text()
	_refresh()
	if step == Step.LOOK:
		_name_edit.grab_focus()
	elif step == Step.BACKGROUND and _cards.has(draft.background_id):
		(_cards[draft.background_id] as Button).grab_focus()
	else:
		_next.grab_focus()


func can_advance() -> bool:
	match step:
		Step.BACKGROUND:
			return _data.table("backgrounds").has(draft.background_id)
		Step.LOOK:
			return draft.validate(_data).is_ok()
	return true


# --- building the rows ---------------------------------------------------------

func _build_cards() -> void:
	var template: Button = _cards_grid.get_node("CardTemplate")
	for background_id in _data.ids("backgrounds"):
		var background: Dictionary = _data.get_entry("backgrounds", background_id)
		var card: Button = template.duplicate()
		card.visible = true
		card.name = "Card_" + background_id
		var text := card.get_node("Margin/Text")
		(text.get_node("Name") as Label).text = Localization.t(str(background.get("name_key", "")))
		(text.get_node("Description") as Label).text = Localization.t(str(background.get("description_key", "")))
		(text.get_node("Detail") as Label).text = _background_detail(background)
		card.pressed.connect(func() -> void: choose_background(background_id))
		_cards_grid.add_child(card)
		_cards[background_id] = card
	template.queue_free()


func _build_choices() -> void:
	var template: HBoxContainer = _choices.get_node("ChoiceTemplate")
	for key in LOOK_CHOICES:
		if PlayerLook.options(key, draft.appearance).is_empty():
			continue   # styles without the art, trousers with it: nothing to choose
		var row: HBoxContainer = template.duplicate()
		row.visible = true
		row.name = "Choice_" + key
		(row.get_node("Name") as Label).text = Localization.t("ui.create.look." + key)
		(row.get_node("Prev") as Button).pressed.connect(func() -> void: cycle_look(key, -1))
		(row.get_node("Next") as Button).pressed.connect(func() -> void: cycle_look(key, 1))
		_choices.add_child(row)
		_choice_rows[key] = row
	template.queue_free()


func _build_attributes() -> void:
	var template: HBoxContainer = _attributes.get_node("AttributeTemplate")
	for attribute in ATTRIBUTES:
		var row: HBoxContainer = template.duplicate()
		row.visible = true
		row.name = "Attribute_" + attribute
		(row.get_node("Name") as Label).text = Localization.t("attr." + attribute)
		(row.get_node("Minus") as Button).pressed.connect(func() -> void: lower_attribute(attribute))
		(row.get_node("Plus") as Button).pressed.connect(func() -> void: raise_attribute(attribute))
		_attributes.add_child(row)
		_attribute_rows[attribute] = row
	template.queue_free()


# --- keeping the screen in step with the draft ---------------------------------

func _refresh() -> void:
	for figure in [_figure, _portrait]:
		figure.palette = PlayerLook.palette(draft.appearance)
		figure.look = PlayerLook.look(draft.appearance)
	for key in _choice_rows:
		_refresh_choice(key, _choice_rows[key])
	var background := _background()
	var values := draft.attributes(background)
	for attribute in _attribute_rows:
		var row: HBoxContainer = _attribute_rows[attribute]
		(row.get_node("Value") as Label).text = str(values.get(attribute, "-"))
	var unplaced := draft.unspent()
	_attributes_hint.text = Localization.t("ui.create.attributes.unspent", {"n": unplaced}) if unplaced > 0 \
		else Localization.t("ui.create.attributes.hint", {
			"points": CharacterDraft.ATTRIBUTE_POINTS,
			"min": CharacterDraft.ATTRIBUTE_MIN,
			"max": CharacterDraft.ATTRIBUTE_MAX,
		})
	_next.disabled = not can_advance()
	_refusal.text = ""
	if step == Step.LOOK:
		var checked := draft.validate(_data)
		if checked.is_err():
			_refusal.text = Localization.t("ui.create.refusal." + checked.code)


func _refresh_choice(key: String, row: HBoxContainer) -> void:
	var value := row.get_node("Value") as Label
	var swatch := row.get_node("Swatch") as ColorRect
	var chosen := str(draft.appearance.get(key, ""))
	if CharacterDraft.APPEARANCE_COLOURS.has(key):
		value.visible = false
		swatch.visible = true
		swatch.color = Color(chosen) if Color.html_is_valid(chosen) else Color.WHITE
	else:
		swatch.visible = false
		value.visible = true
		var options := PlayerLook.options(key)
		value.text = "%d / %d" % [options.find(chosen) + 1, options.size()]


func _turn_preview() -> void:
	_facing_index = (_facing_index + 1) % PREVIEW_FACINGS.size()
	_figure.facing = PREVIEW_FACINGS[_facing_index]


func _background() -> Dictionary:
	return _data.get_entry("backgrounds", draft.background_id) if _data.table("backgrounds").has(draft.background_id) else {}


func _background_detail(background: Dictionary) -> String:
	var skills: Dictionary = background.get("skills", {})
	var ranked := skills.keys()
	ranked.sort_custom(func(a: Variant, b: Variant) -> bool: return int(skills[a]) > int(skills[b]))
	var best: Array[String] = []
	for skill_id in ranked.slice(0, 2):
		best.append("%s %d" % [Localization.t("skill." + str(skill_id)), int(skills[skill_id])])
	return Localization.t("ui.create.background.detail", {
		"cash": int(background.get("cash", 0)),
		"bank": int(background.get("bank", 0)),
		"skills": ", ".join(best),
	})


## The last look before it begins. The player's own name goes in escaped:
## it is the one piece of text here nobody wrote in advance.
func _summary_text() -> String:
	var background := _background()
	var lines: Array[String] = []
	var who := draft.display_name.strip_edges().replace("[", "[lb]")
	lines.append("[font_size=30][b]%s[/b][/font_size]  (%s)" % [who, Localization.t("ui.create.pronouns." + draft.pronouns)])
	lines.append("[b]%s[/b] — %s" % [
		Localization.t(str(background.get("name_key", ""))),
		Localization.t(str(background.get("description_key", "")))])
	lines.append("")
	var values := draft.attributes(background)
	var attribute_text: Array[String] = []
	for attribute in ATTRIBUTES:
		attribute_text.append("%s %s" % [Localization.t("attr." + attribute), values.get(attribute, "-")])
	lines.append("[b]%s[/b]  %s" % [Localization.t("ui.create.attributes"), "  ·  ".join(attribute_text)])
	var skills: Dictionary = background.get("skills", {})
	var skill_text: Array[String] = []
	for skill_id in skills:
		skill_text.append("%s %d" % [Localization.t("skill." + str(skill_id)), int(skills[skill_id])])
	lines.append("[b]%s[/b]  %s" % [Localization.t("ui.create.summary.skills"), "  ·  ".join(skill_text)])
	lines.append("[b]%s[/b]  %s" % [Localization.t("ui.create.summary.money"), Localization.t("ui.create.summary.money_value", {
		"cash": int(background.get("cash", 0)), "bank": int(background.get("bank", 0))})])
	var items: Array[String] = []
	for entry: Dictionary in background.get("items", []):
		var item: Dictionary = _data.get_entry("items", str(entry.get("id", "")))
		var count := int(entry.get("count", 1))
		var item_name := Localization.t(str(item.get("name_key", entry.get("id", ""))))
		items.append(item_name if count == 1 else "%s ×%d" % [item_name, count])
	lines.append("[b]%s[/b]  %s" % [Localization.t("ui.create.summary.carrying"), ", ".join(items)])
	var contacts: Array[String] = []
	for npc_id in background.get("contacts", []):
		var npc: Dictionary = _data.get_entry("npcs", str(npc_id))
		contacts.append(str(npc.get("name", npc_id)))
	lines.append("[b]%s[/b]  %s" % [Localization.t("ui.create.summary.knows"),
		", ".join(contacts) if not contacts.is_empty() else Localization.t("ui.create.summary.nobody")])
	return "\n".join(lines)


# --- for tests ----------------------------------------------------------------

func card_for(background_id: String) -> Button:
	return _cards.get(background_id)


func next_button() -> Button:
	return _next


## Where this screen goes next. Tests set `scene_changer` to see where it would
## go without replacing the test runner's own scene.
var scene_changer: Callable = Callable()


func _go(path: String) -> void:
	if scene_changer.is_valid():
		scene_changer.call(path)
	else:
		get_tree().change_scene_to_file(path)
