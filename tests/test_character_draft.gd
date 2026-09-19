extends TestCase
## CharacterDraft and the way a life starts (D-033): what the creation screens
## may propose, what Game refuses, what a new life begins with, and the bed as
## the save point that Continue reads.

var _data: DataRegistry


func before_each() -> void:
	_data = DataRegistry.new()
	_data.load_all()


func _draft() -> CharacterDraft:
	var d := CharacterDraft.new()
	d.background_id = "bg_dockhand"
	d.display_name = "Aino"
	d.pronouns = "she"
	d.appearance = {"skin": "#bd8877", "hair": "#3b2a20", "shirt": "#3f6e8c", "hair_style": "05", "outfit_style": "12"}
	return d


func _background(id: String) -> Dictionary:
	return _data.table("backgrounds")[id]


# --- validation --------------------------------------------------------------

func test_a_complete_draft_is_accepted() -> void:
	assert_ok(_draft().validate(_data))


func test_a_name_is_required_and_kept_short() -> void:
	var d := _draft()
	d.display_name = "   "
	assert_err(d.validate(_data), "name_empty")
	d.display_name = "x".repeat(CharacterDraft.NAME_MAX + 1)
	assert_err(d.validate(_data), "name_too_long")
	d.display_name = "  Aino  "
	assert_ok(d.validate(_data), "surrounding spaces are trimmed, not refused")


func test_unknown_pronouns_and_backgrounds_are_refused() -> void:
	var d := _draft()
	d.pronouns = "it"
	assert_err(d.validate(_data), "unknown_pronouns")
	d = _draft()
	d.background_id = "bg_astronaut"
	assert_err(d.validate(_data), "unknown_background")


func test_attributes_may_be_reshuffled_but_not_inflated() -> void:
	var d := _draft()
	d.attribute_shifts = {"wits": 1, "charisma": 1, "strength": -1, "endurance": -1}
	assert_ok(d.validate(_data), "two points moved is allowed")
	d.attribute_shifts = {"wits": 2}
	assert_err(d.validate(_data), "attributes_unbalanced")
	d.attribute_shifts = {"wits": 2, "charisma": 1, "strength": -1, "endurance": -1, "resolve": -1}
	assert_err(d.validate(_data), "too_many_points")
	d.attribute_shifts = {"luck": 1, "strength": -1}
	assert_err(d.validate(_data), "unknown_attribute")


func test_no_attribute_may_leave_its_bounds() -> void:
	var d := _draft()
	# The dockhand's endurance is 7; two more would be 9.
	d.attribute_shifts = {"endurance": 2, "wits": -1, "charisma": -1}
	assert_err(d.validate(_data), "attribute_out_of_range")


func test_a_look_may_only_hold_colours_and_style_ids() -> void:
	var d := _draft()
	d.appearance["skin"] = "not a colour"
	assert_err(d.validate(_data), "bad_appearance")
	d = _draft()
	d.appearance["hair_style"] = "../../etc"
	assert_err(d.validate(_data), "bad_appearance")
	d = _draft()
	d.appearance["wings"] = "#ffffff"
	assert_err(d.validate(_data), "bad_appearance")


func test_a_point_must_be_taken_before_it_can_be_given() -> void:
	var d := _draft()
	var bg := _background("bg_dockhand")
	assert_false(d.raise(bg, "wits"), "nothing has been freed yet")
	assert_true(d.lower(bg, "strength"))
	assert_eq(d.unspent(), 1)
	assert_err(d.validate(_data), "attributes_unbalanced", "a freed point must be placed")
	assert_true(d.raise(bg, "wits"))
	assert_eq(d.unspent(), 0)
	assert_ok(d.validate(_data))


func test_no_more_than_two_points_can_be_taken() -> void:
	var d := _draft()
	var bg := _background("bg_dockhand")
	assert_true(d.lower(bg, "strength"))
	assert_true(d.lower(bg, "endurance"))
	assert_false(d.lower(bg, "agility"), "the third point is refused")
	assert_true(d.raise(bg, "wits"))
	assert_true(d.raise(bg, "charisma"))
	assert_false(d.raise(bg, "resolve"), "both freed points are spent")
	assert_ok(d.validate(_data))
	assert_eq(d.attributes(bg)["charisma"], int(bg["attributes"]["charisma"]) + 1)


func test_undoing_a_change_gives_the_point_back() -> void:
	var d := _draft()
	var bg := _background("bg_dockhand")
	assert_true(d.lower(bg, "strength"))
	assert_true(d.raise(bg, "strength"), "putting it back is always allowed")
	assert_eq(d.attribute_shifts, {}, "and leaves no trace")
	assert_true(d.lower(bg, "strength"))
	assert_true(d.raise(bg, "wits"))
	assert_true(d.lower(bg, "wits"), "taking back what was given")
	assert_eq(d.unspent(), 1)


func test_no_button_can_push_an_attribute_past_its_bounds() -> void:
	var d := _draft()
	var bg := _background("bg_dockhand")
	assert_true(d.lower(bg, "wits"))
	assert_false(d.lower(bg, "wits"), "wits 4 cannot go below 3")
	assert_true(d.lower(bg, "charisma"))
	assert_true(d.raise(bg, "strength"))
	assert_false(d.raise(bg, "strength"), "strength 7 +2 would be 9")
	assert_true(d.raise(bg, "agility"))
	assert_ok(d.validate(_data))


# --- starting a life ---------------------------------------------------------

func test_game_refuses_a_bad_draft_and_builds_nothing() -> void:
	Game.unload()
	var d := _draft()
	d.display_name = ""
	assert_err(Game.new_game_from(d, 7), "name_empty")
	assert_false(Game.is_running(), "a refused draft starts no world")


func test_a_new_life_is_the_background_plus_the_players_choices() -> void:
	var d := _draft()
	d.attribute_shifts = {"wits": 1, "strength": -1}
	assert_ok(Game.new_game_from(d, 7))
	var p := Game.player
	assert_eq(p.display_name, "Aino")
	assert_eq(p.pronouns, "she")
	assert_eq(p.appearance["hair_style"], "05")
	assert_eq(p.background_id, "bg_dockhand")
	assert_eq(Game.work.job_id, "job_dockhand", "the background still sets the life up")
	var bg := _background("bg_dockhand")
	assert_eq(p.stats.attribute("wits"), int(bg["attributes"]["wits"]) + 1)
	assert_eq(p.stats.attribute("strength"), int(bg["attributes"]["strength"]) - 1)


func test_a_new_life_starts_at_home_indoors() -> void:
	assert_ok(Game.new_game_from(_draft(), 7))
	assert_eq(Game.player.interior, Game.player.home_location)
	var map := Game.current_map()
	assert_true(map.is_interior(), "you wake up in your own flat")
	assert_false(map.is_blocked(DistrictMap.world_to_cell(Game.player_start_position())))


# --- the save point ----------------------------------------------------------

func test_sleeping_in_your_bed_saves_and_continue_brings_you_back() -> void:
	assert_ok(Game.new_game_from(_draft(), 7))
	Game.pause_time(true)
	Game.saves.delete_slot(Game.save_slot)
	assert_false(Game.has_saved_game())

	Game.advance_time(16 * 60)
	Game.player.stats.sleep = 0.2
	assert_ok(Game.move_player(DistrictMap.cell_to_world(Vector2i(3, 2))))
	var slept := Game.interact_at(Vector2i(2, 2))
	assert_ok(slept)
	assert_true(bool((slept.value as Dictionary)["saved"]), "the bed is the save point")
	assert_true(Game.has_saved_game())

	Game.player.display_name = "Someone else"
	assert_ok(Game.continue_game())
	assert_eq(Game.player.display_name, "Aino", "Continue restores the life that was saved")
	assert_eq(Game.player.appearance["outfit_style"], "12", "and how they looked")
	Game.saves.delete_slot(Game.save_slot)


func test_the_test_suite_never_saves_over_the_players_life() -> void:
	assert_ne(Game.save_slot, "main", "the runner points the bed at a test slot")


# --- the look ----------------------------------------------------------------

func test_a_look_turns_hex_choices_into_the_figures_palette() -> void:
	var palette := PlayerLook.palette({"shirt": "#8c3f4a"})
	assert_eq(palette["shirt"], Color("8c3f4a"))
	assert_eq(palette["skin"], CharacterFigure.DEFAULTS["skin"], "what was not chosen keeps its default")
	assert_eq(PlayerLook.chosen_styles({"hair_style": "05"}), {"hairstyles": "05"})


func test_cycling_a_choice_wraps_round_and_stays_valid() -> void:
	var look := PlayerLook.default_appearance()
	var hair_colours := PlayerLook.options("hair", look)
	assert_false(hair_colours.is_empty(), "there is always a hair colour to choose")
	for i in hair_colours.size():
		look = PlayerLook.cycle(look, "hair", 1)
	assert_eq(look["hair"], PlayerLook.default_appearance()["hair"], "a full lap comes back round")
	look = PlayerLook.cycle(look, "hair", -1)
	assert_eq(str(look["hair"]).trim_prefix("#"), hair_colours[hair_colours.size() - 1])
	for key in ["skin", "hair_style", "outfit_style", "shirt", "trousers"]:
		look = PlayerLook.cycle(look, key, 3)
	var d := _draft()
	d.appearance = look
	assert_ok(d.validate(_data), "whatever the screen can pick, Game accepts")


func test_every_colour_offered_is_one_the_chosen_style_is_drawn_in() -> void:
	if not CharacterSprites.available():
		assert_true(true, "art not installed on this machine; colours are free choices")
		return
	var look := PlayerLook.cycle(PlayerLook.default_appearance(), "outfit_style", 7)
	for colour in PlayerLook.options("shirt", look):
		var worn := PlayerLook.look(look.merged({"shirt": "#" + colour}, true))
		assert_true(str(worn["outfits"]).contains("_%s_" % look["outfit_style"]),
			"%s is a version of the chosen outfit" % colour)
	assert_true(PlayerLook.options("trousers", look).is_empty(),
		"LimeZu outfits include trousers; a separate choice would change nothing")


func test_changing_a_style_keeps_the_colour_as_close_as_it_can() -> void:
	if not CharacterSprites.available():
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	var look := PlayerLook.default_appearance()
	look["shirt"] = "#8c3f4a"   # a red
	var next := PlayerLook.cycle(look, "outfit_style", 1)
	assert_true(PlayerLook.options("shirt", next).has(str(next["shirt"]).trim_prefix("#")),
		"the colour is one the new style has")


func test_a_chosen_style_is_worn_when_the_art_has_it() -> void:
	var styles := PlayerLook.options("hair_style")
	if styles.size() < 2:
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	var a := PlayerLook.look({"hair_style": styles[0]})
	var b := PlayerLook.look({"hair_style": styles[1]})
	assert_ne(a["hairstyles"], b["hairstyles"], "a different style is a different hairstyle file")
	assert_true(str(b["hairstyles"]).contains("_%s_" % styles[1]))
