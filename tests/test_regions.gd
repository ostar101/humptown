extends TestCase
## The next districts, Old Town and Eastfield (D-072): how the way opens, what
## the walk costs, where you arrive, who lives there and what they sell.

var _refused: Array[String] = []
var _travelled: Array[String] = []


func before_each() -> void:
	Game.new_game("bg_dockhand", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_refused = []
	_travelled = []
	Events.region_refused.connect(_on_refused)
	Events.player_travelled.connect(_on_travelled)


func after_each() -> void:
	Events.region_refused.disconnect(_on_refused)
	Events.player_travelled.disconnect(_on_travelled)
	Game.saves.delete_slot("test_regions")


func _on_refused(_region: String, reason: String) -> void:
	_refused.append(reason)


func _on_travelled(region: String, _minutes: int) -> void:
	_travelled.append(region)


func _exit_cell(map: DistrictMap, to: String) -> Vector2i:
	for e in map.exits:
		if str(e["to"]) == to:
			return (e["rect"] as Rect2i).position
	fail("no exit to %s on %s" % [to, map.id])
	return Vector2i.ZERO


func _walk_to_exit(from_region: String, to: String) -> Result:
	var map := Game.world.map_for(from_region)
	return Game.move_player(DistrictMap.cell_to_world(_exit_cell(map, to)))


func _activity(npc_id: String, minute_of_day: int, day: int) -> String:
	var npc := Game.npcs.get_npc(npc_id)
	return str(Game.npcs.schedule_for(npc).resolve(day, minute_of_day).get("activity", ""))


# --- the way opens by what it asks ----------------------------------------------------------------

func test_old_town_is_open_from_the_start() -> void:
	assert_ok(_walk_to_exit("harbourside", "old_town"))
	assert_eq(_refused, [] as Array[String])
	assert_eq(Game.player.region, "old_town")


func test_the_bus_timetable_can_still_be_read() -> void:
	# The sign is flavour now, not a gate (D-077): reading it costs nothing
	# and the road was always open.
	var map := Game.world.map_for("harbourside")
	var timetable := {}
	for cell: Vector2i in map.objects:
		if str(map.objects[cell]["id"]) == "obj_bus_timetable":
			timetable = map.objects[cell]
	assert_false(timetable.is_empty())
	assert_eq(timetable["sets_flag"], "heard_about_old_town")
	Game.player.position = DistrictMap.cell_to_world(Vector2i(45, 22))
	var read := Game.interact_at(Vector2i(46, 22))
	assert_ok(read)
	assert_eq(read.value["kind"], "read")
	assert_true(Game.world.has_flag("heard_about_old_town"))


func test_eastfield_is_open_with_no_money_and_no_contact() -> void:
	Game.player.wallet.cash = 10
	Game.player.wallet.bank = 0
	Game.player.known_contacts.erase("npc_veikko")
	assert_ok(_walk_to_exit("harbourside", "eastfield"))
	assert_eq(_refused, [] as Array[String])


# --- walking between them --------------------------------------------------------------------------

func test_the_walk_takes_as_long_as_the_road() -> void:
	Game.world.set_flag("heard_about_old_town")
	var before := Game.clock.total_minutes
	var made := _walk_to_exit("harbourside", "old_town")
	assert_ok(made)
	assert_eq(made.value["minutes"], 9)
	assert_eq(Game.clock.total_minutes - before, 9)
	assert_eq(_travelled, ["old_town"] as Array[String])
	assert_eq(Game.world.current_region, "old_town")
	assert_true(Game.world.regions["old_town"].discovered)


func test_you_arrive_by_the_road_you_came_in_on_and_not_on_the_exit() -> void:
	Game.world.set_flag("heard_about_old_town")
	assert_ok(_walk_to_exit("harbourside", "old_town"))
	var here := DistrictMap.world_to_cell(Game.player.position)
	var map := Game.world.map_for("old_town")
	assert_eq(map.exit_at(here), "", "not on an exit, or you would walk straight back")
	assert_false(map.is_blocked(here))
	assert_lt(absf(float(here.x - 44)), 3.0, "on the south road, where the road from Harbourside comes in")
	assert_gt(float(here.y), 60.0)
	assert_ok(_walk_to_exit("old_town", "harbourside"))
	assert_eq(Game.player.region, "harbourside")
	var back := DistrictMap.world_to_cell(Game.player.position)
	assert_lt(float(back.y), 8.0, "at the top of the north road")


func test_old_town_and_eastfield_are_joined() -> void:
	Game.world.set_flag("heard_about_old_town")
	Game.player.wallet.cash = 500
	Game.player.add_contact("npc_veikko")
	assert_ok(_walk_to_exit("harbourside", "old_town"))
	assert_ok(_walk_to_exit("old_town", "eastfield"))
	assert_eq(Game.player.region, "eastfield")
	var arrived := DistrictMap.world_to_cell(Game.player.position)
	assert_lt(float(arrived.x), 8.0, "in from the west edge")
	assert_lt(float(arrived.y), 20.0, "on the northern road, the one from Old Town")
	assert_ok(_walk_to_exit("eastfield", "harbourside"))
	assert_eq(Game.player.region, "harbourside")
	assert_gt(float(DistrictMap.world_to_cell(Game.player.position).x), 88.0, "the east end of Dock Street")


func test_downtown_is_joined_to_its_neighbours() -> void:
	assert_ok(_walk_to_exit("harbourside", "downtown"))
	assert_eq(Game.player.region, "downtown")
	assert_ok(_walk_to_exit("downtown", "old_town"))
	assert_eq(Game.player.region, "old_town")
	assert_ok(_walk_to_exit("old_town", "downtown"))
	assert_eq(Game.player.region, "downtown")
	assert_ok(_walk_to_exit("downtown", "harbourside"))
	assert_eq(Game.player.region, "harbourside")


func test_people_are_sorted_by_where_you_now_are() -> void:
	Game.world.set_flag("heard_about_old_town")
	assert_ok(_walk_to_exit("harbourside", "old_town"))
	var here := Game.npcs.ids_in_regions(["old_town"] as Array[String])
	assert_gt(float(here.size()), 3.0, "Old Town has people of its own")
	var somebody_awake := false
	for npc_id: String in here:
		if Game.npcs.get_npc(npc_id).tier >= SimLod.Tier.ACTIVE:
			somebody_awake = true
	assert_true(somebody_awake or Game.clock.minute_of_day() < 6 * 60, "those up and about here are simulated in detail now")


func test_the_open_regions_are_saved() -> void:
	Game.world.set_flag("heard_about_old_town")
	assert_ok(_walk_to_exit("harbourside", "old_town"))
	assert_ok(Game.save_game("test_regions"))
	Game.world.regions["old_town"].unlocked = false
	assert_ok(Game.load_game("test_regions"))
	assert_true(Game.world.regions["old_town"].unlocked)
	assert_eq(Game.player.region, "old_town")


# --- what is there ----------------------------------------------------------------------------------

## Name predates downtown (D-091/D-092): "both" now means three districts.
func test_every_place_in_both_districts_is_on_its_map() -> void:
	for region: String in ["old_town", "eastfield", "downtown"]:
		var map := Game.world.map_for(region)
		assert_true(map != null, region)
		for location_id: String in Game.world.locations_in(region):
			assert_true(map.has_location(location_id), "%s is not on the %s map" % [location_id, region])


func test_the_new_buildings_are_the_size_the_drawn_art_needs() -> void:
	for region: String in ["old_town", "eastfield", "downtown"]:
		var map := Game.world.map_for(region)
		for location_id: String in map.buildings:
			var kind := map.kind_of(location_id)
			var rect: Rect2i = map.buildings[location_id]["rect"]
			var door: Vector2i = map.buildings[location_id]["door"]
			var art := BuildingArt.art_kind(kind, location_id)
			assert_eq(rect.size, BuildingArt.footprint(art), "%s is the wrong size for its art" % location_id)
			assert_eq(door.x - rect.position.x, BuildingArt.door_column(art), "%s: door is not where the art draws it" % location_id)


func test_every_new_person_lives_and_works_in_their_own_district() -> void:
	for npc_id: String in ["npc_aarne", "npc_helmi", "npc_tapio", "npc_ilona", "npc_oskar",
			"npc_reijo", "npc_pauliina", "npc_jari", "npc_marko", "npc_kimmo",
			"npc_saana", "npc_iiro", "npc_taina", "npc_venla",
			"npc_raili", "npc_tomi", "npc_marja", "npc_lauri"]:
		var npc := Game.npcs.get_npc(npc_id)
		assert_true(npc != null, npc_id)
		var region := Game.world.region_of(npc.home)
		assert_true(region in ["old_town", "eastfield", "downtown"], npc_id)
		if npc.workplace != "":
			assert_eq(Game.world.region_of(npc.workplace), region, "%s works elsewhere" % npc_id)
		for day in 7:
			for hour in 24:
				var where := Game.npcs.scheduled_location_of(npc_id, day * 1440 + hour * 60, day)
				assert_eq(Game.world.region_of(where), region, "%s leaves their district at %02d:00 on day %d (%s)" % [npc_id, hour, day, where])


## D-103: every person, not just a list of them. D-088 reused three schedules
## that name Harbourside's own places, and eight people in Old Town and
## Eastfield spent every day in Harbourside because nothing walked them all.
func test_nobody_spends_their_ordinary_week_outside_their_own_district() -> void:
	for npc_id: String in Game.data.ids("npcs"):
		var npc := Game.npcs.get_npc(npc_id)
		var home_region := Game.world.region_of(npc.home)
		var work_region := Game.world.region_of(npc.workplace) if npc.workplace != "" else home_region
		var strays: Array[String] = []
		for day in 7:
			for hour in 24:
				var where := Game.npcs.scheduled_location_of(npc_id, day * 1440 + hour * 60, day)
				var region := Game.world.region_of(where)
				if region != home_region and region != work_region:
					strays.append("%s at %02d:00 day %d" % [where, hour, day])
		assert_true(strays.is_empty(), "%s (%s) leaves: %s" % [npc_id, home_region, ", ".join(strays.slice(0, 3))])


## Every shop with a counter, every day of the week (D-104; it once checked
## a list of shops on a Wednesday, and five were open with nobody in them on
## a weekend). A closed day is not an open hour, so it needs no staff.
func test_every_shop_has_someone_behind_the_counter_whenever_open() -> void:
	for shop_id: String in Game.data.ids("shops"):
		var entry: Dictionary = Game.data.get_entry("shops", shop_id)
		if not entry.has("location"):
			continue   # a kept shop is wherever its keeper is (D-084)
		var location_id := str(entry["location"])
		var location := Game.world.get_location(location_id)
		var staff: Array[String] = []
		for npc_id: String in Game.npcs.living_ids():
			if Game.npcs.get_npc(npc_id).workplace == location_id:
				staff.append(npc_id)
		for day in 7:
			var open_slots := 0
			var staffed_slots := 0
			for minute in range(0, 1440, 30):
				if not location.is_open_at(minute, day):
					continue
				open_slots += 1
				for npc_id in staff:
					if Game.npcs.scheduled_location_of(npc_id, day * 1440 + minute, day) == location_id 							and _activity(npc_id, minute, day) == "work":
						staffed_slots += 1
						break
			# a lunch hour without anyone is how a small shop is, but not a whole afternoon
			assert_true(staffed_slots >= open_slots * 0.8, "%s is open on day %d with nobody behind the counter for too long (%d of %d half-hours)" % [shop_id, day, staffed_slots, open_slots])


## Nobody's day takes them to a place on the day it is shut (D-104): they
## would stand inside a building the player cannot enter.
func test_nobody_is_sent_to_a_place_on_its_closed_day() -> void:
	for npc_id: String in Game.data.ids("npcs"):
		var strays: Array[String] = []
		for day in 7:
			for hour in 24:
				var where := Game.npcs.scheduled_location_of(npc_id, day * 1440 + hour * 60, day)
				var location := Game.world.get_location(where)
				if location != null and location.is_closed_on(day, hour * 60):
					strays.append("%s at %02d:00 day %d" % [where, hour, day])
		assert_true(strays.is_empty(), "%s: %s" % [npc_id, ", ".join(strays.slice(0, 3))])


func test_the_pawn_shop_can_now_be_reached_and_entered() -> void:
	Game.world.set_flag("heard_about_old_town")
	assert_ok(_walk_to_exit("harbourside", "old_town"))
	var map := Game.world.map_for("old_town")
	var door: Vector2i = map.buildings["loc_pawn_shop"]["door"]
	Game.clock.advance(posmod(12 * 60 - Game.clock.minute_of_day(), 1440))   # noon, inside its hours
	Game.player.position = DistrictMap.cell_to_world(door + Vector2i.DOWN)
	var entered := Game.interact_at(door)
	assert_ok(entered)
	assert_eq(Game.player.interior, "loc_pawn_shop")


func test_the_jobs_out_there_are_real() -> void:
	assert_true(bool(Game.data.get_entry("jobs", "job_eastfield_yard")["casual"]))
	assert_eq(Game.data.get_entry("jobs", "job_bakery")["employer"], "npc_helmi")
	assert_eq(Game.data.get_entry("jobs", "job_eastfield_yard")["workplace"], "loc_eastfield_yard")
