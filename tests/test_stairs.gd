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
