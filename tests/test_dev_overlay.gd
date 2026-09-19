extends TestCase
## The developer overlay (D-038): hidden until asked for, and when shown it
## tells the truth about calls, readings, rules, memories and refusals.

var _overlay: DevOverlay


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	var model := ScriptedDialogueModel.new()
	model.available = false
	Game.dialogue.model = model
	_overlay = DevOverlay.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_overlay)


func after_each() -> void:
	if Game.dialogue.is_talking():
		Game.end_conversation()
	_overlay.free()


func _talk_to_ida() -> void:
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))
	assert_ok(Game.start_conversation("npc_ida"))


func test_it_is_hidden_until_asked_for() -> void:
	assert_false(_overlay.visible)
	_overlay.toggle()
	assert_eq(_overlay.visible, DevOverlay.allowed(), "shown only where developers are")
	_overlay.toggle()
	assert_false(_overlay.visible)


func test_it_shows_how_a_refused_gift_was_handled() -> void:
	Game.player.wallet.cash = 5
	_talk_to_ida()
	await Game.say_to_npc("Here's 50 euros.")
	_overlay.refresh()
	var text := _overlay.shown_text()
	assert_true(text.contains("\"Here's 50 euros.\""), text)
	assert_true(text.contains("meant give_money by offline (offline)"), text)
	assert_true(text.contains("rules REFUSED not_enough_cash"), text)
	assert_true(text.contains("reply authored (offline)"), text)
	assert_true(text.contains("REJECTED\n  not_enough_cash (say/give_money)"), text)
	assert_true(text.contains("MEMORY of npc_ida"), "the memories selected for the person being talked to")


func test_it_lists_model_calls_by_purpose() -> void:
	Events.llm_request_started.emit("r1", "intent")
	Events.llm_request_finished.emit("r1", true, {
		"model": "claude-haiku-4-5", "latency_ms": 312, "prompt_tokens": 180, "completion_tokens": 20, "cached": false,
	})
	Events.llm_request_finished.emit("r2", false, {"model": "claude-opus-5", "error": "timeout"})
	_overlay.refresh()
	var text := _overlay.shown_text()
	assert_true(text.contains("intent    claude-haiku-4-5     312 ms   180/20   ok"), text)
	assert_true(text.contains("ERROR timeout"), text)


func test_an_empty_snapshot_still_renders() -> void:
	var text := DevOverlay.render({})
	assert_true(text.begins_with("LLM  none"), text)
	assert_false(text.contains("TURNS"))
