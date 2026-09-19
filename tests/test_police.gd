extends TestCase
## The police response (D-052): proportionate to what an officer believes —
## how sure, how serious, whether there is a record — and how a summons plays
## out: coming in, or not.

var _actions: Array[String] = []
var _arrested: Array[String] = []
var _issued: Array[int] = []


func before_each() -> void:
	Game.new_game("bg_returning", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_actions = []
	_arrested = []
	_issued = []
	Events.police_action.connect(_on_action)
	Events.player_arrested.connect(_on_arrested)
	Events.summons_issued.connect(_on_issued)


func after_each() -> void:
	Events.police_action.disconnect(_on_action)
	Events.player_arrested.disconnect(_on_arrested)
	Events.summons_issued.disconnect(_on_issued)
	Game.saves.delete_slot("test_police")


func _on_action(outcome: String, officer: String, _fine: int, forced: bool) -> void:
	_actions.append("%s:%s:%s" % [outcome, officer, "forced" if forced else "asked"])


func _on_arrested(officer: String, _at: int) -> void:
	_arrested.append(officer)


func _on_issued(summons_id: int) -> void:
	_issued.append(summons_id)


func _entry(severity: float, strength: float) -> Dictionary:
	return {"severity": severity, "strength": strength}


# --- the rules -----------------------------------------------------------------------------------

func test_how_sure_she_is_is_what_reached_her_less_how_garbled_it_is() -> void:
	assert_almost(PoliceRules.strength(1.0, 0.0), 1.0, 0.0001, "she saw it")
	assert_almost(PoliceRules.strength(0.85, 0.12), 0.748, 0.001, "she was told")
	assert_lt(PoliceRules.strength(0.4, 0.48), PoliceRules.EVIDENCE_MIN, "a rumour passed along a few times")
	assert_eq(PoliceRules.strength(2.0, -1.0), 1.0, "clamped")


func test_the_answer_is_proportionate_to_what_she_believes() -> void:
	var petty_seen := [_entry(0.28, 1.0)]
	var petty_told := [_entry(0.28, 0.75)]
	var middling := [_entry(0.5, 0.75)]
	var serious := [_entry(0.7, 0.75)]
	assert_eq(PoliceRules.judge_response([], 0, []), "none", "nothing to go on")
	assert_eq(PoliceRules.judge_response(petty_told, 0, []), "warning")
	assert_eq(PoliceRules.judge_response(petty_seen, 0, []), "warning")
	assert_eq(PoliceRules.judge_response(middling, 0, []), "fine")
	assert_eq(PoliceRules.judge_response(serious, 0, []), "arrest")
	assert_eq(PoliceRules.judge_response([_entry(0.25, 0.4)], 0, []), "none", "too petty and too unsure to act on")
	assert_eq(PoliceRules.judge_response([_entry(0.9, 0.3)], 0, []), "none", "however serious, a rumour is not enough")


func test_a_record_and_a_by_the_book_officer_and_ignoring_a_summons_all_weigh() -> void:
	var petty := [_entry(0.28, 0.75)]
	assert_eq(PoliceRules.judge_response(petty, 0, []), "warning")
	assert_eq(PoliceRules.judge_response(petty, 1, []), "fine", "the second time is not the first")
	assert_eq(PoliceRules.judge_response(petty, 3, []), "arrest", "the fourth is worse")
	assert_eq(PoliceRules.judge_response(petty, 9, []), "arrest")
	assert_almost(PoliceRules.weight(petty, 9, []), PoliceRules.weight(petty, 3, []), 0.0001, "the record's weight is capped")
	assert_gt(PoliceRules.weight(petty, 0, ["by_the_book"]), PoliceRules.weight(petty, 0, []))
	assert_eq(PoliceRules.judge_response(petty, 0, [], true), "fine", "not coming in turns a warning into a fine")
	assert_eq(PoliceRules.judge_response([_entry(0.5, 0.75)], 0, [], true), "arrest")
	assert_gt(PoliceRules.weight([_entry(0.28, 0.75), _entry(0.28, 0.75)], 0, []), PoliceRules.weight(petty, 0, []), "a second matter")


func test_a_fine_that_cannot_be_paid_is_a_night_in_the_cells() -> void:
	assert_eq(PoliceRules.settle("fine", 47, 100), "fine")
	assert_eq(PoliceRules.settle("fine", 47, 20), "arrest")
	assert_eq(PoliceRules.settle("warning", 47, 0), "warning")
	assert_lt(PoliceRules.fine_for(0.3), PoliceRules.fine_for(0.8))
	assert_gt(PoliceRules.assess_delay(["unhurried"]), PoliceRules.assess_delay([]))


# --- from a theft to a summons ------------------------------------------------------------------------

func _at_idas_counter() -> void:
	for npc_id: String in Game.npcs.living_ids():
		var npc := Game.npcs.get_npc(npc_id)
		npc.location = npc.home
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))
	assert_ok(Game.open_shop())


func _rig_a_catch() -> void:
	var stream := Game.rng.stream("theft")
	for seed_value in range(1, 20000):
		stream.seed = seed_value
		if stream.randf() < 0.03:
			stream.seed = seed_value
			return
	assert_true(false, "no seed")


## Runs the clock to the next event of a kind.
func _run(kind: String) -> void:
	for event in Game.events_queue.pending():
		if event.kind == kind:
			Game.pause_time(false)
			Game.advance_time(maxi(event.at - Game.clock.total_minutes, 1))
			Game.pause_time(true)
			return
	assert_true(false, "no %s is waiting" % kind)


## Ida catches the player at the till and, not being fond of them, tells.
func _caught_stealing() -> void:
	_at_idas_counter()
	Game.relationships.get_edge("npc_ida", PlayerState.ID).affection = 0.0
	_rig_a_catch()
	assert_ok(Game.steal("item_sandwich"))
	Game.close_shop()


func _serious_crime_seen_by_marika() -> String:
	var witnesses: Array[String] = ["npc_marika"]
	return Game.knowledge.observe_event(PlayerState.ID, "stole_from", Game.clock.total_minutes, witnesses, {
		"object": "npc_ida", "location": "loc_corner_shop", "severity": 0.8, "visibility": "social"})


func test_a_reported_theft_becomes_a_summons_in_the_officers_own_time() -> void:
	_caught_stealing()
	assert_eq(Game.crime.summons.size(), 0)
	_run("crime_report")
	assert_eq(_issued, [] as Array[int], "she has been told; she has not decided")
	_run("police_assess")
	assert_eq(_issued.size(), 1)
	var summons: Dictionary = Game.crime.summons[0]
	assert_eq(summons["officer"], "npc_marika")
	assert_eq(summons["status"], "open")
	assert_eq(int(summons["due"]), Game.clock.total_minutes + PoliceRules.SUMMONS_WINDOW, "a day to come in")


func test_the_summons_comes_by_text_and_names_the_place() -> void:
	_caught_stealing()
	_run("crime_report")
	_run("police_assess")
	Game.npcs.get_npc("npc_marika").activity = "idle"
	Game.clock.total_minutes = (Game.clock.day_index()) * GameClock.MINUTES_PER_DAY + 12 * 60
	Game.phone_director.run_outreach()
	assert_true(Game.phone.is_contact("npc_marika"), "the police have your number")
	var text := PhoneText.render(Game.phone.thread("npc_marika")[0])
	assert_true(text.begins_with("Harbourside police."), text)
	assert_true(text.contains("Police Post"), text)
	assert_true(Game.player.knows_place("loc_police_post"), "you know where to go")


func test_a_rumour_is_not_enough_to_send_for_anyone() -> void:
	var fact_id := Game.knowledge.record(PlayerState.ID, "stole_from", Game.clock.total_minutes,
		{"object": "npc_ida", "severity": 0.9, "visibility": "social"})
	Game.knowledge.witness("npc_ida", fact_id, Game.clock.total_minutes)
	var chain := ["npc_ida", "npc_elias", "npc_tuomas", "npc_leena", "npc_marika"]
	for i in chain.size() - 1:
		assert_ok(Game.knowledge.tell(chain[i], chain[i + 1], fact_id, Game.clock.total_minutes))
	assert_lt(PoliceRules.strength(Game.knowledge.belief_of("npc_marika", fact_id).confidence,
		Game.knowledge.belief_of("npc_marika", fact_id).distortion), PoliceRules.EVIDENCE_MIN)
	_run("police_assess")
	assert_eq(Game.crime.summons.size(), 0, "she has heard something, not enough")
	assert_eq(_issued, [] as Array[int])


func test_an_unwitnessed_theft_never_reaches_them() -> void:
	_at_idas_counter()
	var stream := Game.rng.stream("theft")
	for seed_value in range(1, 20000):
		stream.seed = seed_value
		if stream.randf() > 0.96:
			stream.seed = seed_value
			break
	assert_ok(Game.steal("item_sandwich"))
	Game.close_shop()
	var waiting := Game.events_queue.pending().filter(func(e: WorldEventQueue.QueuedEvent) -> bool: return e.kind.begins_with("police") or e.kind == "crime_report")
	assert_eq(waiting.size(), 0)
	assert_eq(Game.crime.summons.size(), 0)


# --- coming in ---------------------------------------------------------------------------------------

## The desk in the police post, with Marika behind it, and the player in front.
func _at_the_desk() -> Vector2i:
	var marika := Game.npcs.get_npc("npc_marika")
	marika.location = "loc_police_post"
	marika.activity = "work"
	Game.player.interior = ""   # out of wherever they were, and onto the street
	var map := Game.world.map_for(Game.player.region)
	Game.player.position = DistrictMap.cell_to_world(map.anchor_of("loc_police_post"))
	assert_ok(Game.interact_at(map.buildings["loc_police_post"]["door"]))
	var inside := Game.current_map()
	var desk := Vector2i(-1, -1)
	for cell: Vector2i in inside.objects:
		if inside.objects[cell]["kind"] == "counter":
			desk = cell
	for step: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		if not inside.is_blocked(desk + step):
			assert_ok(Game.move_player(DistrictMap.cell_to_world(desk + step)))
			return desk
	assert_true(false, "nowhere to stand at the desk")
	return desk


func test_coming_in_for_a_petty_first_offence_earns_a_warning() -> void:
	_caught_stealing()
	_run("crime_report")
	_run("police_assess")
	var cash := Game.player.wallet.total()
	var desk := _at_the_desk()
	var came := Game.interact_at(desk)
	assert_ok(came)
	assert_eq(came.value["kind"], "desk")
	assert_eq(came.value["outcome"], "warning")
	assert_eq(Game.player.wallet.total(), cash, "a warning costs nothing")
	assert_eq(Game.crime.summons[0]["status"], "attended")
	assert_eq(Game.crime.record.size(), 1, "but it is on the record")
	assert_eq(_actions, ["warning:npc_marika:asked"] as Array[String])
	assert_true(InteractionText.outcome_text({"kind": "counter"}, came).contains("warning"), "and the desk says so")
	assert_eq(Game.crime.case_for("npc_marika"), [] as Array[Dictionary], "it is dealt with, not held over you")
	var again := Game.interact_at(desk)
	assert_eq(again.value["outcome"], "nothing", "and there is nothing more to say")


func test_a_serious_matter_is_a_night_in_the_cells() -> void:
	var fact_id := _serious_crime_seen_by_marika()
	_run("police_assess")
	assert_eq(_issued.size(), 1, "she saw it herself, and it was serious")
	var desk := _at_the_desk()
	var came := Game.interact_at(desk)
	assert_eq(came.value["outcome"], "arrest")
	assert_eq(_arrested, ["npc_marika"] as Array[String])
	assert_eq(Game.player.interior, "loc_police_post", "held at the post")
	assert_true(Game.clock.minute_of_day() >= Game.RELEASE_MINUTE and Game.clock.minute_of_day() < Game.RELEASE_MINUTE + 10, "let go in the morning")
	assert_eq(Game.crime.handled[fact_id], "arrest")
	var known := Game.knowledge.what_is_known_about("npc_marika", PlayerState.ID)
	assert_true(known.any(func(f: Dictionary) -> bool: return f["predicate"] == "arrested"), "and it is known")


func test_a_fine_is_paid_from_what_you_have() -> void:
	var facts: Array[String] = ["npc_marika"]
	Game.knowledge.observe_event(PlayerState.ID, "stole_from", Game.clock.total_minutes, facts, {
		"object": "npc_ida", "location": "loc_corner_shop", "severity": 0.35, "visibility": "social"})
	_run("police_assess")
	Game.player.wallet.cash = 200
	Game.player.wallet.bank = 0
	var desk := _at_the_desk()
	var came := Game.interact_at(desk)
	assert_eq(came.value["outcome"], "fine")
	assert_gt(int(came.value["fine"]), 0)
	assert_eq(Game.player.wallet.cash, 200 - int(came.value["fine"]), "paid on the spot")
	assert_eq(_arrested, [] as Array[String])
	assert_true(InteractionText.outcome_text({"kind": "counter"}, came).contains("fine"))


func test_a_fine_that_cannot_be_paid_is_not_waived() -> void:
	var facts: Array[String] = ["npc_marika"]
	Game.knowledge.observe_event(PlayerState.ID, "stole_from", Game.clock.total_minutes, facts, {
		"object": "npc_ida", "location": "loc_corner_shop", "severity": 0.35, "visibility": "social"})
	_run("police_assess")
	Game.player.wallet.cash = 0
	Game.player.wallet.bank = 0
	var desk := _at_the_desk()
	assert_eq(Game.interact_at(desk).value["outcome"], "arrest", "a night in the cells instead")
	assert_eq(_arrested, ["npc_marika"] as Array[String])


func test_a_second_offence_is_treated_as_one() -> void:
	var facts: Array[String] = ["npc_marika"]
	Game.knowledge.observe_event(PlayerState.ID, "stole_from", Game.clock.total_minutes, facts, {
		"object": "npc_ida", "location": "loc_corner_shop", "severity": 0.15, "visibility": "social"})
	_run("police_assess")
	var desk := _at_the_desk()
	assert_eq(Game.interact_at(desk).value["outcome"], "warning", "the first time")
	Game.knowledge.observe_event(PlayerState.ID, "stole_from", Game.clock.total_minutes, facts, {
		"object": "npc_ida", "location": "loc_corner_shop", "severity": 0.15, "visibility": "social"})
	_run("police_assess")
	Game.player.wallet.cash = 300
	var back := _at_the_desk()   # time has moved everyone on
	assert_eq(Game.interact_at(back).value["outcome"], "fine", "the same again is worse")


# --- not coming in ----------------------------------------------------------------------------

## Lets time pass in hours, eating and sleeping enough that the body is not
## what ends the wait.
func _wait_fed(minutes: int) -> void:
	Game.pause_time(false)
	var left := minutes
	while left > 0:
		var chunk := mini(left, 240)
		Game.player.stats.hunger = 0.0
		Game.player.stats.sleep = 1.0
		Game.advance_time(chunk)
		left -= chunk
	Game.pause_time(true)

func test_ignoring_a_summons_makes_it_worse_and_they_come_for_you() -> void:
	var fact_id := _serious_crime_seen_by_marika()
	_run("police_assess")
	var summons: Dictionary = Game.crime.summons[0]
	assert_eq(_arrested, [] as Array[String])
	_wait_fed(int(summons["due"]) - Game.clock.total_minutes + 5)
	assert_eq(Game.crime.summons[0]["status"], "ignored")
	assert_eq(_arrested, ["npc_marika"] as Array[String], "taken in, after time stopped moving")
	assert_eq(Game.player.interior, "loc_police_post")
	assert_eq(_actions.back(), "arrest:npc_marika:forced")
	assert_eq(Game.crime.handled[fact_id], "arrest")


func test_ignoring_a_lesser_summons_costs_you_more_than_coming_in_would_have() -> void:
	var facts: Array[String] = ["npc_marika"]
	Game.knowledge.observe_event(PlayerState.ID, "stole_from", Game.clock.total_minutes, facts, {
		"object": "npc_ida", "location": "loc_corner_shop", "severity": 0.15, "visibility": "social"})
	_run("police_assess")
	assert_eq(_issued.size(), 1)
	Game.player.wallet.cash = 500
	var summons: Dictionary = Game.crime.summons[0]
	_wait_fed(int(summons["due"]) - Game.clock.total_minutes + 5)
	assert_eq(_actions.back(), "fine:npc_marika:forced", "it would have been a warning")
	assert_lt(Game.player.wallet.cash, 500)


func test_without_a_phone_the_summons_still_stands() -> void:
	Game.player.inventory.remove(PhoneDirector.ITEM, 1)
	_serious_crime_seen_by_marika()
	_run("police_assess")
	assert_eq(Game.crime.summons.size(), 1)
	assert_eq(Game.phone.messages.size(), 0, "no one to tell you")
	assert_eq(Game.phone.pending.size(), 0)


func test_one_summons_at_a_time_and_more_news_is_folded_in() -> void:
	_serious_crime_seen_by_marika()
	_run("police_assess")
	var again := _serious_crime_seen_by_marika()
	assert_eq(Game.events_queue.pending().filter(func(e: WorldEventQueue.QueuedEvent) -> bool: return e.kind == "police_assess").size(), 0, "she is already waiting on you")
	var desk := _at_the_desk()
	Game.interact_at(desk)
	assert_eq(Game.crime.handled[again], "arrest", "both matters were dealt with together")


# --- kept ---------------------------------------------------------------------------------------------------

func test_the_record_and_the_open_summons_are_saved() -> void:
	_serious_crime_seen_by_marika()
	_run("police_assess")
	Game.crime.record.append({"fact": "fact_x", "outcome": "warning", "day": 3})
	assert_ok(Game.save_game("test_police"))
	assert_ok(Game.load_game("test_police"))
	Game.pause_time(true)
	assert_eq(Game.crime.record.size(), 1)
	assert_eq(Game.crime.summons.size(), 1)
	assert_eq(Game.crime.summons[0]["status"], "open")
	var kinds: Array[String] = []
	for event in Game.events_queue.pending():
		kinds.append(event.kind)
	assert_has(kinds, "police_summons_due", "and the day she gave you is still running out")


func test_a_version_7_save_has_no_record() -> void:
	var migrated := SaveMigrations.migrate({"schema_version": 7, "calendar": {}})
	assert_ok(migrated)
	assert_eq(migrated.value["schema_version"], SaveMigrations.CURRENT_VERSION)
	assert_eq(migrated.value["crime"]["record"], [])
