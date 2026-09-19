extends TestCase
## Walking with the player, and being honest about what cannot be promised
## (D-057): the rules, the reading of the words, the world carrying it out.

var _model: ScriptedDialogueModel
var _rejected: Array[String] = []
var _changes: Array[String] = []


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_model = ScriptedDialogueModel.new()
	_model.available = false
	Game.dialogue.model = _model
	_rejected = []
	_changes = []
	Events.action_rejected.connect(_on_rejected)
	Events.follow_changed.connect(_on_changed)


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)
	Events.follow_changed.disconnect(_on_changed)
	if Game.dialogue.is_talking():
		Game.end_conversation()


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


func _on_changed(npc_id: String, following: bool, why: String) -> void:
	_changes.append("%s:%s:%s" % [npc_id, following, why])


# --- helpers ---------------------------------------------------------------------

func _state(overrides: Dictionary = {}) -> Dictionary:
	var state := {
		"npc_id": "npc_ida", "player_name": "Aino", "player_cash": 100,
		"relationship": {}, "warmth": 0.0, "channel": "in_person",
		"follow": {"following": false, "free_minutes": 120},
	}
	state.merge(overrides, true)
	return state


func _judge(kind: String, state: Dictionary = {}) -> Result:
	return ConversationRules.judge({"kind": kind, "subject": "", "amount": 0, "name": ""}, _state(state))


func _does(verdict: Dictionary, what: String) -> bool:
	for effect: Dictionary in verdict["effects"]:
		if effect["do"] == what:
			return true
	return false


func _read(text: String) -> String:
	return str(OfflineTopics.topic_of(text, "npc_ida", {}, {})["topic"])


## A routine with nothing in it until `work_at`, then a shift.
func _routine(work_at: int) -> NpcSchedule:
	return NpcSchedule.from_data({"id": "sched_test", "blocks": [
		{"start": 0, "days": "all", "location": "loc_dock_street", "activity": "idle"},
		{"start": work_at, "days": "all", "location": "loc_corner_shop", "activity": "work"},
	]})


## Ida on the street with a routine that leaves her free, and the player on the
## street too, ready to talk.
func _meet_ida(work_at: int = 1400) -> Npc:
	var ida := Game.npcs.get_npc("npc_ida")
	Game.npcs.schedules["sched_test"] = _routine(work_at)
	ida.schedule_id = "sched_test"
	ida.location = "loc_dock_street"
	ida.activity = "idle"
	Game.npcs.invalidate_location_cache(ida.id)
	Game.player.interior = ""
	Game.player.location = ""
	assert_ok(Game.start_conversation("npc_ida"))
	return ida


func _say(text: String) -> Dictionary:
	var said: Result = await Game.say_to_npc(text)
	assert_ok(said, text)
	return said.value if said.is_ok() else {}


# --- the schedule knows when someone is free ---------------------------------------

func test_free_minutes_run_out_at_the_next_shift() -> void:
	var routine := _routine(600)
	assert_eq(FollowRules.free_minutes(routine, 500, 1), 100)
	assert_eq(FollowRules.free_minutes(routine, 300, 1), FollowRules.MAX_MINUTES, "capped: one outing is not the whole day")
	assert_eq(FollowRules.free_minutes(routine, 700, 1), 0, "on a shift already")
	assert_eq(FollowRules.free_minutes(null, 700, 1), FollowRules.MAX_MINUTES, "no routine, nothing to be late for")


func test_the_night_ends_an_outing_too() -> void:
	var routine := NpcSchedule.from_data({"id": "s", "blocks": [
		{"start": 0, "days": "all", "location": "loc_dock_street", "activity": "sleep"},
		{"start": 420, "days": "all", "location": "loc_dock_street", "activity": "idle"},
		{"start": 1320, "days": "all", "location": "loc_dock_street", "activity": "sleep"},
	]})
	assert_eq(FollowRules.free_minutes(routine, 1300, 1), 20)
	assert_eq(FollowRules.free_minutes(routine, 100, 1), 0, "asleep")


# --- the rules -----------------------------------------------------------------------

func test_someone_free_and_not_hostile_comes_along() -> void:
	var verdict: Dictionary = _judge("ask_follow").value
	assert_true(_does(verdict, "follow"))
	assert_eq(verdict["effects"][0]["minutes"], 120)
	assert_eq(verdict["topic"], "follow_yes")
	assert_true(str(verdict["happened"]).contains("agreed"))


func test_a_shift_a_grudge_and_a_phone_are_each_a_refusal() -> void:
	assert_err(_judge("ask_follow", {"follow": {"following": false, "free_minutes": 10}}), "follow_busy")
	assert_err(_judge("ask_follow", {"relationship": {"trust": -0.6}}), "follow_distrust")
	assert_err(_judge("ask_follow", {"relationship": {"affection": -0.6}}), "follow_distrust")
	assert_err(_judge("ask_follow", {"channel": "call"}), "follow_remote")
	assert_err(_judge("ask_follow", {"channel": "text"}), "follow_remote")


func test_a_stranger_is_not_a_suspect() -> void:
	assert_ok(_judge("ask_follow", {"relationship": {"familiarity": 0.0, "trust": 0.0}}))


func test_asking_someone_already_with_you_changes_nothing() -> void:
	var verdict: Dictionary = _judge("ask_follow", {"follow": {"following": true, "free_minutes": 120}}).value
	assert_true(verdict["effects"].is_empty())
	assert_eq(verdict["topic"], "follow_already")


func test_wait_stops_a_follower_and_is_harmless_otherwise() -> void:
	var stopped: Dictionary = _judge("ask_wait", {"follow": {"following": true, "free_minutes": 120}}).value
	assert_true(_does(stopped, "stop_following"))
	assert_eq(stopped["topic"], "wait_ok")
	var idle: Dictionary = _judge("ask_wait").value
	assert_true(idle["effects"].is_empty())
	assert_eq(idle["topic"], "wait_nothing")


func test_fetching_and_carrying_are_not_promised() -> void:
	var refused := _judge("ask_action")
	assert_err(refused, "cannot_do")
	assert_true(refused.message.contains("did not promise"), "the person is told nothing will happen")
	assert_eq(ConversationRules.topic_for_refusal("cannot_do"), "cannot_do")
	assert_eq(ConversationRules.topic_for_refusal("follow_distrust"), "follow_no")


# --- reading the words -----------------------------------------------------------------

func test_the_words_are_read_in_both_languages() -> void:
	for line in ["Follow me.", "come with me", "Seuraa minua.", "Tule mukaan!", "walk with me please"]:
		assert_eq(_read(line), "ask_follow", line)
	for line in ["Wait here.", "stay put", "Odota tässä.", "Pysy täällä", "stop following me", "Lopeta seuraaminen"]:
		assert_eq(_read(line), "ask_wait", line)
	for line in ["Bring me a coffee", "tuo minulle leipä", "Fetch me the paper"]:
		assert_eq(_read(line), "ask_action", line)


func test_a_request_beats_a_place_or_a_farewell() -> void:
	var places := OfflineTopics.name_words({"loc_dock_street": ["Dock Street"]}, false)
	var read := OfflineTopics.topic_of("follow me to Dock Street", "npc_ida", {}, places)
	assert_eq(read["topic"], "ask_follow", "a place in the line does not make it a question about the place")
	assert_eq(_read("wait here, see you later"), "ask_wait")


func test_every_new_kind_is_offered_to_the_model() -> void:
	var system := IntentPrompt.build("follow me", "Ida").system
	for kind in ["ask_follow", "ask_wait", "ask_action"]:
		assert_true(system.contains("- %s:" % kind), kind)


# --- in the world -----------------------------------------------------------------------

func test_agreeing_to_come_along_makes_her_follow() -> void:
	var ida := _meet_ida()
	var said := await _say("Follow me.")
	assert_eq(said["intent"]["kind"], "ask_follow")
	assert_true(_rejected.is_empty(), str(_rejected))
	assert_true(Game.director.is_following("npc_ida"))
	assert_true(ida.state.has("following"))
	assert_eq(ida.activity, "follow")
	assert_eq(ida.tier, SimLod.Tier.ACTIVE)
	assert_eq(said["text"], Localization.t(DialogueLines.pick("npc_ida", "follow_yes", 1)))
	assert_has(_changes, "npc_ida:true:asked")


func test_her_reply_is_told_the_truth_about_it() -> void:
	_meet_ida()
	_model.available = true
	_model.intents.append(ScriptedDialogueModel.meaning("ask_follow"))
	_model.replies.append(ScriptedDialogueModel.say("Lead on."))
	await _say("hey, walk over there with me?")
	var request := _model.requests_for(LlmRequest.Purpose.DIALOGUE)[0]
	assert_true(request.system.contains("What just happened: They asked you to come along. You agreed"), request.system)
	assert_true(Game.director.is_following("npc_ida"), "the model read it; the rules and Godot did it")


func test_a_model_that_says_yes_to_nothing_changes_nothing() -> void:
	# The line means "fetch", the model's reply says yes anyway: nothing follows.
	_meet_ida()
	_model.available = true
	_model.intents.append(ScriptedDialogueModel.meaning("ask_action"))
	_model.replies.append(ScriptedDialogueModel.say("Sure, I'll go get it."))
	await _say("Go and get me some bread")
	assert_eq(_rejected, ["cannot_do"])
	var request := _model.requests_for(LlmRequest.Purpose.DIALOGUE)[0]
	assert_true(request.system.contains("You cannot, and you did not promise anything."), request.system)
	assert_false(Game.director.is_following("npc_ida"))


func test_refusals_change_nothing_and_are_announced() -> void:
	var ida := _meet_ida(0)   # a shift that is on now
	var said := await _say("Follow me.")
	assert_eq(_rejected, ["follow_busy"])
	assert_eq(said["topic"], "follow_busy")
	assert_false(ida.state.has("following"))
	assert_false(Game.director.is_following("npc_ida"))


func test_distrust_is_a_refusal_in_her_own_words() -> void:
	Game.relationships.adjust("npc_ida", PlayerState.ID, "trust", -0.6)
	var ida := _meet_ida()
	var said := await _say("Come with me.")
	assert_eq(_rejected, ["follow_distrust"])
	assert_eq(said["topic"], "follow_no")
	assert_false(ida.state.has("following"))


func test_she_goes_where_the_player_goes_and_comes_out_again() -> void:
	var ida := _meet_ida()
	await _say("Follow me.")
	Game.end_conversation()
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))
	assert_eq(ida.location, "loc_corner_shop", "in through the door behind the player")
	assert_true(Game.director.is_following("npc_ida"))
	assert_ok(Game.interact_at(Game.current_map().exit_door))
	assert_eq(ida.location, "loc_dock_street", "out to the street, not left inside")
	assert_true(Game.director.is_following("npc_ida"))


func test_wait_lets_her_go_back_to_her_day() -> void:
	var ida := _meet_ida()
	await _say("Follow me.")
	ida.location = "loc_court"   # somewhere else entirely, as if she had walked there
	await _say("Wait here.")
	assert_false(Game.director.is_following("npc_ida"))
	assert_false(ida.state.has("following"))
	assert_eq(ida.location, "loc_dock_street", "her routine takes her back")
	assert_has(_changes, "npc_ida:false:asked")


func test_the_shift_ends_it_even_across_a_long_skip() -> void:
	var ida := _meet_ida(Game.clock.minute_of_day() + 60)
	await _say("Follow me.")
	Game.end_conversation()
	assert_true(Game.director.is_following("npc_ida"))
	Game.advance_time(90)
	assert_false(Game.director.is_following("npc_ida"), "an hour and a half is past the shift")
	assert_false(ida.state.has("following"))
	assert_has(_changes, "npc_ida:false:time_up")
	assert_eq(ida.location, "loc_corner_shop", "and she is at work")


func test_sleeping_or_trouble_ends_it() -> void:
	var ida := _meet_ida()
	await _say("Follow me.")
	Game.end_conversation()
	Events.crime_committed.emit("fact", "loc_dock_street")
	assert_false(Game.director.is_following("npc_ida"))
	assert_has(_changes, "npc_ida:false:trouble")
	Game.director.start_follow("npc_ida", 60)
	Game._player_activity = "sleep"
	Game.advance_time(10)
	Game._player_activity = "idle"
	assert_false(Game.director.is_following("npc_ida"))
	assert_has(_changes, "npc_ida:false:slept")
	assert_false(ida.state.has("following"))


func test_leaving_the_region_leaves_her_behind() -> void:
	var ida := _meet_ida()
	await _say("Follow me.")
	Game.director.stop_all_following("left_region")
	assert_false(Game.director.is_following(ida.id))
	assert_has(_changes, "npc_ida:false:left_region")


func test_a_retier_does_not_send_a_follower_home() -> void:
	var ida := _meet_ida()
	await _say("Follow me.")
	# She is off in a region that would only make her background, or dormant.
	ida.location = "loc_pawn_shop"
	Game.director.assign_tiers()
	assert_eq(ida.tier, SimLod.Tier.ACTIVE, "someone walking with the player stays simulated")
	assert_true(Game.director.followers.has(ida.id))
	Game.director.stop_follow(ida.id, "asked")
	assert_false(Game.director.followers.has(ida.id), "and once let go she is an ordinary schedule again")


func test_following_survives_a_save_and_a_load() -> void:
	var ida := _meet_ida()
	await _say("Follow me.")
	Game.end_conversation()
	var until := int((ida.state["following"] as Dictionary)["until"])
	assert_ok(Game.save_game(Game.save_slot))
	assert_ok(Game.load_game(Game.save_slot))
	var loaded := Game.npcs.get_npc("npc_ida")
	assert_true(loaded.state.has("following"))
	assert_eq(int((loaded.state["following"] as Dictionary)["until"]), until, "as an int, not a float")
	assert_true(Game.director.is_following("npc_ida"), "the index is rebuilt from what people carry")
	assert_eq(loaded.tier, SimLod.Tier.ACTIVE)


func test_her_body_stays_with_the_player() -> void:
	var ida := _meet_ida()
	await _say("Follow me.")
	Game.end_conversation()
	var map := Game.current_map()
	Game.player.position = DistrictMap.cell_to_world(map.spawn)
	var tree := Engine.get_main_loop() as SceneTree
	var view: WorldView = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	tree.root.add_child(view)
	var bodies := view.npc_bodies()
	var body := bodies.body_for(ida.id)
	assert_not_null(body, "someone walking with the player is on screen")
	var player_cell := DistrictMap.world_to_cell(Game.player.position)
	assert_true(_apart(body.current_cell(), player_cell) <= 3, "placed beside the player, not at a spot down the street")

	var far := map.anchor_of("loc_bus_stop")
	Game.player.position = DistrictMap.cell_to_world(far)
	bodies.follow_player(far)
	assert_true(body.is_walking(), "she sets off after them")
	body.advance(600.0)
	assert_true(_apart(body.current_cell(), far) <= 3, "and catches up")
	view.free()


static func _apart(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func test_every_new_line_has_finnish_too() -> void:
	for topic in ["follow_yes", "follow_no", "follow_busy", "follow_remote", "follow_already", "wait_ok", "wait_nothing", "cannot_do"]:
		Localization.set_locale("en")
		var english := DialogueLines.keys_for("npc_ida", topic)
		assert_false(english.is_empty(), topic)
		Localization.set_locale("fi")
		for key in english:
			assert_ne(String(TranslationServer.translate(key)), key, key + " in Finnish")
	Localization.set_locale("en")
