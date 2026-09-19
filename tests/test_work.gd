extends TestCase
## Jobs, shifts and wages (D-042): who may start a shift and when, what it
## pays, how reliability is kept, getting hired and quitting in conversation,
## and the job surviving a save.

var _rejected: Array[String] = []
var _lost: Array[String] = []


func before_each() -> void:
	_rejected = []
	_lost = []
	Events.action_rejected.connect(_on_rejected)
	Events.job_lost.connect(_on_lost)


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)
	Events.job_lost.disconnect(_on_lost)
	if Game.dialogue.is_talking():
		Game.end_conversation()
	Game.saves.delete_slot("test_work")


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


func _on_lost(job_id: String, _reason: String) -> void:
	_lost.append(job_id)


func _start(background: String) -> void:
	Game.new_game(background, 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	var model := ScriptedDialogueModel.new()
	model.available = false
	Game.dialogue.model = model


## Onto the quay: the harbour is a place on the map, not a building.
func _walk_to_the_harbour() -> void:
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_harbour"))))
	assert_eq(Game.player.location, "loc_harbour")


func _rested() -> void:
	Game.player.stats.sleep = 1.0
	Game.player.stats.hunger = 0.0
	Game.player.stats.health = 1.0


# --- the rules --------------------------------------------------------------------------

func _shift_facts(overrides: Dictionary = {}) -> Dictionary:
	var facts := {
		"job": {"id": "j", "days": "weekday", "shift_start": 360, "shift_end": 960},
		"employed_here": true, "at_workplace": true, "weekday": 2, "minute": 355, "day": 5,
		"last_worked_day": 4, "intoxication": 0.0, "sleep": 1.0,
	}
	facts.merge(overrides, true)
	return facts


func test_a_shift_starts_on_a_work_day_at_work_in_time_and_in_a_fit_state() -> void:
	var on_time := WorkRules.judge_shift(_shift_facts())
	assert_ok(on_time)
	assert_eq(on_time.value["minutes"], 605, "from now until the end")
	assert_almost(float(on_time.value["fraction"]), 1.0, 0.001)
	assert_false(on_time.value["late"])
	var late := WorkRules.judge_shift(_shift_facts({"minute": 480}))
	assert_true(late.value["late"])
	assert_almost(float(late.value["fraction"]), 0.8, 0.001)
	assert_err(WorkRules.judge_shift(_shift_facts({"employed_here": false})), "no_job")
	assert_err(WorkRules.judge_shift(_shift_facts({"at_workplace": false})), "not_at_work")
	assert_err(WorkRules.judge_shift(_shift_facts({"weekday": 0})), "not_a_work_day")
	assert_err(WorkRules.judge_shift(_shift_facts({"minute": 200})), "too_early")
	assert_err(WorkRules.judge_shift(_shift_facts({"minute": 700})), "too_late")
	assert_err(WorkRules.judge_shift(_shift_facts({"last_worked_day": 5})), "already_worked")
	assert_err(WorkRules.judge_shift(_shift_facts({"intoxication": 0.6})), "too_drunk")
	assert_err(WorkRules.judge_shift(_shift_facts({"sleep": 0.0})), "too_exhausted")


func test_days_and_pay() -> void:
	assert_true(WorkRules.works_on("weekday", 1) and not WorkRules.works_on("weekday", 6))
	assert_true(WorkRules.works_on([2, 3], 3) and not WorkRules.works_on([2, 3], 4))
	assert_eq(WorkRules.pay(100, 1.0, 1.0), 100)
	assert_eq(WorkRules.pay(100, 0.5, 1.0), 50)
	assert_eq(WorkRules.pay(100, 1.0, 0.2), 50, "a wreck still earns half")


func test_hiring_needs_what_the_job_asks() -> void:
	var data := DataRegistry.new()
	data.load_all()
	var harbour := data.get_entry("jobs", "job_dockhand")
	assert_ok(WorkRules.judge_hire(harbour, ["has_harbour_pass"], {}, 0.0))
	assert_ok(WorkRules.judge_hire(harbour, [], {"labour": 6}, 0.0), "or the skill")
	assert_err(WorkRules.judge_hire(harbour, [], {"labour": 2}, 0.0), "not_qualified")
	assert_err(WorkRules.judge_hire({"requires": {"familiarity": 0.1}}, [], {}, 0.05), "do_not_know_you")


# --- through the game -----------------------------------------------------------------------

func test_the_dockhand_starts_with_a_job_and_nobody_else_does() -> void:
	_start("bg_dockhand")
	assert_eq(Game.work.job_id, "job_dockhand")
	assert_eq(StatusText.job(), "Dockhand at The Harbour · Mon–Fri 06:00–16:30")
	_start("bg_trained")
	assert_false(Game.work.has_job())


func test_a_late_first_morning_is_paid_for_what_is_worked() -> void:
	_start("bg_dockhand")
	_rested()
	_walk_to_the_harbour()
	assert_eq(Game.interaction_at(DistrictMap.world_to_cell(Game.player.position) + Vector2i.RIGHT)["kind"], "work",
		"standing on the quay in shift hours, the button starts the shift")
	var bank_before := Game.player.wallet.bank
	var labour_before := Game.player.skills.xp_of("labour")
	var worked := Game.work_shift()
	assert_ok(worked)
	assert_true(worked.value["late"])
	assert_eq(Game.clock.format_time(), "16:30")
	assert_gt(Game.player.wallet.bank, bank_before + 80)
	assert_lt(Game.player.wallet.bank, bank_before + 110, "late: less than a full day")
	assert_gt(Game.player.skills.xp_of("labour"), labour_before)
	assert_lt(Game.player.stats.stamina, 0.9, "work is work")
	assert_err(Game.work_shift(), "not_at_work" if Game.job_here().is_empty() else "already_worked")


func test_casual_work_takes_anyone_and_pays_cash() -> void:
	_start("bg_trained")
	_rested()
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_worksite"))))
	var cash_before := Game.player.wallet.cash
	var worked := Game.work_shift()
	assert_ok(worked)
	assert_eq(worked.value["pay_to"], "cash")
	assert_gt(Game.player.wallet.cash, cash_before)
	assert_false(Game.work.has_job(), "a day's work is not a job")


func test_missed_shifts_cost_the_job() -> void:
	_start("bg_dockhand")
	Game.advance_time(GameClock.MINUTES_PER_DAY * 5)
	assert_eq(_lost, ["job_dockhand"], "four weekdays missed after the first morning")
	assert_false(Game.work.has_job())


func test_asking_for_work_is_a_proposal_the_rules_judge() -> void:
	_start("")
	var leena := Game.npcs.get_npc("npc_leena")
	leena.location = "loc_cafe_kaisla"
	leena.activity = "work"
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_cafe_kaisla"))))
	assert_ok(Game.interact_at(map.buildings["loc_cafe_kaisla"]["door"]))
	assert_ok(Game.start_conversation("npc_leena"))
	var first: Dictionary = (await Game.say_to_npc("Are you hiring?")).value
	assert_eq(first["topic"], "do_not_know_you")
	assert_eq(_rejected, ["do_not_know_you"])
	assert_false(Game.work.has_job())
	Game.relationships.adjust("npc_leena", PlayerState.ID, "familiarity", 0.3)
	var second: Dictionary = (await Game.say_to_npc("Any work going?")).value
	assert_eq(second["topic"], "hired")
	assert_eq(Game.work.job_id, "job_kaisla")
	var third: Dictionary = (await Game.say_to_npc("I quit.")).value
	assert_eq(third["topic"], "quit")
	assert_false(Game.work.has_job())


func test_someone_without_work_to_give_says_so() -> void:
	_start("")
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))
	assert_ok(Game.start_conversation("npc_ida"))
	var said: Dictionary = (await Game.say_to_npc("Are you hiring?")).value
	assert_eq(said["topic"], "not_hiring")
	assert_eq(_rejected, ["not_hiring"])


func test_the_job_is_saved() -> void:
	_start("bg_dockhand")
	_rested()
	_walk_to_the_harbour()
	assert_ok(Game.work_shift())
	var standing := Game.work.standing
	assert_ok(Game.save_game("test_work"))
	assert_ok(Game.load_game("test_work"))
	Game.pause_time(true)
	assert_eq(Game.work.job_id, "job_dockhand")
	assert_almost(Game.work.standing, standing, 0.0001)
	assert_eq(Game.work.shifts_worked, 1)


func test_a_version_3_dockhand_keeps_the_job() -> void:
	var migrated := SaveMigrations.migrate({"schema_version": 3, "player": {"job_id": "occ_dockhand", "display_name": "A"}})
	assert_ok(migrated)
	assert_eq(migrated.value["work"]["job"], "job_dockhand")
	assert_false(migrated.value["player"].has("job_id"), "the job lives in one place now")
