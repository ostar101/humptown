extends TestCase
## Dynamic events (D-055): what the world does, once a day, about what people
## have come to know — a job lost, a grudge that escalates to a meeting and a
## fight, a debt that is collected — and that it never happens to what nobody knows.

var _lost: Array[String] = []
var _ambushes: Array[String] = []
var _day0 := 0


func before_each() -> void:
	_lost = []
	_ambushes = []
	Events.job_lost.connect(_on_lost)
	Events.ambush.connect(_on_ambush)


func after_each() -> void:
	Events.job_lost.disconnect(_on_lost)
	Events.ambush.disconnect(_on_ambush)
	Game.fights.roll_source = Callable()
	Game.saves.delete_slot("test_consequences")
	Localization.set_locale("en")


func _on_lost(job_id: String, reason: String) -> void:
	_lost.append("%s:%s" % [job_id, reason])


func _on_ambush(npc_id: String) -> void:
	_ambushes.append(npc_id)


func _start(background: String = "bg_returning") -> void:
	Game.new_game(background, 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	var model := ScriptedDialogueModel.new()
	model.available = false
	Game.dialogue.model = model
	_day0 = Game.clock.day_index()
	for npc_id: String in Game.npcs.living_ids():
		var npc := Game.npcs.get_npc(npc_id)
		npc.location = npc.home
		npc.activity = "idle"


## The clock at noon, this many days after the game began.
func _noon(day: int) -> void:
	Game.clock.total_minutes = (_day0 + day) * GameClock.MINUTES_PER_DAY + 12 * 60


func _daily(day: int) -> void:
	_noon(day)
	Game.consequences.run_daily()


## Lets waiting messages arrive.
func _deliver() -> void:
	Game.phone_director.run_outreach()


func _beaten(victim: String, witnesses: Array[String]) -> String:
	return Game.knowledge.observe_event(PlayerState.ID, "assaulted", Game.clock.total_minutes, witnesses, {
		"object": victim, "location": "loc_court", "severity": 0.6, "visibility": "social"})


func _texts(npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for message in Game.phone.thread(npc_id):
		out.append(PhoneText.render(message))
	return out


# --- the rules ---------------------------------------------------------------------------------

func test_an_employer_lets_go_someone_they_believe_dangerous() -> void:
	assert_true(ConsequenceRules.dismissal_due([{"severity": 0.6, "strength": 1.0}]))
	assert_true(ConsequenceRules.dismissal_due([{"severity": 0.6, "strength": 0.6}]), "a serious matter, less sure")
	assert_false(ConsequenceRules.dismissal_due([{"severity": 0.28, "strength": 1.0}]), "a sandwich is not enough")
	assert_false(ConsequenceRules.dismissal_due([{"severity": 0.9, "strength": 0.3}]), "nor is a rumour, however dreadful")
	assert_false(ConsequenceRules.dismissal_due([]))


func test_a_grudge_goes_warning_meeting_meeting_rest() -> void:
	var state := {"warnings": 0, "confrontations": 0, "last_day": 0, "quiet_until": 0}
	assert_eq(ConsequenceRules.next_step(state, 0), "warn")
	state["warnings"] = 1
	state["last_day"] = 0
	assert_eq(ConsequenceRules.next_step(state, 1), "", "not the very next day")
	assert_eq(ConsequenceRules.next_step(state, 2), "confront")
	state["confrontations"] = 2
	assert_eq(ConsequenceRules.next_step(state, 4), "rest", "they have said their piece")
	state["quiet_until"] = 16
	assert_eq(ConsequenceRules.next_step(state, 10), "", "and leave it a while")
	assert_eq(ConsequenceRules.next_step({"warnings": 0, "confrontations": 0, "last_day": 0, "quiet_until": 16}, 16), "warn", "then it may start again")


func test_a_creditor_is_more_patient() -> void:
	var state := {"warnings": 1, "confrontations": 0, "last_day": 0, "quiet_until": 0}
	assert_eq(ConsequenceRules.next_step(state, 2, 3), "warn", "a second reminder before anyone is sent")
	state["warnings"] = 3
	assert_eq(ConsequenceRules.next_step(state, 2, 3), "confront")
	assert_false(ConsequenceRules.fit_to_confront(0.3), "someone still mending")
	assert_true(ConsequenceRules.fit_to_confront(0.8))


# --- being let go -----------------------------------------------------------------------------------

func test_a_serious_offence_the_employer_knows_of_costs_the_job() -> void:
	_start("bg_dockhand")
	assert_true(Game.work.has_job())
	var witnesses: Array[String] = ["npc_veikko"]
	_beaten("npc_joonas", witnesses)
	_daily(0)
	assert_false(Game.work.has_job(), "let go")
	assert_eq(_lost, ["job_dockhand:reputation"] as Array[String])
	assert_has(Game.consequences.dismissed, "job_dockhand")
	assert_lt(Game.relationships.get_edge("npc_veikko", PlayerState.ID).respect, 0.0)
	Game.npcs.get_npc("npc_veikko").activity = "idle"
	_deliver()
	assert_eq(_texts("npc_veikko").back(), "I can't have you working for me after what I've heard. Don't come in tomorrow.")
	_daily(1)
	assert_eq(_lost.size(), 1, "once")


func test_only_what_the_employer_knows_counts() -> void:
	_start("bg_dockhand")
	var witnesses: Array[String] = ["npc_marika"]
	_beaten("npc_joonas", witnesses)
	_daily(0)
	assert_true(Game.work.has_job(), "he does not know, so nothing happens")
	assert_eq(_lost, [] as Array[String])


func test_a_petty_matter_is_forgiven_and_casual_work_has_no_one_to_mind() -> void:
	_start("bg_dockhand")
	var witnesses: Array[String] = ["npc_veikko"]
	Game.knowledge.observe_event(PlayerState.ID, "stole_from", Game.clock.total_minutes, witnesses, {
		"object": "npc_ida", "severity": 0.28, "visibility": "social"})
	_daily(0)
	assert_true(Game.work.has_job())
	Game.work.leave()
	Game.work.hire("job_worksite", 0)
	_beaten("npc_joonas", ["npc_veikko"] as Array[String])
	_daily(1)
	assert_true(Game.work.has_job(), "the worksite takes anyone for the day")


# --- a grudge -----------------------------------------------------------------------------------------

func test_the_one_you_beat_warns_you() -> void:
	_start()
	_beaten("npc_elias", ["npc_elias"] as Array[String])
	_daily(0)
	assert_eq(Game.consequences.grudges["npc_elias"]["warnings"], 1)
	Game.npcs.get_npc("npc_elias").activity = "idle"
	_deliver()
	assert_true(Game.phone.is_contact("npc_elias"), "he has your number")
	assert_eq(_texts("npc_elias"), ["You hit me. I haven't forgotten it."] as Array[String])


func test_friends_take_it_up_one_a_day() -> void:
	_start()
	Game.relationships.get_edge("npc_leena", "npc_elias").affection = 0.7
	_beaten("npc_elias", ["npc_elias", "npc_leena", "npc_marika"] as Array[String])
	Game.relationships.get_edge("npc_marika", "npc_elias").affection = 0.9
	_daily(0)
	assert_eq(Game.consequences.grudges.size(), 1, "one a day, not a barrage")
	assert_true(Game.consequences.grudges.has("npc_elias"), "the victim first")
	_daily(1)
	assert_true(Game.consequences.grudges.has("npc_leena"), "then the friend who knows")
	assert_false(Game.consequences.grudges.has("npc_marika"), "the law does not hold grudges; it has procedures")
	Game.npcs.get_npc("npc_leena").activity = "idle"
	_noon(1)
	_deliver()
	assert_eq(_texts("npc_leena"), ["You hurt Elias Lahtinen. Don't think that's the end of it."] as Array[String])


func test_an_ignored_warning_becomes_a_time_and_a_place() -> void:
	_start()
	_beaten("npc_elias", ["npc_elias"] as Array[String])
	_daily(0)
	Game.npcs.get_npc("npc_elias").activity = "idle"
	_deliver()
	_daily(1)
	assert_eq(Game.calendar.meetings.size(), 0, "not yet")
	_daily(2)
	assert_eq(Game.calendar.meetings.size(), 1)
	var meeting: Dictionary = Game.calendar.meetings[0]
	assert_true(meeting["hostile"])
	assert_eq(meeting["status"], "accepted", "you are told, not asked")
	assert_eq(meeting["npc"], "npc_elias")
	assert_eq(int(meeting["start"]), (_day0 + 3) * GameClock.MINUTES_PER_DAY + 21 * 60, "tomorrow night")
	assert_eq(Game.world.get_location(str(meeting["location"])).kind, "park")
	Game.npcs.get_npc("npc_elias").activity = "idle"
	_noon(2)
	_deliver()
	var text: String = _texts("npc_elias").back()
	assert_true(text.contains("Come alone"), text)
	assert_true(text.contains("Tomorrow at 21:00"), text)
	assert_eq(Game.calendar.upcoming(Game.clock.total_minutes).size(), 1, "it is in your calendar")
	assert_true(Game.player.knows_place(str(meeting["location"])))


func test_someone_still_mending_does_not_come() -> void:
	_start()
	_beaten("npc_elias", ["npc_elias"] as Array[String])
	Game.npcs.get_npc("npc_elias").state["health"] = 0.2
	Game.npcs.get_npc("npc_elias").state["hurt_at"] = (_day0 + 2) * GameClock.MINUTES_PER_DAY + 12 * 60
	_daily(0)
	_daily(2)
	assert_eq(Game.calendar.meetings.size(), 0, "he cannot stand up yet")
	Game.npcs.get_npc("npc_elias").state["hurt_at"] = 0
	_daily(3)
	assert_eq(Game.calendar.meetings.size(), 1, "days later he can")


func _hostile_meeting() -> Dictionary:
	_beaten("npc_elias", ["npc_elias"] as Array[String])
	_daily(0)
	_daily(2)
	return Game.calendar.meetings[0]


func test_if_you_go_they_start_it_and_that_grudge_rests() -> void:
	_start()
	var meeting := _hostile_meeting()
	var id := int(meeting["id"])
	Game.clock.total_minutes = int(meeting["start"]) - MeetingRules.GATHER_LEAD
	Game.meetings.on_event("meeting_gather", {"meeting": id})
	Game.player.location = str(meeting["location"])
	Game.clock.total_minutes = int(meeting["start"]) + MeetingRules.GRACE
	Game.meetings.on_event("meeting_check", {"meeting": id})
	assert_eq(_ambushes, ["npc_elias"] as Array[String])
	assert_eq(Game.calendar.get_meeting(id)["status"], "kept")
	var state: Dictionary = Game.consequences.grudges["npc_elias"]
	assert_eq(state["warnings"], 0, "he has had his say, win or lose")
	assert_gt(int(state["quiet_until"]), Game.clock.day_index(), "and it rests")


func test_if_you_stay_away_nothing_is_asked_of_your_manners() -> void:
	_start()
	var meeting := _hostile_meeting()
	var id := int(meeting["id"])
	var affection := Game.relationships.get_edge("npc_elias", PlayerState.ID).affection
	Game.clock.total_minutes = int(meeting["start"]) - MeetingRules.GATHER_LEAD
	Game.meetings.on_event("meeting_gather", {"meeting": id})
	Game.player.location = "loc_dock_street"
	Game.clock.total_minutes = int(meeting["start"]) + MeetingRules.GRACE
	Game.meetings.on_event("meeting_check", {"meeting": id})
	assert_eq(_ambushes, [] as Array[String])
	assert_eq(Game.calendar.get_meeting(id)["status"], "missed")
	assert_eq(Game.relationships.get_edge("npc_elias", PlayerState.ID).affection, affection, "no penalty for not walking into it")
	for waiting in Game.phone.pending:
		assert_ne(waiting["cause"]["kind"], "meeting_missed", "and no 'I waited for you' text")


func test_being_met_for_a_fight_you_were_told_of_is_not_a_crime() -> void:
	_start()
	var elias := Game.npcs.get_npc("npc_elias")
	elias.location = Game.player.location
	elias.activity = "idle"
	elias.state["health"] = 0.05
	elias.state["hurt_at"] = Game.clock.total_minutes
	var facts_before := Game.knowledge.facts.size()
	var affection := Game.relationships.get_edge("npc_elias", PlayerState.ID).affection
	assert_ok(Game.start_fight("npc_elias", "npc"))
	Game.fights.roll_source = func() -> float: return 0.1
	var done := Game.fight_act("attack")
	assert_true(done.value["over"])
	assert_eq(Game.knowledge.facts.size(), facts_before, "no assault on record: he asked for it")
	assert_gt(Game.relationships.get_edge("npc_elias", PlayerState.ID).affection, affection - 0.2, "and it costs less between you")
	assert_false(Game.memories.recall("npc_elias", Game.clock.total_minutes, func(_l: String) -> String: return "").is_empty())


func test_a_grudge_that_is_never_answered_lets_go_and_may_return() -> void:
	_start()
	_beaten("npc_elias", ["npc_elias"] as Array[String])
	var did: Array[String] = []
	for day in [0, 2, 4, 6]:
		var before := Game.calendar.meetings.size()
		var warned := int((Game.consequences.grudges.get("npc_elias", {"warnings": 0}) as Dictionary)["warnings"])
		_daily(day)
		var after: Dictionary = Game.consequences.grudges["npc_elias"]
		did.append("warn" if int(after["warnings"]) > warned else ("meet" if Game.calendar.meetings.size() > before else "rest"))
	assert_eq(did, ["warn", "meet", "meet", "rest"] as Array[String])
	_daily(10)
	assert_eq(Game.calendar.meetings.size(), 2, "and he leaves it alone for a while")
	_daily(19)
	assert_eq(Game.consequences.grudges["npc_elias"]["warnings"], 1, "until it starts again")


# --- a debt that was let go ---------------------------------------------------------------------------

func test_a_debt_gone_bad_is_collected_more_and_more_firmly() -> void:
	_start("bg_in_debt")
	Game.quests.active.erase("q_rauno_debt")
	Game.quests.finished["q_rauno_debt"] = "failed"
	for npc_id: String in ["npc_rauno", "npc_joonas"]:
		Game.npcs.get_npc(npc_id).activity = "idle"
	_daily(0)
	_daily(2)
	_daily(4)
	_noon(4)
	Game.phone.last_started.clear()
	_deliver()
	var texts := _texts("npc_rauno")
	assert_true(texts[0].begins_with("€300."), texts[0])
	assert_eq(Game.consequences.grudges["npc_rauno"]["warnings"], 3)
	assert_eq(Game.calendar.meetings.size(), 0, "three reminders first")
	_daily(6)
	assert_eq(Game.calendar.meetings.size(), 1)
	assert_eq(Game.calendar.meetings[0]["npc"], "npc_joonas", "and now he sends someone stronger")
	assert_true(Game.calendar.meetings[0]["hostile"])
	assert_eq(Game.consequences.grudges["npc_rauno"]["enforcer"], "npc_joonas")


func test_a_paid_debt_is_not_collected() -> void:
	_start("bg_in_debt")
	Game.quests.active.erase("q_rauno_debt")
	Game.quests.finished["q_rauno_debt"] = "done"
	_daily(0)
	assert_eq(Game.consequences.grudges.size(), 0)


func test_the_enforcers_ambush_settles_the_debtors_grudge() -> void:
	_start("bg_in_debt")
	Game.quests.active.erase("q_rauno_debt")
	Game.quests.finished["q_rauno_debt"] = "failed"
	for day in [0, 2, 4, 6]:
		_daily(day)
	assert_gt(int(Game.consequences.grudges["npc_rauno"]["confrontations"]), 0)
	Game.consequences.on_ambush("npc_joonas")
	assert_eq(Game.consequences.grudges["npc_rauno"]["warnings"], 0)
	assert_gt(int(Game.consequences.grudges["npc_rauno"]["quiet_until"]), 6)


# --- alive to the clock and kept -------------------------------------------------------------------------

func test_the_clock_turning_over_is_what_starts_it() -> void:
	_start()
	_beaten("npc_elias", ["npc_elias"] as Array[String])
	Game.pause_time(false)
	Game.advance_time(GameClock.MINUTES_PER_DAY + 30)
	Game.pause_time(true)
	assert_true(Game.consequences.grudges.has("npc_elias"), "midnight came and he acted")


func test_grudges_and_dismissals_are_saved() -> void:
	_start()
	_beaten("npc_elias", ["npc_elias"] as Array[String])
	_daily(0)
	Game.consequences.dismissed.append("job_dockhand")
	assert_ok(Game.save_game("test_consequences"))
	assert_ok(Game.load_game("test_consequences"))
	Game.pause_time(true)
	assert_eq(Game.consequences.grudges["npc_elias"]["warnings"], 1)
	assert_eq(Game.consequences.dismissed, ["job_dockhand"] as Array[String])
	var migrated := SaveMigrations.migrate({"schema_version": 9, "asks": {}})
	assert_ok(migrated)
	assert_eq(migrated.value["consequences"]["grudges"], {})


func test_the_calendar_shows_what_you_have_been_told() -> void:
	_start()
	_hostile_meeting()
	var window: PhoneWindow = (load("res://scenes/ui/phone_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	Game.player.inventory.add(PhoneDirector.ITEM, 1)
	assert_true(window.open())
	window.show_page(PhoneWindow.Page.CALENDAR)
	assert_true(window.row_texts()[0].ends_with("|with Elias Lahtinen"), window.row_texts()[0])
	window.close()
	window.free()


# --- the clinic ---------------------------------------------------------------------------------------

func test_the_clinic_prices_and_refuses() -> void:
	assert_eq(ClinicRules.fee(0), 0)
	assert_eq(ClinicRules.fee(2), 40)
	assert_eq(ClinicRules.fee(9), ClinicRules.MAX_FEE, "capped")
	assert_eq(ClinicRules.judge_treatment({"injuries": 0, "health": 1.0, "money": 50}).code, "nothing_to_treat")
	assert_eq(ClinicRules.judge_treatment({"injuries": 2, "health": 0.5, "money": 10}).code, "not_enough_money")
	assert_ok(ClinicRules.judge_treatment({"injuries": 0, "health": 0.5, "money": 0}), "someone just hurt, nothing to dress: free")
	assert_eq(ClinicRules.judge_treatment({"injuries": 2, "health": 0.5, "money": 100}).value["fee"], 40)


func test_the_nurse_sets_your_wounds_so_they_mend_faster() -> void:
	_start()
	_noon(0)   # the clinic is open
	var sanna := Game.npcs.get_npc("npc_sanna")
	sanna.location = "loc_clinic"
	sanna.activity = "work"
	var now := Game.clock.total_minutes
	Game.player.stats.add_injury("cracked_rib", "torso", 0.3, now + 5 * GameClock.MINUTES_PER_DAY)
	Game.player.stats.health = 0.5
	Game.player.wallet.cash = 100
	Game.player.wallet.bank = 0
	Game.player.interior = ""
	var map := Game.world.map_for(Game.player.region)
	Game.player.position = DistrictMap.cell_to_world(map.anchor_of("loc_clinic"))
	assert_ok(Game.interact_at(map.buildings["loc_clinic"]["door"]))
	var inside := Game.current_map()
	var treated: Result = Result.failure("no_desk")
	for cell: Vector2i in inside.objects:
		if inside.objects[cell]["kind"] == "counter":
			for step: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
				if not inside.is_blocked(cell + step):
					assert_ok(Game.move_player(DistrictMap.cell_to_world(cell + step)))
					treated = Game.interact_at(cell)
					break
	assert_ok(treated)
	assert_eq(treated.value["kind"], "treated")
	assert_eq(treated.value["fee"], 20)
	assert_eq(Game.player.wallet.cash, 80, "billed for one wound")
	var left: int = int(Game.player.stats.injuries[0]["heals_at"]) - Game.clock.total_minutes
	assert_lt(left, 2 * GameClock.MINUTES_PER_DAY, "five days became under two")
	assert_gt(Game.player.stats.health, 0.5)
	assert_true(InteractionText.outcome_text({"kind": "counter"}, treated).contains("sees to your injuries"))
