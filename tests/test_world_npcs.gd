extends TestCase
## World state, region unlocking, and the NPC simulation director.

var data: DataRegistry
var world: WorldState
var registry: NpcRegistry
var clock: GameClock
var director: NpcDirector


func before_each() -> void:
	data = DataRegistry.new()
	data.load_all()
	world = WorldState.new()
	world.build_from(data)
	registry = NpcRegistry.new()
	registry.setup(data, world)
	clock = GameClock.new()
	director = NpcDirector.new()
	director.setup(registry, world, clock)


# --- world ------------------------------------------------------------------

func test_regions_and_locations_are_built() -> void:
	assert_gt(float(world.regions.size()), 0.0)
	assert_not_null(world.get_region("harbourside"))
	assert_not_null(world.get_location("loc_corner_shop"))


func test_locations_index_by_region() -> void:
	var here := world.locations_in("harbourside")
	assert_gt(float(here.size()), 5.0)
	assert_has(here, "loc_corner_shop")
	assert_eq(world.region_of("loc_corner_shop"), "harbourside")


func test_entering_any_known_region_works() -> void:
	# Regions are freely walkable (D-077): no lock left to test.
	assert_ok(world.enter_region("eastfield"))
	assert_err(world.enter_region("no_such_place"), "no_such_region")


func test_entering_an_open_region_works_and_marks_it_discovered() -> void:
	assert_ok(world.enter_region("harbourside"))
	assert_eq(world.current_region, "harbourside")
	assert_true(world.get_region("harbourside").discovered)


func test_try_unlock_is_idempotent() -> void:
	# No region has requirements left (D-077), but the mechanism stays in
	# place for a road that may be shut later, and must still be safe to
	# call twice.
	assert_ok(world.try_unlock("old_town", {}))
	assert_true(world.get_region("old_town").unlocked)
	assert_ok(world.try_unlock("old_town", {}))


func test_flags_round_trip() -> void:
	world.set_flag("owes_money", true)
	world.enter_region("harbourside")
	var restored := WorldState.new()
	restored.build_from(data)
	restored.from_dict(world.to_dict())
	assert_true(restored.has_flag("owes_money"))
	assert_eq(restored.current_region, "harbourside")


func test_opening_hours_including_past_midnight() -> void:
	var shop: Location = world.get_location("loc_corner_shop")
	assert_true(shop.is_open_at(600))
	assert_false(shop.is_open_at(60))

	var bar: Location = world.get_location("loc_anchor_bar")
	assert_true(bar.is_open_at(1400), "still open before midnight")
	assert_true(bar.is_open_at(60), "and after it")
	assert_false(bar.is_open_at(600), "but not in the morning")


## D-104: a closed day shuts the whole day, and a bar's small hours belong to
## the evening they started.
func test_closed_days_including_past_midnight() -> void:
	var shop: Location = world.get_location("loc_corner_shop")
	assert_eq(shop.closed_days, [0] as Array[int])
	assert_false(shop.is_open_at(600, 0), "shut on Sunday")
	assert_true(shop.is_open_at(600, 1), "open on Monday")
	assert_true(shop.is_open_at(600), "no weekday given, no closed day considered")
	var bar := Location.from_data({"id": "loc_test_bar", "open_from": 1200, "open_until": 180, "closed_days": [0]})
	assert_true(bar.is_open_at(60, 0), "one on Sunday morning is still Saturday night")
	assert_false(bar.is_open_at(1300, 0), "Sunday evening it stays shut")
	assert_false(bar.is_open_at(60, 1), "and so do the small hours after it")
	assert_true(bar.is_open_at(1300, 1), "open again on Monday evening")


func test_a_closed_day_outside_the_week_is_reported() -> void:
	var fresh := DataRegistry.new()
	fresh.load_all()
	fresh.tables["locations"]["loc_corner_shop"]["closed_days"] = [7]
	var text := "
".join(fresh.validate_references())
	assert_true(text.contains("closed day that is not 0-6"), text)


# --- population -------------------------------------------------------------

func test_the_town_has_persistent_inhabitants() -> void:
	assert_gt(float(registry.count()), 5.0)
	var ida := registry.get_npc("npc_ida")
	assert_not_null(ida)
	assert_eq(ida.name, "Ida Lahtinen")
	assert_true(ida.is_story_critical())


func test_dormant_npcs_have_a_computed_location() -> void:
	# Nothing has ticked yet. Everyone must still be somewhere sensible,
	# because position is derived from the routine rather than simulated.
	var ida := registry.get_npc("npc_ida")
	assert_eq(ida.tier, SimLod.Tier.DORMANT)
	var at_seven := registry.location_of("npc_ida", 7 * 60, 1)
	assert_ne(at_seven, "")
	var at_ten := registry.location_of("npc_ida", 10 * 60, 1)
	assert_eq(at_ten, "loc_corner_shop", "she is at work on a Monday morning")


func test_location_tokens_resolve_per_person() -> void:
	# One routine, two people, two different homes and workplaces.
	var veikko_home := registry.location_of("npc_veikko", 2 * 60, 1)
	var joonas_home := registry.location_of("npc_joonas", 2 * 60, 1)
	assert_eq(veikko_home, "loc_veikko_flat")
	assert_eq(joonas_home, "loc_veikko_flat")
	assert_eq(registry.get_npc("npc_veikko").schedule_id,
		registry.get_npc("npc_joonas").schedule_id, "sharing one routine")


func test_workplace_token_falls_back_to_home() -> void:
	var elias := registry.get_npc("npc_elias")
	assert_eq(elias.workplace, "")
	assert_eq(registry.resolve_location_token(elias, "@work"), elias.home)


func test_people_are_somewhere_at_every_hour_of_the_week() -> void:
	# The bug this catches: a schedule gap that teleports someone to "".
	for npc_id in registry.all_ids():
		for day in range(7):
			for hour in range(24):
				var minutes := day * 1440 + hour * 60
				var location := registry.location_of(npc_id, minutes, day)
				assert_ne(location, "", "%s is nowhere on day %d at %02d:00" % [npc_id, day, hour])
				assert_not_null(world.get_location(location),
					"%s is at unknown location '%s'" % [npc_id, location])


func test_npcs_at_a_location() -> void:
	var at_shop := registry.npcs_at("loc_corner_shop", 10 * 60, 1)
	assert_has(at_shop, "npc_ida")


func test_npcs_in_a_region() -> void:
	assert_gt(float(registry.npcs_in_region("harbourside", 10 * 60, 1).size()), 5.0)


# --- simulation tiers -------------------------------------------------------

func test_tiers_are_assigned_by_proximity() -> void:
	world.enter_region("harbourside")
	director.assign_tiers()
	var stats := director.stats()
	assert_gt(float(stats["active"]), 0.0, "people in the player's region are simulated")


func test_active_population_is_capped() -> void:
	world.enter_region("harbourside")
	for i in range(SimLod.MAX_ACTIVE + 40):
		var npc := Npc.from_data({
			"id": "crowd_%d" % i, "name": "Extra %d" % i,
			"home": "loc_dock_street", "schedule": "sched_local_idle",
		})
		registry.npcs[npc.id] = npc
	registry.rebuild_region_index()
	director.assign_tiers()
	assert_lt(float(director.stats()["active"]), float(SimLod.MAX_ACTIVE + 1))


func test_conversation_partners_are_promoted_to_focus() -> void:
	world.enter_region("harbourside")
	director.set_focus(["npc_ida"])
	assert_eq(registry.get_npc("npc_ida").tier, SimLod.Tier.FOCUS)
	director.clear_focus()
	assert_ne(registry.get_npc("npc_ida").tier, SimLod.Tier.FOCUS)


func test_dormant_npcs_are_never_ticked() -> void:
	# The core performance guarantee.
	world.enter_region("harbourside")
	director.assign_tiers()
	var dormant: Npc = null
	for npc_id in registry.all_ids():
		var npc: Npc = registry.get_npc(npc_id)
		if npc.tier == SimLod.Tier.DORMANT:
			dormant = npc
			break
	if dormant == null:
		return    # everyone is nearby in this small map; nothing to assert
	var before := dormant.last_simulated
	for minute in range(600, 700):
		director.tick(minute)
	assert_eq(dormant.last_simulated, before)


func test_background_npcs_tick_coarsely() -> void:
	assert_false(SimLod.ticks_this_minute(SimLod.Tier.BACKGROUND, 601))
	assert_true(SimLod.ticks_this_minute(SimLod.Tier.BACKGROUND, 600))
	assert_true(SimLod.ticks_this_minute(SimLod.Tier.ACTIVE, 601))
	assert_false(SimLod.ticks_this_minute(SimLod.Tier.DORMANT, 600))


func test_active_npcs_follow_their_schedule() -> void:
	world.enter_region("harbourside")
	clock.set_absolute(10 * 60)     # Monday 10:00
	director.assign_tiers()
	director.tick(10 * 60)
	var ida := registry.get_npc("npc_ida")
	if ida.tier != SimLod.Tier.DORMANT:
		assert_eq(ida.location, "loc_corner_shop")
		assert_eq(ida.activity, "work")


func test_catch_up_after_a_time_skip_costs_one_step() -> void:
	world.enter_region("harbourside")
	clock.set_absolute(8 * 60)
	director.assign_tiers()
	director.tick(8 * 60)

	clock.set_absolute(20 * 60)      # skipped twelve hours
	director.catch_up(20 * 60)
	for npc_id in registry.all_ids():
		var npc: Npc = registry.get_npc(npc_id)
		if npc.tier != SimLod.Tier.DORMANT:
			assert_eq(npc.last_simulated, 20 * 60,
				"%s did not catch up" % npc_id)


func test_needs_drift_over_time() -> void:
	var needs := NpcNeeds.new()
	needs.drift(600, "work")
	assert_gt(needs.hunger, 0.5)
	assert_lt(needs.energy, 1.0)
	assert_eq(needs.dominant_need(0.5), "food")


func test_sleeping_restores_energy() -> void:
	var needs := NpcNeeds.new()
	needs.energy = 0.1
	needs.drift(480, "sleep")
	assert_gt(needs.energy, 0.9)


# --- death and persistence --------------------------------------------------

func test_story_npcs_resist_incidental_death() -> void:
	assert_err(registry.kill("npc_ida", "bar_fight"), "story_protected")
	assert_true(registry.get_npc("npc_ida").alive)


func test_story_npcs_can_die_when_the_story_says_so() -> void:
	assert_ok(registry.kill("npc_ida", "act_two_finale", true))
	assert_false(registry.get_npc("npc_ida").alive)


func test_ordinary_npcs_can_die() -> void:
	assert_ok(registry.kill("npc_joonas", "accident"))
	assert_false(registry.get_npc("npc_joonas").alive)
	assert_eq(registry.get_npc("npc_joonas").state["death_cause"], "accident")


func test_the_dead_are_nowhere() -> void:
	registry.kill("npc_joonas", "accident")
	assert_eq(registry.location_of("npc_joonas", 600, 1), "")


func test_adding_people_requires_a_stated_origin() -> void:
	var newcomer := Npc.from_data({
		"id": "npc_new", "name": "New Arrival",
		"home": "loc_player_flat", "schedule": "sched_local_idle",
	})
	assert_ok(registry.add_npc(newcomer, "moved_in"))
	assert_eq(registry.get_npc("npc_new").state["origin"], "moved_in")
	assert_err(registry.add_npc(newcomer, "moved_in"), "duplicate_npc")


func test_npc_state_round_trips() -> void:
	var ida := registry.get_npc("npc_ida")
	ida.tier = SimLod.Tier.ACTIVE
	ida.location = "loc_anchor_bar"
	ida.activity = "socialise"
	ida.needs.hunger = 0.7
	ida.set_override(100, 200, "loc_police_post", "questioned", "witness")

	var fresh := NpcRegistry.new()
	fresh.setup(data, world)
	var orphans := fresh.from_dict(registry.to_dict())
	assert_eq(orphans.size(), 0)

	var restored := fresh.get_npc("npc_ida")
	assert_eq(restored.location, "loc_anchor_bar")
	assert_almost(restored.needs.hunger, 0.7)
	assert_not_null(restored.schedule_override)
	assert_eq(restored.schedule_override.reason, "witness")


func test_saves_referencing_removed_content_report_orphans() -> void:
	# Renaming a content id must be a loud failure, not a silent one.
	var fresh := NpcRegistry.new()
	fresh.setup(data, world)
	var orphans := fresh.from_dict({"npcs": {"npc_deleted_person": {"location": "x"}}})
	assert_has(orphans, "npc_deleted_person")
