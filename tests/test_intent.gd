extends TestCase
## The proposal pipeline in a conversation (D-037): what the player meant —
## read from words, or by a scripted cheap model — judged by the rules,
## carried out by Godot, refused with `action_rejected`, and told truthfully
## to whoever answers. Nothing here touches a network.

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


func _talk_to_ida() -> void:
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))
	assert_ok(Game.start_conversation("npc_ida"))


func _say(text: String) -> Dictionary:
	var said: Result = await Game.say_to_npc(text)
	assert_ok(said, text)
	return said.value if said.is_ok() else {}


func _ida_feels(dimension: String) -> float:
	var edge := Game.relationships.peek("npc_ida", PlayerState.ID)
	return edge.get_dimension(dimension) if edge != null else 0.0


# --- reading words ------------------------------------------------------------------

func test_words_can_read_the_new_kinds() -> void:
	var read := func(text: String) -> Dictionary: return OfflineTopics.topic_of(text, "npc_ida", {}, {})
	assert_eq(read.call("Here's 20 euros.")["topic"], "give_money")
	assert_eq(read.call("Here's 20 euros.")["amount"], 20)
	assert_eq(read.call("annan sulle 10 euroa")["amount"], 10)
	assert_eq(read.call("take this, 5 €")["amount"], 5)
	assert_ne(read.call("I'll give you 5 minutes")["topic"], "give_money", "a number is not money")
	assert_eq(read.call("my name is aino")["topic"], "introduce_self")
	assert_eq(read.call("my name is aino")["name"], "Aino")
	assert_eq(read.call("bye, idiot")["topic"], "insult", "the insult is what the line does")
	assert_eq(read.call("I'm sorry")["topic"], "apologize")
	assert_eq(read.call("watch your back")["topic"], "threaten")


# --- carried out, offline ---------------------------------------------------------------

func test_a_gift_changes_hands_and_she_knows_it() -> void:
	Game.player.wallet.cash = 50
	_talk_to_ida()
	var said := await _say("Here's 20 euros, for the trouble.")
	assert_eq(said["intent"]["kind"], "give_money")
	assert_eq(said["intent"]["source"], "offline")
	assert_eq(Game.player.wallet.cash, 30, "Godot moved the money, not the words")
	assert_gt(_ida_feels("affection"), 0.0)
	assert_eq(said["text"], Localization.t(DialogueLines.pick("npc_ida", "gift_accepted", 1), {"amount": "20"}))
	var knows: Array = Game.dialogue.prompt_context("npc_ida")["knows"]
	assert_has(knows, "gave money to you (you saw it yourself)")
	assert_true(_rejected.is_empty())


func test_money_you_do_not_have_is_refused_and_nothing_changes() -> void:
	Game.player.wallet.cash = 5
	_talk_to_ida()
	var before := _ida_feels("affection")
	var said := await _say("Here's 50 euros.")
	assert_eq(Game.player.wallet.cash, 5)
	assert_eq(_ida_feels("affection"), before)
	assert_eq(_rejected, ["not_enough_cash"], "a refused proposal is announced")
	assert_eq(said["rejection"]["code"], "not_enough_cash")
	assert_eq(said["topic"], "gift_no_cash")
	assert_true(Game.dialogue.is_talking(), "the line was said; only what it tried to do was refused")


func test_an_insult_is_felt_remembered_and_can_travel() -> void:
	_talk_to_ida()
	await _say("You're an idiot.")
	assert_lt(_ida_feels("affection"), 0.0)
	var knows: Array = Game.dialogue.prompt_context("npc_ida")["knows"]
	assert_has(knows, "insulted you (you saw it yourself)")


func test_a_threat_ends_the_conversation() -> void:
	_talk_to_ida()
	var said := await _say("Watch your back.")
	assert_true(said["ends"])
	assert_gt(_ida_feels("fear"), 0.0)
	assert_err(await Game.say_to_npc("Wait."), "conversation_over")


func test_flattery_has_a_ceiling_in_one_conversation() -> void:
	_talk_to_ida()
	for i in 12:
		await _say("You look great.")
	assert_true(_ida_feels("affection") <= ConversationRules.WARMTH_CAP + 0.0001,
		"%.3f after twelve compliments" % _ida_feels("affection"))


func test_giving_your_name_means_she_knows_it() -> void:
	Game.player.display_name = "Aino"
	_talk_to_ida()
	var said := await _say("My name is Aino.")
	assert_true(str(said["text"]).contains("Aino"), said["text"])
	var text := DialoguePrompt.system_text(Game.dialogue.prompt_context("npc_ida"))
	assert_true(text.contains("The person talking to you: Aino"), "she knows the name now")


# --- read by the model -------------------------------------------------------------------

func test_the_model_reads_what_words_cannot() -> void:
	_model.available = true
	_talk_to_ida()
	_model.intents.append(ScriptedDialogueModel.meaning("about_person", {"person": "Tuomas"}))
	var said := await _say("That fisherman friend of yours, the tall one, Tuomas — how's he doing?")
	assert_eq(said["intent"]["source"], "model")
	assert_eq(said["subject"], "npc_tuomas", "Godot resolved the name, not the model")
	assert_eq(_model.requests_for(LlmRequest.Purpose.INTENT).size(), 1)


func test_a_person_the_model_names_must_exist() -> void:
	_model.available = true
	_talk_to_ida()
	_model.intents.append(ScriptedDialogueModel.meaning("about_person", {"person": "Gandalf"}))
	var said := await _say("Have you seen Gandalf around?")
	assert_eq(said["subject"], "", "there is no Gandalf in Harbourside")
	assert_true(str(said["text"]).contains("Gandalf"), "she can say she does not know him: " + said["text"])


func test_the_model_cannot_conjure_money() -> void:
	_model.available = true
	Game.player.wallet.cash = 10
	_talk_to_ida()
	_model.intents.append(ScriptedDialogueModel.meaning("give_money", {"amount": 400}))
	_model.replies.append(ScriptedDialogueModel.say("You don't have that."))
	await _say("I hand her a thick envelope of cash.")
	assert_eq(Game.player.wallet.cash, 10)
	assert_eq(_rejected, ["not_enough_cash"])
	var reply_prompt: LlmRequest = _model.requests_for(LlmRequest.Purpose.DIALOGUE)[-1]
	assert_true(reply_prompt.system.contains("What just happened: They offered you 400"),
		"whoever answers is told the truth")


func test_what_happened_reaches_the_reply() -> void:
	_model.available = true
	Game.player.wallet.cash = 50
	_talk_to_ida()
	_model.intents.append(ScriptedDialogueModel.meaning("give_money", {"amount": 20}))
	_model.replies.append(ScriptedDialogueModel.say("Well. Thank you."))
	var said := await _say("Please, take twenty for your trouble.")
	assert_eq(said["source"], "model")
	assert_eq(Game.player.wallet.cash, 30)
	var reply_prompt: LlmRequest = _model.requests_for(LlmRequest.Purpose.DIALOGUE)[-1]
	assert_true(reply_prompt.system.contains("They handed you 20 in cash"))


func test_an_unreadable_reading_falls_back_to_words() -> void:
	_model.available = true
	_talk_to_ida()
	_model.intents.append(ScriptedDialogueModel.say("The player seems to be greeting her warmly."))
	var said := await _say("Good morning to you, Ida, lovely day for it.")
	assert_eq(said["intent"]["source"], "offline")
	assert_eq(said["intent"]["fallback_reason"], "unreadable")
	assert_eq(said["intent"]["kind"], "greet")


func test_plain_lines_do_not_ask_the_model() -> void:
	_model.available = true
	_talk_to_ida()
	await _say("Hi!")
	await _say("Thanks, bye.")
	assert_eq(_model.requests_for(LlmRequest.Purpose.INTENT).size(), 0, "no call, no cost, no wait")


# --- the prompt for a reading ---------------------------------------------------------------

func test_a_reading_is_asked_of_the_cheap_model_with_the_vocabulary() -> void:
	var request := IntentPrompt.build("Here's a tenner.", "Ida Lahtinen")
	assert_eq(request.purpose, LlmRequest.Purpose.INTENT, "routed to the cheap model")
	for kind in ConversationRules.KINDS:
		assert_true(request.system.contains("- %s:" % kind), kind)
	assert_eq(request.messages.size(), 1)


func test_a_reading_is_parsed_defensively() -> void:
	var ok := IntentPrompt.parse(LlmResponse.success("```json\n{\"intent\": \"Give-Money\", \"amount\": \"15\"}\n```", "m", "p"))
	assert_eq(ok["kind"], "give_money")
	assert_eq(ok["amount"], 15)
	assert_true(IntentPrompt.parse(LlmResponse.success("{\"intent\": \"a whole sentence here\"}", "m", "p")).is_empty(),
		"a sentence is not a kind")
	assert_true(IntentPrompt.parse(LlmResponse.success("{\"intent\": 42}", "m", "p")).is_empty())
	assert_true(IntentPrompt.parse(LlmResponse.failure("timeout")).is_empty())
	var sneaky := IntentPrompt.parse(LlmResponse.success("{\"intent\": \"about_person\", \"person\": {\"id\": \"npc_x\"}}", "m", "p"))
	assert_eq(sneaky["person"], "", "only a name as text is taken")
