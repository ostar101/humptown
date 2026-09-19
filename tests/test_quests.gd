extends TestCase
## Quests and errands (D-044): story threads started by the background and
## moved by deeds Godot already judged, deadlines with consequences, errands
## people ask for when you offer to help, the log, and saving.

var _updates: Array[String] = []


func before_each() -> void:
	_updates = []
	Events.quest_updated.connect(_on_updated)


func after_each() -> void:
	Events.quest_updated.disconnect(_on_updated)
	if Game.dialogue.is_talking():
		Game.end_conversation()
	Game.saves.delete_slot("test_quests")


func _on_updated(quest_id: String, status: String) -> void:
	_updates.append("%s:%s" % [quest_id, status])


func _start(background: String) -> void:
	Game.new_game(background, 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	var model := ScriptedDialogueModel.new()
	model.available = false
	Game.dialogue.model = model


## Someone out on Dock Street, where the player can walk up and talk.
func _meet_outside(npc_id: String) -> void:
	var npc := Game.npcs.get_npc(npc_id)
	npc.location = "loc_dock_street"
	npc.activity = "walk"
	assert_eq(Game.player.interior, "", "the player starts outdoors")
	assert_ok(Game.start_conversation(npc_id))


func _say(text: String) -> Dictionary:
	var said: Result = await Game.say_to_npc(text)
	assert_ok(said, text)
	return said.value if said.is_ok() else {}


# --- the rules ----------------------------------------------------------------------------

func test_deeds_count_only_when_they_match() -> void:
	var when := {"deed": "gave_money", "match": {"npc": "npc_rauno"}, "sum": "amount", "at_least": 300}
	var progress := QuestRules.count_deed(when, {}, "gave_money", {"npc": "npc_rauno", "amount": 120})
	progress = QuestRules.count_deed(when, progress, "gave_money", {"npc": "npc_ida", "amount": 500})
	progress = QuestRules.count_deed(when, progress, "worked_shift", {"job": "x"})
	assert_eq(progress["sum"], 120)
	assert_false(QuestRules.is_met(when, progress, Callable()))
	assert_eq(QuestRules.progress_of(when, progress), {"have": 120, "need": 300})
	progress = QuestRules.count_deed(when, progress, "gave_money", {"npc": "npc_rauno", "amount": 180})
	assert_true(QuestRules.is_met(when, progress, Callable()))


func test_an_open_thread_never_ends_and_feelings_are_read_live() -> void:
	assert_false(QuestRules.is_met({"open": true}, {"count": 99}, Callable()))
	var when := {"feeling": {"npc": "npc_ida", "dimension": "affection", "at_least": 0.25}}
	assert_true(QuestRules.is_met(when, {}, func(_n: String, _d: String) -> float: return 0.3))
	assert_false(QuestRules.is_met(when, {}, func(_n: String, _d: String) -> float: return 0.1))


func test_errands_come_round_again() -> void:
	assert_true(QuestRules.errand_available(false, -1, 3, 0))
	assert_false(QuestRules.errand_available(true, -1, 3, 0), "not while it is running")
	assert_false(QuestRules.errand_available(false, 5, 3, 6))
	assert_true(QuestRules.errand_available(false, 5, 3, 8))


# --- story threads ---------------------------------------------------------------------------

func test_each_background_brings_its_thread() -> void:
	_start("bg_in_debt")
	assert_true(Game.quests.active.has("q_rauno_debt"))
	assert_eq(int(Game.quests.active["q_rauno_debt"]["deadline_day"]), Game.clock.day_index() + 14)
	assert_has(_updates, "q_rauno_debt:started")
	_start("bg_returning")
	assert_eq(Game.quests.active.keys(), ["q_old_face"])
	_start("")
	assert_true(Game.quests.active.is_empty(), "no background, no thread: live your own life")


func test_a_shift_and_a_question_move_the_warehouse_thread() -> void:
	_start("bg_dockhand")
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_harbour"))))
	Game.player.stats.sleep = 1.0
	assert_ok(Game.work_shift())
	assert_eq(int(Game.quests.active["q_warehouse_9"]["stage"]), 1)
	var veikko := Game.npcs.get_npc("npc_veikko")
	veikko.location = "loc_harbour"
	veikko.activity = "socialise"
	assert_ok(Game.start_conversation("npc_veikko"))
	await _say("What goes on in Warehouse 9?")
	assert_eq(int(Game.quests.active["q_warehouse_9"]["stage"]), 2)
	assert_true(Game.quests.active.has("q_warehouse_9"), "the thread stays open for what comes later")


func test_paying_rauno_back_in_parts() -> void:
	_start("bg_in_debt")
	Game.player.wallet.cash = 400
	_meet_outside("npc_rauno")
	await _say("Here's 100 euros.")
	await _say("Here's 150 euros.")
	assert_true(Game.quests.active.has("q_rauno_debt"), "250 of 300 is not paid")
	await _say("Here's 50 euros.")
	assert_eq(Game.quests.finished.get("q_rauno_debt"), "done")
	assert_has(_updates, "q_rauno_debt:done")
	assert_false(bool(Game.player.quest_flags.get("owes_money", true)), "the debt is off the books")
	assert_gt(Game.relationships.peek("npc_rauno", PlayerState.ID).trust, 0.0)


func test_a_missed_deadline_has_consequences() -> void:
	_start("bg_in_debt")
	Game.advance_time(GameClock.MINUTES_PER_DAY * 15)
	assert_eq(Game.quests.finished.get("q_rauno_debt"), "failed")
	assert_has(_updates, "q_rauno_debt:failed")
	assert_lt(Game.relationships.peek("npc_rauno", PlayerState.ID).affection, 0.0)
	var known := Game.knowledge.what_is_known_about("npc_rauno", PlayerState.ID)
	assert_true(known.any(func(f: Dictionary) -> bool: return f["predicate"] == "owes_money_to"),
		"and it is out in the open now")


func test_how_someone_feels_can_finish_a_stage() -> void:
	_start("bg_returning")
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))
	assert_ok(Game.start_conversation("npc_ida"))
	await _say("Hello, Ida.")
	assert_eq(int(Game.quests.active["q_old_face"]["stage"]), 1)
	Game.relationships.adjust("npc_ida", PlayerState.ID, "affection", 0.3)
	assert_eq(Game.quests.finished.get("q_old_face"), "done", "noticed the moment she warms")
	assert_true(bool(Game.player.quest_flags.get("ida_glad", false)))


# --- errands ------------------------------------------------------------------------------------

func test_offering_help_gets_an_errand_and_bringing_it_gets_paid() -> void:
	_start("")
	_meet_outside("npc_pirjo")
	var asked := await _say("Can I help you with anything?")
	assert_eq(asked["topic"], "errand_asked")
	assert_true(str(asked["text"]).contains("Sandwich"), asked["text"])
	assert_true(Game.quests.errands.has("errand_pirjo_groceries"))
	assert_has(_updates, "errand_pirjo_groceries:errand_taken")
	var again := await _say("Need any help?")
	assert_eq(again["topic"], "errand_waiting")
	Game.end_conversation()

	Game.player.inventory.add("item_sandwich", 2)
	var cash := Game.player.wallet.cash
	_meet_outside("npc_pirjo")
	assert_eq(Game.player.inventory.count_of("item_sandwich"), 0, "handed over")
	assert_eq(Game.player.wallet.cash, cash + 16)
	assert_false(Game.quests.errands.has("errand_pirjo_groceries"))
	assert_has(_updates, "errand_pirjo_groceries:errand_done")
	var later := await _say("Anything I can do?")
	assert_eq(later["topic"], "no_errand", "not again so soon")


# --- the log and the save ----------------------------------------------------------------------------

func test_the_log_states_the_goal_and_the_time_left() -> void:
	_start("bg_in_debt")
	Game.player.wallet.cash = 400
	_meet_outside("npc_rauno")
	await _say("Here's 120 euros.")
	Game.end_conversation()
	var window: QuestWindow = (load("res://scenes/ui/quest_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	window.open()
	var texts := window.entry_texts()
	assert_eq(texts[0], "Rauno's money|Rauno Virta · 14 days left|Pay Rauno back the €300 you owe him. (120 of 300)")
	window.close()
	window.free()


func test_quests_are_saved() -> void:
	_start("bg_in_debt")
	Game.player.wallet.cash = 400
	_meet_outside("npc_rauno")
	await _say("Here's 100 euros.")
	Game.end_conversation()
	assert_ok(Game.save_game("test_quests"))
	assert_ok(Game.load_game("test_quests"))
	Game.pause_time(true)
	assert_eq(int(Game.quests.active["q_rauno_debt"]["progress"]["sum"]), 100)


func test_a_version_4_save_gains_an_empty_log() -> void:
	var migrated := SaveMigrations.migrate({"schema_version": 4, "work": {"job": ""}})
	assert_ok(migrated)
	assert_eq(migrated.value["quests"]["active"], {})
