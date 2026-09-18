extends TestCase
## NPC bodies: routes over the map, where people stand, how they look, and the
## pooled bodies in a real World scene reacting to the simulation.

const WORLD_SCENE := "res://scenes/world/world.tscn"


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)


func _map() -> DistrictMap:
	return Game.world.map_for("harbourside")


func _spawn_world() -> WorldView:
	var tree := Engine.get_main_loop() as SceneTree
	var packed: PackedScene = load(WORLD_SCENE)
	var view: WorldView = packed.instantiate()
	tree.root.add_child(view)
	return view


## Someone the director is simulating in detail in the shown region.
func _active_npc() -> Npc:
	var npc := Game.npcs.get_npc("npc_joonas")
	assert_eq(npc.tier, SimLod.Tier.ACTIVE, "harbourside residents are ACTIVE at the start")
	return npc


# --- routes -----------------------------------------------------------------

func test_path_joins_two_cells_over_walkable_ground_only() -> void:
	var map := _map()
	var from := map.spawn
	var to := map.anchor_of("loc_corner_shop")
	var route := map.find_path(from, to)
	assert_gt(float(route.size()), 1.0)
	assert_eq(route[0], from)
	assert_eq(route[route.size() - 1], to)
	for i in route.size():
		assert_false(map.is_blocked(route[i]), "route cell %s is walkable" % route[i])
		if i > 0:
			var step := route[i] - route[i - 1]
			assert_true(absi(step.x) <= 1 and absi(step.y) <= 1, "one step at a time")
			if step.x != 0 and step.y != 0:
				assert_false(map.is_blocked(route[i - 1] + Vector2i(step.x, 0))
					or map.is_blocked(route[i - 1] + Vector2i(0, step.y)), "no corner cutting")


func test_path_to_or_from_a_blocked_cell_is_empty() -> void:
	var map := _map()
	var door: Vector2i = map.buildings["loc_corner_shop"]["door"]
	assert_eq(map.find_path(map.spawn, door).size(), 0)
	assert_eq(map.find_path(door, map.spawn).size(), 0)
	assert_eq(map.find_path(Vector2i(-3, -3), map.spawn).size(), 0)


func test_path_across_water_does_not_exist() -> void:
	var built := DistrictMap.from_data({
		"id": "split", "region": "x", "width": 5, "height": 3, "fill": "grass",
		"areas": [{"terrain": "water", "rect": [2, 0, 1, 3]}],
		"spawn": [0, 1],
	})
	assert_ok(built)
	var map: DistrictMap = built.value
	assert_eq(map.find_path(Vector2i(0, 1), Vector2i(4, 1)).size(), 0)
	assert_eq(map.find_path(Vector2i(0, 0), Vector2i(1, 2)).size(), 3, "diagonal steps allowed in the open")


# --- where people stand -----------------------------------------------------

func test_people_stand_in_front_of_a_building_door() -> void:
	var map := _map()
	assert_eq(map.standing_cell("loc_clinic", "anyone"), map.anchor_of("loc_clinic"))
	assert_eq(map.standing_cell("loc_nowhere", "anyone"), Vector2i(-1, -1))


func test_a_crowd_spreads_over_a_place_and_each_keeps_their_spot() -> void:
	var map := _map()
	var spots := {}
	for npc_id in Game.npcs.all_ids():
		var cell := map.standing_cell("loc_harbour", str(npc_id))
		assert_eq(map.location_at(cell), "loc_harbour", "spot lies in the place")
		assert_false(map.is_blocked(cell))
		assert_eq(map.standing_cell("loc_harbour", str(npc_id)), cell, "same person, same spot")
		spots[cell] = true
	assert_gt(float(spots.size()), 5.0, "ten people do not share one cell")


func test_edge_cell_is_walkable_and_inside_an_exit() -> void:
	var map := _map()
	var cell := map.edge_cell()
	assert_false(map.is_blocked(cell))
	assert_ne(map.exit_at(cell), "")


# --- looks ------------------------------------------------------------------

func test_authored_look_wins_over_the_generated_one() -> void:
	var ida := Game.npcs.get_npc("npc_ida")
	var palette := NpcLook.palette_for(ida)
	assert_eq(palette["shirt"], Color(str(ida.look["shirt"])))
	assert_eq(palette.size(), CharacterFigure.DEFAULTS.size())


func test_generated_look_is_stable_and_drawn_from_the_set() -> void:
	var first := NpcLook.generated("npc_someone")
	assert_eq(NpcLook.generated("npc_someone"), first, "same id, same outfit")
	assert_true(NpcLook.SKINS.has(first["skin"].to_html(false)))
	assert_true(NpcLook.SHIRTS.has(first["shirt"].to_html(false)))
	var outfits := {}
	for i in 20:
		outfits[NpcLook.generated("npc_gen_%03d" % i)] = true
	assert_gt(float(outfits.size()), 10.0, "strangers mostly look different")


func test_every_recognisable_npc_has_a_valid_authored_look() -> void:
	for npc_id in Game.npcs.all_ids():
		var npc := Game.npcs.get_npc(str(npc_id))
		if npc.importance == Npc.Importance.BACKGROUND:
			continue
		assert_false(npc.look.is_empty(), "%s has a look" % npc_id)
		for key in npc.look:
			assert_true(CharacterFigure.DEFAULTS.has(key), "%s: known part '%s'" % [npc_id, key])
			assert_true(Color.html_is_valid(str(npc.look[key])), "%s: colour for '%s'" % [npc_id, key])


# --- bodies in the world ----------------------------------------------------

func test_people_outdoors_get_a_body_and_people_indoors_do_not() -> void:
	var outdoors := _active_npc()
	outdoors.location = "loc_harbour"
	var indoors := Game.npcs.get_npc("npc_leena")
	indoors.location = "loc_cafe_kaisla"
	var view := _spawn_world()
	var bodies := view.npc_bodies()
	var body := bodies.body_for(outdoors.id)
	assert_not_null(body)
	assert_eq(body.current_cell(), _map().standing_cell("loc_harbour", outdoors.id))
	assert_eq(body.palette(), NpcLook.palette_for(outdoors))
	assert_null(bodies.body_for(indoors.id))
	view.free()


func test_walking_indoors_follows_a_route_and_ends_with_the_body_returned() -> void:
	var npc := _active_npc()
	npc.location = "loc_harbour"
	var view := _spawn_world()
	var bodies := view.npc_bodies()
	var body := bodies.body_for(npc.id)
	var pooled_before := bodies.pooled_count()

	Game.npcs.move_to(npc.id, "loc_corner_shop")
	assert_eq(npc.location, "loc_corner_shop", "the world moved at once")
	assert_true(body.is_walking(), "the body is on its way")
	assert_eq(bodies.body_for(npc.id), body, "the same body walks")

	body.advance(0.5)
	assert_false(_map().is_blocked(body.current_cell()))
	body.advance(600.0)
	assert_null(bodies.body_for(npc.id), "went in through the door")
	assert_eq(bodies.pooled_count(), pooled_before + 1)
	assert_eq(DistrictMap.world_to_cell(body.position), _map().anchor_of("loc_corner_shop"))
	view.free()


func test_leaving_a_building_starts_at_its_door() -> void:
	var npc := _active_npc()
	npc.location = "loc_veikko_flat"
	var view := _spawn_world()
	var bodies := view.npc_bodies()
	assert_null(bodies.body_for(npc.id))

	Game.npcs.move_to(npc.id, "loc_harbour")
	var body := bodies.body_for(npc.id)
	assert_not_null(body)
	assert_eq(body.current_cell(), _map().anchor_of("loc_veikko_flat"))
	body.advance(600.0)
	assert_false(body.is_walking())
	assert_eq(bodies.body_for(npc.id), body, "stays visible at an open-air place")
	assert_eq(body.current_cell(), _map().standing_cell("loc_harbour", npc.id))
	view.free()


func test_changing_course_mid_walk_starts_from_where_the_body_is() -> void:
	var npc := _active_npc()
	npc.location = "loc_harbour"
	var view := _spawn_world()
	var bodies := view.npc_bodies()
	var body := bodies.body_for(npc.id)
	Game.npcs.move_to(npc.id, "loc_corner_shop")
	body.advance(2.0)
	var midway := body.position
	Game.npcs.move_to(npc.id, "loc_bus_stop")
	assert_eq(bodies.body_for(npc.id), body)
	assert_eq(body.position, midway, "no jump when the plan changes")
	body.advance(600.0)
	assert_eq(body.current_cell(), _map().standing_cell("loc_bus_stop", npc.id))
	view.free()


func test_dropping_out_of_detail_returns_the_body_to_the_pool() -> void:
	var npc := _active_npc()
	npc.location = "loc_harbour"
	var view := _spawn_world()
	var bodies := view.npc_bodies()
	var visible_before := bodies.visible_count()
	assert_gt(float(visible_before), 0.0)

	# The player leaves: harbourside people are no longer simulated in detail.
	Game.world.get_region("old_town").unlocked = true
	Game.world.enter_region("old_town")
	Game.director.assign_tiers()
	assert_eq(bodies.visible_count(), 0)
	assert_eq(bodies.pooled_count(), visible_before)

	# And back: the same bodies serve again, none are created.
	var children := bodies.get_child_count()
	Game.world.enter_region("harbourside")
	Game.director.assign_tiers()
	assert_eq(bodies.visible_count(), visible_before)
	assert_eq(bodies.get_child_count(), children, "pooled, not rebuilt")
	view.free()


func test_the_player_moving_does_not_create_a_body() -> void:
	var view := _spawn_world()
	var bodies := view.npc_bodies()
	var before := bodies.visible_count()
	Game.move_player(DistrictMap.cell_to_world(_map().anchor_of("loc_dock_street")))
	assert_eq(bodies.visible_count(), before)
	view.free()
