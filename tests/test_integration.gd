extends TestCase
## End-to-end: a world that starts, runs, remembers and reloads.
##
## The unit tests above prove each system in isolation. This one proves they
## were wired together, which is a different claim and the one that actually
## breaks.

const SLOT := "integration_test"


func after_each() -> void:
	Game.saves.delete_slot(SLOT)


func test_a_new_game_starts_cleanly() -> void:
	assert_ok(Game.new_game("bg_returning", 12345))
	assert_true(Game.is_running())
	assert_gt(float(Game.npcs.count()), 5.0)
	assert_ne(Game.world.current_region, "")
	assert_eq(Game.player.background_id, "bg_returning")


func test_the_background_shapes_the_opening_position() -> void:
	Game.new_game("bg_dockhand", 1)
	assert_eq(Game.player.wallet.cash, 45)
	assert_true(Game.player.knows_contact("npc_veikko"))
	assert_gt(float(Game.player.skills.level_of("labour")), 5.0)
	assert_true(Game.player.inventory.has("item_work_boots"))

	Game.new_game("bg_trained", 1)
	assert_gt(float(Game.player.skills.level_of("first_aid")), 5.0)
	assert_false(Game.player.knows_contact("npc_veikko"))


func test_an_unknown_background_still_produces_a_playable_world() -> void:
	assert_ok(Game.new_game("not_a_real_background", 1))
	assert_true(Game.is_running())
	assert_ne(Game.player.home_location, "")


func test_time_passes_and_people_move() -> void:
	Game.new_game("bg_returning", 7)
	Game.clock.set_absolute(3 * 60)          # everyone asleep
	Game.director.assign_tiers()
	Game.director.tick(3 * 60)
	var night := Game.npcs.location_of("npc_ida", Game.clock.total_minutes, Game.clock.weekday())

	Game.advance_time(9 * 60)                 # -> midday
	var midday := Game.npcs.location_of("npc_ida", Game.clock.total_minutes, Game.clock.weekday())
	assert_ne(night, midday, "she does not spend the whole day in bed")


func test_sleeping_eight_hours_resolves_the_world_rather_than_replaying_it() -> void:
	Game.new_game("bg_returning", 7)
	var minute_ticks := [0]
	var handler := func(_t: int) -> void: minute_ticks[0] += 1
	Events.minute_passed.connect(handler)
	Game.advance_time(480)
	Events.minute_passed.disconnect(handler)
	assert_eq(minute_ticks[0], 0, "a night's sleep is not 480 simulation steps")
	assert_eq(Game.clock.total_minutes, 900)


func test_scheduled_events_fire_during_a_time_skip() -> void:
	Game.new_game("bg_returning", 7)
	var fired: Array[String] = []
	var handler := func(event: Dictionary) -> void: fired.append(str(event["kind"]))
	Events.world_event_fired.connect(handler)
	Game.events_queue.schedule_in(Game.clock.total_minutes, 120, "test_meeting", {"npc": "npc_rauno"})
	Game.advance_time(300)
	Events.world_event_fired.disconnect(handler)
	assert_has(fired, "test_meeting")


func test_gossip_crosses_the_town_over_a_day() -> void:
	Game.new_game("bg_returning", 7)
	var fact_id := Game.knowledge.observe_event(
		"npc_elias", "stole_from", Game.clock.total_minutes, ["npc_tuomas"],
		{"object": "loc_corner_shop", "severity": 0.9, "visibility": "social"})
	assert_eq(Game.knowledge.knowers_of(fact_id).size(), 1)

	Game.advance_time(60 * 24 * 2)
	assert_gt(float(Game.knowledge.knowers_of(fact_id).size()), 1.0,
		"two days on, more than the eyewitness has heard")


func test_reputation_follows_what_people_learned() -> void:
	Game.new_game("bg_returning", 7)
	var before := Game.reputation.standing("group:harbourside_traders")
	Game.knowledge.observe_event(
		"player", "stole_from", Game.clock.total_minutes,
		["npc_ida", "npc_tuomas", "npc_leena"],
		{"object": "loc_corner_shop", "severity": 0.9})
	Game.reputation.invalidate()
	assert_lt(Game.reputation.standing("group:harbourside_traders"), before)


func test_a_secret_crime_leaves_reputation_untouched() -> void:
	Game.new_game("bg_returning", 7)
	var before := Game.reputation.standing("group:harbourside_traders")
	Game.knowledge.record("player", "stole_from", Game.clock.total_minutes, {"severity": 1.0})
	Game.reputation.invalidate()
	assert_almost(Game.reputation.standing("group:harbourside_traders"), before,
		0.0001, "nobody saw it, so nobody thinks less of you")


func test_full_save_and_load_round_trip() -> void:
	Game.new_game("bg_in_debt", 4242)
	Game.player.display_name = "Round Trip"
	Game.advance_time(500)
	Game.player.wallet.add_cash(123, "test")
	Game.player.skills.award("persuasion", 3000.0)
	Game.world.set_flag("heard_about_old_town")
	Game.relationships.apply("npc_ida", "player", {"trust": 0.4, "familiarity": 0.6})
	var fact_id := Game.knowledge.observe_event(
		"player", "helped", Game.clock.total_minutes, ["npc_ida"], {"severity": 0.6})
	Game.events_queue.schedule_in(Game.clock.total_minutes, 600, "later_meeting")

	var when := Game.clock.total_minutes
	var cash := Game.player.wallet.cash
	var persuasion := Game.player.skills.level_of("persuasion")

	assert_ok(Game.save_game(SLOT))
	assert_ok(Game.load_game(SLOT))

	assert_eq(Game.clock.total_minutes, when)
	assert_eq(Game.player.display_name, "Round Trip")
	assert_eq(Game.player.wallet.cash, cash)
	assert_eq(Game.player.skills.level_of("persuasion"), persuasion)
	assert_true(Game.world.has_flag("heard_about_old_town"))
	assert_almost(Game.relationships.disposition("npc_ida", "player"),
		0.4 * 0.4, 0.001)
	assert_true(Game.knowledge.knows("npc_ida", fact_id))
	assert_gt(float(Game.events_queue.size()), 0.0)
	assert_true(Game.is_running())


func test_a_loaded_world_keeps_running() -> void:
	Game.new_game("bg_returning", 9)
	Game.advance_time(200)
	Game.save_game(SLOT)
	Game.load_game(SLOT)
	var before := Game.clock.total_minutes
	Game.advance_time(120)
	assert_eq(Game.clock.total_minutes, before + 120)
	assert_gt(float(Game.director.stats()["total"]), 0.0)


func test_save_headers_describe_the_slot() -> void:
	Game.new_game("bg_returning", 3)
	Game.player.display_name = "Header Test"
	Game.save_game(SLOT)
	var header := Game.saves.read_header(SLOT)
	assert_eq(header["meta"]["player_name"], "Header Test")
	assert_eq(header["meta"]["region"], Game.world.current_region)


func test_the_game_is_fully_playable_with_no_ai_configured() -> void:
	# The offline guarantee: nothing above depends on a model being reachable.
	assert_false(Game.llm.is_available())
	assert_ok(Game.new_game("bg_returning", 5))
	Game.advance_time(600)
	assert_true(Game.is_running())
	assert_ok(Game.save_game(SLOT))


func test_debug_snapshot_reports_a_live_world() -> void:
	Game.new_game("bg_returning", 6)
	var snapshot := Game.debug_snapshot()
	assert_true(snapshot["running"])
	assert_gt(float(snapshot["npc_tiers"]["total"]), 0.0)
	assert_has(snapshot, "llm")


func test_unload_leaves_no_world_behind() -> void:
	Game.new_game("bg_returning", 8)
	Game.unload()
	assert_false(Game.is_running())
	assert_eq(Game.events_queue.size(), 0)
