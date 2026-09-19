extends TestCase
## What people remember of the player (D-038): episodes written by rule from
## what the rules judged, folded into a bounded summary, rewritten by a
## scripted model when one is there, recalled into prompts, and saved.

var _model: ScriptedDialogueModel


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_model = ScriptedDialogueModel.new()
	_model.available = false
	Game.dialogue.model = _model


func after_each() -> void:
	if Game.dialogue.is_talking():
		Game.end_conversation()
	Game.saves.delete_slot("test_memory")


func _talk_to_ida() -> void:
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	var map := Game.current_map()
	if Game.player.interior != "loc_corner_shop":
		assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
		assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))
	assert_ok(Game.start_conversation("npc_ida"))


func _conversation(lines: Array[String]) -> void:
	_talk_to_ida()
	for line in lines:
		assert_ok(await Game.say_to_npc(line), line)
	if Game.dialogue.is_talking():
		assert_ok(Game.end_conversation())


func _place(id: String) -> String:
	return "the " + id


# --- the book itself ------------------------------------------------------------------

func test_episodes_are_recalled_with_how_long_ago() -> void:
	var book := MemoryBook.new()
	var things: Array[String] = ["asked about your work"]
	book.add_episode("npc_ida", 100, "shop", things, 0.1)
	var recalled := book.recall("npc_ida", 100 + GameClock.MINUTES_PER_DAY, _place)
	assert_eq(recalled, ["Yesterday, at the shop: they asked about your work."])
	var nothing: Array[String] = []
	book.add_episode("npc_ida", 200 + GameClock.MINUTES_PER_DAY, "shop", nothing, 0.1)
	assert_eq(book.recall("npc_ida", 300 + GameClock.MINUTES_PER_DAY, _place)[-1],
		"Earlier today, at the shop: they stopped for a chat.")


func test_old_episodes_fold_into_a_bounded_summary() -> void:
	var book := MemoryBook.new()
	for i in MemoryBook.MAX_EPISODES + 1:
		var things: Array[String] = ["gave you %d in cash" % (i + 1)]
		book.add_episode("npc_ida", i * 60, "shop", things, 0.5)
	assert_true(book.needs_folding("npc_ida"))
	var folded := book.fold_by_rule("npc_ida", _place)
	assert_eq(folded.size(), MemoryBook.MAX_EPISODES + 1 - MemoryBook.KEEP_EPISODES)
	assert_eq(book.episodes("npc_ida").size(), MemoryBook.KEEP_EPISODES, "the latest kept whole")
	assert_true(book.summary("npc_ida").contains("Once, at the shop, they gave you 1 in cash."))
	assert_eq(book.folds("npc_ida"), 1)


func test_a_summary_that_grows_too_long_loses_what_mattered_least() -> void:
	var book := MemoryBook.new()
	var long_thing := "asked about " + "the weather ".repeat(12)
	for round in 6:
		for i in MemoryBook.MAX_EPISODES + 1:
			var weight := 0.9 if round == 0 and i == 0 else 0.1
			var things: Array[String] = ["threatened you" if weight > 0.5 else long_thing]
			book.add_episode("npc_ida", round * 10000 + i, "shop", things, weight)
		book.fold_by_rule("npc_ida", _place)
	var gist := book.summary("npc_ida")
	assert_true(gist.length() <= MemoryBook.SUMMARY_MAX_CHARS + 2, "%d chars" % gist.length())
	assert_true(gist.contains("threatened you"), "the threat outlasts the small talk")


func test_a_rewritten_summary_must_be_fit_to_keep() -> void:
	var book := MemoryBook.new()
	for i in MemoryBook.MAX_EPISODES + 1:
		var things: Array[String] = ["complimented you"]
		book.add_episode("npc_ida", i, "shop", things, 0.2)
	book.fold_by_rule("npc_ida", _place)
	assert_err(book.set_summary("npc_ida", "They are kind.", 0), "stale_summary")
	assert_err(book.set_summary("npc_ida", "   ", 1), "empty_summary")
	assert_err(book.set_summary("npc_ida", "They know npc_tuomas.", 1), "summary_has_ids")
	assert_ok(book.set_summary("npc_ida", "They are always kind to you.", 1))
	assert_eq(book.summary("npc_ida"), "They are always kind to you.")


func test_the_book_round_trips() -> void:
	var book := MemoryBook.new()
	var things: Array[String] = ["gave you 5 in cash", "insulted you"]
	book.add_episode("npc_ida", 42, "loc_corner_shop", things, 0.6)
	var copy := MemoryBook.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(book.to_dict())))
	assert_eq(copy.recall("npc_ida", 42, _place), book.recall("npc_ida", 42, _place))
	assert_eq(copy.episodes("npc_ida")[0]["things"], things)


# --- through the game --------------------------------------------------------------------

func test_a_conversation_leaves_a_memory_of_what_was_done() -> void:
	Game.player.wallet.cash = 50
	await _conversation(["Who are you?", "Here's 20 euros.", "You look great.", "You look great."])
	var recalled: Array = Game.dialogue.prompt_context("npc_ida")["memories"]
	assert_eq(recalled.size(), 1, str(recalled))
	assert_eq(recalled[0],
		"Earlier today, at Lahtinen's Corner Shop: they asked who you are, gave you 20 in cash, and complimented you.",
		"once each, in order, in her words")


func test_what_a_model_says_is_not_remembered() -> void:
	_model.available = true
	_model.replies.append(ScriptedDialogueModel.say("For you, a lifetime discount and my brother's boat."))
	await _conversation(["Good morning to you, Ida, lovely day for it."])
	for memory in Game.dialogue.prompt_context("npc_ida")["memories"]:
		assert_false(str(memory).contains("discount"), "only what the rules judged is kept")


func test_memories_age() -> void:
	await _conversation(["You're an idiot."])
	Game.advance_time(GameClock.MINUTES_PER_DAY)
	var recalled: Array = Game.dialogue.prompt_context("npc_ida")["memories"]
	assert_true(str(recalled[-1]).begins_with("Yesterday"), str(recalled))
	var text := DialoguePrompt.system_text(Game.dialogue.prompt_context("npc_ida"))
	assert_true(text.contains("What you remember of them:\n- Yesterday"), "and reach the prompt")


func test_many_conversations_fold_and_a_model_may_rewrite_the_summary() -> void:
	for i in MemoryBook.MAX_EPISODES + 1:
		await _conversation(["Who are you?"])
	assert_eq(Game.memories.episodes("npc_ida").size(), MemoryBook.KEEP_EPISODES)
	assert_ne(Game.memories.summary("npc_ida"), "", "folded by rule, with no model at all")

	_model.available = true
	_model.replies.append(ScriptedDialogueModel.say("They keep asking who you are."))
	var folded: Array[String] = ["Once, at Lahtinen's Corner Shop, they asked who you are."]
	var rewritten: Result = await Game.dialogue.summarise("npc_ida", folded, Game.memories.folds("npc_ida"))
	assert_ok(rewritten)
	assert_eq(Game.memories.summary("npc_ida"), "They keep asking who you are.")
	var request: LlmRequest = _model.requests_for(LlmRequest.Purpose.SUMMARISE)[-1]
	assert_true(request.messages[0]["content"].contains("they asked who you are"), "built from the record")
	assert_false(request.messages[0]["content"].contains("npc_"), "no ids")


func test_ending_the_conversation_that_folds_asks_for_a_rewrite() -> void:
	for i in MemoryBook.MAX_EPISODES:
		await _conversation(["Who are you?"])
	_talk_to_ida()
	assert_ok(await Game.say_to_npc("Who are you?"))
	_model.available = true
	_model.replies.append(ScriptedDialogueModel.say("They keep asking who you are."))
	assert_ok(Game.end_conversation())
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(_model.requests_for(LlmRequest.Purpose.SUMMARISE).size(), 1, "the game asked, and did not wait")
	assert_eq(Game.memories.summary("npc_ida"), "They keep asking who you are.")


func test_a_failed_rewrite_leaves_the_rule_summary() -> void:
	for i in MemoryBook.MAX_EPISODES + 1:
		await _conversation(["Who are you?"])
	var before := Game.memories.summary("npc_ida")
	_model.available = true
	var folded: Array[String] = []
	assert_err(await Game.dialogue.summarise("npc_ida", folded, Game.memories.folds("npc_ida")), "network")
	assert_eq(Game.memories.summary("npc_ida"), before)


func test_memories_are_saved() -> void:
	await _conversation(["Watch your back."])
	var before: Array = Game.dialogue.prompt_context("npc_ida")["memories"]
	assert_ok(Game.save_game("test_memory"))
	assert_ok(Game.load_game("test_memory"))
	Game.pause_time(true)
	assert_eq(Game.memories.episodes("npc_ida").size(), 1)
	assert_eq(Game.dialogue.prompt_context("npc_ida")["memories"], before, "the same memory after loading")


func test_a_version_1_save_gains_an_empty_book() -> void:
	var migrated := SaveMigrations.migrate({"schema_version": 1, "player": {"display_name": "Aino"}})
	assert_ok(migrated)
	assert_eq(migrated.value["schema_version"], SaveMigrations.CURRENT_VERSION)
	assert_eq(migrated.value["memories"], {"books": {}})
	var book := MemoryBook.new()
	book.from_dict(migrated.value["memories"])
	assert_eq(book.knower_count(), 0)
