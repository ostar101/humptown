extends TestCase
## Walkable upper floors: DistrictMap.storey, the `stairs` object, and
## Game._change_floor() — climbing and descending, refused past either end,
## and the ordinary ground-floor door left untouched by any of it.
##
## No real building has an upper floor yet (that is downtown's job); a second
## floor is attached to an existing test building at runtime, the same way
## content will attach one through data/interiors.json later.

func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)


func _outside() -> DistrictMap:
	return Game.world.map_for("harbourside")


func _shop_ground() -> DistrictMap:
	return Game.world.interior_for("loc_corner_shop")


func _stand(cell: Vector2i) -> void:
	assert_ok(Game.move_player(DistrictMap.cell_to_world(cell)))


func _enter_shop() -> void:
	var outside := _outside()
	_stand(outside.anchor_of("loc_corner_shop"))
	assert_ok(Game.interact_at(outside.buildings["loc_corner_shop"]["door"]))


## A second floor over the corner shop, built the way real content will, but
## attached directly to the running world rather than through
## data/interiors.json — proving the mechanic before any building needs it.
func _add_floor_two() -> DistrictMap:
	var built := DistrictMap.from_data({
		"id": "test_shop_floor_2", "interior_of": "loc_corner_shop", "floor": 2,
		"width": 6, "height": 6, "fill": "floor", "door": [3, 5],
	})
	assert_ok(built)
	var floor2: DistrictMap = built.value
	Game.world.interiors[DistrictMap.floor_key("loc_corner_shop", 2)] = floor2
	return floor2


func test_climbing_and_descending_moves_the_player_between_floors() -> void:
	_enter_shop()
	var ground := _shop_ground()
	var floor2 := _add_floor_two()
	var stairs_cell := ground.entry_cell() + Vector2i.RIGHT
	ground.objects[stairs_cell] = {"id": "obj_test_stairs", "kind": "stairs", "text_key": "", "sets_flag": ""}

	_stand(ground.entry_cell())
	var up := Game.interact_at(stairs_cell)
	assert_ok(up)
	assert_eq((up.value as Dictionary)["kind"], "climbed")
	assert_eq(Game.player.interior, "loc_corner_shop#2")
	assert_eq(Game.player.location, "loc_corner_shop", "still the same building")
	assert_eq(Game.current_map(), floor2)
	assert_eq(DistrictMap.world_to_cell(Game.player.position), floor2.entry_cell())

	var down := Game.interact_at(floor2.exit_door)
	assert_ok(down)
	assert_eq((down.value as Dictionary)["kind"], "descended")
	assert_eq(Game.player.interior, "loc_corner_shop")
	assert_eq(Game.current_map(), ground)
	assert_eq(DistrictMap.world_to_cell(Game.player.position), ground.entry_cell())


func test_the_upper_floor_door_prompts_and_acts_as_stairs_down() -> void:
	_enter_shop()
	_add_floor_two()
	Game.player.interior = "loc_corner_shop#2"
	var floor2 := Game.current_map()
	assert_eq(Game.interaction_at(floor2.exit_door)["kind"], "stairs_down")


func test_a_ground_floor_door_still_leaves_to_the_region_unchanged() -> void:
	_enter_shop()
	var ground := _shop_ground()
	assert_eq(Game.interaction_at(ground.exit_door)["kind"], "exit", "ground floor: still a plain exit")
	var result := Game.interact_at(ground.exit_door)
	assert_ok(result)
	assert_eq((result.value as Dictionary)["kind"], "exited")
	assert_eq(Game.player.interior, "")


## Up the corner shop's stairs to the test's second floor.
func _climb_to_floor_two() -> DistrictMap:
	var ground := _shop_ground()
	var floor2 := _add_floor_two()
	var stairs_cell := ground.entry_cell() + Vector2i.RIGHT
	ground.objects[stairs_cell] = {"id": "obj_test_stairs", "kind": "stairs", "text_key": "", "sets_flag": ""}
	_stand(ground.entry_cell())
	assert_ok(Game.interact_at(stairs_cell))
	assert_eq(Game.player.interior, "loc_corner_shop#2")
	return floor2


## D-097: a floor key is never a place. floor_key()'s inverse gives back the
## building, which is what anything asking "where is the player" compares.
func test_every_floor_key_belongs_to_its_building() -> void:
	assert_eq(DistrictMap.building_of("loc_corner_shop"), "loc_corner_shop")
	assert_eq(DistrictMap.building_of(DistrictMap.floor_key("loc_corner_shop", 3)), "loc_corner_shop")
	assert_eq(DistrictMap.building_of(""), "")
	_enter_shop()
	_climb_to_floor_two()
	assert_eq(Game.player.interior_base(), "loc_corner_shop")


## Someone walking with the player goes upstairs with them into the same
## building — a real Location — never into "loc_corner_shop#2", which is not one.
func test_someone_walking_with_the_player_follows_them_upstairs() -> void:
	_enter_shop()
	Game.director.follow_location = Game.follow_location()
	assert_true(Game.director.start_follow("npc_ida", 60))
	_climb_to_floor_two()
	var ida := Game.npcs.get_npc("npc_ida")
	assert_eq(ida.location, "loc_corner_shop")
	assert_true(Game.world.get_location(ida.location) != null, "a follower stands somewhere real")


## Anyone at the building is in the room on whichever floor the player is on
## (their body is drawn there, NpcBodies reads interior_of); talking to them
## must agree. Someone elsewhere is still nobody there.
func test_someone_in_the_building_can_be_talked_to_upstairs() -> void:
	_enter_shop()
	_climb_to_floor_two()
	Game.npcs.move_to("npc_ida", "loc_corner_shop")
	Game.npcs.get_npc("npc_ida").activity = "idle"
	assert_ok(Game.dialogue.can_talk_to("npc_ida"))
	Game.npcs.move_to("npc_ida", "loc_dock_street")
	assert_err(Game.dialogue.can_talk_to("npc_ida"), "nobody_there")


func test_climbing_past_the_top_floor_is_refused() -> void:
	_enter_shop()
	assert_err(Game._change_floor({}, 1), "no_such_floor", "no floor 2 exists for this building")
	assert_eq(Game.player.interior, "loc_corner_shop", "a refusal changes nothing")


func test_descending_below_the_ground_floor_is_refused() -> void:
	_enter_shop()
	assert_err(Game._change_floor({}, -1), "no_such_floor", "floor 1's own way down is the door, not this")
	assert_eq(Game.player.interior, "loc_corner_shop")


func test_a_composite_floor_key_survives_a_save_round_trip_with_no_migration() -> void:
	Game.player.interior = "loc_corner_shop#2"
	var copy := PlayerState.new()
	copy.from_dict(Game.player.to_dict())
	assert_eq(copy.interior, "loc_corner_shop#2")
	assert_eq(SaveMigrations.CURRENT_VERSION, 13, "the floor mechanic needed no new save version")


# --- real content: downtown's towers (D-093, D-095) --------------------------
## Both towers are semi_public and walk-in; the two apartment blocks are
## private homes now lived in (D-095), so they are not climbed here — only
## confirmed still correctly locked to a stranger at the door, same as any
## other resident's flat.

const DOWNTOWN_TOWERS := {"loc_downtown_tower_a": 4, "loc_downtown_tower_b": 6}


func _walk_to_exit(from_region: String, to: String) -> Result:
	var map := Game.world.map_for(from_region)
	for e in map.exits:
		if str(e["to"]) == to:
			return Game.move_player(DistrictMap.cell_to_world((e["rect"] as Rect2i).position))
	fail("no exit from %s to %s" % [from_region, to])
	return Result.failure("test_setup")


func _enter_downtown(location_id: String) -> void:
	assert_ok(_walk_to_exit("harbourside", "downtown"))
	var outside := Game.world.map_for("downtown")
	var door: Vector2i = outside.buildings[location_id]["door"]
	_stand(outside.anchor_of(location_id))
	assert_ok(Game.interact_at(door))


func test_every_downtown_tower_can_be_climbed_to_the_top_and_back() -> void:
	for location_id: String in DOWNTOWN_TOWERS:
		var top: int = DOWNTOWN_TOWERS[location_id]
		_enter_downtown(location_id)
		assert_eq(Game.player.interior, location_id, "%s: starts on the ground floor" % location_id)
		for floor_n in range(2, top + 1):
			_stand(Vector2i(2, 2))   # beside the stairs; every floor uses the same 6x6 layout
			var up := Game.interact_at(Vector2i(1, 2))
			assert_ok(up, "%s: climb to floor %d" % [location_id, floor_n])
			assert_eq((up.value as Dictionary)["floor"], floor_n)
			assert_eq(Game.player.interior, "%s#%d" % [location_id, floor_n])
			assert_eq(DistrictMap.world_to_cell(Game.player.position), Game.current_map().entry_cell())
		var top_map := Game.current_map()
		assert_eq(top_map.storey, top, "%s: reached the top floor" % location_id)
		assert_eq(Game.interaction_at(top_map.exit_door)["kind"], "stairs_down", "%s: no stairs up from the top" % location_id)

		for floor_n in range(top, 1, -1):
			_stand(Game.current_map().entry_cell())
			var down := Game.interact_at(Game.current_map().exit_door)
			assert_ok(down, "%s: descend from floor %d" % [location_id, floor_n])
		assert_eq(Game.player.interior, location_id, "%s: back on the ground floor" % location_id)

		_stand(Game.current_map().entry_cell())
		var left := Game.interact_at(Game.current_map().exit_door)
		assert_ok(left)
		assert_eq((left.value as Dictionary)["kind"], "exited")
		assert_eq(Game.player.interior, "", "%s: back outside" % location_id)


func test_downtowns_apartment_blocks_stay_private_to_a_stranger() -> void:
	for location_id: String in ["loc_downtown_flats_a", "loc_downtown_flats_b"]:
		assert_ok(_walk_to_exit("harbourside", "downtown"))
		var outside := Game.world.map_for("downtown")
		var door: Vector2i = outside.buildings[location_id]["door"]
		_stand(outside.anchor_of(location_id))
		assert_err(Game.interact_at(door), "private", location_id)
		assert_eq(Game.player.interior, "")
