extends TestCase
## The model behind the conversation (D-036): what a prompt is built from —
## and, as much, what it is not — how a reply is cleaned, and what happens
## when the model answers, fails, or is not there. A scripted stand-in answers
## instead of a real provider; nothing here touches a network.


var _model: ScriptedDialogueModel


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_model = ScriptedDialogueModel.new()
	Game.dialogue.model = _model


func after_each() -> void:
	if Game.dialogue.is_talking():
		Game.end_conversation()


func _reply(text: String) -> LlmResponse:
	return ScriptedDialogueModel.say(text)


func _talk_to_ida_in_her_shop() -> void:
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))
	assert_ok(Game.start_conversation("npc_ida"))


# --- what goes into a prompt ---------------------------------------------------

func test_the_prompt_is_who_they_are_where_they_are_and_the_rules() -> void:
	_talk_to_ida_in_her_shop()
	var text := DialoguePrompt.system_text(Game.dialogue.prompt_context("npc_ida"))
	assert_true(text.contains("You are Ida Lahtinen, 44, shopkeeper"), text.substr(0, 120))
	assert_true(text.contains("Keeps a ledger"), "her bio")
	assert_true(text.contains("Blunt and brief"), "her voice")
	assert_true(text.contains("Lahtinen's Corner Shop"), "where she is")
	assert_true(text.contains("working"), "what she is doing")
	assert_true(text.contains("Never make up people, places, events"), "the anti-hallucination rule")
	assert_true(text.contains("Never say you are an AI"))


## M8 step 12, D-088: an Old Town or Eastfield person is not told they live
## in Harbourside.
func test_someone_elsewhere_is_told_where_they_actually_are() -> void:
	var aarne := Game.npcs.get_npc("npc_aarne")
	aarne.location = aarne.home
	var text := DialoguePrompt.system_text(Game.dialogue.prompt_context("npc_aarne"))
	assert_true(text.contains("in Old Town, the old quarter"), text.substr(0, 160))
	assert_false(text.contains("harbour district"), text.substr(0, 160))


## D-100: a region added after D-088 got the bare fallback until this was
## checked for every region, not just the ones that existed then.
func test_every_region_has_its_own_phrase() -> void:
	for region_id: String in Game.data.ids("regions"):
		assert_true(DialoguePrompt.REGION_PHRASE.has(region_id), "%s has no REGION_PHRASE" % region_id)
	var saana := Game.npcs.get_npc("npc_saana")
	saana.location = saana.home
	var text := DialoguePrompt.system_text(Game.dialogue.prompt_context("npc_saana"))
	assert_true(text.contains("in Downtown, the newer centre"), text.substr(0, 160))


func test_they_know_the_people_they_know_and_nobody_else() -> void:
	_talk_to_ida_in_her_shop()
	var people: Array = Game.dialogue.prompt_context("npc_ida")["people"]
	assert_true(people.has("Tuomas Rask (friend)"), str(people))
	assert_true(people.has("Elias Lahtinen (family)"), str(people))
	for entry in people:
		assert_false(str(entry).contains("Joonas"), "Ida has never met Joonas")


func test_a_stranger_does_not_know_the_players_name_until_they_have_talked() -> void:
	Game.player.display_name = "Aino"
	_talk_to_ida_in_her_shop()
	var before := DialoguePrompt.system_text(Game.dialogue.prompt_context("npc_ida"))
	assert_false(before.contains("Aino"), "Ida has never met the player")
	assert_true(before.contains("someone whose name you do not know"))
	assert_true(before.contains("never talked to them before"))
	_model.replies.append(_reply("Hm."))
	await Game.say_to_npc("Hello.")
	Game.end_conversation()
	assert_ok(Game.start_conversation("npc_ida"))
	var after := DialoguePrompt.system_text(Game.dialogue.prompt_context("npc_ida"))
	assert_true(after.contains("Aino"), "having talked, she knows who the player is")


func test_only_what_they_believe_reaches_the_prompt() -> void:
	var now := Game.clock.total_minutes
	var seen := Game.knowledge.record(PlayerState.ID, "was_seen_at", now, {"object": "loc_warehouse_9"})
	Game.knowledge.witness("npc_ida", seen, now)
	var secret := Game.knowledge.record(PlayerState.ID, "owes_money_to", now, {"object": "npc_rauno"})
	Game.knowledge.witness("npc_veikko", secret, now)
	_talk_to_ida_in_her_shop()
	var knows: Array = Game.dialogue.prompt_context("npc_ida")["knows"]
	assert_eq(knows.size(), 1, str(knows))
	assert_eq(str(knows[0]), "was seen at Warehouse 9 (you saw it yourself)", "names, not ids")
	var text := DialoguePrompt.system_text(Game.dialogue.prompt_context("npc_ida"))
	assert_false(text.contains("owes money to Rauno Virta ("), "only Veikko knows that; Ida's prompt must not")


func test_the_player_speaks_first_and_last_and_turns_alternate() -> void:
	_talk_to_ida_in_her_shop()
	_model.replies.append(_reply("What do you want?"))
	_model.replies.append(_reply("Ida."))
	await Game.say_to_npc("Hello.")
	await Game.say_to_npc("Who are you?")
	var request: LlmRequest = _model.requests_for(LlmRequest.Purpose.DIALOGUE)[-1]
	assert_eq(request.purpose, LlmRequest.Purpose.DIALOGUE)
	assert_true(request.max_output_tokens <= 200, "a line, not an essay")
	assert_eq(request.messages[0]["role"], "user", "every API wants the player first")
	assert_eq(request.messages[-1]["role"], "user")
	assert_eq(request.messages[-1]["content"], "Who are you?")
	for i in range(1, request.messages.size()):
		assert_ne(request.messages[i]["role"], request.messages[i - 1]["role"], "turns alternate")
	assert_true(request.system.contains("You have just said:"), "her greeting is in the system prompt")


# --- what comes back -------------------------------------------------------------

func test_the_model_answers_as_the_person() -> void:
	_talk_to_ida_in_her_shop()
	_model.replies.append(_reply("Ida: *wipes the counter* \"We're open, aren't we?\""))
	var said: Dictionary = (await Game.say_to_npc("Are you open?")).value
	assert_eq(said["text"], "We're open, aren't we?", "no label, no stage direction, no quotes")
	assert_eq(said["source"], "model")


func test_a_failed_model_falls_back_to_an_authored_line_and_the_talk_goes_on() -> void:
	_talk_to_ida_in_her_shop()
	_model.replies.append(LlmResponse.failure("timeout", "too slow"))
	var said: Dictionary = (await Game.say_to_npc("Who are you?")).value
	assert_eq(said["source"], "authored")
	assert_eq(said["fallback_reason"], "timeout")
	assert_eq(said["text"], Localization.t("dialogue.npc_ida.about_self.1"))
	assert_true(Game.dialogue.is_talking(), "the conversation carries on")


func test_an_empty_reply_counts_as_a_failure() -> void:
	_talk_to_ida_in_her_shop()
	_model.replies.append(_reply("*shrugs*"))
	var said: Dictionary = (await Game.say_to_npc("Hello.")).value
	assert_eq(said["source"], "authored")
	assert_eq(said["fallback_reason"], "empty_reply")


func test_without_a_model_nothing_is_asked() -> void:
	_model.available = false
	_talk_to_ida_in_her_shop()
	var said: Dictionary = (await Game.say_to_npc("Hello.")).value
	assert_eq(_model.requests.size(), 0, "no call, no cost")
	assert_eq(said["fallback_reason"], "offline")


func test_what_a_line_does_comes_from_the_players_words_not_the_reply() -> void:
	_talk_to_ida_in_her_shop()
	_model.replies.append(_reply("Oh, stay a while, there's no hurry."))
	var said: Dictionary = (await Game.say_to_npc("Goodbye.")).value
	assert_true(said["ends"], "the player said goodbye; the model does not get to keep them")


func test_the_game_speaks_through_its_llm_client() -> void:
	Game.new_game("", 7)
	assert_true(Game.dialogue.model is LlmDialogueModel)
	assert_false(Game.dialogue.model.is_available(), "the test runner never configures a real provider")


# --- cleaning a reply ------------------------------------------------------------

func test_cleaning_keeps_speech_and_drops_everything_else() -> void:
	assert_eq(DialoguePrompt.clean_reply("Ida Lahtinen: Fine.", "Ida Lahtinen"), "Fine.")
	assert_eq(DialoguePrompt.clean_reply("Ida: Fine.", "Ida Lahtinen"), "Fine.")
	assert_eq(DialoguePrompt.clean_reply("Listen: I don't know.", "Ida Lahtinen"), "Listen: I don't know.",
		"a colon in speech is speech")
	assert_eq(DialoguePrompt.clean_reply("(sighs) Fine. *turns away*", "Ida Lahtinen"), "Fine.")
	assert_eq(DialoguePrompt.clean_reply("  \"Fine.\"  ", "Ida Lahtinen"), "Fine.")
	assert_eq(DialoguePrompt.clean_reply("*nods*", "Ida Lahtinen"), "")


func test_a_speech_is_cut_at_a_sentence() -> void:
	var long := "This is a sentence that goes on. ".repeat(30)
	var cut := DialoguePrompt.clean_reply(long, "Ida Lahtinen")
	assert_true(cut.length() <= DialoguePrompt.MAX_REPLY_CHARS, "%d chars" % cut.length())
	assert_true(cut.ends_with("."), cut.right(20))


func test_relationship_numbers_become_feelings() -> void:
	assert_true(DialoguePrompt.relationship_words({}).contains("never talked"))
	var close := DialoguePrompt.relationship_words({"familiarity": 0.9, "affection": 0.6, "trust": 0.7})
	assert_true(close.contains("know them well") and close.contains("like them") and close.contains("trust them"))
	var sour := DialoguePrompt.relationship_words({"familiarity": 0.5, "trust": -0.6, "fear": 0.5})
	assert_true(sour.contains("do not trust") and sour.contains("frighten"))


func test_a_reply_cut_off_by_the_limit_keeps_its_finished_sentences() -> void:
	assert_eq(DialoguePrompt.clean_reply("Hei vain. Kuulin että olit satamassa ja sitten mi", "Ida", true),
		"Hei vain.")
	assert_eq(DialoguePrompt.clean_reply("Hei vain. Mitä kuuluu?", "Ida", true), "Hei vain. Mitä kuuluu?")
	assert_eq(DialoguePrompt.clean_reply("Kuulin että olit satamassa ja sitten mi", "Ida", true).right(1), "…",
		"nothing finished: show it as unfinished rather than as a whole thought")
	assert_eq(DialoguePrompt.clean_reply("Hei vain. Kuulin että", "Ida", false), "Hei vain. Kuulin että")
