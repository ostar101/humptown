extends TestCase
## The bag and the bench, merged into one window with tabs (M8 step 3,
## D-079): lay things from the bag on the grid, see what they make, make it;
## the recipe book lays a recipe out; `I` opens on the bag, `C` on the bench,
## and if the window is already open the key switches tab instead of closing.

var _view: WorldView = null


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	Game.player.inventory.clear()
	var packed: PackedScene = load("res://scenes/world/world.tscn")
	_view = packed.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(_view)


func after_each() -> void:
	if _view.items_window().is_open():
		_view.items_window().close()
	_view.free()
	Game.saves.delete_slot("test_items_window")


func _bag(item_id: String, count: int = 1) -> void:
	assert_ok(Game.player.inventory.add(item_id, count))


func _window() -> ItemsWindow:
	_view.open_bench()
	return _view.items_window()


func test_the_key_opens_the_bench_and_walking_waits() -> void:
	var event := InputEventAction.new()
	event.action = "craft"
	event.pressed = true
	_view._unhandled_input(event)
	assert_true(_view.items_window().is_open())
	assert_false(_view.player_body().input_enabled, "you are at the bench, not walking")
	assert_true(Game.clock.paused)
	_view.items_window().close()
	assert_true(_view.player_body().input_enabled)


func test_an_empty_grid_says_what_to_do() -> void:
	var window := _window()
	assert_eq(window.grid_ids(), ["", "", "", "", "", "", "", "", ""] as Array[String])
	assert_eq(window.output_id(), "")
	assert_false(window.can_make())
	assert_true(window.result_text().contains("Lay things"), window.result_text())


func test_laying_things_shows_what_they_make() -> void:
	_bag("item_cannabis_bud")
	_bag("item_rolling_papers")
	var window := _window()
	assert_ok(window.place("item_cannabis_bud"))
	assert_eq(window.output_id(), "", "one ingredient makes nothing yet")
	assert_true(window.result_text().contains("doesn't make anything"))
	assert_ok(window.place("item_rolling_papers"))
	assert_eq(window.output_id(), "item_joint")
	assert_true(window.can_make())
	assert_eq(window.result_text(), "Makes: Joint (3 min)")


func test_a_thing_can_only_be_laid_as_often_as_you_have_it() -> void:
	_bag("item_nails", 2)
	var window := _window()
	assert_ok(window.place("item_nails"))
	assert_ok(window.place("item_nails"))
	assert_err(window.place("item_nails"), "not_owned")
	assert_eq(window.message(), "You don't have enough of that.")
	assert_err(window.place("item_axe"), "not_owned")


func test_the_grid_fills_up() -> void:
	_bag("item_nails", 12)
	var window := _window()
	for i in 9:
		assert_ok(window.place("item_nails"))
	assert_err(window.place("item_nails"), "grid_full")


func test_a_laid_thing_comes_back_off_the_grid_and_the_grid_clears() -> void:
	_bag("item_cannabis_bud")
	_bag("item_rolling_papers")
	var window := _window()
	window.place("item_cannabis_bud")
	window.place("item_rolling_papers")
	window.take_off(0)
	assert_eq(window.grid_ids()[0], "")
	assert_eq(window.output_id(), "")
	window.place("item_cannabis_bud")
	assert_eq(window.grid_ids()[0], "item_cannabis_bud", "the first empty slot")
	window.clear()
	assert_eq(window.grid_ids().count(""), 9)


func test_the_bag_shows_what_is_left_to_lay() -> void:
	_bag("item_nails", 3)
	var window := _window()
	assert_eq(window.bag_texts(), ["item_nails|3"] as Array[String])
	window.place("item_nails")
	assert_eq(window.bag_texts(), ["item_nails|2"] as Array[String])


func test_making_it_uses_the_things_and_says_so() -> void:
	var window := _window()
	_bag("item_cannabis_bud")
	_bag("item_rolling_papers", 2)
	window.place("item_cannabis_bud")
	window.place("item_rolling_papers")
	assert_ok(window.make())
	assert_eq(Game.player.inventory.count_of("item_joint"), 1)
	assert_true(window.message().begins_with("You make: Joint (3 min)."), window.message())
	assert_true(window.message().contains("New recipe."), "the first time")
	assert_eq(window.grid_ids().count("item_cannabis_bud"), 0, "the bud is gone")
	assert_eq(window.grid_ids().count("item_rolling_papers"), 1, "the second paper is still in the bag, so it stays laid")
	assert_true(window.book_texts().has("Roll a joint"))


func test_the_same_thing_can_be_made_again_while_it_lasts() -> void:
	_bag("item_cannabis_bud", 2)
	_bag("item_rolling_papers", 2)
	var window := _window()
	window.place("item_cannabis_bud")
	window.place("item_rolling_papers")
	assert_ok(window.make())
	assert_eq(window.output_id(), "item_joint", "one more of each is in the bag, so the grid still stands")
	assert_ok(window.make())
	assert_eq(Game.player.inventory.count_of("item_joint"), 2)
	assert_eq(window.output_id(), "")


func test_making_what_makes_nothing_is_refused_in_plain_words() -> void:
	_bag("item_lighter")
	var window := _window()
	window.place("item_lighter")
	assert_err(window.make(), "no_recipe")
	assert_eq(window.message(), "That doesn't make anything.")
	assert_eq(Game.player.inventory.count_of("item_lighter"), 1)


func test_the_book_lists_what_you_have_the_makings_of_and_lays_it_out() -> void:
	_bag("item_cannabis_bud")
	_bag("item_rolling_papers")
	var window := _window()
	assert_true(window.book_texts().has("Roll a joint"), "opening the bench finds it")
	assert_ok(window.fill_recipe("rcp_joint_from_bud"))
	assert_eq(window.output_id(), "item_joint")
	assert_err(window.fill_recipe("rcp_first_aid_kit"), "unknown_recipe")


func test_a_recipe_laid_out_short_says_so() -> void:
	_bag("item_cannabis_bud")
	_bag("item_rolling_papers")
	var window := _window()
	Game.player.inventory.remove("item_rolling_papers", 1)
	assert_err(window.fill_recipe("rcp_joint_from_bud"), "missing")
	assert_eq(window.grid_ids().count("item_cannabis_bud"), 1, "what there is, is laid out")
	assert_eq(window.message(), "You don't have everything for that.")


func test_an_empty_book_says_how_to_start() -> void:
	var window := _window()
	assert_eq(window.book_texts(), [] as Array[String])
	assert_true(_view.items_window().get_node("%BookRows").get_child(0) is Label)


func test_the_bench_closes_when_you_collapse() -> void:
	var window := _window()
	assert_true(window.is_open())
	Game.player.stats.health = 0.01
	Game.player.stats.hunger = 1.0
	Game.advance_time(120)
	assert_false(window.is_open())


# --- the merge itself (D-079) -------------------------------------------------

func test_the_bag_key_opens_on_the_bag_tab() -> void:
	_view.open_bag()
	var window := _view.items_window()
	assert_true(window.is_open())
	assert_eq(window.current_tab(), ItemsWindow.Tab.BAG)


func test_pressing_the_other_key_switches_tab_instead_of_closing() -> void:
	_view.open_bag()
	var window := _view.items_window()
	assert_true(window.is_open())
	_view.open_bench()
	assert_true(window.is_open(), "the window stays open")
	assert_eq(window.current_tab(), ItemsWindow.Tab.BENCH)
	_view.open_bag()
	assert_true(window.is_open())
	assert_eq(window.current_tab(), ItemsWindow.Tab.BAG)


func test_the_bag_and_the_bench_share_what_is_carried() -> void:
	_bag("item_sandwich", 1)
	_view.open_bag()
	var window := _view.items_window()
	assert_has(window.row_texts(), "Sandwich|× 1|0.3 kg")
	_view.open_bench()
	assert_eq(window.bag_texts(), ["item_sandwich|1"] as Array[String])
