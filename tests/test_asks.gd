extends TestCase
## Talking someone round (D-053): asks that can go well, half well, badly or
## worse, and that change what the world's own rules then do — a debt's time,
## an officer's leniency.

var _grades: Array[String] = []
var _model: ScriptedDialogueModel


func before_each() -> void:
	_grades = []
	Events.ask_resolved.connect(_on_resolved)


func after_each() -> void:
	Events.ask_resolved.disconnect(_on_resolved)
	if Game.dialogue.is_talking():
		Game.end_conversation()
	Game.saves.delete_slot("test_asks")
	Localization.set_locale("en")


func _on_resolved(_ask_id: String, grade: String) -> void:
	_grades.append(grade)


func _start(background: String = "bg_in_debt") -> void:
	Game.new_game(background, 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_model = ScriptedDialogueModel.new()
	_model.available = false
	Game.dialogue.model = _model
	_grades = []


func _meet_outside(npc_id: String) -> void:
	var npc := Game.npcs.get_npc(npc_id)
	npc.location = "loc_dock_street"
	npc.activity = "walk"
	assert_ok(Game.start_conversation(npc_id))


func _say(text: String) -> Dictionary:
	var said: Result = await Game.say_to_npc(text)
	assert_ok(said, text)
	return said.value if said.is_ok() else {}


func _chance(npc_id: String, skill: String, difficulty: int) -> float:
	return AskRules.chance(Game.player.skills.level_of(skill), difficulty,
		Game.relationships.disposition(npc_id, PlayerState.ID), Game.player.stats.effectiveness())


## The next ask's dice fall in this grade's window.
func _rig(grade: String, odds: float) -> void:
	var window: Array = {
		"success": [0.0, odds * AskRules.SUCCESS_SHARE], "partial": [odds * AskRules.SUCCESS_SHARE, odds],
		"failure": [odds, odds + (1.0 - odds) * AskRules.FAILURE_SHARE], "backfire": [odds + (1.0 - odds) * AskRules.FAILURE_SHARE, 1.0],
	}[grade]
	var stream := Game.rng.stream("ask")
	for seed_value in range(1, 60000):
		stream.seed = seed_value
		var roll := stream.randf()
		if roll >= float(window[0]) and roll < float(window[1]):
			stream.seed = seed_value
			return
	assert_true(false, "no seed lands in %s" % grade)


func _deadline() -> int:
	return int(Game.quests.active["q_rauno_debt"]["deadline_day"])


# --- the rules ---------------------------------------------------------------------------------

func test_the_chance_is_skill_against_difficulty_and_never_certain() -> void:
	assert_gt(AskRules.chance(60, 25, 0.0), AskRules.chance(10, 25, 0.0), "skill helps")
	assert_gt(AskRules.chance(20, 25, 0.5), AskRules.chance(20, 25, -0.5), "a friend is easier")
	assert_lt(AskRules.chance(40, 25, 0.0, 0.5), AskRules.chance(40, 25, 0.0, 1.0), "a tired or drunk person argues worse")
	assert_eq(AskRules.chance(99, 1, 1.0), 0.95, "never certain")
	assert_eq(AskRules.chance(1, 99, -1.0), 0.05, "never hopeless")


func test_a_roll_comes_to_one_of_four_grades() -> void:
	assert_eq(AskRules.grade(0.6, 0.0), "success")
	assert_eq(AskRules.grade(0.6, 0.29), "success")
	assert_eq(AskRules.grade(0.6, 0.31), "partial")
	assert_eq(AskRules.grade(0.6, 0.59), "partial")
	assert_eq(AskRules.grade(0.6, 0.61), "failure")
	assert_eq(AskRules.grade(0.6, 0.85), "failure")
	assert_eq(AskRules.grade(0.6, 0.95), "backfire")
	assert_eq(AskRules.grade(0.05, 0.99), "backfire", "and a long shot mostly ends badly")
	for grade: String in AskRules.GRADES:
		assert_gt(AskRules.xp(grade), 0.0, "every try teaches something")
	assert_gt(AskRules.xp("success"), AskRules.xp("backfire"))


func test_asks_can_be_refused() -> void:
	assert_eq(AskRules.judge({"has_ask": false}).code, "nothing_to_ask")
	assert_eq(AskRules.judge({"has_ask": true, "on_cooldown": true}).code, "already_asked")
	assert_eq(AskRules.judge({"has_ask": true, "chance": 0.5, "roll": 0.1}).value["grade"], "success")


func test_the_authored_asks_are_consistent() -> void:
	_start()
	assert_eq(Game.data.validate_references(), [] as Array[String])
	assert_false(Game.data.table("asks").is_empty())


func test_a_broken_ask_is_reported_not_swallowed() -> void:
	var data := DataRegistry.new()
	data.load_all()
	data.tables["asks"]["ask_broken"] = {"id": "ask_broken", "npc": "npc_nobody", "skill": "not_a_skill",
		"requires": {"quest": "q_nothing"}, "grades": {"success": [{"do": "teleport"}], "partial": [], "failure": []}}
	var problems := data.validate_references()
	var text := "\n".join(problems)
	assert_true(text.contains("unknown person 'npc_nobody'"), text)
	assert_true(text.contains("unknown skill"), text)
	assert_true(text.contains("unknown quest 'q_nothing'"), text)
	assert_true(text.contains("does not say what 'backfire' does"), text)
	assert_true(text.contains("unknown effect 'teleport'"), text)


# --- Rauno and the debt ------------------------------------------------------------------------------

func test_a_good_argument_buys_a_week() -> void:
	_start()
	_meet_outside("npc_rauno")
	var before := _deadline()
	_rig("success", _chance("npc_rauno", "persuasion", 25))
	var reply := await _say("Could I have some more time to pay?")
	assert_eq(reply["topic"], "ask_success")
	assert_eq(_deadline(), before + 7)
	assert_eq(_grades, ["success"] as Array[String])
	assert_eq(Game.quests.active["q_rauno_debt"]["extra_need"], 0, "and no strings")


func test_half_a_win_costs_you() -> void:
	_start()
	_meet_outside("npc_rauno")
	var before := _deadline()
	_rig("partial", _chance("npc_rauno", "persuasion", 25))
	var reply := await _say("Give me some time to pay, please.")
	assert_eq(reply["topic"], "ask_partial")
	assert_eq(_deadline(), before + 3, "three days, not seven")
	assert_eq(Game.quests.active["q_rauno_debt"]["extra_need"], 30, "and the debt has grown")
	assert_eq(QuestText.entries()[0]["goal"], "Pay Rauno back the €300 you owe him. (0 of 330) He wants €30 more.")
	# It has to be paid in full, including the cost of the extra time.
	Game.player.wallet.cash = 400
	await _say("Here's 300 euros.")
	assert_true(Game.quests.active.has("q_rauno_debt"), "three hundred is no longer enough")
	await _say("Here's 30 euros.")
	assert_eq(Game.quests.finished.get("q_rauno_debt"), "done")


func test_a_no_costs_a_little_goodwill() -> void:
	_start()
	_meet_outside("npc_rauno")
	var before := _deadline()
	var trust := Game.relationships.get_edge("npc_rauno", PlayerState.ID).trust
	_rig("failure", _chance("npc_rauno", "persuasion", 25))
	var reply := await _say("Can I pay later?")
	assert_eq(reply["topic"], "ask_failure")
	assert_eq(_deadline(), before, "no more time")
	assert_lt(Game.relationships.get_edge("npc_rauno", PlayerState.ID).trust, trust)


func test_pushing_too_hard_makes_it_worse() -> void:
	_start()
	_meet_outside("npc_rauno")
	var before := _deadline()
	var affection := Game.relationships.get_edge("npc_rauno", PlayerState.ID).affection
	_rig("backfire", _chance("npc_rauno", "persuasion", 25))
	var reply := await _say("Give me a break, I need more time.")
	assert_eq(reply["topic"], "ask_backfire")
	assert_eq(_deadline(), before - 2, "he has lost patience")
	assert_lt(Game.relationships.get_edge("npc_rauno", PlayerState.ID).affection, affection)
	assert_eq(_grades, ["backfire"] as Array[String])


func test_you_cannot_ask_twice_in_a_breath_and_then_you_can() -> void:
	_start()
	_meet_outside("npc_rauno")
	_rig("failure", _chance("npc_rauno", "persuasion", 25))
	await _say("Can I have more time?")
	var stream_state := Game.rng.stream("ask").state
	var deadline := _deadline()
	var again := await _say("Please, more time?")
	assert_eq(again["topic"], "ask_again")
	assert_eq(Game.rng.stream("ask").state, stream_state, "no dice were thrown")
	assert_eq(_deadline(), deadline)
	Game.end_conversation()
	Game.clock.total_minutes += 4 * GameClock.MINUTES_PER_DAY
	_meet_outside("npc_rauno")
	_rig("success", _chance("npc_rauno", "persuasion", 25))
	var later := await _say("Could I have more time to pay?")
	assert_eq(later["topic"], "ask_success", "four days on he will hear you out")


func test_there_has_to_be_something_to_bargain_over() -> void:
	_start()
	_meet_outside("npc_ida")
	var stream_state := Game.rng.stream("ask").state
	var reply := await _say("Could I have some more time?")
	assert_eq(reply["topic"], "no_ask")
	assert_eq(Game.rng.stream("ask").state, stream_state)
	assert_eq(_grades, [] as Array[String])
	Game.end_conversation()
	_start("bg_dockhand")   # Veikko has no authored ask at all, debt or not
	_meet_outside("npc_veikko")
	assert_eq((await _say("More time, please."))["topic"], "no_ask")


func test_a_model_may_call_it_persuading_or_asking_a_favour() -> void:
	_start()
	_meet_outside("npc_rauno")
	_model.available = true
	_model.intents.append(ScriptedDialogueModel.meaning("persuade"))
	_rig("success", _chance("npc_rauno", "persuasion", 25))
	var before := _deadline()
	var reply := await _say("Look, we both know I'm good for it, so how about we say the end of the month?")
	assert_eq(reply["intent"]["kind"], "persuade")
	assert_eq(_deadline(), before + 7)
	assert_eq(_grades, ["success"] as Array[String])


func test_persuasion_is_practised_and_more_by_winning() -> void:
	_start()
	_meet_outside("npc_rauno")
	var xp := Game.player.skills.xp_of("persuasion")
	_rig("success", _chance("npc_rauno", "persuasion", 25))
	await _say("Can I have some more time to pay?")
	var won := Game.player.skills.xp_of("persuasion") - xp
	assert_gt(won, 0.0)
	Game.end_conversation()
	Game.clock.total_minutes += 4 * GameClock.MINUTES_PER_DAY
	_meet_outside("npc_rauno")
	var mark := Game.player.skills.xp_of("persuasion")
	_rig("backfire", _chance("npc_rauno", "persuasion", 25))
	await _say("Please, some more time to pay?")
	assert_lt(Game.player.skills.xp_of("persuasion") - mark, won)


func test_it_works_by_text_as_well() -> void:
	_start()
	Game.phone_director.add_contact("npc_rauno")
	var rauno := Game.npcs.get_npc("npc_rauno")
	rauno.activity = "idle"
	Game.clock.total_minutes = Game.clock.day_index() * GameClock.MINUTES_PER_DAY + 12 * 60
	var before := _deadline()
	_rig("success", _chance("npc_rauno", "persuasion", 25))
	assert_ok(Game.send_text("npc_rauno", "Could I have some more time to pay?"))
	Game.clock.total_minutes += 60
	await Game.phone_director.process_due()
	assert_eq(_deadline(), before + 7)


# --- vouching (M8 step 11, D-087) -----------------------------------------------------------------------

## Rauno has nothing to extend once there is no debt (bg_dockhand), so
## `ask_vouch_rauno` is what `offer()` finds instead — the natural way to
## reach it without waiting out `ask_rauno_time`'s cooldown.

func test_vouching_for_yourself_writes_knowledge_not_a_flag() -> void:
	_start("bg_dockhand")
	_meet_outside("npc_rauno")
	_rig("success", _chance("npc_rauno", "persuasion", 40))
	var reply := await _say("Give me a break, would you?")
	assert_eq(reply["topic"], "ask_success")
	var known := Game.knowledge.what_is_known_about("npc_rauno", PlayerState.ID)
	assert_eq(known[0]["predicate"], "vouched_for")
	assert_true(known[0]["firsthand"])


func test_only_a_full_win_vouches() -> void:
	_start("bg_dockhand")
	_meet_outside("npc_rauno")
	_rig("partial", _chance("npc_rauno", "persuasion", 40))
	await _say("Give me a break, would you?")
	assert_eq(Game.knowledge.what_is_known_about("npc_rauno", PlayerState.ID), [] as Array[Dictionary])


func test_being_vouched_for_opens_the_shop_to_a_stranger() -> void:
	_start("bg_dockhand")
	_meet_outside("npc_rauno")
	_rig("success", _chance("npc_rauno", "persuasion", 40))
	await _say("Give me a break, would you?")
	Game.end_conversation()
	var floor_needed := DealRules.familiarity_floor(0.75, 0.1)   # Rauno's own greed and lawfulness
	assert_lt(Game.relationships.peek("npc_rauno", PlayerState.ID).familiarity, floor_needed,
		"too little to pass the ordinary floor on its own")
	var rejected: Array[String] = []
	var handler := func(_proposal: Dictionary, code: String) -> void: rejected.append(code)
	Events.action_rejected.connect(handler)
	_meet_outside("npc_rauno")
	var said := await _say("Got anything?")
	Events.action_rejected.disconnect(handler)
	assert_true(rejected.is_empty(), str(rejected))
	assert_eq(said["topic"], "deal_offered")


func test_an_ask_requiring_dealing_must_be_put_to_a_dealer() -> void:
	var data := DataRegistry.new()
	data.load_all()
	data.tables["asks"]["ask_broken_vouch"] = {"id": "ask_broken_vouch", "npc": "npc_ida", "skill": "persuasion",
		"requires": {"deals": true}, "grades": {"success": [], "partial": [], "failure": [], "backfire": []}}
	var text := "\n".join(data.validate_references())
	assert_true(text.contains("requires dealing but 'npc_ida' deals from nothing"), text)


# --- Marika and the case -------------------------------------------------------------------------------

## Marika saw a middling theft and has sent for the player: left to herself, a fine.
func _summoned() -> void:
	var facts: Array[String] = ["npc_marika"]
	Game.knowledge.observe_event(PlayerState.ID, "stole_from", Game.clock.total_minutes, facts, {
		"object": "npc_ida", "location": "loc_corner_shop", "severity": 0.35, "visibility": "social"})
	for event in Game.events_queue.pending():
		if event.kind == "police_assess":
			Game.pause_time(false)
			Game.advance_time(maxi(event.at - Game.clock.total_minutes, 1))
			Game.pause_time(true)
			break
	assert_eq(Game.crime.summons.size(), 1)


func _at_the_desk() -> Result:
	var marika := Game.npcs.get_npc("npc_marika")
	marika.location = "loc_police_post"
	marika.activity = "work"
	Game.player.interior = ""
	var map := Game.world.map_for(Game.player.region)
	Game.player.position = DistrictMap.cell_to_world(map.anchor_of("loc_police_post"))
	assert_ok(Game.interact_at(map.buildings["loc_police_post"]["door"]))
	var inside := Game.current_map()
	for cell: Vector2i in inside.objects:
		if inside.objects[cell]["kind"] == "counter":
			for step: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
				if not inside.is_blocked(cell + step):
					assert_ok(Game.move_player(DistrictMap.cell_to_world(cell + step)))
					return Game.interact_at(cell)
	return Result.failure("no_desk")


func _plead_and_attend(grade: String) -> String:
	_summoned()
	_meet_outside("npc_marika")
	_rig(grade, _chance("npc_marika", "persuasion", 45))
	await _say("Please, go easy on me.")
	Game.end_conversation()
	var came := _at_the_desk()
	assert_ok(came)
	return str(came.value["outcome"])


func test_without_a_summons_there_is_nothing_to_plead() -> void:
	_start("bg_returning")
	_meet_outside("npc_marika")
	assert_eq((await _say("Please, go easy on me."))["topic"], "no_ask")


func test_talking_the_officer_round_can_turn_a_fine_into_nothing() -> void:
	_start("bg_returning")
	assert_eq(await _plead_and_attend("success"), "none")
	assert_eq(Game.crime.leniency, {}, "what was said is spent once she has decided")


func test_a_half_win_is_a_warning_and_a_backfire_is_worse_than_asking_nothing() -> void:
	_start("bg_returning")
	assert_eq(await _plead_and_attend("partial"), "warning")
	_start("bg_returning")
	assert_eq(await _plead_and_attend("failure"), "fine", "unchanged")
	_start("bg_returning")
	assert_eq(await _plead_and_attend("backfire"), "arrest", "she resents being played")


# --- kept ---------------------------------------------------------------------------------------------------

func test_what_was_asked_and_what_it_cost_are_saved() -> void:
	_start()
	_meet_outside("npc_rauno")
	_rig("partial", _chance("npc_rauno", "persuasion", 25))
	await _say("Could I have some more time to pay?")
	Game.end_conversation()
	Game.crime.leniency["npc_marika"] = -0.15
	assert_ok(Game.save_game("test_asks"))
	assert_ok(Game.load_game("test_asks"))
	Game.pause_time(true)
	assert_true(Game.asks.asked.has("ask_rauno_time"))
	assert_true(Game.asks.on_cooldown("ask_rauno_time"), "still too soon to ask again")
	assert_eq(Game.quests.active["q_rauno_debt"]["extra_need"], 30)
	assert_almost(float(Game.crime.leniency["npc_marika"]), -0.15)


func test_a_version_8_save_has_asked_nobody_anything() -> void:
	var migrated := SaveMigrations.migrate({"schema_version": 8, "crime": {}})
	assert_ok(migrated)
	assert_eq(migrated.value["schema_version"], SaveMigrations.CURRENT_VERSION)
	assert_eq(migrated.value["asks"]["asked"], {})
	var log := QuestLog.new()
	log.from_dict({"active": {}})
	assert_eq(log.active.size(), 0)
