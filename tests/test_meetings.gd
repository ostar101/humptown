extends TestCase
## Meetings and the calendar (D-047): who suggests them, what may be accepted,
## how they are kept or missed from where people actually stand, and saving.

var _day0 := 0
var _updates: Array[String] = []
var _deeds: Array[String] = []
var _rejected: Array[String] = []


func before_each() -> void:
	_updates = []
	_deeds = []
	_rejected = []
	Events.meeting_updated.connect(_on_updated)
	Events.player_deed.connect(_on_deed)
	Events.action_rejected.connect(_on_rejected)


func after_each() -> void:
	Events.meeting_updated.disconnect(_on_updated)
	Events.player_deed.disconnect(_on_deed)
	Events.action_rejected.disconnect(_on_rejected)
	Localization.set_locale("en")
	Game.saves.delete_slot("test_meetings")


func _on_updated(meeting_id: int, status: String) -> void:
	_updates.append("%d:%s" % [meeting_id, status])


func _on_deed(kind: String, _data: Dictionary) -> void:
	_deeds.append(kind)


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


func _start() -> void:
	Game.new_game("bg_returning", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	var model := ScriptedDialogueModel.new()
	model.available = false
	Game.dialogue.model = model
	_day0 = Game.clock.day_index()
	_at(0, 12)


func _at(day_offset: int, hour: int) -> void:
	Game.clock.total_minutes = (_day0 + day_offset) * GameClock.MINUTES_PER_DAY + hour * 60


func _fond(npc_id: String) -> void:
	Game.phone_director.add_contact(npc_id)
	Game.npcs.get_npc(npc_id).activity = "idle"
	Game.relationships.adjust(npc_id, PlayerState.ID, "familiarity", 0.4)
	Game.relationships.adjust(npc_id, PlayerState.ID, "affection", 0.4)


## Someone suggests a meeting by text; returns the meeting.
func _request(npc_id: String) -> Dictionary:
	_fond(npc_id)
	var spec := Game.meetings.suggest(npc_id)
	assert_false(spec.is_empty(), "somewhere is open")
	var sent := Game.phone_director.deliver({"npc": npc_id, "kind": "meeting_request", "key": "phone.msg.meeting_request",
		"args": {"place": spec["location"], "start": spec["start"]}, "meeting": spec})
	assert_ok(sent)
	var message: Dictionary = sent.value
	return Game.calendar.get_meeting(int(message["action"]["meeting"]))


func _message_for(meeting: Dictionary) -> Dictionary:
	for message in Game.phone.messages:
		if int((message["action"] as Dictionary).get("meeting", 0)) == int(meeting["id"]):
			return message
	return {}


# --- the rules ---------------------------------------------------------------------------------

func test_what_may_be_accepted() -> void:
	var meeting := {"status": "proposed", "start": 1000}
	assert_ok(MeetingRules.judge_accept(meeting, {"now": 100, "clash": false}))
	assert_eq(MeetingRules.judge_accept(meeting, {"now": 100, "clash": true}).code, "clash")
	assert_eq(MeetingRules.judge_accept(meeting, {"now": 1000 - MeetingRules.MIN_NOTICE + 1, "clash": false}).code, "too_late")
	assert_eq(MeetingRules.judge_accept({"status": "lapsed", "start": 1000}, {"now": 100}).code, "too_late")
	assert_eq(MeetingRules.judge_accept({"status": "accepted", "start": 1000}, {"now": 100}).code, "already_answered")
	assert_eq(MeetingRules.judge_accept({}, {"now": 100}).code, "already_answered")


func test_how_a_meeting_went_is_read_from_where_people_stood() -> void:
	assert_eq(MeetingRules.judge_attendance({"player_here": true, "npc_here": true}), "kept")
	assert_eq(MeetingRules.judge_attendance({"player_here": false, "npc_here": true}), "missed")
	assert_eq(MeetingRules.judge_attendance({"player_here": true, "npc_here": false}), "stood_up")
	assert_eq(MeetingRules.judge_attendance({"player_here": false, "npc_here": false}), "stood_up")
	assert_eq(MeetingRules.judge_attendance({"player_here": true, "npc_here": true, "late": true}), "missed", "skipped through")
	assert_eq(MeetingRules.judge_attendance({"player_here": true, "npc_here": false, "late": true}), "missed")


func test_hours_and_open_places() -> void:
	for day in 20:
		var hour := MeetingRules.start_hour("npc_ida", day)
		assert_true(hour >= MeetingRules.FIRST_START_HOUR and hour < MeetingRules.FIRST_START_HOUR + MeetingRules.START_HOURS)
	assert_eq(MeetingRules.start_hour("npc_ida", 3), MeetingRules.start_hour("npc_ida", 3), "the same day, the same hour")
	var bar := func(minute: int) -> bool: return minute >= 960 or minute < 180
	assert_true(MeetingRules.open_throughout(bar, 18 * 60), "open from four")
	assert_false(MeetingRules.open_throughout(bar, 16 * 60), "not open when they arrive at half past three")
	assert_false(MeetingRules.open_throughout(func(m: int) -> bool: return m >= 420 and m < 1080, 17 * 60), "shuts before it ends")


# --- the calendar -------------------------------------------------------------------------------------

func test_the_calendar_keeps_what_is_coming() -> void:
	var book := Calendar.new()
	var late := book.propose("npc_ida", "loc_court", 3000, 90)
	var soon := book.propose("npc_pirjo", "loc_court", 2000, 90)
	book.set_status(int(late["id"]), "accepted")
	book.set_status(int(soon["id"]), "accepted")
	assert_eq(book.upcoming(0).map(func(m: Dictionary) -> String: return str(m["npc"])), ["npc_pirjo", "npc_ida"])
	assert_eq(book.upcoming(2200).size(), 1, "one is over")
	assert_true(book.has_open_with("npc_ida", 0))
	assert_false(book.has_open_with("npc_ida", 3200), "done with")
	assert_eq(book.clashes(2050, 2100, 0).size(), 1)
	assert_eq(book.clashes(2130, 2230, MeetingRules.BUFFER).size(), 1, "an hour to get there")
	assert_eq(book.clashes(2130, 2230, 0).size(), 0)
	var restored := Calendar.new()
	restored.from_dict(book.to_dict())
	assert_eq(restored.meetings.size(), 2)
	assert_eq(int(restored.propose("npc_ida", "loc_court", 9000, 90)["id"]), 3, "ids go on")


func test_the_calendar_forgets_the_long_past() -> void:
	var book := Calendar.new()
	for i in Calendar.KEEP_FINISHED + 5:
		var m := book.propose("npc_ida", "loc_court", i * 1000, 90)
		book.set_status(int(m["id"]), "kept")
	assert_eq(book.meetings.size(), Calendar.KEEP_FINISHED)


# --- being asked ---------------------------------------------------------------------------------------

func test_a_friend_suggests_tomorrow_somewhere_open() -> void:
	_start()
	_fond("npc_pirjo")
	var spec := Game.meetings.suggest("npc_pirjo")
	assert_false(spec.is_empty())
	assert_eq(int(spec["start"]) / GameClock.MINUTES_PER_DAY, _day0 + 1, "tomorrow")
	assert_true(bool(Game.data.get_entry("locations", str(spec["location"])).get("meeting_place", false)))
	var place := Game.world.get_location(str(spec["location"]))
	var minute := int(spec["start"]) % GameClock.MINUTES_PER_DAY
	assert_true(place.is_open_at(posmod(minute - MeetingRules.GATHER_LEAD, 1440)), "open when they arrive")
	assert_true(place.is_open_at((minute + MeetingRules.DURATION) % 1440), "and when it ends")
	var meeting := _request("npc_pirjo")
	assert_eq(meeting["status"], "proposed")
	assert_eq(Game.meetings.suggest("npc_pirjo"), {}, "not another while one is open")


## D-104: nobody suggests meeting somewhere that is shut tomorrow.
func test_nowhere_closed_tomorrow_is_suggested() -> void:
	_start()
	_fond("npc_pirjo")
	var tomorrow := posmod(Game.clock.weekday() + 1, 7)
	for location_id: String in Game.world.locations_in("harbourside"):
		Game.world.get_location(location_id).closed_days = [tomorrow] as Array[int]
	assert_eq(Game.meetings.suggest("npc_pirjo"), {})


func test_the_request_arrives_as_a_text_with_an_answer() -> void:
	_start()
	var meeting := _request("npc_pirjo")
	var message := _message_for(meeting)
	assert_eq(message["kind"], "meeting_request")
	assert_true(Game.phone.is_open(message))
	var text := PhoneText.render(message)
	assert_true(text.begins_with("Want to meet at "), text)
	assert_true(text.contains("Tomorrow at %s" % PhoneText.clock_of(int(meeting["start"]))), text)


func test_fond_friends_do_ask_over_the_days() -> void:
	_start()
	_fond("npc_ida")
	var asked := false
	for day in 8:
		_at(day, 21)
		Game.phone.last_started.clear()
		Game.phone_director.run_outreach()
		for message in Game.phone.thread("npc_ida"):
			asked = asked or message["kind"] == "meeting_request"
	assert_true(asked, "some evening she suggests meeting")


func test_a_friend_only_asks_where_she_could_go() -> void:
	_start()
	_fond("npc_ida")
	assert_false(Game.meetings.suggest("npc_ida").is_empty())
	var flagged: Array[String] = []
	for id: String in Game.data.ids("locations"):
		if bool(Game.data.get_entry("locations", id).get("meeting_place", false)):
			flagged.append(id)
			Game.data.tables["locations"][id]["meeting_place"] = false
	assert_eq(Game.meetings.suggest("npc_ida"), {}, "no suitable place, no suggestion")
	for id in flagged:
		Game.data.tables["locations"][id]["meeting_place"] = true


# --- answering -------------------------------------------------------------------------------------------

func test_accepting_puts_it_on_the_calendar_and_sets_the_day() -> void:
	_start()
	var meeting := _request("npc_pirjo")
	var queued_before := Game.events_queue.size()
	assert_ok(Game.answer_message(int(_message_for(meeting)["id"]), "accept"))
	assert_eq(Game.calendar.get_meeting(int(meeting["id"]))["status"], "accepted")
	assert_eq(Game.events_queue.size(), queued_before + 4, "a reminder, the gathering, the check and the end")
	assert_eq(_updates, ["%d:accepted" % int(meeting["id"])] as Array[String])
	assert_eq(PhoneText.render(Game.phone.thread("npc_pirjo").back()), "Sounds good. See you there.")
	assert_eq(Game.calendar.upcoming(Game.clock.total_minutes).size(), 1)


func test_declining_schedules_nothing() -> void:
	_start()
	var meeting := _request("npc_pirjo")
	var queued_before := Game.events_queue.size()
	assert_ok(Game.answer_message(int(_message_for(meeting)["id"]), "decline"))
	assert_eq(Game.calendar.get_meeting(int(meeting["id"]))["status"], "declined")
	assert_eq(Game.events_queue.size(), queued_before)
	assert_eq(Game.meetings.suggest("npc_pirjo").is_empty(), false, "and she may ask again another time")


func test_two_meetings_too_close_together_are_refused() -> void:
	_start()
	var first := _request("npc_pirjo")
	assert_ok(Game.answer_message(int(_message_for(first)["id"]), "accept"))
	var other := Game.calendar.propose("npc_ida", str(first["location"]), int(first["start"]) + 60, MeetingRules.DURATION)
	var message := Game.phone.add_message("npc_ida", true, "meeting_request", "phone.msg.meeting_request",
		{"place": first["location"], "start": other["start"]}, Game.clock.total_minutes, {"do": "meeting", "meeting": other["id"]})
	Game.phone_director.add_contact("npc_ida")
	assert_eq(Game.answer_message(int(message["id"]), "accept").code, "clash")
	assert_eq(_rejected, ["clash"] as Array[String])
	assert_eq(Game.calendar.get_meeting(int(other["id"]))["status"], "proposed", "nothing changed")
	assert_ok(Game.answer_message(int(message["id"]), "decline"), "but you can always say no")


func test_it_is_too_late_to_accept_what_is_almost_here() -> void:
	_start()
	var meeting := _request("npc_pirjo")
	Game.clock.total_minutes = int(meeting["start"]) - 10
	assert_eq(Game.answer_message(int(_message_for(meeting)["id"]), "accept").code, "too_late")


func test_unanswered_suggestions_lapse() -> void:
	_start()
	var meeting := _request("npc_pirjo")
	Game.clock.total_minutes = int(meeting["start"]) + 5
	Game.meetings.lapse()
	assert_eq(Game.calendar.get_meeting(int(meeting["id"]))["status"], "lapsed")
	assert_eq(Game.answer_message(int(_message_for(meeting)["id"]), "accept").code, "too_late")


# --- the day ------------------------------------------------------------------------------------------------

## An accepted meeting, with the player and the friend where they would be.
func _agreed(npc_id: String = "npc_pirjo") -> Dictionary:
	var meeting := _request(npc_id)
	assert_ok(Game.answer_message(int(_message_for(meeting)["id"]), "accept"))
	return meeting


func test_the_friend_heads_there_and_a_kept_meeting_is_remembered() -> void:
	_start()
	var meeting := _agreed()
	var id := int(meeting["id"])
	var npc := Game.npcs.get_npc("npc_pirjo")
	var affection := Game.relationships.peek("npc_pirjo", PlayerState.ID).affection
	Game.clock.total_minutes = int(meeting["start"]) - MeetingRules.GATHER_LEAD
	Game.meetings.on_event("meeting_gather", {"meeting": id})
	assert_not_null(npc.schedule_override, "she has somewhere to be")
	assert_eq(npc.schedule_override.location, meeting["location"])
	assert_eq(npc.schedule_override.reason, "meeting:%d" % id)
	Game.clock.total_minutes = int(meeting["start"]) + MeetingRules.GRACE
	Game.player.location = str(meeting["location"])
	Game.meetings.on_event("meeting_check", {"meeting": id})
	assert_eq(Game.calendar.get_meeting(id)["status"], "kept")
	assert_has(_updates, "%d:kept" % id)
	assert_has(_deeds, "met")
	assert_gt(Game.relationships.peek("npc_pirjo", PlayerState.ID).affection, affection)
	assert_false(Game.memories.recall("npc_pirjo", Game.clock.total_minutes, func(_l: String) -> String: return "").is_empty())
	Game.meetings.on_event("meeting_end", {"meeting": id})
	assert_null(npc.schedule_override, "and she goes back to her day")


func test_the_clock_brings_everyone_to_the_place() -> void:
	_start()
	var meeting := _agreed()
	var id := int(meeting["id"])
	Game.player.location = str(meeting["location"])
	Game.pause_time(false)
	Game.clock.advance_to(int(meeting["start"]) + MeetingRules.GRACE + 2)
	Game.pause_time(true)
	assert_eq(Game.calendar.get_meeting(id)["status"], "kept", "she was there because the schedule put her there")
	assert_has(_updates, "%d:reminder" % id)


func test_not_turning_up_costs_trust_and_she_says_so() -> void:
	_start()
	var meeting := _agreed()
	var id := int(meeting["id"])
	Game.clock.total_minutes = int(meeting["start"]) - MeetingRules.GATHER_LEAD
	Game.meetings.on_event("meeting_gather", {"meeting": id})
	Game.player.location = "loc_dock_street"
	var trust := Game.relationships.peek("npc_pirjo", PlayerState.ID).trust
	Game.clock.total_minutes = int(meeting["start"]) + MeetingRules.GRACE
	Game.meetings.on_event("meeting_check", {"meeting": id})
	assert_eq(Game.calendar.get_meeting(id)["status"], "missed")
	assert_lt(Game.relationships.peek("npc_pirjo", PlayerState.ID).trust, trust)
	assert_false(_deeds.has("met"))
	assert_eq(Game.phone.pending.size(), 1, "a text is waiting for a civil hour")
	Game.clock.total_minutes = (Game.clock.day_index() + 1) * GameClock.MINUTES_PER_DAY + 10 * 60
	Game.npcs.get_npc("npc_pirjo").activity = "idle"
	Game.phone.last_started.clear()
	Game.phone_director.run_outreach()
	var last: Dictionary = Game.phone.thread("npc_pirjo").back()
	assert_eq(last["kind"], "meeting_missed")
	assert_true(PhoneText.render(last).begins_with("I waited at "), PhoneText.render(last))


func test_being_stood_up_costs_you_nothing() -> void:
	_start()
	var meeting := _agreed()
	var id := int(meeting["id"])
	Game.player.location = str(meeting["location"])
	var npc := Game.npcs.get_npc("npc_pirjo")
	npc.set_override(int(meeting["start"]) - 60, int(meeting["start"]) + 200, "loc_dock_street", "idle", "something came up")
	var trust := Game.relationships.peek("npc_pirjo", PlayerState.ID).trust
	Game.clock.total_minutes = int(meeting["start"]) + MeetingRules.GRACE
	Game.meetings.on_event("meeting_check", {"meeting": id})
	assert_eq(Game.calendar.get_meeting(id)["status"], "stood_up")
	assert_eq(Game.relationships.peek("npc_pirjo", PlayerState.ID).trust, trust)
	assert_eq(Game.phone.pending.size(), 0)


func test_sleeping_through_it_is_missing_it() -> void:
	_start()
	var meeting := _agreed()
	var id := int(meeting["id"])
	Game.player.location = str(meeting["location"])
	Game.clock.total_minutes = int(meeting["start"]) + 400
	Game.meetings.on_event("meeting_check", {"meeting": id})
	assert_eq(Game.calendar.get_meeting(id)["status"], "missed")


func test_a_finished_meeting_does_not_run_twice() -> void:
	_start()
	var meeting := _agreed()
	var id := int(meeting["id"])
	Game.player.location = str(meeting["location"])
	Game.clock.total_minutes = int(meeting["start"]) + MeetingRules.GRACE
	Game.meetings.on_event("meeting_check", {"meeting": id})
	var updates := _updates.size()
	Game.meetings.on_event("meeting_check", {"meeting": id})
	Game.meetings.on_event("meeting_reminder", {"meeting": id})
	assert_eq(_updates.size(), updates, "settled is settled")


# --- the window and the save ---------------------------------------------------------------------------------

func _window() -> PhoneWindow:
	var window: PhoneWindow = (load("res://scenes/ui/phone_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	return window


func test_the_calendar_page_shows_what_is_coming() -> void:
	_start()
	var window := _window()
	assert_true(window.open())
	window.show_page(PhoneWindow.Page.CALENDAR)
	assert_eq(window.row_texts(), ["Nothing planned."] as Array[String])
	var meeting := _agreed()
	window.show_page(PhoneWindow.Page.CALENDAR)
	var rows := window.row_texts()
	assert_true(rows[0].begins_with("Tomorrow %s · " % PhoneText.clock_of(int(meeting["start"]))), rows[0])
	assert_true(rows[0].ends_with("|with Pirjo Salo"), rows[0])
	Game.clock.total_minutes = int(meeting["start"]) - MeetingRules.GATHER_LEAD
	Game.meetings.on_event("meeting_gather", {"meeting": int(meeting["id"])})
	Game.player.location = str(meeting["location"])
	Game.clock.total_minutes = int(meeting["start"]) + MeetingRules.GRACE
	Game.meetings.on_event("meeting_check", {"meeting": int(meeting["id"])})
	Game.clock.total_minutes = int(meeting["start"]) + 200
	window.show_page(PhoneWindow.Page.CALENDAR)
	assert_true(window.row_texts().has("Behind you"))
	assert_true(window.row_texts().any(func(r: String) -> bool: return r.ends_with("kept")))
	window.close()
	window.free()


func test_the_answer_buttons_are_offered_for_a_meeting_too() -> void:
	_start()
	var meeting := _request("npc_pirjo")
	var window := _window()
	window.open()
	window.open_thread("npc_pirjo")
	assert_eq(window.answer_labels(), ["I'll do it", "Not now"] as Array[String])
	assert_true(window.press_answer("accept"))
	assert_eq(Game.calendar.get_meeting(int(meeting["id"]))["status"], "accepted")
	window.close()
	window.free()


func test_the_words_follow_the_language() -> void:
	_start()
	var meeting := _request("npc_pirjo")
	Localization.set_locale("fi")
	var text := PhoneText.render(_message_for(meeting))
	assert_true(text.begins_with("Tavataanko"), text)
	assert_true(text.contains("huomenna") or text.contains("Huomenna"), text)


func test_meetings_and_their_events_are_saved() -> void:
	_start()
	var meeting := _agreed()
	var id := int(meeting["id"])
	assert_ok(Game.save_game("test_meetings"))
	assert_ok(Game.load_game("test_meetings"))
	Game.pause_time(true)
	assert_eq(Game.calendar.get_meeting(id)["status"], "accepted")
	assert_eq(Game.calendar.get_meeting(id)["location"], meeting["location"])
	var kinds: Array[String] = []
	for event in Game.events_queue.pending():
		kinds.append(event.kind)
	assert_eq(kinds.count("meeting_check"), 1, "and the moment it is settled is still coming")
	Game.player.location = str(meeting["location"])
	Game.pause_time(false)
	Game.clock.advance_to(int(meeting["start"]) + MeetingRules.GRACE + 1)
	Game.pause_time(true)
	assert_eq(Game.calendar.get_meeting(id)["status"], "kept", "it runs after loading")


func test_a_version_6_save_gains_an_empty_calendar() -> void:
	var migrated := SaveMigrations.migrate({"schema_version": 6, "phone": {}})
	assert_ok(migrated)
	assert_eq(migrated.value["schema_version"], SaveMigrations.CURRENT_VERSION)
	assert_eq(migrated.value["calendar"]["meetings"], [])
