extends TestCase
## Player movement: the rule (Game.move_player) and the body (PlayerBody in a
## real World scene, stepped with real physics frames).

const WORLD_SCENE := "res://scenes/world/world.tscn"
## Physics tests run eight times faster than real time. Ticks per second rise
## by the same factor, so each physics step is exactly the game's own
## 1/30 s: the same collision behaviour, in an eighth of the wait.
const SPEED_UP := 8
const GAME_TICKS := 30

var _rejections: Array = []
var _entered: Array[String] = []


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	_rejections = []
	_entered = []
	Events.action_rejected.connect(_on_rejected)
	Events.location_entered.connect(_on_entered)
	Engine.time_scale = SPEED_UP
	Engine.physics_ticks_per_second = GAME_TICKS * SPEED_UP
	Engine.max_physics_steps_per_frame = 16


func after_each() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = GAME_TICKS
	Engine.max_physics_steps_per_frame = 8
	Events.action_rejected.disconnect(_on_rejected)
	Events.location_entered.disconnect(_on_entered)


func _on_rejected(proposal: Dictionary, code: String) -> void:
	_rejections.append([proposal, code])


func _on_entered(actor: String, location_id: String) -> void:
	if actor == PlayerState.ID:
		_entered.append(location_id)


func _map() -> DistrictMap:
	return Game.world.map_for("harbourside")


# --- the rule ---------------------------------------------------------------

func test_moving_onto_open_ground_is_accepted_and_sets_location() -> void:
	var street := DistrictMap.cell_to_world(_map().anchor_of("loc_dock_street"))
	var result := Game.move_player(street)
	assert_ok(result)
	assert_eq(Game.player.location, "loc_dock_street")
	assert_eq(Game.player.position, street)
	assert_true(_entered.has("loc_dock_street"))


func test_moving_into_a_wall_is_refused_and_changes_nothing() -> void:
	var before := Game.player.position
	var before_location := Game.player.location
	var door: Vector2i = _map().buildings["loc_corner_shop"]["door"]
	var result := Game.move_player(DistrictMap.cell_to_world(door))
	assert_err(result, "cell_blocked")
	assert_eq(Game.player.position, before)
	assert_eq(Game.player.location, before_location)
	assert_eq(_rejections.size(), 1)
	assert_eq(_rejections[0][1], "cell_blocked")


func test_moving_into_water_or_off_the_map_is_refused() -> void:
	assert_err(Game.move_player(DistrictMap.cell_to_world(Vector2i(10, 60))), "cell_blocked")
	assert_err(Game.move_player(Vector2(-50, 100)), "cell_blocked")


func test_moving_in_an_unmapped_region_is_refused() -> void:
	Game.player.region = "old_town"
	assert_err(Game.move_player(Vector2(100, 100)), "region_unmapped")


# --- region exits -------------------------------------------------------

## Harbourside's own exits (data/maps.json), by destination.
func _exit_cell(to: String) -> Vector2i:
	for e in _map().exits:
		if str(e["to"]) == to:
			var rect: Rect2i = e["rect"]
			return rect.position
	fail("no exit to %s on harbourside" % to)
	return Vector2i.ZERO


func test_walking_onto_an_exit_to_a_locked_region_is_refused() -> void:
	assert_false(Game.world.regions["old_town"].unlocked, "unlocked by default would invalidate this test")
	var before := Game.player.position
	var result := Game.move_player(DistrictMap.cell_to_world(_exit_cell("old_town")))
	assert_err(result, "region_locked")
	assert_eq(Game.player.position, before, "a refused travel changes nothing")
	assert_eq(Game.player.region, "harbourside")


func test_walking_onto_an_exit_to_an_unlocked_but_unmapped_region_is_refused() -> void:
	Game.world.regions["old_town"].unlocked = true
	assert_err(Game.move_player(DistrictMap.cell_to_world(_exit_cell("old_town"))), "region_unmapped")
	assert_eq(Game.player.region, "harbourside", "still nowhere to go")


func test_walking_onto_an_exit_to_an_unlocked_mapped_region_travels_there() -> void:
	Game.world.regions["old_town"].unlocked = true
	var built := DistrictMap.from_data({
		"id": "old_town", "region": "old_town", "width": 10, "height": 10,
		"fill": "grass", "spawn": [3, 3],
		"places": [{"location": "loc_test_square", "rects": [[0, 0, 10, 10]]}],
	})
	assert_ok(built)
	Game.world.maps["old_town"] = built.value

	var result := Game.move_player(DistrictMap.cell_to_world(_exit_cell("old_town")))
	assert_ok(result)
	assert_eq(result.value, {"kind": "travelled", "region": "old_town"})
	assert_eq(Game.player.region, "old_town")
	assert_eq(Game.player.position, DistrictMap.cell_to_world(Vector2i(3, 3)), "placed at the new map's spawn")
	assert_eq(Game.player.location, "loc_test_square")
	assert_true(_entered.has("loc_test_square"))


func test_open_town_ground_belongs_to_no_location() -> void:
	# A grass cell between houses: in the region, at no particular place.
	var result := Game.move_player(DistrictMap.cell_to_world(Vector2i(2, 16)))
	assert_ok(result)
	assert_eq(Game.player.location, "")


func test_start_position_prefers_a_valid_saved_position() -> void:
	var saved := DistrictMap.cell_to_world(Vector2i(20, 30))
	Game.player.position = saved
	assert_eq(Game.player_start_position(), saved)


func test_start_position_falls_back_to_the_location_anchor() -> void:
	Game.player.position = Vector2.ZERO
	Game.player.location = "loc_corner_shop"
	assert_eq(Game.player_start_position(),
		DistrictMap.cell_to_world(_map().anchor_of("loc_corner_shop")))
	# A saved position that is now inside a wall is not trusted.
	var door: Vector2i = _map().buildings["loc_corner_shop"]["door"]
	Game.player.position = DistrictMap.cell_to_world(door)
	assert_eq(Game.player_start_position(),
		DistrictMap.cell_to_world(_map().anchor_of("loc_corner_shop")))


func test_position_survives_a_save_round_trip() -> void:
	Game.player.position = Vector2(123.5, 456.0)
	var copy := PlayerState.new()
	copy.from_dict(Game.player.to_dict())
	assert_eq(copy.position, Vector2(123.5, 456.0))


func test_facing_is_four_way_with_horizontal_winning_ties() -> void:
	assert_eq(PlayerBody.facing_for(Vector2(1, 0)), Vector2i.RIGHT)
	assert_eq(PlayerBody.facing_for(Vector2(-0.2, 0.9)), Vector2i.DOWN)
	assert_eq(PlayerBody.facing_for(Vector2(0, -1)), Vector2i.UP)
	assert_eq(PlayerBody.facing_for(Vector2(-1, 1)), Vector2i.LEFT)


# --- the body, with real physics --------------------------------------------

func _spawn_world() -> WorldView:
	var tree := Engine.get_main_loop() as SceneTree
	var packed: PackedScene = load(WORLD_SCENE)
	var view: WorldView = packed.instantiate()
	tree.root.add_child(view)
	return view


## Advances this many seconds of game time, one real physics step at a time.
func _step(seconds: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i in ceili(seconds * GAME_TICKS):
		await tree.physics_frame


func test_body_walks_along_the_street_and_the_rules_follow() -> void:
	var view := _spawn_world()
	var body := view.player_body()
	var start := body.position
	body.scripted_direction = Vector2.RIGHT
	await _step(1.4)
	body.scripted_direction = Vector2.ZERO
	await _step(0.1)
	assert_gt(body.position.x - start.x, 32.0, "moved at least a cell")
	assert_eq(DistrictMap.world_to_cell(Game.player.position), body.current_cell(),
		"Game knows which cell the body is in")
	assert_gt(float(view.region_view().resident_chunk_count()), 0.0)
	view.free()


func test_body_cannot_walk_through_a_house() -> void:
	var view := _spawn_world()
	var body := view.player_body()
	# Stand in front of the player's own door and walk straight at it.
	var anchor := _map().anchor_of("loc_player_flat")
	body.place_at(DistrictMap.cell_to_world(anchor))
	body.scripted_direction = Vector2.UP
	await _step(1.5)
	body.scripted_direction = Vector2.ZERO
	assert_false(_map().is_blocked(DistrictMap.world_to_cell(body.position)),
		"the body never stands inside a structure")
	assert_eq(body.current_cell().y, anchor.y, "stopped at the wall")
	assert_eq(_rejections.size(), 0, "physics kept it out; the rule never had to")
	view.free()


## Walks the body from `from` in `direction` for a while and returns where it ends up.
func _walk(body: PlayerBody, from: Vector2i, direction: Vector2, seconds: float) -> Vector2i:
	body.place_at(DistrictMap.cell_to_world(from))
	body.scripted_direction = direction
	await _step(seconds)
	body.scripted_direction = Vector2.ZERO
	return body.current_cell()


## D-065: a house collides where its roof is drawn, not where its grid
## rectangle ends. Needs the art installed, like the drawing does.
func _house() -> Rect2i:
	var rect: Rect2i = _map().buildings["loc_ida_flat"]["rect"]
	return rect if BuildingArt.sprite_for(_map().kind_of("loc_ida_flat"), "loc_ida_flat", rect.size) != "" else Rect2i()


func test_body_stops_at_the_ridge_from_behind() -> void:
	var rect := _house()
	if rect.size == Vector2i.ZERO:
		return   # no art installed: the footprint is a plain rectangle, tested above
	var view := _spawn_world()
	var end := await _walk(view.player_body(), Vector2i(rect.position.x + rect.size.x / 2, rect.position.y - 1), Vector2.DOWN, 1.5)
	assert_lt(float(end.y), float(rect.position.y + 1), "stopped at the ridge, the roof's highest edge")
	assert_true(_map().allows_body(end))
	assert_eq(_rejections.size(), 0)
	view.free()


func test_body_walks_into_the_bare_corner_and_stops_at_the_slope() -> void:
	var rect := _house()
	if rect.size == Vector2i.ZERO:
		return
	var view := _spawn_world()
	var end := await _walk(view.player_body(), Vector2i(rect.position.x, rect.position.y - 1), Vector2.DOWN, 1.5)
	assert_gt(float(end.y), float(rect.position.y - 1), "the corner the roof leaves clear is open ground")
	assert_lt(float(end.y), float(rect.end.y - 3), "but not the roof below it")
	assert_true(_map().allows_body(end), "the rule accepts a cell the art leaves partly clear")
	assert_eq(_map().location_at(end), "", "it is not inside the house")
	assert_eq(_rejections.size(), 0, "physics and the rule agree")
	view.free()


func test_body_stops_at_the_roofs_side() -> void:
	var rect := _house()
	if rect.size == Vector2i.ZERO:
		return
	var view := _spawn_world()
	var end := await _walk(view.player_body(), Vector2i(rect.position.x - 2, rect.position.y + 4), Vector2.RIGHT, 1.5)
	assert_lt(float(end.x), float(rect.position.x + 1), "stopped at the roof's side")
	assert_eq(_rejections.size(), 0)
	view.free()


## D-066: a street lamp's foot stops the body, the way a wall does.
func test_body_cannot_walk_through_a_lamp_post() -> void:
	if not StreetProps.available():
		return
	var lamp := Vector2i(-1, -1)
	for prop: Dictionary in StreetProps.props_in(_map(), Rect2i(Vector2i.ZERO, _map().size)):
		var cell: Vector2i = prop["cell"]
		if prop["kind"] == "lamp" and cell.x == 41 and not _map().is_blocked(cell + Vector2i.LEFT):
			lamp = cell
			break
	assert_ne(lamp, Vector2i(-1, -1), "a lamp on the west kerb of the north road")
	var view := _spawn_world()
	var body := view.player_body()
	body.place_at(DistrictMap.cell_to_world(lamp + Vector2i.LEFT))
	body.scripted_direction = Vector2.RIGHT
	await _step(1.0)
	body.scripted_direction = Vector2.ZERO
	var foot_left := float(lamp.x) * DistrictMap.CELL_PIXELS + StreetProps.LAMP_FOOT.position.x
	assert_lt(body.position.x, foot_left, "stopped against the pole's foot")
	view.free()


func test_camera_lead_and_chunks_follow_the_player() -> void:
	var view := _spawn_world()
	var body := view.player_body()
	body.place_at(DistrictMap.cell_to_world(Vector2i(2, 29)))   # the back row of the pavement: lamps stand at the kerb row
	body.scripted_direction = Vector2.RIGHT
	body.scripted_running = true
	# Far enough that the start chunk is beyond the load radius plus margin.
	await _step(13.0)
	assert_gt(body.position.x, float(4 * DistrictMap.CHUNK_SIZE * DistrictMap.CELL_PIXELS))
	var focus_chunk := DistrictMap.chunk_of(body.current_cell())
	assert_true(view.region_view().is_chunk_resident(focus_chunk), "the chunk underfoot is drawn")
	assert_false(view.region_view().is_chunk_resident(Vector2i(0, 0)), "the start was released")
	view.free()
