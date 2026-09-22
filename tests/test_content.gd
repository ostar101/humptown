extends TestCase
## Content integrity. These tests fail when a data file is edited carelessly,
## which is the most common way a data-driven game breaks.

var data: DataRegistry


func before_each() -> void:
	data = DataRegistry.new()
	data.load_all()


func test_all_content_files_load_without_errors() -> void:
	assert_eq(data.load_errors.size(), 0,
		"content errors: " + "; ".join(data.load_errors))


func test_every_table_has_entries() -> void:
	for table_name in DataRegistry.REQUIRED_KEYS:
		assert_gt(float(data.table(table_name).size()), 0.0,
			"table '%s' is empty" % table_name)


func test_cross_references_all_resolve() -> void:
	var problems := data.validate_references()
	assert_eq(problems.size(), 0, "; ".join(problems))


func test_every_npc_has_a_reachable_home_in_a_real_region() -> void:
	for npc_id in data.ids("npcs"):
		var npc := data.get_entry("npcs", npc_id)
		var home := data.get_entry("locations", str(npc["home"]))
		assert_false(home.is_empty(), "%s has no home location" % npc_id)
		assert_true(data.has_entry("regions", str(home.get("region", ""))),
			"%s lives in an unknown region" % npc_id)


## M8 step 12, D-088: the median age was 46 before this step (a town of
## nobody young); guards against that drifting back unnoticed.
func test_the_town_has_young_adults_too() -> void:
	var young := 0
	for npc_id in data.ids("npcs"):
		if int(data.get_entry("npcs", npc_id).get("age", 99)) < 30:
			young += 1
	assert_gt(float(young), 10.0, "the town should not read as everyone being middle-aged or older")


func test_every_npc_is_an_adult() -> void:
	# The world contains mature themes; every simulated inhabitant who can be
	# approached romantically must be unambiguously an adult. Enforcing it in
	# content rather than in dialogue means it cannot be forgotten later.
	for npc_id in data.ids("npcs"):
		var npc := data.get_entry("npcs", npc_id)
		assert_gt(float(npc.get("age", 0)), 17.0,
			"%s is not an adult" % npc_id)


func test_relationship_targets_exist() -> void:
	for npc_id in data.ids("npcs"):
		for tie in data.get_entry("npcs", npc_id).get("relationships", []):
			var target := str(tie.get("to", ""))
			assert_true(data.has_entry("npcs", target),
				"%s points at unknown person '%s'" % [npc_id, target])


func test_schedules_cover_every_hour_of_every_day() -> void:
	for schedule_id in data.ids("schedules"):
		var schedule := NpcSchedule.from_data(data.get_entry("schedules", schedule_id))
		for day in range(7):
			for hour in range(24):
				var resolved := schedule.resolve(day, hour * 60)
				assert_ne(str(resolved["location"]), "",
					"%s has a gap on day %d at %02d:00" % [schedule_id, day, hour])


func test_schedule_location_tokens_are_known() -> void:
	for schedule_id in data.ids("schedules"):
		for block in data.get_entry("schedules", schedule_id).get("blocks", []):
			var location := str(block.get("location", ""))
			if NpcSchedule.is_token(location):
				assert_true(location in [NpcSchedule.TOKEN_HOME, NpcSchedule.TOKEN_WORK],
					"%s uses unknown token '%s'" % [schedule_id, location])


func test_backgrounds_grant_only_real_items_and_skills() -> void:
	for background_id in data.ids("backgrounds"):
		var background := data.get_entry("backgrounds", background_id)
		for entry in background.get("items", []):
			assert_true(data.has_entry("items", str(entry.get("id", ""))),
				"%s grants unknown item '%s'" % [background_id, entry.get("id")])
		for skill_id in background.get("skills", {}):
			assert_true(data.has_entry("skills", str(skill_id)),
				"%s grants unknown skill '%s'" % [background_id, skill_id])
		for contact in background.get("contacts", []):
			assert_true(data.has_entry("npcs", str(contact)),
				"%s grants unknown contact '%s'" % [background_id, contact])


func test_backgrounds_differ_meaningfully() -> void:
	# Four starts that all begin the same way are one start with four names.
	var cash_values := {}
	var contact_sets := {}
	for background_id in data.ids("backgrounds"):
		var background := data.get_entry("backgrounds", background_id)
		cash_values[int(background.get("cash", 0))] = true
		contact_sets[JSON.stringify(background.get("contacts", []))] = true
	assert_gt(float(cash_values.size()), 2.0)
	assert_gt(float(contact_sets.size()), 2.0)


func test_at_least_one_region_is_open_at_the_start() -> void:
	var open_count := 0
	for region_id in data.ids("regions"):
		if data.get_entry("regions", region_id).get("unlock", []).is_empty():
			open_count += 1
	assert_gt(float(open_count), 0.0, "the player must be able to stand somewhere")


func test_region_neighbours_are_mutual() -> void:
	for region_id in data.ids("regions"):
		for neighbour_id in data.get_entry("regions", region_id).get("neighbours", []):
			var neighbour := data.get_entry("regions", str(neighbour_id))
			assert_false(neighbour.is_empty(), "%s borders unknown region" % region_id)
			assert_has(neighbour.get("neighbours", []), region_id,
				"%s lists %s as a neighbour but not the reverse" % [region_id, neighbour_id])


func test_malformed_entries_are_dropped_not_fatal() -> void:
	var registry := DataRegistry.new()
	registry.tables["regions"] = {}
	registry._load_table("regions")
	assert_eq(registry.load_errors.size(), 0)


func test_find_by_filters() -> void:
	var homes := data.find_by("locations", "kind", "home")
	assert_gt(float(homes.size()), 3.0)
