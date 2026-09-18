extends TestCase
## The way into the game (D-034): the title screen, character creation and
## the opening, driven the way a player would drive them — but with the scene
## change captured, so the test runner's own scene is never replaced.

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const CREATION_SCENE := "res://scenes/ui/character_creation.tscn"
const OPENING_SCENE := "res://scenes/ui/opening.tscn"

var _went_to: Array[String] = []


func before_each() -> void:
	_went_to = []
	Game.saves.delete_slot(Game.save_slot)


func after_each() -> void:
	Game.saves.delete_slot(Game.save_slot)


func _spawn(path: String) -> Node:
	var node: Node = (load(path) as PackedScene).instantiate()
	node.set("scene_changer", func(target: String) -> void: _went_to.append(target))
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	return node


# --- title -----------------------------------------------------------------

func test_continue_is_offered_only_when_there_is_a_life_to_continue() -> void:
	var title: TitleScreen = _spawn(TITLE_SCENE)
	assert_true(title.continue_button().disabled, "no save, nothing to continue")
	title.free()

	Game.new_game("", 7)
	assert_ok(Game.save_game(Game.save_slot))
	title = _spawn(TITLE_SCENE)
	assert_false(title.continue_button().disabled)
	assert_ok(title.continue_saved_game())
	assert_eq(_went_to, [TitleScreen.WORLD], "continuing goes straight into the world")
	title.free()


func test_new_game_goes_to_character_creation() -> void:
	var title: TitleScreen = _spawn(TITLE_SCENE)
	title.start_new_game()
	assert_eq(_went_to, [TitleScreen.CREATION])
	title.free()


# --- creation --------------------------------------------------------------

func test_there_is_a_card_for_every_background() -> void:
	var creation: CharacterCreation = _spawn(CREATION_SCENE)
	var data := DataRegistry.new()
	data.load_all()
	for background_id in data.ids("backgrounds"):
		assert_not_null(creation.card_for(background_id), background_id)
	creation.free()


func test_next_waits_for_a_background_and_then_a_name() -> void:
	var creation: CharacterCreation = _spawn(CREATION_SCENE)
	assert_true(creation.next_button().disabled, "nothing chosen yet")
	assert_err(creation.next(), "not_ready")

	creation.choose_background("bg_trained")
	assert_false(creation.next_button().disabled)
	assert_ok(creation.next())
	assert_eq(creation.step, CharacterCreation.Step.LOOK)
	assert_true(creation.next_button().disabled, "a character needs a name")

	creation.draft.display_name = "Aino"
	creation.cycle_look("hair", 1)
	assert_false(creation.next_button().disabled)
	creation.lower_attribute("strength")
	assert_true(creation.next_button().disabled, "a freed point has to be placed first")
	creation.raise_attribute("wits")
	assert_false(creation.next_button().disabled)
	creation.free()


func test_changing_background_forgets_the_old_reshuffle() -> void:
	var creation: CharacterCreation = _spawn(CREATION_SCENE)
	creation.choose_background("bg_dockhand")
	creation.lower_attribute("strength")
	creation.raise_attribute("wits")
	creation.choose_background("bg_in_debt")
	assert_eq(creation.draft.attribute_shifts, {}, "shifts made for one life do not carry to another")
	creation.free()


func test_begin_starts_the_life_that_was_chosen_and_goes_to_the_opening() -> void:
	var creation: CharacterCreation = _spawn(CREATION_SCENE)
	creation.choose_background("bg_returning")
	assert_ok(creation.next())
	creation.draft.display_name = "[b]Aino[/b]"
	creation.choose_pronouns("she")
	assert_ok(creation.next())
	assert_eq(creation.step, CharacterCreation.Step.CONFIRM)
	var summary: RichTextLabel = creation.get_node("%Summary")
	assert_true(summary.text.contains("[lb]b]Aino"), "the player's own text cannot become markup")

	assert_ok(creation.next())
	assert_eq(_went_to, [CharacterCreation.OPENING])
	assert_true(Game.is_running())
	assert_eq(Game.player.display_name, "[b]Aino[/b]", "stored as typed; only its display is escaped")
	assert_eq(Game.player.background_id, "bg_returning")
	assert_eq(Game.player.pronouns, "she")
	creation.free()


func test_back_from_the_first_page_returns_to_the_title() -> void:
	var creation: CharacterCreation = _spawn(CREATION_SCENE)
	creation.back()
	assert_eq(_went_to, [CharacterCreation.TITLE])
	creation.free()


# --- opening ---------------------------------------------------------------

func test_every_background_has_its_own_opening_ending_on_the_shared_line() -> void:
	var data := DataRegistry.new()
	data.load_all()
	for background_id in data.ids("backgrounds"):
		var keys := Opening.lines_for(background_id)
		assert_gt(float(keys.size()), 1.0, "%s has lines of its own" % background_id)
		assert_true(keys[0].begins_with("opening.%s." % background_id), keys[0])
		assert_eq(keys[keys.size() - 1], Opening.LAST_LINE)
	var fallback := Opening.lines_for("")
	assert_true(fallback[0].begins_with("opening.fallback."), "a life with no background still opens")


func test_the_opening_reveals_a_line_per_key_press_then_leaves_for_the_world() -> void:
	Game.new_game("bg_dockhand", 7)
	var opening: Opening = _spawn(OPENING_SCENE)
	var total := Opening.lines_for("bg_dockhand").size()
	assert_eq(opening.shown_keys().size(), 1, "the first line appears by itself")
	for i in total * 2:
		opening.advance()   # each press finishes a fade or shows the next line
	assert_eq(opening.shown_keys().size(), total, "all of them, in the end")
	opening.advance()
	assert_eq(_went_to, [], "it fades out first rather than cutting away")
	# Real time, not frames: a headless frame is far shorter than a displayed one.
	await opening.get_tree().create_timer(Opening.FADE_SECONDS + 0.3).timeout
	assert_eq(_went_to, [Opening.WORLD], "after the last line, into the world")
	opening.free()
