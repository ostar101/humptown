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


## One holder per blow (D-090): the one who took it. It used to be them and
## every friend who knew, each with their own warnings and meetings.
func test_the_one_you_beat_holds_it_and_their_friends_leave_it_to_them() -> void:
	_start()
	Game.relationships.get_edge("npc_leena", "npc_elias").affection = 0.7
	_beaten("npc_elias", ["npc_elias", "npc_leena"] as Array[String])
	for day in [0, 1, 2]:
		_daily(day)
	assert_eq(Game.consequences.grudges.keys(), ["npc_elias"], "the victim, and only the victim")


## A friend takes it up only when the one it was done to will not: here the
## victim is the law, who has procedures rather than grudges.
func test_a_friend_takes_it_up_when_the_victim_cannot() -> void:
	_start()
	Game.relationships.get_edge("npc_leena", "npc_marika").affection = 0.7
	_beaten("npc_marika", ["npc_marika", "npc_leena"] as Array[String])
	_daily(0)
	assert_eq(Game.consequences.grudges.keys(), ["npc_leena"])
	Game.npcs.get_npc("npc_leena").activity = "idle"
	_deliver()
	assert_eq(_texts("npc_leena").size(), 1)
	assert_true(_texts("npc_leena")[0].begins_with("You hurt Marika"), _texts("npc_leena")[0])


func test_someone_you_have_made_up_with_holds_no_grudge() -> void:
	_start()
	_beaten("npc_elias", ["npc_elias"] as Array[String])
	_daily(0)
	assert_eq(Game.consequences.grudges["npc_elias"]["warnings"], 1, "warned, while it still hurt")
	Game.relationships.get_edge("npc_elias", PlayerState.ID).affection = FightDirector.JOIN_AFFECTION
	for day in range(2, 30):
		_daily(day)
	assert_eq(Game.consequences.grudges["npc_elias"]["confrontations"], 0, "a friend by now names no time and place")
	assert_eq(Game.consequences.grudges["npc_elias"]["warnings"], 1, "and starts nothing again")


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


## Played: the one you beat kept coming back, "as if they did not remember the
## fight" (D-090). Once there has been a fight between you, win or lose, that
## blow is settled for good.
func test_if_you_go_they_start_it_and_once_it_is_fought_it_is_over() -> void:
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
	Events.player_deed.emit("fought", {"npc": "npc_elias", "result": "won"})
	assert_false(Game.consequences.grudges.has("npc_elias"), "he has had his fight")
	var meetings := Game.calendar.meetings.size()
	for day in range(4, 60, 2):
		_daily(day)
	assert_false(Game.consequences.grudges.has("npc_elias"), "and does not start it again")
	assert_eq(Game.calendar.meetings.size(), meetings, "no more times and places")


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


## Played: "I haven't forgotten" came back every twelve days, for ever, from
## the same old blow (D-090). One warning, two times and places, and a grudge
## nobody answered is let go for good.
func test_a_grudge_that_is_never_answered_is_let_go_for_good() -> void:
	_start()
	_beaten("npc_elias", ["npc_elias"] as Array[String])
	var did: Array[String] = []
	for day in [0, 2, 4, 6]:
		var before := Game.calendar.meetings.size()
		var warned := int((Game.consequences.grudges.get("npc_elias", {"warnings": 0}) as Dictionary)["warnings"])
		_daily(day)
		var after: Dictionary = Game.consequences.grudges.get("npc_elias", {})
		did.append("over" if after.is_empty() else ("warn" if int(after["warnings"]) > warned
			else ("meet" if Game.calendar.meetings.size() > before else "wait")))
	assert_eq(did, ["warn", "meet", "meet", "over"] as Array[String])
	for day in range(8, 90, 2):
		_daily(day)
	assert_false(Game.consequences.grudges.has("npc_elias"), "not after twelve days, nor ever")
	assert_eq(Game.calendar.meetings.size(), 2)
	Game.npcs.get_npc("npc_elias").activity = "idle"
	for day in range(0, 90):
		_noon(day)
		_deliver()
	var warnings := _texts("npc_elias").filter(func(t: String) -> bool: return t.contains("haven't forgotten"))
	assert_eq(warnings.size(), 1, "he said it once")


## A new blow is a new grievance, and may start one.
func test_hitting_them_again_is_a_new_grudge() -> void:
	_start()
	_beaten("npc_elias", ["npc_elias"] as Array[String])
	_daily(0)
	Events.player_deed.emit("fought", {"npc": "npc_elias", "result": "won"})
	assert_false(Game.consequences.grudges.has("npc_elias"))
	_noon(3)
	_beaten("npc_elias", ["npc_elias"] as Array[String])
	_daily(3)
	assert_eq(Game.consequences.grudges["npc_elias"]["warnings"], 1, "that one is new")


# --- a debt that was let go ---------------------------------------------------------------------------

## The debt quest lets fail with €100 paid and €50 of interest added: €250 owed.
func _debt_gone_bad() -> void:
	_start("bg_in_debt")
	Game.quests.on_deed("gave_money", {"npc": "npc_rauno", "amount": 100}, Game._feeling)
	Game.quests.raise_requirement("q_rauno_debt", 50)
	Game.quests.active["q_rauno_debt"]["deadline_day"] = _day0
	assert_eq(Game.quests.expire(_day0 + 1), ["q_rauno_debt"] as Array[String])
	for npc_id: String in ["npc_rauno", "npc_joonas"]:
		Game.npcs.get_npc(npc_id).activity = "idle"


## Played: the debt was three texts and a meeting, then it rested and began
## again, and could never be paid (D-090). Now: come and talk, a threat, a last
## warning naming who will come — and then they come looking.
func test_a_debt_gone_bad_calls_you_in_threatens_and_warns() -> void:
	_debt_gone_bad()
	_daily(0)
	assert_eq(Game.consequences.owed_to("npc_rauno"), 250, "less what was paid, plus the interest")
	assert_eq(Game.calendar.meetings.size(), 1)
	var meeting: Dictionary = Game.calendar.meetings[0]
	assert_eq(meeting["npc"], "npc_rauno")
	assert_false(meeting["hostile"], "to talk, not to fight")
	assert_eq(meeting["purpose"], "collection")
	assert_eq(meeting["status"], "accepted", "you are told, not asked")
	assert_eq(int(meeting["start"]) % GameClock.MINUTES_PER_DAY, MeetingDirector.TALK_HOUR * 60)
	_deliver()
	for day in [1, 2, 3]:
		_daily(day)
		_deliver()
	for day in [4, 5, 6]:
		_daily(day)
		_deliver()
	var texts := _texts("npc_rauno")
	assert_eq(texts.size(), 3, str(texts))
	assert_true(texts[0].begins_with("€250, and your time's up.") and texts[0].contains("Come and talk to me."), texts[0])
	assert_true(texts[1].contains("hurt"), texts[1])
	assert_true(texts[2].contains("comes looking for you"), texts[2])
	assert_eq(int(Game.consequences.grudges["npc_rauno"]["step"]), 3, "three days between each")
	_daily(9)
	assert_eq(int(Game.consequences.grudges["npc_rauno"]["step"]), ConsequenceRules.HUNT_STEP, "and now someone is looking")
	assert_eq(Game.consequences.grudges["npc_rauno"]["enforcer"], "npc_joonas", "someone stronger")
	for day in range(10, 20):
		_daily(day)
		_deliver()
	assert_eq(_texts("npc_rauno").size(), 3, "nothing more is said")


func test_the_one_you_owe_brings_it_up_first() -> void:
	_debt_gone_bad()
	_daily(0)
	var rauno := Game.npcs.get_npc("npc_rauno")
	rauno.location = "loc_dock_street"
	Game.npcs.invalidate_location_cache("npc_rauno")
	Game.player.interior = ""
	Game.player.location = "loc_dock_street"
	var started := Game.start_conversation("npc_rauno")
	assert_ok(started)
	assert_true(str(started.value["text"]).contains("250"), started.value["text"])
	var prompt := DialoguePrompt.system_text(Game.dialogue.prompt_context("npc_rauno"))
	assert_true(prompt.contains("owes you €250"), "and the model is told")
	Game.end_conversation()


## A debt gone as far as a hunt, on day nine, with every demand read.
func _hunting() -> void:
	_debt_gone_bad()
	for day in range(0, 10):
		_daily(day)
		_deliver()
	assert_eq(int(Game.consequences.grudges["npc_rauno"]["step"]), ConsequenceRules.HUNT_STEP)
	_noon(9)
	Game.player.interior = ""
	Game.player.location = "loc_dock_street"


func test_a_collector_comes_looking_when_you_are_out() -> void:
	_hunting()
	var queued := Game.events_queue.size()
	Game._collector_looks()
	assert_eq(Game.events_queue.size(), queued + 1, "on his way")
	Game._collector_looks()
	assert_eq(Game.events_queue.size(), queued + 1, "once")
	Game._collector_arrives("npc_joonas")
	assert_eq(_ambushes, ["npc_joonas"] as Array[String], "he found you, and he starts it")
	assert_eq(Game.npcs.get_npc("npc_joonas").location, "loc_dock_street")


func test_a_collector_does_not_find_you_at_home_or_at_night() -> void:
	_hunting()
	Game.player.interior = Game.player.home_location
	Game.player.location = Game.player.home_location
	var queued := Game.events_queue.size()
	Game._collector_looks()
	assert_eq(Game.events_queue.size(), queued, "not at home")
	Game.player.interior = ""
	Game.player.location = "loc_dock_street"
	Game.clock.total_minutes = (_day0 + 9) * GameClock.MINUTES_PER_DAY + 23 * 60
	Game._collector_looks()
	assert_eq(Game.events_queue.size(), queued, "nor in the small hours")
	_noon(9)
	Game._collector_looks()
	Game.player.interior = Game.player.home_location
	Game.player.location = Game.player.home_location
	Game._collector_arrives("npc_joonas")
	assert_eq(_ambushes, [] as Array[String], "gone home before he got there: missed you")
	Game.player.interior = ""
	Game.player.location = "loc_dock_street"
	Game._collector_looks()
	Game._collector_arrives("npc_joonas")
	assert_eq(_ambushes, ["npc_joonas"] as Array[String], "and he looks again")


func test_losing_to_the_collector_costs_what_you_carry() -> void:
	_hunting()
	Game.player.wallet.cash = 100
	Events.player_deed.emit("fought", {"npc": "npc_joonas", "result": "lost"})
	assert_eq(Game.player.wallet.cash, 0, "he took it")
	assert_eq(Game.consequences.owed_to("npc_rauno"), 150)
	assert_gt(int(Game.consequences.grudges["npc_rauno"]["quiet_until"]), Game.clock.day_index(), "and leaves you be a while")
	_deliver()
	assert_true(_texts("npc_rauno").back().contains("€100") and _texts("npc_rauno").back().contains("€150"),
		_texts("npc_rauno").back())


func test_seeing_the_collector_off_buys_time_not_freedom() -> void:
	_hunting()
	Events.player_deed.emit("fought", {"npc": "npc_joonas", "result": "won"})
	assert_eq(Game.consequences.owed_to("npc_rauno"), 250, "still owed")
	var state: Dictionary = Game.consequences.grudges["npc_rauno"]
	assert_eq(int(state["quiet_until"]), Game.clock.day_index() + ConsequenceRules.AFTER_BEATEN_DAYS)
	var queued := Game.events_queue.size()
	Game._collector_looks()
	assert_eq(Game.events_queue.size(), queued, "not while he licks his wounds")


func test_paying_what_is_owed_ends_it() -> void:
	_hunting()
	Events.player_deed.emit("gave_money", {"npc": "npc_rauno", "amount": 200})
	assert_eq(Game.consequences.owed_to("npc_rauno"), 50, "part of it")
	Events.player_deed.emit("gave_money", {"npc": "npc_joonas", "amount": 50})
	assert_eq(Game.consequences.owed_to("npc_rauno"), 0, "the rest, to the one he sent")
	assert_false(Game.consequences.grudges.has("npc_rauno"))
	assert_has(Game.consequences.settled_debts, "q_rauno_debt")
	for day in range(8, 30, 2):
		_daily(day)
	assert_false(Game.consequences.grudges.has("npc_rauno"), "and it stays paid")
	_deliver()
	assert_eq(_texts("npc_rauno").back(), "That's all of it. We're square.")


func test_a_paid_debt_is_not_collected() -> void:
	_start("bg_in_debt")
	Game.quests.active.erase("q_rauno_debt")
	Game.quests.finished["q_rauno_debt"] = "done"
	_daily(0)
	assert_eq(Game.consequences.grudges.size(), 0)


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
