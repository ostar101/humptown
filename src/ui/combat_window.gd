class_name CombatWindow
extends CanvasLayer
## A fight (D-054), laid out the way a turn-based JRPG does it: who you are
## against and how they are, how you are, what has just happened, and a short
## list of things to do. It shows and asks; `Game.fight_act()` decides, and a
## refusal is shown in plain words. The world stands still while it is open.

signal closed()

const COMMANDS: Array[String] = ["attack", "heavy", "defend", "intimidate", "item", "flee", "yield"]
const LOG_LINES := 8
const FOE_COLOUR := Color(0.78, 0.32, 0.30)
const HEALTH_COLOUR := Color(0.33, 0.66, 0.42)
const STAMINA_COLOUR := Color(0.36, 0.52, 0.80)
const TRACK_COLOUR := Color(0.62, 0.62, 0.68)

var _target := ""
var _buttons: Dictionary = {}

@onready var _root: Control = $Root
@onready var _foes: VBoxContainer = %Foes
@onready var _health: ProgressBar = %YouHealth
@onready var _stamina: ProgressBar = %YouStamina
@onready var _log: Label = %Log
@onready var _commands: HFlowContainer = %Commands
@onready var _outcome: Label = %Outcome
@onready var _continue: Button = %Continue


func _ready() -> void:
	_root.visible = false
	_paint(_health, HEALTH_COLOUR)
	_paint(_stamina, STAMINA_COLOUR)
	_continue.pressed.connect(close)
	for action in COMMANDS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(120, 0)
		button.pressed.connect(func() -> void: press(action))
		_commands.add_child(button)
		_buttons[action] = button


## Starts the fight and shows it. Refused as `Game.start_fight()` refuses.
func open(npc_id: String, aggressor: String = "player") -> Result:
	var started := Game.start_fight(npc_id, aggressor)
	if started.is_err():
		return started
	_target = str((started.value["foes"] as Array)[0])
	_outcome.text = ""
	_root.visible = true
	_render()
	return started


## Puts the fight away — only once it is over. There is no leaving a fight by
## closing a window; there is running, and there is backing down.
func close() -> void:
	if not _root.visible or _fighting():
		return
	_root.visible = false
	closed.emit()


func is_open() -> bool:
	return _root.visible


## A move, by name: "attack", "heavy", "defend", "intimidate", "item", "flee",
## "yield". Returns the game's answer.
func press(action: String) -> Result:
	var arg := ""
	match action:
		"attack", "heavy", "intimidate":
			arg = _target
		"item":
			arg = FightDirector.HEAL_ITEM
	var acted := Game.fight_act(action, arg)
	if acted.is_err():
		_outcome.text = Localization.t("ui.combat.refused." + acted.code)
	else:
		_outcome.text = ""
	_render()
	return acted


## Chooses who the next attack is aimed at.
func target(npc_id: String) -> void:
	_target = npc_id
	_render()


## "name|health%|state" per foe, for tests and reading.
func foe_rows() -> Array[String]:
	var out: Array[String] = []
	for row in _foes.get_children():
		var parts: Array[String] = []
		for child in row.get_children():
			if child is Button:
				parts.append((child as Button).text)
			elif child is ProgressBar:
				parts.append("%d" % int(round((child as ProgressBar).value)))
			elif child is Label:
				parts.append((child as Label).text)
		out.append("|".join(parts))
	return out


func log_lines() -> Array[String]:
	var out: Array[String] = []
	for line in _log.text.split("\n"):
		if line != "":
			out.append(line)
	return out


func outcome_text() -> String:
	return _outcome.text


func command_enabled(action: String) -> bool:
	return _buttons.has(action) and not (_buttons[action] as Button).disabled


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed("ui_cancel") and not _fighting():
		get_viewport().set_input_as_handled()
		close()


func _fighting() -> bool:
	return Game.fights.is_fighting()


func _combat() -> Combat:
	return Game.fights.combat if Game.fights.is_fighting() else Game.fights.last


func _render() -> void:
	var fight := _combat()
	if fight == null:
		return
	var me := fight.player()
	_health.value = float(me["health"]) * 100.0
	_stamina.value = float(me["stamina"]) * 100.0
	for child in _foes.get_children():
		_foes.remove_child(child)
		child.queue_free()
	for foe in fight.foes():
		_foes.add_child(_foe_row(foe))
	var recent := fight.entries.slice(maxi(fight.entries.size() - LOG_LINES, 0))
	_log.text = "\n".join(recent.map(func(e: Dictionary) -> String: return CombatText.line(e)))
	var over := fight.is_over()
	var allowed := {}
	for option in fight.available():
		allowed[option["action"]] = option["ok"]
	for action: String in COMMANDS:
		var button: Button = _buttons[action]
		button.text = Localization.t("ui.combat.command." + action)
		if action == "item":
			var bandages := int((fight.items.get(FightDirector.HEAL_ITEM, {}) as Dictionary).get("count", 0))
			button.text = Localization.t("ui.combat.command.item", {"count": bandages})
		button.disabled = over or (["heavy", "intimidate", "item"].has(action) and not bool(allowed.get(action, false)))
	_continue.visible = over
	if over:
		_outcome.text = CombatText.result(fight.result)
		_continue.grab_focus()
	else:
		(_buttons["attack"] as Button).grab_focus()


func _foe_row(foe: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var pick := Button.new()
	pick.text = str(foe["name"]) if Game.dialogue.knows_name(str(foe["id"])) else CombatText.name_of(str(foe["id"]))
	pick.custom_minimum_size = Vector2(220, 0)
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.toggle_mode = true
	pick.button_pressed = str(foe["id"]) == _target
	pick.disabled = foe["state"] != "up"
	var id := str(foe["id"])
	pick.pressed.connect(func() -> void: target(id))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(180, 18)
	bar.show_percentage = false
	bar.value = float(foe["health"]) * 100.0
	_paint(bar, FOE_COLOUR)
	var state := Label.new()
	state.theme_type_variation = &"MutedLabel"
	state.text = CombatText.state_word(str(foe["state"]))
	for child: Control in [pick, bar, state]:
		row.add_child(child)
	return row


## A bar you can read: a coloured fill on a pale track.
func _paint(bar: ProgressBar, fill: Color) -> void:
	var filled := StyleBoxFlat.new()
	filled.bg_color = fill
	filled.set_corner_radius_all(4)
	var track := StyleBoxFlat.new()
	track.bg_color = TRACK_COLOUR
	track.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", filled)
	bar.add_theme_stylebox_override("background", track)
