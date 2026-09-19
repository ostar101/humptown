extends TestCase
## Writing to people by phone (D-046): what may be sent, when it is read, and
## that a text goes through exactly the road a spoken line does.

var _model: ScriptedDialogueModel
var _day0 := 0
var _rejected: Array[String] = []
var _arrived: Array[String] = []
var _deeds: Array[String] = []


func before_each() -> void:
	_rejected = []
	_arrived = []
	_deeds = []
	Events.action_rejected.connect(_on_rejected)
	Events.phone_message.connect(_on_message)
	Events.player_deed.connect(_on_deed)


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)
	Events.phone_message.disconnect(_on_message)
	Events.player_deed.disconnect(_on_deed)
	Localization.set_locale("en")
	Game.saves.delete_slot("test_phone_texts")


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


func _on_message(npc_id: String, _message_id: int) -> void:
	_arrived.append(npc_id)


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
	_at(0, 12)


func _at(day_offset: int, hour: int) -> void:
	Game.clock.total_minutes = (_day0 + day_offset) * GameClock.MINUTES_PER_DAY + hour * 60


## Someone with a number in the phone, up and about.
func _contact(npc_id: String, activity: String = "idle") -> void:
	Game.phone_director.add_contact(npc_id)
	Game.npcs.get_npc(npc_id).activity = activity


## Sends a text, lets the person get to it, and returns what they answered.
func _text_and_wait(npc_id: String, line: String) -> Dictionary:
	assert_ok(Game.send_text(npc_id, line), line)
	Game.clock.total_minutes += 60
	await Game.phone_director.process_due()
	var thread := Game.phone.thread(npc_id)
	return thread[thread.size() - 1]


# --- the rules ---------------------------------------------------------------------------------

func test_what_may_be_sent() -> void:
	var ok := {"has_phone": true, "is_contact": true, "waiting": 0}
	assert_eq(PhoneRules.judge_send("  hello  ", ok).value, "hello", "trimmed")
	assert_eq(PhoneRules.judge_send("hi", {"has_phone": false, "is_contact": true, "waiting": 0}).code, "no_phone")
	assert_eq(PhoneRules.judge_send("hi", {"has_phone": true, "is_contact": false, "waiting": 0}).code, "not_a_contact")
	assert_eq(PhoneRules.judge_send("   ", ok).code, "empty")
	assert_eq(PhoneRules.judge_send("x".repeat(PhoneRules.MAX_TEXT_LENGTH + 1), ok).code, "too_long")
	assert_ok(PhoneRules.judge_send("x".repeat(PhoneRules.MAX_TEXT_LENGTH), ok))
	assert_eq(PhoneRules.judge_send("hi", {"has_phone": true, "is_contact": true, "waiting": PhoneRules.MAX_WAITING}).code, "too_many_waiting")


func test_when_a_text_can_be_read() -> void:
	assert_ok(PhoneRules.judge_reading({"npc_awake": true, "hour": 12}))
	assert_eq(PhoneRules.judge_reading({"npc_awake": false, "hour": 12}).code, "asleep")
	assert_eq(PhoneRules.judge_reading({"npc_awake": true, "hour": 3}).code, "quiet_hours")
	assert_eq(PhoneRules.judge_reading({"npc_awake": true, "hour": PhoneRules.LAST_HOUR}).code, "quiet_hours")
	assert_gt(PhoneRules.reading_delay("work"), PhoneRules.reading_delay("idle"), "at work it takes longer")


# --- sending -------------------------------------------------------------------------------------

func test_a_sent_text_is_in_the_thread_and_waits_to_be_read() -> void:
	_start()
	_contact("npc_ida")
	var sent := Game.send_text("npc_ida", "  Hello, Ida.  ")
	assert_ok(sent)
	var thread := Game.phone.thread("npc_ida")
	assert_eq(thread.size(), 1)
	assert_eq(PhoneText.render(thread[0]), "Hello, Ida.")
	assert_eq(thread[0]["from"], "player")
	assert_true(bool(thread[0]["read"]), "your own words are read")
	assert_eq(Game.phone.waiting_for("npc_ida"), 1)
	assert_eq(Game.phone.outbox[0]["due"], Game.clock.total_minutes + PhoneRules.reading_delay("idle"))
	assert_eq(PhoneText.preview("npc_ida"), "You: Hello, Ida.")


func test_a_text_that_cannot_be_sent_is_refused_and_announced() -> void:
	_start()
	assert_eq(Game.send_text("npc_ida", "Hello").code, "not_a_contact", "no number")
	_contact("npc_ida")
	assert_eq(Game.send_text("npc_ida", "  ").code, "empty")
	for i in PhoneRules.MAX_WAITING:
		assert_ok(Game.send_text("npc_ida", "Hello %d" % i))
	assert_eq(Game.send_text("npc_ida", "Hello again").code, "too_many_waiting", "give her a moment")
	assert_eq(Game.phone.thread("npc_ida").size(), PhoneRules.MAX_WAITING, "and nothing was added")
	Game.player.inventory.remove(PhoneDirector.ITEM, 1)
	assert_eq(Game.send_text("npc_ida", "Hello").code, "no_phone")
	assert_eq(_rejected, ["not_a_contact", "empty", "too_many_waiting", "no_phone"] as Array[String])


# --- being read ------------------------------------------------------------------------------------

func test_nothing_happens_before_they_get_to_it() -> void:
	_start()
	_contact("npc_ida")
	Game.send_text("npc_ida", "Hello, Ida.")
	await Game.phone_director.process_due()
	assert_eq(Game.phone.thread("npc_ida").size(), 1, "not yet")
	Game.clock.total_minutes += PhoneRules.READ_DELAY_DEFAULT
	await Game.phone_director.process_due()
	assert_eq(Game.phone.thread("npc_ida").size(), 2, "now")
	assert_eq(Game.phone.outbox.size(), 0)


func test_the_answer_is_a_text_from_them() -> void:
	_start()
	_contact("npc_ida")
	var reply := await _text_and_wait("npc_ida", "Hello, Ida.")
	assert_eq(reply["from"], "npc")
	assert_eq(reply["kind"], "reply")
	assert_ne(PhoneText.render(reply), "", "she said something")
	assert_eq(_arrived, ["npc_ida"] as Array[String])
	assert_eq(Game.phone.unread_count("npc_ida"), 1)
	assert_eq(Game.phone.waiting_for("npc_ida"), 0)


func test_an_answer_does_not_use_up_their_turn_to_write_first() -> void:
	_start()
	_contact("npc_ida")
	await _text_and_wait("npc_ida", "Hello, Ida.")
	assert_eq(Game.phone.started_since(0), 0, "she answered; she did not start anything")
	assert_false(Game.phone.last_started.has("npc_ida"))
	var cause := {"npc": "npc_ida", "kind": "check_in", "key": "phone.msg.check_in.1", "args": {}}
	assert_ok(Game.phone_director.deliver(cause), "and may still write first today")


func test_the_asleep_and_the_small_hours_read_later() -> void:
	_start()
	_contact("npc_ida", "sleep")
	Game.send_text("npc_ida", "Hello, Ida.")
	Game.clock.total_minutes += 60
	await Game.phone_director.process_due()
	assert_eq(Game.phone.outbox.size(), 1, "still asleep")
	assert_eq(Game.phone.outbox[0]["due"], Game.clock.total_minutes + PhoneRules.READ_RETRY, "she will look again")
	Game.npcs.get_npc("npc_ida").activity = "idle"
	_at(1, 3)
	Game.phone.outbox[0]["due"] = Game.clock.total_minutes
	await Game.phone_director.process_due()
	assert_eq(Game.phone.outbox.size(), 1, "awake, but not at three in the morning")
	_at(1, 8)
	Game.phone.outbox[0]["due"] = Game.clock.total_minutes
	await Game.phone_director.process_due()
	assert_eq(Game.phone.outbox.size(), 0, "read at breakfast")
	assert_eq(Game.phone.thread("npc_ida").size(), 2)


func test_someone_at_work_takes_longer() -> void:
	_start()
	_contact("npc_ida", "work")
	Game.send_text("npc_ida", "Hello, Ida.")
	assert_eq(Game.phone.outbox[0]["due"], Game.clock.total_minutes + PhoneRules.READ_DELAY["work"])


func test_the_clock_reads_texts_as_it_goes() -> void:
	_start()
	_contact("npc_ida")
	Game.send_text("npc_ida", "Hello, Ida.")
	Game.pause_time(false)
	Game.advance_time(PhoneRules.READ_DELAY_DEFAULT + 1)
	Game.pause_time(true)
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(Game.phone.outbox.size(), 0, "read when the time came")


# --- the same road as speech ----------------------------------------------------------------------------

func test_a_text_can_do_what_a_word_can() -> void:
	_start()
	_contact("npc_pirjo")
	var before := Game.relationships.peek("npc_pirjo", PlayerState.ID)
	var affection := before.affection if before != null else 0.0
	await _text_and_wait("npc_pirjo", "You look great.")
	assert_gt(Game.relationships.peek("npc_pirjo", PlayerState.ID).affection, affection, "a compliment warms by text too")
	var reply := await _text_and_wait("npc_pirjo", "Can I help you with anything?")
	assert_true(Game.quests.errands.has("errand_pirjo_groceries"), "and an offer of help gets an errand")
	assert_true(PhoneText.render(reply).contains("Sandwich"), PhoneText.render(reply))
	assert_has(_deeds, "texted")
	assert_false(_deeds.has("talked"), "a text is not a conversation")


func test_money_by_text_goes_through_the_account_and_not_the_hand() -> void:
	_start()
	_contact("npc_pirjo")
	Game.player.wallet.cash = 100
	Game.player.wallet.bank = 200
	await _text_and_wait("npc_pirjo", "Here's 50 euros.")
	assert_eq(Game.player.wallet.cash, 100, "no hands, no cash")
	assert_eq(Game.player.wallet.bank, 150, "it left the account")
	assert_eq(_rejected, [] as Array[String])
	assert_has(_deeds, "gave_money")
	Game.player.wallet.bank = 10
	var reply := await _text_and_wait("npc_pirjo", "Here's 50 euros.")
	assert_eq(Game.player.wallet.bank, 10, "nothing was sent")
	assert_eq(_rejected, ["not_enough_bank"] as Array[String])
	assert_true(["That is not in your account. Don't play games with me.",
		"The transfer bounced. Check your balance before you offer."].has(PhoneText.render(reply)), PhoneText.render(reply))


func test_a_text_is_remembered_and_earns_a_little_familiarity() -> void:
	_start()
	_contact("npc_pirjo")
	var edge := Game.relationships.get_edge("npc_pirjo", PlayerState.ID)
	var before := edge.familiarity
	await _text_and_wait("npc_pirjo", "You look great.")
	assert_almost(Game.relationships.get_edge("npc_pirjo", PlayerState.ID).familiarity, before + DialogueDirector.FAMILIARITY_PER_TEXT)
	assert_false(Game.memories.recall("npc_pirjo", Game.clock.total_minutes, func(_id: String) -> String: return "").is_empty(),
		"and she remembers it")


func test_a_text_can_be_read_while_talking_to_someone_else() -> void:
	_start()
	_contact("npc_ida")
	var npc := Game.npcs.get_npc("npc_pirjo")
	npc.location = "loc_dock_street"
	npc.activity = "walk"
	assert_ok(Game.start_conversation("npc_pirjo"))
	var before := Game.dialogue.conversation
	await _text_and_wait("npc_ida", "Hello, Ida.")
	assert_true(Game.dialogue.conversation == before, "the conversation on the quay was not disturbed")
	assert_eq(Game.dialogue.conversation.npc_id, "npc_pirjo")
	Game.end_conversation()


func test_a_model_answers_a_text_knowing_it_is_one() -> void:
	_start()
	_contact("npc_ida")
	_model.available = true
	_model.intents.append(ScriptedDialogueModel.meaning("about_work"))
	_model.replies.append(ScriptedDialogueModel.say("Busy day. Come by later."))
	var reply := await _text_and_wait("npc_ida", "How is work going for you these days?")
	assert_eq(PhoneText.render(reply), "Busy day. Come by later.")
	var asked := _model.requests_for(LlmRequest.Purpose.DIALOGUE)
	assert_eq(asked.size(), 1)
	assert_true(asked[0].system.contains("text message"), "the model was told it is a text")
	assert_false(asked[0].system.contains("face to face"))


# --- the window and the save --------------------------------------------------------------------------

func _window() -> PhoneWindow:
	var window: PhoneWindow = (load("res://scenes/ui/phone_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	return window


func test_you_can_text_from_the_contacts_page() -> void:
	_start()
	_contact("npc_ida")
	var window := _window()
	assert_true(window.open())
	window.show_page(PhoneWindow.Page.CONTACTS)
	assert_true(window.row_texts()[0].begins_with("Ida"))
	assert_true(window.press_thread("npc_ida"), "a contact opens as a thread")
	assert_true(window.row_texts()[0].begins_with("Nothing here yet"))
	assert_ok(window.type_and_send("Hello, Ida."))
	assert_eq(window.row_texts(), ["You · 12:00|Hello, Ida.", "…"] as Array[String], "yours, and waiting")
	assert_eq(window.notice_text(), "")
	window.close()
	window.free()


func test_the_window_says_why_a_text_was_not_sent() -> void:
	_start()
	_contact("npc_ida")
	var window := _window()
	window.open()
	window.open_thread("npc_ida")
	for i in PhoneRules.MAX_WAITING:
		assert_ok(window.type_and_send("Hello %d" % i))
	assert_err(window.type_and_send("Hello again"))
	assert_eq(window.notice_text(), "They have not answered yet.")
	assert_err(window.type_and_send("   "))
	assert_eq(window.notice_text(), "", "an empty box is not worth a complaint")
	window.close()
	window.free()


func test_a_reply_that_arrives_while_the_thread_is_open_is_read() -> void:
	_start()
	_contact("npc_ida")
	var window := _window()
	window.open()
	window.open_thread("npc_ida")
	window.type_and_send("Hello, Ida.")
	Game.clock.total_minutes += 10
	await Game.phone_director.process_due()
	assert_eq(Game.phone.unread_count(), 0, "you were looking at it")
	assert_eq(window.row_texts().size(), 2)
	window.close()
	window.free()


func test_texts_waiting_to_be_read_are_saved() -> void:
	_start()
	_contact("npc_ida")
	Game.send_text("npc_ida", "Hello, Ida.")
	assert_ok(Game.save_game("test_phone_texts"))
	assert_ok(Game.load_game("test_phone_texts"))
	Game.pause_time(true)
	assert_eq(Game.phone.outbox.size(), 1)
	assert_eq(Game.phone.outbox[0]["line"], "Hello, Ida.")
	assert_eq(PhoneText.render(Game.phone.thread("npc_ida")[0]), "Hello, Ida.")
	Game.npcs.get_npc("npc_ida").activity = "idle"
	Game.clock.total_minutes = maxi(Game.clock.total_minutes, int(Game.phone.outbox[0]["due"])) + 1
	Game.clock.total_minutes = (Game.clock.day_index() * GameClock.MINUTES_PER_DAY) + 12 * 60
	Game.phone.outbox[0]["due"] = Game.clock.total_minutes
	await Game.phone_director.process_due()
	assert_eq(Game.phone.thread("npc_ida").size(), 2, "and read after loading")


func test_a_phone_saved_before_texting_still_loads() -> void:
	var older := PhoneState.new()
	older.from_dict({"contacts": {"npc_ida": 0}, "messages": [
		{"id": 4, "npc": "npc_ida", "from": "npc", "kind": "check_in", "key": "phone.msg.check_in.1", "args": {}, "minute": 5, "read": true}],
		"last_started": {"npc_ida": 5}, "pending": [], "next_id": 5})
	assert_eq(older.outbox.size(), 0)
	assert_eq(older.messages[0]["text"], "")
	assert_eq(PhoneState.new().waiting_for("npc_ida"), 0)
