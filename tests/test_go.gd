extends TestCase
## Sending someone to a place (D-061): the rules, the reading of the words, and
## the world carrying it out — or refusing, honestly.

var _model: ScriptedDialogueModel
var _rejected: Array[String] = []


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_model = ScriptedDialogueModel.new()
	_model.available = false
	Game.dialogue.model = _model
	_rejected = []
	Events.action_rejected.connect(_on_rejected)


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)
	if Game.dialogue.is_talking():
		Game.end_conversation()


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


# --- helpers ---------------------------------------------------------------------

func _state(overrides: Dictionary = {}) -> Dictionary:
	var state := {
		"npc_id": "npc_ida", "player_name": "Aino", "player_cash": 100,
		"relationship": {}, "warmth": 0.0, "channel": "in_person",
		"follow": {"following": false, "free_minutes": 120},
		"go": {"problem": "", "free_minutes": 200, "busy": false, "here": false},
	}
	state.merge(overrides, true)
	return state


func _judge(state: Dictionary = {}, subject: String = "loc_harbour_park") -> Result:
	return ConversationRules.judge({"kind": "ask_go", "subject": subject, "amount": 0, "name": ""}, _state(state))


func _routine(work_at: int) -> NpcSchedule:
	return NpcSchedule.from_data({"id": "sched_test", "blocks": [
		{"start": 0, "days": "all", "location": "loc_dock_street", "activity": "idle"},
		{"start": work_at, "days": "all", "location": "loc_corner_shop", "activity": "work"},
	]})


## Ida on the street with a routine that leaves her free, the player beside her.
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


func _read(text: String) -> Dictionary:
	var places := OfflineTopics.name_words({"loc_harbour_park": ["Ropewalk Park"], "loc_court": ["Dock Street Court"]}, false)
	return OfflineTopics.topic_of(text, "npc_ida", {}, places)


# --- the rules -----------------------------------------------------------------------

func test_someone_free_goes_where_asked() -> void:
	var verdict: Dictionary = _judge().value
	assert_eq(verdict["topic"], "go_yes")
	assert_eq(verdict["effects"][0], {"do": "go", "place": "loc_harbour_park", "minutes": FollowRules.GO_MINUTES})


func test_the_trip_is_cut_short_by_their_own_day() -> void:
	var verdict: Dictionary = _judge({"go": {"problem": "", "free_minutes": 45, "busy": false, "here": false}}).value
	assert_eq(verdict["effects"][0]["minutes"], 45)


func test_a_shut_far_or_busy_place_or_person_is_a_refusal() -> void:
	assert_err(_judge({"go": {"problem": "closed", "free_minutes": 200, "busy": false, "here": false}}), "go_closed")
	assert_err(_judge({"go": {"problem": "far", "free_minutes": 200, "busy": false, "here": false}}), "go_closed")
	assert_err(_judge({"go": {"problem": "", "free_minutes": 10, "busy": false, "here": false}}), "go_busy")
	assert_err(_judge({"go": {"problem": "", "free_minutes": 200, "busy": true, "here": false}}), "go_busy")
	assert_err(_judge({"relationship": {"trust": -0.6}}), "go_distrust")
	assert_err(_judge({"channel": "call"}), "go_remote")
	assert_err(_judge({}, ""), "cannot_do")
	assert_err(_judge({}, "npc_ida"), "cannot_do")


func test_already_there_changes_nothing() -> void:
	var verdict: Dictionary = _judge({"go": {"problem": "", "free_minutes": 200, "busy": false, "here": true}}).value
	assert_true(verdict["effects"].is_empty())
	assert_eq(verdict["topic"], "go_here")


func test_a_follower_sent_away_stops_following() -> void:
	var verdict: Dictionary = _judge({"follow": {"following": true, "free_minutes": 120}}).value
	assert_eq(verdict["effects"][0], {"do": "stop_following"})
	assert_eq(verdict["effects"][1]["do"], "go")


func test_each_refusal_has_a_topic_in_her_own_words() -> void:
	assert_eq(ConversationRules.topic_for_refusal("go_closed"), "go_closed")
	assert_eq(ConversationRules.topic_for_refusal("go_remote"), "go_remote")
	assert_eq(ConversationRules.topic_for_refusal("go_busy"), "follow_busy")
	assert_eq(ConversationRules.topic_for_refusal("go_distrust"), "follow_no")
	for topic in ["go_yes", "go_closed", "go_here", "go_remote"]:
		assert_false(DialogueLines.pick("npc_ida", topic, 1).is_empty(), topic)
		assert_ne(Localization.t(DialogueLines.pick("npc_ida", topic, 1)), DialogueLines.pick("npc_ida", topic, 1), topic)


# --- reading the words -----------------------------------------------------------------

func test_a_place_in_the_request_is_what_makes_it_one() -> void:
	var read := _read("Go to Ropewalk Park.")
	assert_eq(read["topic"], "ask_go")
	assert_eq(read["subject"], "loc_harbour_park")
	assert_eq(_read("Mene Ropewalk Parkiin")["topic"], "ask_go", "inflected, in Finnish")
	assert_eq(_read("go to hell")["topic"], "unknown", "no place, no errand")
	assert_eq(_read("Go and get me some bread")["topic"], "ask_action", "fetching still is not built")


func test_walking_with_the_player_beats_going_alone() -> void:
	assert_eq(_read("follow me to Ropewalk Park")["topic"], "ask_follow")


func test_the_model_is_offered_it() -> void:
	assert_true(IntentPrompt.build("go to the park", "Ida").system.contains("- ask_go:"))


# --- in the world -----------------------------------------------------------------------

func test_she_goes_and_the_world_shows_it() -> void:
	var ida := _meet_ida()
	var said := await _say("Go to Ropewalk Park.")
	assert_eq(said["intent"]["kind"], "ask_go")
	assert_true(_rejected.is_empty(), str(_rejected))
	assert_eq(said["text"], Localization.t(DialogueLines.pick("npc_ida", "go_yes", 1)))
	assert_not_null(ida.schedule_override)
	assert_eq(ida.schedule_override.location, "loc_harbour_park")
	assert_eq(Game.npcs.scheduled_location_of("npc_ida", Game.clock.total_minutes, Game.clock.weekday()), "loc_harbour_park")
	# ... and when the trip is over she is back to her day.
	var later: int = Game.clock.total_minutes + FollowRules.GO_MINUTES + 1
	assert_eq(Game.npcs.scheduled_location_of("npc_ida", later, Game.clock.weekday()), "loc_dock_street")


func test_a_locked_place_is_refused_and_nothing_changes() -> void:
	var ida := _meet_ida()
	_model.available = true
	_model.intents.append(ScriptedDialogueModel.meaning("ask_go", {"place": "Warehouse 9"}))
	_model.replies.append(ScriptedDialogueModel.say("Sure, I'll go."))
	await _say("Go and wait for me at Warehouse 9")
	assert_eq(_rejected.size(), 1)
	assert_null(ida.schedule_override)
	var request := _model.requests_for(LlmRequest.Purpose.DIALOGUE)[0]
	assert_false(request.system.contains("you are on your way"), request.system)


func test_a_meeting_already_has_her() -> void:
	var ida := _meet_ida()
	ida.set_override(Game.clock.total_minutes, Game.clock.total_minutes + 60, "loc_court", "socialise", "meeting:1")
	await _say("Go to Ropewalk Park.")
	assert_eq(_rejected, ["go_busy"])
	assert_eq(ida.schedule_override.location, "loc_court", "the earlier plan stands")


func test_she_remembers_being_sent() -> void:
	_meet_ida()
	await _say("Go to Ropewalk Park.")
	Game.end_conversation()
	assert_true(str(Game.memories.episodes("npc_ida")).contains("asked you to go to"), str(Game.memories.episodes("npc_ida")))


func test_the_override_survives_a_save() -> void:
	var ida := _meet_ida()
	await _say("Go to Ropewalk Park.")
	var restored := Npc.from_data(Game.data.get_entry("npcs", "npc_ida"))
	restored.from_dict(ida.to_dict())
	assert_not_null(restored.schedule_override)
	assert_eq(restored.schedule_override.location, "loc_harbour_park")
