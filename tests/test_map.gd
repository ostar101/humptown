extends TestCase
## The map (D-049): what the player has come to know of the district — places
## they have been to, places they have only heard of, and nothing else.

var _learned: Array[String] = []


func before_each() -> void:
	_learned = []
	Events.place_learned.connect(_on_learned)


func after_each() -> void:
	Events.place_learned.disconnect(_on_learned)
	if Game.dialogue.is_talking():
		Game.end_conversation()
	Localization.set_locale("en")
	Game.saves.delete_slot("test_map")


func _on_learned(location_id: String, how: String) -> void:
	_learned.append("%s:%s" % [location_id, how])


func _start(background: String = "bg_returning") -> void:
	Game.new_game(background, 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	var model := ScriptedDialogueModel.new()
	model.available = false
	Game.dialogue.model = model
	_learned = []


func _walk_to(location_id: String) -> void:
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of(location_id))), location_id)


# --- knowing a place ---------------------------------------------------------------------------------

func test_a_place_is_new_once_and_being_there_outranks_hearing_of_it() -> void:
	var player := PlayerState.new()
	assert_false(player.learn_place("", "visited"), "nowhere is not a place")
	assert_true(player.learn_place("loc_court", "told"), "new")
	assert_false(player.learn_place("loc_court", "told"), "not new again")
	assert_eq(player.known_places["loc_court"], "told")
	assert_false(player.learn_place("loc_court", "visited"), "known already, though it is now been-to")
	assert_eq(player.known_places["loc_court"], "visited")
	assert_false(player.learn_place("loc_court", "told"), "hearing of it does not undo having been")
	assert_eq(player.known_places["loc_court"], "visited")
	assert_true(player.knows_place("loc_court"))
	assert_false(player.knows_place("loc_harbour"))
	assert_eq(_learned, ["loc_court:told"] as Array[String], "announced when it first appeared, and only then")


func test_you_start_knowing_home_and_your_work() -> void:
	_start("bg_dockhand")
	var known := Game.player.known_places
	assert_eq(known[Game.player.home_location], "visited")
	assert_eq(known.get("loc_harbour"), "told", "the job is at the harbour")
	assert_false(known.has("loc_court"), "and not much else")
	assert_false(known.has("loc_anchor_bar"))
	_start("")
	assert_eq(Game.player.known_places.size(), 1 if Game.player.home_location != "" else 0)


func test_walking_somewhere_puts_it_on_the_map_once() -> void:
	_start()
	assert_false(Game.player.knows_place("loc_court"))
	_walk_to("loc_court")
	assert_eq(Game.player.known_places["loc_court"], "visited")
	assert_has(_learned, "loc_court:visited")
	var count := _learned.size()
	_walk_to("loc_dock_street")
	_walk_to("loc_court")
	assert_eq(_learned.count("loc_court:visited"), 1)
	assert_gt(_learned.size(), count - 1)


func test_going_where_you_were_told_makes_it_solid_without_a_second_announcement() -> void:
	_start()
	Game.player.learn_place("loc_court", "told")
	_learned = []
	_walk_to("loc_court")
	assert_eq(Game.player.known_places["loc_court"], "visited")
	assert_eq(_learned, [] as Array[String], "you already knew of it")


func test_being_told_where_a_place_is_puts_it_on_the_map() -> void:
	_start()
	var npc := Game.npcs.get_npc("npc_pirjo")
	npc.location = "loc_dock_street"
	npc.activity = "walk"
	assert_ok(Game.start_conversation("npc_pirjo"))
	assert_false(Game.player.knows_place("loc_anchor_bar"))
	var said: Result = await Game.say_to_npc("Where is The Anchor?")
	assert_ok(said)
	assert_eq(said.value["intent"]["kind"], "about_place", "read as a question about a place")
	assert_eq(Game.player.known_places.get("loc_anchor_bar"), "told")
	assert_has(_learned, "loc_anchor_bar:told")
	var about_a_person: Result = await Game.say_to_npc("Who is Ida?")
	assert_ok(about_a_person)
	assert_false(Game.player.known_places.has("npc_ida"), "people are not places")


func test_the_rule_tells_a_place_only_for_a_place() -> void:
	var place := ConversationRules.judge({"kind": "about_place", "subject": "loc_court"}, {})
	assert_ok(place)
	assert_eq(place.value["effects"], [{"do": "tell_place", "place": "loc_court"}] as Array[Dictionary])
	assert_eq(ConversationRules.judge({"kind": "about_place", "subject": ""}, {}).value["effects"], [] as Array[Dictionary], "an unknown place")
	assert_eq(ConversationRules.judge({"kind": "about_place", "subject": "npc_ida"}, {}).value["effects"], [] as Array[Dictionary])


func test_a_meeting_request_says_where_and_so_you_know() -> void:
	_start()
	Game.phone_director.add_contact("npc_pirjo")
	Game.npcs.get_npc("npc_pirjo").activity = "idle"
	Game.clock.total_minutes = Game.clock.day_index() * GameClock.MINUTES_PER_DAY + 12 * 60
	var spec := Game.meetings.suggest("npc_pirjo")
	assert_false(spec.is_empty())
	var place := str(spec["location"])
	Game.player.known_places.erase(place)
	assert_ok(Game.phone_director.deliver({"npc": "npc_pirjo", "kind": "meeting_request", "key": "phone.msg.meeting_request",
		"args": {"place": place, "start": spec["start"]}, "meeting": spec}))
	assert_eq(Game.player.known_places[place], "told")


func test_being_hired_tells_you_where_you_will_work() -> void:
	_start()
	assert_false(Game.player.knows_place("loc_cafe_kaisla"))
	assert_ok(Game.hire_player("job_kaisla"))
	assert_eq(Game.player.known_places["loc_cafe_kaisla"], "told")


# --- the map ------------------------------------------------------------------------------------------

func _window() -> PhoneWindow:
	var window: PhoneWindow = (load("res://scenes/ui/phone_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	return window


func test_the_map_shows_only_what_is_known() -> void:
	_start()
	Game.player.learn_place("loc_court", "visited")
	Game.player.learn_place("loc_anchor_bar", "told")
	var window := _window()
	assert_true(window.open())
	window.show_page(PhoneWindow.Page.MAP)
	var view := window.map_view()
	assert_not_null(view)
	var states := {}
	for mark in view.marks():
		states[mark["id"]] = mark["state"]
	assert_eq(states.get("loc_court"), "visited")
	assert_eq(states.get("loc_anchor_bar"), "told")
	assert_eq(states.get(Game.player.home_location), "visited")
	assert_false(states.has("loc_harbour"), "the harbour is not known to this player")
	assert_false(states.has("loc_clinic"), "nor the clinic")
	assert_eq(states.size(), Game.player.known_places.size(), "everything known that is on this district, and nothing else")
	window.close()
	window.free()


func test_you_are_on_the_map_and_no_one_else_is() -> void:
	_start()
	Game.player.learn_place("loc_court", "visited")
	_walk_to("loc_court")
	var window := _window()
	window.open()
	window.show_page(PhoneWindow.Page.MAP)
	var view := window.map_view()
	assert_true(view.has_you())
	assert_eq(view.you_cell(), DistrictMap.world_to_cell(Game.player.position))
	assert_true((Game.current_map().places["loc_court"]["rects"][0] as Rect2i).has_point(view.you_cell()), "in the court")
	for mark in view.marks():
		assert_false(mark.has("npc"), "people are not on the map")
	window.close()
	window.free()


func test_inside_a_building_you_are_at_the_building() -> void:
	_start()
	var map := Game.current_map()
	_walk_to("loc_corner_shop")
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))
	var window := _window()
	window.open()
	window.show_page(PhoneWindow.Page.MAP)
	var rect: Rect2i = map.buildings["loc_corner_shop"]["rect"]
	assert_eq(window.map_view().you_cell(), rect.get_center())
	window.close()
	window.free()


func test_the_legend_names_and_numbers_what_the_map_marks() -> void:
	_start()
	Game.player.learn_place("loc_court", "visited")
	Game.player.learn_place("loc_anchor_bar", "told")
	var window := _window()
	window.open()
	window.show_page(PhoneWindow.Page.MAP)
	var rows := window.row_texts()
	var numbered: Dictionary = {}
	for mark in window.map_view().marks():
		numbered[mark["id"]] = mark["number"]
	assert_eq(numbered.size(), window.map_view().marks().size())
	assert_true(rows.has("%d · Dock Street Court · been there" % numbered["loc_court"]), str(rows))
	assert_true(rows.any(func(r: String) -> bool: return r.ends_with("· heard of") and r.contains("Anchor")), str(rows))
	var seen := {}
	for n in numbered.values():
		assert_false(seen.has(n), "each number is one place")
		seen[n] = true
	window.close()
	window.free()


func test_places_in_other_districts_are_listed_but_not_drawn() -> void:
	_start()
	Game.player.learn_place("loc_pawn_shop", "told")
	var window := _window()
	window.open()
	window.show_page(PhoneWindow.Page.MAP)
	var ids: Array[String] = []
	for mark in window.map_view().marks():
		ids.append(str(mark["id"]))
	assert_false(ids.has("loc_pawn_shop"), "Old Town has no map yet")
	assert_true(window.row_texts().any(func(r: String) -> bool: return r.begins_with("Pawn") and r.ends_with("heard of")))
	window.close()
	window.free()


func test_what_you_know_is_saved() -> void:
	_start()
	Game.player.learn_place("loc_court", "visited")
	Game.player.learn_place("loc_anchor_bar", "told")
	assert_ok(Game.save_game("test_map"))
	assert_ok(Game.load_game("test_map"))
	Game.pause_time(true)
	assert_eq(Game.player.known_places["loc_court"], "visited")
	assert_eq(Game.player.known_places["loc_anchor_bar"], "told")


func test_a_save_from_before_the_map_knows_where_you_live() -> void:
	var player := PlayerState.new()
	player.from_dict({"display_name": "Ari", "home_location": "loc_player_flat"})
	assert_eq(player.known_places, {"loc_player_flat": "visited"})
