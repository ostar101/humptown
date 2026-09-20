class_name WorldView
extends Node2D
## The walkable world: the map the player is on (the region, or the inside of
## a building), its people, the player's body, the camera and the HUD.
##
## Composition only. It reads where the player should be from Game, forwards
## the body's cell changes to Game.move_player() and the interact button to
## Game.interact_at() for the rules to decide, and keeps the map's chunks
## streamed around the camera.

@onready var _region: RegionView = $Actors/RegionView
@onready var _npcs: NpcBodies = $Actors/NpcBodies
@onready var _player: PlayerBody = $Actors/Player
@onready var _camera: PlayerCamera = $Camera
@onready var _hud: Hud = $Hud
## The time-of-day tint over everything drawn in the world (DayNight, D-032).
## The HUD is its own CanvasLayer and is not affected.
@onready var _daylight: CanvasModulate = $Daylight
@onready var _dialogue: DialogueBox = $Dialogue
@onready var _shop: ShopWindow = $Shop
@onready var _bag: InventoryWindow = $Inventory
@onready var _stash: StashWindow = $Stash
@onready var _quests: QuestWindow = $Quests
@onready var _phone: PhoneWindow = $Phone
@onready var _atm: AtmWindow = $Atm
@onready var _combat: CombatWindow = $Combat

const NO_CELL := Vector2i(-99999, -99999)

var _last_accepted := Vector2.ZERO
## The cell the player faced when the prompt was last worked out, and who
## was standing on it — people move, so the prompt must notice them arrive.
var _front := NO_CELL
var _front_person := ""
## The body of whoever the player is talking to, held still until it ends.
var _talking_body: NpcBody = null


func _ready() -> void:
	if not Game.is_running():
		var started := Game.new_game()
		if started.is_err():
			Log.error("world", "Could not start a world", {"reason": started.message})
			return
	_player.cell_changed.connect(_on_player_cell_changed)
	_camera.target = _player
	Events.minute_passed.connect(_on_minute_passed)
	Events.time_skipped.connect(_on_time_skipped)
	Events.game_loaded.connect(refresh_daylight)
	_dialogue.closed.connect(_on_dialogue_closed)
	_shop.closed.connect(_on_shop_closed)
	_bag.closed.connect(_on_shop_closed)
	_stash.closed.connect(_on_shop_closed)
	_quests.closed.connect(_on_shop_closed)
	_phone.closed.connect(_on_shop_closed)
	_phone.call_requested.connect(_on_call_requested)
	_atm.closed.connect(_on_shop_closed)
	_combat.closed.connect(_on_shop_closed)
	Events.fight_requested.connect(_on_fight_requested)
	Events.ambush.connect(_on_ambush)
	Events.phone_message.connect(_on_phone_message)
	Events.meeting_updated.connect(_on_meeting_updated)
	Events.place_learned.connect(_on_place_learned)
	Events.player_arrested.connect(_on_player_arrested)
	Events.ask_resolved.connect(_on_ask_resolved)
	Events.police_action.connect(_on_police_action)
	Events.quest_updated.connect(_on_quest_updated)
	Events.player_collapsed.connect(_on_player_collapsed)
	Events.job_lost.connect(_on_job_lost)
	Events.player_deed.connect(_on_player_deed)
	show_current_area()
	DevCapture.maybe_capture(self)


func _exit_tree() -> void:
	if Events.minute_passed.is_connected(_on_minute_passed):
		Events.minute_passed.disconnect(_on_minute_passed)
		Events.time_skipped.disconnect(_on_time_skipped)
		Events.game_loaded.disconnect(refresh_daylight)
	if Events.player_collapsed.is_connected(_on_player_collapsed):
		Events.player_collapsed.disconnect(_on_player_collapsed)
		Events.job_lost.disconnect(_on_job_lost)
		Events.quest_updated.disconnect(_on_quest_updated)
		Events.phone_message.disconnect(_on_phone_message)
		Events.meeting_updated.disconnect(_on_meeting_updated)
		Events.place_learned.disconnect(_on_place_learned)
		Events.player_arrested.disconnect(_on_player_arrested)
		Events.ask_resolved.disconnect(_on_ask_resolved)
		Events.fight_requested.disconnect(_on_fight_requested)
		Events.ambush.disconnect(_on_ambush)
		Events.police_action.disconnect(_on_police_action)
		Events.player_deed.disconnect(_on_player_deed)


## (Re)builds the view for wherever the player is: the region, or the inside
## of the building they are in.
func show_current_area() -> void:
	var map := Game.current_map()
	_region.show_map(map)
	_npcs.show_map(map)
	if map == null:
		Log.error("world", "Nowhere to show", {"region": Game.player.region, "interior": Game.player.interior})
		return
	_camera.set_bounds(_region.pixel_rect())
	var start := Game.player_start_position()
	_player.place_at(start)
	var accepted := Game.move_player(start)
	if accepted.is_ok():
		_last_accepted = start
	_camera.snap()
	_region.focus_on(_camera.get_screen_center_position())
	_front = NO_CELL
	refresh_daylight()


## Tints the world for the time of day and sets the street lamps to match.
## Indoors the lights are on whatever the hour, so a room is never darkened.
## Called per game minute — a minute's change in the tint is far below what
## anyone can see, so there is nothing to gain from doing it per frame.
func refresh_daylight() -> void:
	if not Game.is_running():
		return
	var map := Game.current_map()
	if map != null and map.is_interior():
		_daylight.color = Color.WHITE
		_region.set_lamp_energy(0.0)
		return
	var tint := DayNight.tint_at(Game.clock.minute_of_day())
	_daylight.color = tint
	_region.set_lamp_energy(DayNight.lamp_energy_for(tint))


func daylight() -> CanvasModulate:
	return _daylight


func _on_minute_passed(_total_minutes: int) -> void:
	refresh_daylight()


func _on_time_skipped(_from_minutes: int, _to_minutes: int) -> void:
	refresh_daylight()


func _process(_delta: float) -> void:
	_region.focus_on(_camera.get_screen_center_position())
	_refresh_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player.input_enabled:
		get_viewport().set_input_as_handled()
		interact()
	elif event.is_action_pressed("inventory") and _player.input_enabled:
		get_viewport().set_input_as_handled()
		open_inventory()
	elif event.is_action_pressed("quests") and _player.input_enabled:
		get_viewport().set_input_as_handled()
		open_quests()
	elif event.is_action_pressed("phone") and _player.input_enabled:
		get_viewport().set_input_as_handled()
		open_phone()


## Takes out the phone (D-045); walking waits until it is put away. Without
## one on you, it says so.
func open_phone() -> void:
	if _phone.open():
		_player.input_enabled = false
		_hud.set_prompt("")
	else:
		_hud.show_message(Localization.t("ui.phone.no_phone"))


## The player rang someone from the phone (D-050): the phone is put away
## first, so the time it paused is handed back before the call pauses it again.
func _on_call_requested(npc_id: String) -> void:
	_phone.close()
	var opened := _dialogue.open(npc_id, true)
	if opened.is_err():
		_hud.show_message(Localization.t("ui.phone.call." + opened.code))
		return
	_talking_body = null
	_player.input_enabled = false
	_player.play("phone", true)   # held to the ear until the call ends (D-058)
	_hud.set_prompt("")


func phone_window() -> PhoneWindow:
	return _phone


## Opens the quest log (D-044); walking waits until it closes.
func open_quests() -> void:
	_quests.open()
	if _quests.is_open():
		_player.input_enabled = false
		_hud.set_prompt("")


func quest_window() -> QuestWindow:
	return _quests


## Opens what the player carries (D-041); walking waits until it closes.
func open_inventory() -> void:
	_bag.open()
	if _bag.is_open():
		_player.input_enabled = false
		_hud.set_prompt("")


func inventory_window() -> InventoryWindow:
	return _bag


func atm_window() -> AtmWindow:
	return _atm


func stash_window() -> StashWindow:
	return _stash


## Uses whatever the player is facing — a person first, then whatever is on
## the cell. Public so tests and scripted scenes can press the button.
func interact() -> Result:
	var cell := _player.current_cell() + _player.facing
	var person := _npcs.body_at(cell)
	if person != null:
		return talk_to(person)
	var what := Game.interaction_at(cell)
	var result := Game.interact_at(cell)
	if result.is_ok() and result.value.get("kind") == "served" and Game.shops.shop_at(Game.player.interior) != "":
		# A counter with a shop behind it opens the shop (D-039).
		var opened := open_shop()
		_front = NO_CELL
		return opened
	if result.is_ok() and result.value.get("kind") == "atm":
		# The cash machine (D-048).
		_atm.open()
		_player.input_enabled = false
		_hud.set_prompt("")
		_front = NO_CELL
		return result
	if result.is_ok() and result.value.get("kind") == "stash":
		# The cupboard at home (D-043).
		_stash.open()
		_player.input_enabled = false
		_hud.set_prompt("")
		_front = NO_CELL
		return result
	_hud.show_message(InteractionText.outcome_text(what, result))
	if result.is_ok():
		var outcome: Dictionary = result.value
		if outcome.get("kind") in ["entered", "exited"]:
			show_current_area()
	_front = NO_CELL
	return result


## Steps up to the counter of the shop the player is in; a refusal is shown
## and nothing else changes.
func open_shop() -> Result:
	var opened := _shop.open()
	if opened.is_err():
		_hud.show_message(Localization.t("ui.msg.refused." + opened.code))
		return opened
	_player.input_enabled = false
	_hud.set_prompt("")
	return opened


func shop_window() -> ShopWindow:
	return _shop


## Opens a conversation with the person this body is. Whether they can be
## talked to is Game's decision (D-035); a refusal is shown, and nothing else
## changes.
func talk_to(body: NpcBody) -> Result:
	var opened := _dialogue.open(body.npc_id)
	if opened.is_err():
		_hud.show_message(InteractionText.outcome_text({"kind": "person", "target": body.npc_id}, opened))
		return opened
	_talking_body = body
	body.hold(-_player.facing)
	_player.input_enabled = false
	_hud.set_prompt("")
	return opened


func dialogue_box() -> DialogueBox:
	return _dialogue


func player_body() -> PlayerBody:
	return _player


func region_view() -> RegionView:
	return _region


func npc_bodies() -> NpcBodies:
	return _npcs


func hud() -> Hud:
	return _hud


## Works out the prompt only when the faced cell, or who is standing on it,
## changes — not every frame.
func _refresh_prompt() -> void:
	if _dialogue.is_open() or _shop.is_open() or _bag.is_open() or _stash.is_open() or _quests.is_open() or _phone.is_open() or _atm.is_open() or _combat.is_open():
		return
	var front := _player.current_cell() + _player.facing
	var body := _npcs.body_at(front)
	var person := body.npc_id if body != null else ""
	if front == _front and person == _front_person:
		return
	_front = front
	_front_person = person
	if person != "":
		_hud.set_prompt(InteractionText.prompt_for({"kind": "person", "target": person}))
	else:
		_hud.set_prompt(InteractionText.prompt_for(Game.interaction_at(front)))


## Health ran out (D-041): the player is somewhere else now, and is told why.
func _on_player_collapsed(woke_at: String, bill: int) -> void:
	if _dialogue.is_open():
		_dialogue.close()
	if _shop.is_open():
		_shop.close()
	if _bag.is_open():
		_bag.close()
	if _stash.is_open():
		_stash.close()
	if _quests.is_open():
		_quests.close()
	if _phone.is_open():
		_phone.close()
	if _atm.is_open():
		_atm.close()
	if _combat.is_open():
		_combat.close()
	show_current_area()
	_hud.show_message(Localization.t("ui.msg.collapsed", {"place": InteractionText.place_name(woke_at), "bill": bill}))


## Someone said they would fight (D-054). The conversation is finished with
## first, then the fight begins — a frame later, so nothing is torn down under
## the line that asked for it.
func _on_fight_requested(npc_id: String) -> void:
	call_deferred("_begin_fight", npc_id)


## Someone the player was told to meet has come, and so has the player (D-055).
func _on_ambush(npc_id: String) -> void:
	call_deferred("_begin_fight", npc_id, "npc")


func _begin_fight(npc_id: String, aggressor: String = "player") -> void:
	if _dialogue.is_open():
		_dialogue.close()
	if _phone.is_open():
		_phone.close()
	var opened := _combat.open(npc_id, aggressor)
	if opened.is_err():
		_hud.show_message(Localization.t("ui.combat.refused." + opened.code))
		return
	_player.input_enabled = false
	_hud.set_prompt("")


func combat_window() -> CombatWindow:
	return _combat


## The player put an ask and it came to a grade (D-053).
func _on_ask_resolved(ask_id: String, grade: String) -> void:
	var ask := Game.data.get_entry("asks", ask_id)
	_hud.show_message(Localization.t("ui.msg.ask." + grade, {"ask": Localization.t(str(ask.get("name_key", ask_id)))}))


## A night in the cells, or a fine for not coming in (D-052).
func _on_player_arrested(officer_id: String, _released_at: int) -> void:
	for window: Node in [_dialogue, _shop, _bag, _stash, _quests, _phone, _atm]:
		if window.has_method("is_open") and window.is_open():
			window.close()
	show_current_area()
	_hud.show_message(Localization.t("ui.msg.arrested", {"name": Game.dialogue.display_name(officer_id, Game.data)}))


func _on_police_action(outcome: String, officer_id: String, fine: int, forced: bool) -> void:
	if not forced or outcome == "arrest" or outcome == "none":
		return
	_hud.show_message(Localization.t("ui.msg.police_forced." + outcome, {
		"name": Game.dialogue.display_name(officer_id, Game.data), "fine": fine}))


func _on_place_learned(location_id: String, _how: String) -> void:
	_hud.show_message(Localization.t("ui.msg.place_new", {"place": InteractionText.place_name(location_id)}))


func _on_meeting_updated(meeting_id: int, status: String) -> void:
	_hud.show_message(PhoneText.meeting_message(meeting_id, status))


## Money handed over to someone face to face: the player holds it out (D-058).
## Only the picture; the cash moved when the rules said so.
func _on_player_deed(kind: String, data: Dictionary) -> void:
	if kind == "gave_money" and _talking_body != null and _talking_body.npc_id == str(data.get("npc", "")):
		_player.play("gift")


func _on_phone_message(npc_id: String, _message_id: int) -> void:
	_hud.show_message(PhoneText.new_message_line(npc_id))


func _on_quest_updated(quest_id: String, status: String) -> void:
	_hud.show_message(QuestText.update_message(quest_id, status))


func _on_job_lost(job_id: String, _reason: String) -> void:
	var job := Game.data.get_entry("jobs", job_id)
	_hud.show_message(Localization.t("ui.msg.job_lost", {"place": InteractionText.place_name(str(job.get("workplace", "")))}))


func _on_shop_closed() -> void:
	_player.input_enabled = true
	_front = NO_CELL


func _on_dialogue_closed() -> void:
	_player.end_pose()
	_player.input_enabled = true
	if _talking_body != null and _talking_body.npc_id != "":
		_talking_body.resume()
	_talking_body = null
	_front = NO_CELL


func _on_player_cell_changed(cell: Vector2i) -> void:
	var result := Game.move_player(_player.position)
	if result.is_ok():
		_last_accepted = _player.position
		_npcs.follow_player(cell)
		if result.value is Dictionary and result.value.get("kind") == "travelled":
			show_current_area()
	else:
		# The rules refused a place physics allowed. Rules win.
		_player.place_at(_last_accepted)
