extends TestCase
## Phone calls (D-050): who picks up, that a call is a conversation like any
## other but down a phone, and that ringing hands time back properly.

var _model: ScriptedDialogueModel
var _day0 := 0
var _rejected: Array[String] = []
var _deeds: Array[String] = []


func before_each() -> void:
	_rejected = []
	_deeds = []
	Events.action_rejected.connect(_on_rejected)
	Events.player_deed.connect(_on_deed)


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)
	Events.player_deed.disconnect(_on_deed)
	if Game.dialogue.is_talking():
		Game.end_conversation()
	Localization.set_locale("en")


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


func _on_deed(kind: String, _data: Dictionary) -> void:
	_deeds.append(kind)


func _start() -> void:
	Game.new_game("bg_returning", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_model = ScriptedDialogueModel.new()
	_model.available = false
	Game.dialogue.model = _model
	_day0 = Game.clock.day_index()
	_at(12)


func _at(hour: int) -> void:
	Game.clock.total_minutes = _day0 * GameClock.MINUTES_PER_DAY + hour * 60


func _contact(npc_id: String, activity: String = "idle") -> void:
	Game.phone_director.add_contact(npc_id)
	Game.npcs.get_npc(npc_id).activity = activity


# --- who picks up --------------------------------------------------------------------------------------

func test_who_picks_up() -> void:
	var ok := {"has_phone": true, "is_contact": true, "npc_awake": true, "npc_busy": false, "hour": 12}
	assert_ok(PhoneRules.judge_call(ok))
	var refusals := {
		"has_phone": [false, "no_phone"], "is_contact": [false, "not_a_contact"], "npc_awake": [false, "asleep"],
		"hour": [23, "quiet_hours"], "npc_busy": [true, "busy"],
	}
	for field: String in refusals:
		var state := ok.duplicate()
		state[field] = (refusals[field] as Array)[0]
		assert_eq(PhoneRules.judge_call(state).code, (refusals[field] as Array)[1], field)
	var asleep_and_late := ok.duplicate()
	asleep_and_late["npc_awake"] = false
	asleep_and_late["npc_busy"] = true
	assert_eq(PhoneRules.judge_call(asleep_and_late).code, "asleep", "asleep before busy")


func test_a_refused_call_is_announced_and_starts_nothing() -> void:
	_start()
	assert_eq(Game.start_call("npc_ida").code, "not_a_contact")
	_contact("npc_ida", "sleep")
	assert_eq(Game.start_call("npc_ida").code, "asleep")
	Game.npcs.get_npc("npc_ida").activity = "work"
	assert_eq(Game.start_call("npc_ida").code, "busy")
	Game.npcs.get_npc("npc_ida").activity = "idle"
	_at(3)
	assert_eq(Game.start_call("npc_ida").code, "quiet_hours")
	_at(12)
	Game.player.inventory.remove(PhoneDirector.ITEM, 1)
	assert_eq(Game.start_call("npc_ida").code, "no_phone")
	assert_false(Game.dialogue.is_talking(), "nothing began")
	assert_eq(_rejected, ["not_a_contact", "asleep", "busy", "quiet_hours", "no_phone"] as Array[String])


func test_one_conversation_at_a_time() -> void:
	_start()
	_contact("npc_ida")
	_contact("npc_pirjo")
	assert_ok(Game.start_call("npc_ida"))
	assert_eq(Game.can_call("npc_pirjo").code, "already_talking")
	assert_eq(Game.start_call("npc_pirjo").code, "already_talking")
	assert_eq(Game.dialogue.conversation.npc_id, "npc_ida", "still with Ida")


# --- the call -------------------------------------------------------------------------------------------

func test_they_answer_and_it_is_a_call() -> void:
	_start()
	_contact("npc_ida")
	var started := Game.start_call("npc_ida")
	assert_ok(started)
	assert_eq(Game.dialogue.conversation.channel, "call")
	assert_true(["Hello?", "Yes? It's you.", "Hi. What is it?"].has(started.value["text"]), started.value["text"])
	assert_true(Game.clock.paused, "time stands still while you talk")
	var was_paused := Game.clock.paused
	Game.end_conversation()
	assert_eq(Game.clock.paused, was_paused)


func test_a_call_is_a_conversation_down_a_phone() -> void:
	_start()
	_contact("npc_pirjo")
	var affection := Game.relationships.peek("npc_pirjo", PlayerState.ID)
	var before := affection.affection if affection != null else 0.0
	assert_ok(Game.start_call("npc_pirjo"))
	var said: Result = await Game.say_to_npc("You look great.")
	assert_ok(said)
	assert_gt(Game.relationships.peek("npc_pirjo", PlayerState.ID).affection, before, "the rules judge a call as they judge speech")
	var help: Result = await Game.say_to_npc("Can I help you with anything?")
	assert_eq(help.value["topic"], "errand_asked")
	assert_true(Game.quests.errands.has("errand_pirjo_groceries"))
	assert_has(_deeds, "called")
	assert_false(_deeds.has("talked"), "a call is not standing in front of someone")
	assert_false(_deeds.has("texted"))


func test_money_on_a_call_goes_through_the_account() -> void:
	_start()
	_contact("npc_pirjo")
	Game.player.wallet.cash = 100
	Game.player.wallet.bank = 200
	assert_ok(Game.start_call("npc_pirjo"))
	await Game.say_to_npc("Here's 50 euros.")
	assert_eq(Game.player.wallet.cash, 100)
	assert_eq(Game.player.wallet.bank, 150)
	assert_has(_deeds, "gave_money")


func test_a_call_costs_time_and_earns_familiarity_when_it_ends() -> void:
	_start()
	_contact("npc_pirjo")
	var edge := Game.relationships.get_edge("npc_pirjo", PlayerState.ID)
	var familiarity := edge.familiarity
	assert_ok(Game.start_call("npc_pirjo"))
	await Game.say_to_npc("Hello, Pirjo.")
	await Game.say_to_npc("How is the day?")
	var minute := Game.clock.total_minutes
	assert_ok(Game.end_conversation())
	assert_eq(Game.clock.total_minutes, minute + 2, "a minute for each thing you said")
	assert_almost(Game.relationships.get_edge("npc_pirjo", PlayerState.ID).familiarity, familiarity + DialogueDirector.FAMILIARITY_PER_CONVERSATION)


func test_a_call_does_not_hand_over_errand_goods() -> void:
	_start()
	_contact("npc_pirjo")
	Game.quests.take_errand("errand_pirjo_groceries", _day0)
	Game.player.inventory.add("item_sandwich", 2)
	assert_ok(Game.start_call("npc_pirjo"))
	assert_true(Game.quests.errands.has("errand_pirjo_groceries"), "goods change hands in person")
	assert_eq(Game.player.inventory.count_of("item_sandwich"), 2)


func test_the_model_is_told_it_is_a_call() -> void:
	_start()
	_contact("npc_ida")
	_model.available = true
	_model.intents.append(ScriptedDialogueModel.meaning("about_work"))
	_model.replies.append(ScriptedDialogueModel.say("Busy day."))
	assert_ok(Game.start_call("npc_ida"))
	var said: Result = await Game.say_to_npc("How is work going for you these days?")
	assert_eq(said.value["text"], "Busy day.")
	var system := _model.requests_for(LlmRequest.Purpose.DIALOGUE)[0].system
	assert_true(system.contains("on the phone"), "told it is a call")
	assert_true(system.contains("phone call"))
	assert_false(system.contains("face to face"))
	assert_false(system.contains("text message"))


func test_in_person_is_still_in_person() -> void:
	_start()
	var npc := Game.npcs.get_npc("npc_pirjo")
	npc.location = "loc_dock_street"
	npc.activity = "walk"
	assert_ok(Game.start_conversation("npc_pirjo"))
	assert_eq(Game.dialogue.conversation.channel, "in_person")
	await Game.say_to_npc("Hello, Pirjo.")
	assert_has(_deeds, "talked")


# --- the phone and the world -----------------------------------------------------------------------------

func _window() -> PhoneWindow:
	var window: PhoneWindow = (load("res://scenes/ui/phone_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	return window


func test_the_call_button_says_why_nobody_answered() -> void:
	_start()
	_contact("npc_ida", "sleep")
	var window := _window()
	assert_true(window.open())
	window.open_thread("npc_ida")
	var requested: Array[String] = []
	window.call_requested.connect(func(npc_id: String) -> void: requested.append(npc_id))
	assert_eq(window.press_call().code, "asleep")
	assert_eq(window.notice_text(), "It rings and rings. No answer.")
	assert_eq(requested, [] as Array[String])
	Game.npcs.get_npc("npc_ida").activity = "idle"
	assert_ok(window.press_call())
	assert_eq(requested, ["npc_ida"] as Array[String])
	window.close()
	window.free()


func test_ringing_from_the_world_opens_the_call_and_hands_time_back() -> void:
	_start()
	_contact("npc_ida")
	Game.pause_time(false)
	var view: WorldView = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	view.open_phone()
	assert_true(view.phone_window().is_open())
	view.phone_window().open_thread("npc_ida")
	assert_ok(view.phone_window().press_call())
	assert_false(view.phone_window().is_open(), "the phone is put away")
	assert_true(view.dialogue_box().is_open())
	assert_eq(Game.dialogue.conversation.channel, "call")
	assert_true(Game.clock.paused, "the call holds time still")
	view.dialogue_box().close()
	assert_false(Game.clock.paused, "and gives it back, not still frozen by the phone")
	view.free()
