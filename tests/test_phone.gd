extends TestCase
## The phone (D-045): who has your number, who may write and when, what a text
## can ask, the window, and saving.

var _arrived: Array[String] = []
var _day0 := 0


func before_each() -> void:
	_arrived = []
	Events.phone_message.connect(_on_message)


func after_each() -> void:
	Events.phone_message.disconnect(_on_message)
	Localization.set_locale("en")
	Game.saves.delete_slot("test_phone")


func _on_message(npc_id: String, _message_id: int) -> void:
	_arrived.append(npc_id)


## Every background begins with a phone; the empty one has no kit at all.
func _start(background: String = "bg_returning") -> void:
	Game.new_game(background, 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_arrived = []
	_day0 = Game.clock.day_index()


## The clock at this hour, this many days after the game began, without the world noticing it move.
func _at(day_offset: int, hour: int) -> void:
	Game.clock.total_minutes = (_day0 + day_offset) * GameClock.MINUTES_PER_DAY + hour * 60


func _awake(npc_id: String) -> void:
	Game.npcs.get_npc(npc_id).activity = "idle"


func _check_in(npc_id: String) -> Dictionary:
	return {"npc": npc_id, "kind": "check_in", "key": "phone.msg.check_in.1", "args": {}}


# --- the rules ---------------------------------------------------------------------------------

func _allowed() -> Dictionary:
	return {"has_phone": true, "is_contact": true, "npc_awake": true, "hour": 12, "minutes_since": -1, "started_today": 0}


func test_a_message_needs_every_reason_to_pass() -> void:
	var cause := {"npc": "npc_ida", "kind": "check_in"}
	assert_ok(PhoneRules.judge_outreach(cause, _allowed()))
	var refusals := {
		"has_phone": [false, "no_phone"], "is_contact": [false, "not_a_contact"], "npc_awake": [false, "asleep"],
		"hour": [6, "quiet_hours"], "minutes_since": [60, "too_soon"], "started_today": [PhoneRules.DAILY_CAP, "daily_cap"],
	}
	for field: String in refusals:
		var state := _allowed()
		state[field] = (refusals[field] as Array)[0]
		assert_err(PhoneRules.judge_outreach(cause, state), (refusals[field] as Array)[1])
		assert_eq(PhoneRules.judge_outreach(cause, state).code, (refusals[field] as Array)[1])
	assert_eq(PhoneRules.judge_outreach({"npc": "x", "kind": "spam"}, _allowed()).code, "unknown_kind")
	var late := _allowed()
	late["hour"] = PhoneRules.LAST_HOUR
	assert_eq(PhoneRules.judge_outreach(cause, late).code, "quiet_hours", "not at night either")


func test_answering_is_judged() -> void:
	var message := {"action": {"do": "take_errand", "errand": "e"}}
	var state := {"has_phone": true, "open": true, "still_possible": true}
	assert_ok(PhoneRules.judge_answer(message, "accept", state))
	assert_ok(PhoneRules.judge_answer(message, "decline", state))
	assert_eq(PhoneRules.judge_answer({}, "accept", state).code, "no_such_answer")
	assert_eq(PhoneRules.judge_answer({"action": {}}, "accept", state).code, "no_such_answer", "a text asking nothing")
	assert_eq(PhoneRules.judge_answer(message, "shrug", state).code, "no_such_answer")
	assert_eq(PhoneRules.judge_answer(message, "accept", {"has_phone": false, "open": true, "still_possible": true}).code, "no_phone")
	assert_eq(PhoneRules.judge_answer(message, "accept", {"has_phone": true, "open": false, "still_possible": true}).code, "already_answered")
	assert_eq(PhoneRules.judge_answer(message, "accept", {"has_phone": true, "open": true, "still_possible": false}).code, "no_longer_possible")
	assert_ok(PhoneRules.judge_answer(message, "decline", {"has_phone": true, "open": true, "still_possible": false}), "you can always say no")


# --- numbers -------------------------------------------------------------------------------------

func test_everyone_starts_with_a_phone() -> void:
	for background: String in Game.data.ids("backgrounds"):
		_start(background)
		assert_true(Game.has_phone(), background)


func test_people_who_know_you_give_you_their_number() -> void:
	_start()
	assert_false(Game.phone.is_contact("npc_elias"))
	Game.relationships.adjust("npc_elias", PlayerState.ID, "familiarity", PhoneRules.CONTACT_FAMILIARITY - 0.04)
	Game.phone_director.sync_contacts()
	assert_false(Game.phone.is_contact("npc_elias"), "a stranger has not")
	Game.relationships.adjust("npc_elias", PlayerState.ID, "familiarity", 0.05)
	assert_eq(Game.phone_director.sync_contacts(), ["npc_elias"] as Array[String])
	assert_true(Game.phone.is_contact("npc_elias"))
	assert_eq(Game.phone_director.sync_contacts().size(), 0, "and only once")


func test_being_hired_gives_you_your_employers_number() -> void:
	_start()
	assert_false(Game.phone.is_contact("npc_leena"))
	assert_ok(Game.hire_player("job_kaisla"))
	assert_true(Game.phone.is_contact("npc_leena"))


# --- who writes, and when -------------------------------------------------------------------------

func test_a_message_arrives_when_someone_has_a_reason() -> void:
	_start()
	Game.phone_director.add_contact("npc_ida")
	_awake("npc_ida")
	_at(0, 12)
	var sent := Game.phone_director.deliver(_check_in("npc_ida"))
	assert_ok(sent)
	assert_eq(_arrived, ["npc_ida"] as Array[String])
	assert_eq(Game.phone.unread_count(), 1)
	assert_eq(PhoneText.render(Game.phone.thread("npc_ida")[0]), "Hey, how are things?")
	assert_true(StatusText.line().ends_with("1 new on the phone"), StatusText.line())
	Game.read_thread("npc_ida")
	assert_eq(Game.phone.unread_count(), 0)
	assert_false(StatusText.line().contains("new on the phone"))


func test_strangers_the_sleeping_and_the_small_hours_do_not_text() -> void:
	_start()
	_awake("npc_ida")
	_at(0, 12)
	assert_eq(Game.phone_director.deliver(_check_in("npc_ida")).code, "not_a_contact")
	Game.phone_director.add_contact("npc_ida")
	Game.npcs.get_npc("npc_ida").activity = "sleep"
	assert_eq(Game.phone_director.deliver(_check_in("npc_ida")).code, "asleep")
	_awake("npc_ida")
	_at(0, 3)
	assert_eq(Game.phone_director.deliver(_check_in("npc_ida")).code, "quiet_hours")
	assert_eq(Game.phone.messages.size(), 0, "nothing was queued behind the refusals")


func test_nobody_writes_twice_in_a_row_and_never_more_than_three_a_day() -> void:
	_start()
	_at(0, 12)
	for id: String in ["npc_ida", "npc_pirjo", "npc_elias", "npc_tuomas"]:
		Game.phone_director.add_contact(id)
		_awake(id)
	assert_ok(Game.phone_director.deliver(_check_in("npc_ida")))
	assert_eq(Game.phone_director.deliver(_check_in("npc_ida")).code, "too_soon")
	assert_ok(Game.phone_director.deliver(_check_in("npc_pirjo")))
	assert_ok(Game.phone_director.deliver(_check_in("npc_elias")))
	assert_eq(Game.phone_director.deliver(_check_in("npc_tuomas")).code, "daily_cap")
	_at(1, 12)
	assert_ok(Game.phone_director.deliver(_check_in("npc_tuomas")), "the next day is a new day")
	_at(6, 12)
	assert_ok(Game.phone_director.deliver(_check_in("npc_ida")), "and Ida may write again after five")


func test_without_a_phone_nothing_arrives_and_nothing_waits() -> void:
	_start()
	Game.phone_director.add_contact("npc_ida")
	_awake("npc_ida")
	_at(0, 12)
	Game.player.inventory.remove(PhoneDirector.ITEM, 1)
	assert_false(Game.has_phone())
	assert_eq(Game.phone_director.deliver(_check_in("npc_ida")).code, "no_phone")
	Game.phone_director.missed_shift("npc_ida", "loc_harbour")
	assert_eq(Game.phone_director.run_outreach(), 0)
	assert_eq(Game.phone.pending.size(), 0)
	Game.player.inventory.add(PhoneDirector.ITEM, 1)
	assert_eq(Game.phone_director.run_outreach(), 0, "the earlier ones are not there to find")
	assert_eq(Game.phone.messages.size(), 0)


func test_an_errand_arrives_by_text_and_can_be_taken_there() -> void:
	_start()
	Game.phone_director.add_contact("npc_pirjo")
	_awake("npc_pirjo")
	_at(0, 21)
	assert_eq(Game.phone_director.run_outreach(), 1)
	var message := Game.phone.thread("npc_pirjo")[0]
	assert_eq(message["kind"], "errand_offer")
	assert_eq(PhoneText.render(message), "Hi. Could you bring me 2 × Sandwich? I'll pay €16.")
	assert_true(Game.phone.is_open(message))
	var updates: Array[String] = []
	Events.quest_updated.connect(func(id: String, status: String) -> void: updates.append("%s:%s" % [id, status]))
	assert_ok(Game.answer_message(int(message["id"]), "accept"))
	assert_true(Game.quests.errands.has("errand_pirjo_groceries"))
	assert_eq(updates, ["errand_pirjo_groceries:errand_taken"] as Array[String])
	assert_eq(Game.phone.thread("npc_pirjo").size(), 2, "and your answer is in the thread")
	assert_eq(PhoneText.render(Game.phone.thread("npc_pirjo")[1]), "I'll do it.")
	assert_false(Game.phone.is_open(message))


func test_an_errand_can_be_turned_down_and_then_is_not_offered_at_once() -> void:
	_start()
	Game.phone_director.add_contact("npc_pirjo")
	_awake("npc_pirjo")
	_at(0, 21)
	Game.phone_director.run_outreach()
	var message := Game.phone.thread("npc_pirjo")[0]
	assert_ok(Game.answer_message(int(message["id"]), "decline"))
	assert_false(Game.quests.errands.has("errand_pirjo_groceries"))
	assert_eq(Game.phone_director.run_outreach(), 0, "she does not ask again the same evening")


func test_a_stale_or_repeated_answer_is_refused() -> void:
	_start()
	Game.phone_director.add_contact("npc_pirjo")
	_awake("npc_pirjo")
	_at(0, 21)
	Game.phone_director.run_outreach()
	var message := Game.phone.thread("npc_pirjo")[0]
	var rejected: Array[String] = []
	Events.action_rejected.connect(func(_p: Dictionary, code: String) -> void: rejected.append(code))
	Game.quests.take_errand("errand_pirjo_groceries", Game.clock.day_index())   # taken in person meanwhile
	assert_eq(Game.answer_message(int(message["id"]), "accept").code, "no_longer_possible")
	assert_ok(Game.answer_message(int(message["id"]), "decline"))
	assert_eq(Game.answer_message(int(message["id"]), "decline").code, "already_answered")
	assert_eq(Game.answer_message(9999, "accept").code, "no_such_answer")
	assert_eq(rejected, ["no_longer_possible", "already_answered", "no_such_answer"] as Array[String])


func test_a_deadline_brings_a_reminder_from_whoever_set_it() -> void:
	_start("bg_in_debt")
	Game.phone_director.add_contact("npc_rauno")
	_awake("npc_rauno")
	_at(5, 12)
	assert_eq(Game.phone_director.run_outreach(), 0, "nine days left is not yet a worry")
	_at(12, 12)
	assert_eq(Game.phone_director.run_outreach(), 1)
	assert_eq(PhoneText.render(Game.phone.thread("npc_rauno")[0]), "About \"Rauno's money\": just so you know, 2 days left.")
	_at(14, 12)
	Game.phone.last_started.clear()
	Game.phone_director.run_outreach()
	assert_true(PhoneText.render(Game.phone.thread("npc_rauno")[1]).ends_with("today is the last day."))


func test_a_missed_shift_is_noticed_at_a_civil_hour() -> void:
	_start("bg_dockhand")
	Game.phone_director.add_contact("npc_veikko")
	Game.phone_director.missed_shift("npc_veikko", "loc_harbour")   # counted at midnight
	_at(1, 0)
	assert_eq(Game.phone_director.run_outreach(), 0, "no one writes at midnight")
	assert_eq(Game.phone.pending.size(), 1, "it waits")
	_awake("npc_veikko")
	_at(1, 9)
	assert_eq(Game.phone_director.run_outreach(), 1)
	assert_eq(PhoneText.render(Game.phone.thread("npc_veikko")[0]), "You weren't at The Harbour today. Don't make a habit of it.")
	assert_eq(Game.phone.pending.size(), 0)


func test_a_missed_shift_that_cannot_be_sent_in_a_day_is_dropped() -> void:
	_start("bg_dockhand")
	Game.phone_director.add_contact("npc_veikko")
	Game.phone_director.missed_shift("npc_veikko", "loc_harbour")
	Game.npcs.get_npc("npc_veikko").activity = "sleep"
	_at(2, 12)
	Game.phone_director.run_outreach()
	assert_eq(Game.phone.pending.size(), 0)
	assert_eq(Game.phone.messages.size(), 0)


func test_fond_friends_check_in_but_not_everyone() -> void:
	_start()
	for id: String in ["npc_ida", "npc_elias"]:
		Game.phone_director.add_contact(id)
		_awake(id)
	Game.relationships.adjust("npc_ida", PlayerState.ID, "familiarity", 0.4)
	Game.relationships.adjust("npc_ida", PlayerState.ID, "affection", 0.4)
	_at(0, 21)
	Game.phone_director.run_outreach()
	var kinds: Array[String] = []
	for message in Game.phone.messages:
		kinds.append("%s:%s" % [message["npc"], message["kind"]])
	assert_has(kinds, "npc_ida:check_in")
	assert_false(kinds.has("npc_elias:check_in"), "an acquaintance does not")


func test_the_hourly_pass_runs_from_the_clock() -> void:
	_start()
	Game.pause_time(false)
	Game.phone_director.add_contact("npc_pirjo")
	_awake("npc_pirjo")
	Game.advance_time(GameClock.MINUTES_PER_DAY)
	Game.pause_time(true)
	assert_true(Game.phone.messages.size() <= PhoneRules.DAILY_CAP * 2, "and it is bounded")


# --- the window -------------------------------------------------------------------------------

func _window() -> PhoneWindow:
	var window: PhoneWindow = (load("res://scenes/ui/phone_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	return window


func test_the_phone_shows_threads_and_reading_one_clears_it() -> void:
	_start()
	for id: String in ["npc_pirjo", "npc_ida"]:
		Game.phone_director.add_contact(id)
	Game.phone.add_message("npc_ida", true, "check_in", "phone.msg.check_in.2", {}, Game.clock.total_minutes - 200)
	Game.phone.add_message("npc_pirjo", true, "errand_offer", "phone.msg.errand_offer",
		{"count": 2, "item": "item_sandwich", "reward": 16}, Game.clock.total_minutes - 20,
		{"do": "take_errand", "errand": "errand_pirjo_groceries"})
	var window := _window()
	assert_true(window.open())
	var rows := window.row_texts()
	assert_eq(rows.size(), 2)
	assert_true(rows[0].begins_with("Pirjo"), rows[0])
	assert_true(rows[0].contains("1 new"), rows[0])
	assert_true(rows[1].begins_with("Ida"), rows[1])
	assert_true(window.press_thread("npc_pirjo"))
	assert_eq(window.page(), PhoneWindow.Page.THREAD)
	assert_eq(Game.phone.unread_count("npc_pirjo"), 0, "opening it reads it")
	assert_eq(window.answer_labels(), ["I'll do it", "Not now"] as Array[String])
	assert_true(window.press_answer("accept"))
	assert_eq(window.answer_labels().size(), 0, "answered")
	assert_eq(window.row_texts().size(), 2, "their message and yours")
	assert_true(Game.quests.errands.has("errand_pirjo_groceries"))
	window.close()
	window.free()


func test_contacts_and_an_empty_phone_say_so() -> void:
	_start()
	var window := _window()
	window.open()
	assert_eq(window.row_texts().size(), 1)
	assert_true(window.row_texts()[0].begins_with("No messages yet"))
	window.show_page(PhoneWindow.Page.CONTACTS)
	Game.phone_director.add_contact("npc_ida")
	window.show_page(PhoneWindow.Page.CONTACTS)
	assert_eq(window.row_texts().size(), 1)
	assert_true(window.row_texts()[0].begins_with("Ida"))
	window.close()
	window.free()


func test_the_phone_stops_time_and_needs_to_be_on_you() -> void:
	_start()
	Game.pause_time(false)
	var window := _window()
	assert_true(window.open())
	assert_true(Game.clock.paused, "time stands still while it is out")
	window.close()
	assert_false(Game.clock.paused, "and moves again when it is put away")
	Game.player.inventory.remove(PhoneDirector.ITEM, 1)
	assert_false(window.open(), "no phone, no window")
	assert_false(window.is_open())
	window.free()


func test_messages_are_read_in_the_language_of_the_day() -> void:
	_start()
	Game.phone_director.add_contact("npc_pirjo")
	Game.phone.add_message("npc_pirjo", true, "errand_offer", "phone.msg.errand_offer",
		{"count": 2, "item": "item_sandwich", "reward": 16}, Game.clock.total_minutes)
	var message := Game.phone.thread("npc_pirjo")[0]
	assert_true(PhoneText.render(message).begins_with("Hi."))
	Localization.set_locale("fi")
	assert_true(PhoneText.render(message).begins_with("Moi."), PhoneText.render(message))
	Localization.set_locale("en")


# --- the save --------------------------------------------------------------------------------------

func test_the_phone_is_saved() -> void:
	_start()
	Game.phone_director.add_contact("npc_pirjo")
	_awake("npc_pirjo")
	_at(0, 21)
	Game.phone_director.run_outreach()
	Game.phone_director.missed_shift("npc_pirjo", "loc_harbour")
	Game.phone.mark_read("npc_pirjo")
	assert_ok(Game.save_game("test_phone"))
	assert_ok(Game.load_game("test_phone"))
	Game.pause_time(true)
	assert_true(Game.phone.is_contact("npc_pirjo"))
	var thread := Game.phone.thread("npc_pirjo")
	assert_eq(thread.size(), 1)
	assert_eq(thread[0]["key"], "phone.msg.errand_offer")
	assert_eq(thread[0]["action"]["errand"], "errand_pirjo_groceries")
	assert_true(bool(thread[0]["read"]))
	assert_eq(Game.phone.pending.size(), 1)
	assert_eq(Game.phone.last_started["npc_pirjo"], thread[0]["minute"])
	Game.phone_director.add_contact("npc_ida")
	var next_id := int(Game.phone.add_message("npc_ida", true, "check_in", "phone.msg.check_in.1", {}, 0)["id"])
	assert_gt(next_id, int(thread[0]["id"]), "message ids go on from where they were")


func test_a_version_5_save_gains_an_empty_phone() -> void:
	var migrated := SaveMigrations.migrate({"schema_version": 5, "quests": {}})
	assert_ok(migrated)
	assert_eq(migrated.value["schema_version"], SaveMigrations.CURRENT_VERSION)
	assert_eq(migrated.value["phone"]["messages"], [])
	assert_eq(migrated.value["phone"]["contacts"], {})
	var restored := PhoneState.new()
	restored.from_dict(migrated.value["phone"])
	assert_eq(restored.messages.size(), 0)


func test_the_phone_keeps_to_its_size() -> void:
	var book := PhoneState.new()
	for i in PhoneState.MAX_MESSAGES + 30:
		book.add_message("npc_ida", true, "check_in", "k", {}, i)
	assert_true(book.messages.size() > PhoneState.MAX_MESSAGES, "unread messages are not dropped")
	book.mark_read("npc_ida")
	book.add_message("npc_ida", true, "check_in", "k", {}, 999)
	assert_lt(book.messages.size(), PhoneState.MAX_MESSAGES + 31, "read ones make way")
	var asks := PhoneState.new()
	asks.add_message("npc_ida", true, "errand_offer", "k", {}, 0, {"do": "take_errand", "errand": "e"})
	asks.mark_read("npc_ida")
	for i in PhoneState.MAX_MESSAGES + 5:
		asks.add_message("npc_ida", false, "reply", "k", {}, i + 1)
	assert_eq(asks.messages[0]["kind"], "errand_offer", "a question nobody answered stays")
