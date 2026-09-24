extends TestCase
## Interaction: interiors as maps, the rules behind doors, counters, beds and
## signs (every refusal included), the words shown for them, and the World
## scene carrying the player in and out.

const WORLD_SCENE := "res://scenes/world/world.tscn"

var _rejections: Array = []


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	_rejections = []
	Events.action_rejected.connect(_on_rejected)


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)


func _on_rejected(proposal: Dictionary, code: String) -> void:
	_rejections.append([proposal, code])


func _outside() -> DistrictMap:
	return Game.world.map_for("harbourside")


func _inside(location_id: String) -> DistrictMap:
	return Game.world.interior_for(location_id)


## Puts the player on a cell of the map they are on, through the rule.
func _stand(cell: Vector2i) -> void:
	assert_ok(Game.move_player(DistrictMap.cell_to_world(cell)))


func _door(location_id: String) -> Vector2i:
	return _outside().buildings[location_id]["door"]


func _enter(location_id: String) -> Result:
	_stand(_outside().anchor_of(location_id))
	return Game.interact_at(_door(location_id))


func _set_time(minute_of_day: int) -> void:
	var now := Game.clock.minute_of_day()
	Game.advance_time(posmod(minute_of_day - now, GameClock.MINUTES_PER_DAY))


# --- interiors as maps ------------------------------------------------------

func test_an_interior_is_walled_with_one_door_and_the_building_as_its_floor() -> void:
	var shop := _inside("loc_corner_shop")
	assert_not_null(shop)
	assert_true(shop.is_interior())
	assert_eq(shop.region, "harbourside")
	for x in shop.size.x:
		assert_true(shop.is_blocked(Vector2i(x, 0)), "top wall")
		assert_true(shop.is_blocked(Vector2i(x, shop.size.y - 1)), "bottom wall")
	for y in shop.size.y:
		assert_true(shop.is_blocked(Vector2i(0, y)), "left wall")
		assert_true(shop.is_blocked(Vector2i(shop.size.x - 1, y)), "right wall")
	assert_eq(shop.structure_at(shop.exit_door), DistrictMap.Terrain.DOOR)
	assert_eq(shop.entry_cell(), shop.exit_door + Vector2i.UP)
	assert_eq(shop.location_at(shop.entry_cell()), "loc_corner_shop")
	assert_eq(shop.edge_cell(), shop.entry_cell(), "people come and go by the door")
	assert_eq(shop.object_at(Vector2i(6, 4))["kind"], "counter")


func _interior(extra: Dictionary) -> Result:
	var d := {"id": "t", "interior_of": "loc_t", "width": 6, "height": 6, "fill": "floor", "door": [3, 5]}
	d.merge(extra, true)
	return DistrictMap.from_data(d)


func test_interior_layout_mistakes_are_refused() -> void:
	assert_ok(_interior({}))
	assert_err(_interior({"door": [3, 4]}), "map_invalid")
	assert_err(_interior({"door": [0, 5]}), "map_invalid")
	assert_err(_interior({"width": 3}), "map_invalid")
	assert_err(_interior({"solids": [{"kind": "sofa", "rect": [1, 2, 1, 1]}]}), "map_invalid")
	assert_err(_interior({"solids": [{"kind": "table", "rect": [3, 4, 1, 1]}]}), "map_invalid",
		"furniture in front of the door")
	assert_err(_interior({"staff": [0, 3]}), "map_invalid")
	assert_err(_interior({"objects": [{"id": "o", "kind": "counter", "cell": [2, 3]}]}), "map_invalid",
		"a counter object needs furniture under it")
	assert_err(_interior({"objects": [{"id": "o", "kind": "juggle", "cell": [2, 3]}]}), "map_invalid")
	assert_err(_interior({
		"solids": [{"kind": "shelf", "rect": [1, 2, 4, 3]}],
		"objects": [{"id": "o", "kind": "counter", "cell": [2, 3]}],
	}), "map_invalid", "an object nobody can stand beside")


func test_every_enterable_building_has_an_interior_whose_parts_are_reachable() -> void:
	var outside := _outside()
	for location_id in outside.buildings:
		var location := Game.world.get_location(location_id)
		var enterable := location.is_public() and not location.is_locked()
		if location_id == Game.player.home_location:
			enterable = true
		if not enterable:
			continue
		var inside := _inside(location_id)
		assert_not_null(inside, "%s can be entered, so it needs an inside" % location_id)
		if inside == null:
			continue
		var reach := inside.reachable_from(inside.entry_cell())
		if inside.staff_cell.x >= 0:
			assert_true(reach.has(inside.staff_cell), "%s: staff can reach their spot" % location_id)
		for cell: Vector2i in inside.objects:
			var usable := false
			for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if reach.has(cell + step):
					usable = true
			assert_true(usable, "%s: object at %s can be used from the door side" % [location_id, cell])


func test_an_interior_of_an_unknown_or_unmapped_location_is_a_content_error() -> void:
	var data := DataRegistry.new()
	data.load_all()
	data.tables["interiors"]["int_bad"] = {"id": "int_bad", "interior_of": "loc_nowhere"}
	data.tables["interiors"]["int_square"] = {"id": "int_square", "interior_of": "loc_old_square"}
	var problems := "; ".join(data.validate_references())
	assert_true(problems.contains("loc_nowhere"))
	assert_true(problems.contains("loc_old_square"), "a location with no building cannot have an inside")


# --- doors ------------------------------------------------------------------

func test_entering_an_open_shop_from_its_door() -> void:
	var entered: Array[String] = []
	var on_entered := func(actor: String, loc: String) -> void:
		if actor == PlayerState.ID:
			entered.append(loc)
	Events.location_entered.connect(on_entered)
	var result := _enter("loc_corner_shop")
	Events.location_entered.disconnect(on_entered)

	assert_ok(result)
	assert_eq((result.value as Dictionary)["kind"], "entered")
	assert_eq(Game.player.interior, "loc_corner_shop")
	assert_eq(Game.player.location, "loc_corner_shop")
	assert_eq(Game.current_map(), _inside("loc_corner_shop"))
	assert_eq(DistrictMap.world_to_cell(Game.player.position), _inside("loc_corner_shop").entry_cell())
	assert_true(entered.has("loc_corner_shop"))
	# Walking inside obeys the room's own walls.
	assert_err(Game.move_player(DistrictMap.cell_to_world(Vector2i(0, 4))), "cell_blocked")


func test_a_door_out_of_reach_does_nothing() -> void:
	_stand(_outside().anchor_of("loc_corner_shop") + Vector2i(0, 2))
	assert_err(Game.interact_at(_door("loc_corner_shop")), "out_of_reach")
	assert_eq(Game.player.interior, "")
	assert_eq(_rejections.size(), 1)


func test_a_closed_shop_refuses_and_the_world_is_unchanged() -> void:
	_set_time(22 * 60)
	_stand(_outside().anchor_of("loc_corner_shop"))
	var before := Game.player.position
	assert_err(Game.interact_at(_door("loc_corner_shop")), "closed")
	assert_eq(Game.player.interior, "")
	assert_eq(Game.player.position, before)
	assert_eq(_rejections[-1][1], "closed")


## D-104: inside its hours but on its closed day, the door says so rather
## than quoting hours the shop is keeping every other day.
func test_a_shop_on_its_closed_day_says_so_and_the_world_is_unchanged() -> void:
	_set_time(10 * 60)
	while Game.clock.weekday() != 0:
		Game.clock.total_minutes += GameClock.MINUTES_PER_DAY
	_stand(_outside().anchor_of("loc_corner_shop"))
	var before := Game.player.position
	assert_err(Game.interact_at(_door("loc_corner_shop")), "closed_today")
	assert_eq(Game.player.interior, "")
	assert_eq(Game.player.position, before)
	assert_eq(_rejections[-1][1], "closed_today")
	Localization.set_locale("en")
	var text := InteractionText.outcome_text({"kind": "door", "target": "loc_corner_shop"}, Result.failure("closed_today"))
	assert_true(text.contains("closed today"), text)
	Game.clock.total_minutes += GameClock.MINUTES_PER_DAY
	assert_ok(Game.interact_at(_door("loc_corner_shop")), "open again on Monday")


func test_other_peoples_homes_are_private_and_the_warehouse_is_locked() -> void:
	assert_err(_enter("loc_ida_flat"), "private")
	assert_err(_enter("loc_warehouse_9"), "locked")
	assert_eq(Game.player.interior, "")


func test_your_own_home_opens_at_any_hour() -> void:
	_set_time(3 * 60)
	assert_ok(_enter(Game.player.home_location))
	assert_eq(Game.player.interior, Game.player.home_location)


func test_leaving_puts_you_in_front_of_the_door() -> void:
	assert_ok(_enter("loc_corner_shop"))
	var shop := _inside("loc_corner_shop")
	var result := Game.interact_at(shop.exit_door)
	assert_ok(result)
	assert_eq((result.value as Dictionary)["kind"], "exited")
	assert_eq(Game.player.interior, "")
	assert_eq(DistrictMap.world_to_cell(Game.player.position), _outside().anchor_of("loc_corner_shop"))
	assert_eq(Game.current_map(), _outside())


# --- counters, beds, signs --------------------------------------------------

func test_a_counter_serves_only_when_someone_is_working_there() -> void:
	assert_ok(_enter("loc_corner_shop"))
	_stand(Vector2i(6, 5))
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_ida_flat"
	assert_err(Game.interact_at(Vector2i(6, 4)), "nobody_serving")

	ida.location = "loc_corner_shop"
	ida.activity = "work"
	var result := Game.interact_at(Vector2i(6, 4))
	assert_ok(result)
	assert_eq((result.value as Dictionary)["npc"], "npc_ida")

	ida.activity = "eat"
	assert_err(Game.interact_at(Vector2i(6, 4)), "nobody_serving", "on a break is not serving")


func test_sleeping_in_your_own_bed_skips_to_morning() -> void:
	assert_ok(_enter(Game.player.home_location))
	_stand(Vector2i(3, 2))
	var bed := Vector2i(2, 2)
	assert_err(Game.interact_at(bed), "not_tired", "fresh at the start of the day")

	_set_time(23 * 60)
	Game.player.stats.sleep = 0.2
	var day := Game.clock.day_index()
	var result := Game.interact_at(bed)
	assert_ok(result)
	assert_eq((result.value as Dictionary)["minutes"], 8 * 60)
	assert_eq(Game.clock.minute_of_day(), Game.WAKE_MINUTE)
	assert_eq(Game.clock.day_index(), day + 1)
	assert_gt(Game.player.stats.sleep, 0.8, "rested, not further drained by the idle drift")


func test_someone_elses_bed_is_refused() -> void:
	assert_ok(_enter(Game.player.home_location))
	_stand(Vector2i(3, 2))
	Game.player.stats.sleep = 0.2
	Game.player.home_location = "loc_somewhere_else"
	assert_err(Game.interact_at(Vector2i(2, 2)), "not_your_bed")


func test_reading_a_sign() -> void:
	# Found by id rather than by cell: where the bus stop sits is a layout
	# decision the map is free to change.
	var map := _outside()
	var cell := Vector2i(-1, -1)
	for candidate: Vector2i in map.objects:
		if str(map.objects[candidate]["id"]) == "obj_bus_timetable":
			cell = candidate
	assert_true(map.in_bounds(cell), "the bus timetable is somewhere on the map")
	_stand(cell + Vector2i.DOWN)
	var result := Game.interact_at(cell)
	assert_ok(result)
	assert_eq((result.value as Dictionary)["text_key"], "obj.bus_timetable.text")


func test_interaction_at_describes_without_acting() -> void:
	assert_eq(Game.interaction_at(_door("loc_clinic")), {"kind": "door", "target": "loc_clinic"})
	assert_eq(Game.interaction_at(Vector2i(2, 16)), {})
	assert_eq(Game.player.interior, "")


func test_interior_survives_a_save_round_trip_and_old_saves_mean_outside() -> void:
	Game.player.interior = "loc_corner_shop"
	var copy := PlayerState.new()
	copy.from_dict(Game.player.to_dict())
	assert_eq(copy.interior, "loc_corner_shop")
	var old_shape := Game.player.to_dict()
	old_shape.erase("interior")
	copy.from_dict(old_shape)
	assert_eq(copy.interior, "")


# --- words ------------------------------------------------------------------

func test_prompts_and_outcomes_read_as_english() -> void:
	Localization.set_locale("en")
	var door := {"kind": "door", "target": "loc_corner_shop"}
	var shop_name := InteractionText.place_name("loc_corner_shop")
	assert_ne(shop_name, "loc_corner_shop")
	assert_true(InteractionText.prompt_for(door).contains(shop_name))
	assert_eq(InteractionText.prompt_for({}), "")
	var closed := InteractionText.outcome_text(door, Result.failure("closed"))
	assert_true(closed.contains("07:00") and closed.contains("21:00"), closed)
	assert_eq(InteractionText.outcome_text(door, Result.failure("out_of_reach")), "")
	assert_eq(InteractionText.outcome_text(door, Result.success({"kind": "entered"})), "")


func test_every_explained_refusal_and_sign_has_english_text() -> void:
	Localization.set_locale("en")
	for code in InteractionText.EXPLAINED_REFUSALS:
		var key := "ui.msg.refused." + code
		assert_ne(tr(key), key, key)
	for map: DistrictMap in [_outside()] + Game.world.interiors.values():
		for cell: Vector2i in map.objects:
			var key := str(map.objects[cell]["text_key"])
			if not key.is_empty():
				assert_ne(tr(key), key, key)


func test_the_prompt_names_the_interact_key() -> void:
	assert_eq(Hud.key_hint("interact"), "E")


# --- the World scene --------------------------------------------------------

func _spawn_world() -> WorldView:
	var tree := Engine.get_main_loop() as SceneTree
	var packed: PackedScene = load(WORLD_SCENE)
	var view: WorldView = packed.instantiate()
	tree.root.add_child(view)
	return view


func _face(view: WorldView, cell: Vector2i, facing: Vector2i) -> void:
	var body := view.player_body()
	body.place_at(DistrictMap.cell_to_world(cell))
	body.facing = facing
	_stand(cell)


func test_walking_into_the_shop_and_out_again_in_the_world_scene() -> void:
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	var view := _spawn_world()
	var tree := Engine.get_main_loop() as SceneTree
	_face(view, _outside().anchor_of("loc_corner_shop"), Vector2i.UP)
	# `process_frame` fires *before* the frame's _process calls, so one await
	# only guarantees a _process pass if this test happened to start after the
	# previous frame's. Two make it true wherever the runner resumes from.
	await tree.process_frame
	await tree.process_frame
	assert_true(view.hud().prompt_text().contains(InteractionText.place_name("loc_corner_shop")),
		"prompt: " + view.hud().prompt_text())
	assert_null(view.npc_bodies().body_for("npc_ida"), "indoors, unseen from the street")

	assert_ok(view.interact())
	var shop := _inside("loc_corner_shop")
	assert_eq(view.region_view().map, shop)
	assert_eq(view.player_body().current_cell(), shop.entry_cell())
	var ida_body := view.npc_bodies().body_for("npc_ida")
	assert_not_null(ida_body, "inside, Ida is there")
	assert_eq(ida_body.current_cell(), shop.staff_cell, "behind the counter")

	_face(view, shop.entry_cell(), Vector2i.DOWN)
	assert_ok(view.interact())
	assert_eq(view.region_view().map, _outside())
	assert_null(view.npc_bodies().body_for("npc_ida"))
	view.free()


func test_a_refusal_shows_a_message_and_changes_nothing_on_screen() -> void:
	var view := _spawn_world()
	_face(view, _outside().anchor_of("loc_ida_flat"), Vector2i.UP)
	assert_err(view.interact(), "private")
	assert_ne(view.hud().message_text(), "")
	assert_eq(view.region_view().map, _outside())
	view.free()
