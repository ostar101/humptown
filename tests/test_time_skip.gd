extends TestCase
## Time passing on screen (D-076): sleeping, a shift, a long walk and a collapse
## play a short scene instead of jumping; nothing in it decides anything.

var _view: WorldView = null


func before_each() -> void:
	Game.new_game("bg_dockhand", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	var packed: PackedScene = load("res://scenes/world/world.tscn")
	_view = packed.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(_view)


func after_each() -> void:
	_view.free()


func _overlay() -> TimeSkipOverlay:
	return _view.time_skip()


# --- the overlay itself -------------------------------------------------------------------------

func test_it_starts_quiet_and_plays_when_asked() -> void:
	var overlay := _overlay()
	assert_false(overlay.is_playing())
	overlay.play("Sleeping…", 23 * 60, 31 * 60)
	assert_true(overlay.is_playing())
	assert_eq(overlay.shown_title(), "Sleeping…")
	assert_eq(overlay.shown_time(), "23:00", "the clock starts at the start")
	overlay.skip()


func test_skipping_ends_it_and_says_so() -> void:
	var overlay := _overlay()
	var done := [0]
	overlay.finished.connect(func() -> void: done[0] += 1)
	overlay.play("Working…", 8 * 60, 16 * 60)
	overlay.skip()
	assert_false(overlay.is_playing())
	assert_eq(done[0], 1)
	overlay.skip()
	assert_eq(done[0], 1, "skipping what is not playing does nothing")


func test_the_clock_runs_from_then_to_now_and_wraps_midnight() -> void:
	var overlay := _overlay()
	overlay.play("Sleeping…", 23 * 60 + 30, 31 * 60 + 30)
	overlay._set_progress(0.0)
	assert_eq(overlay.shown_time(), "23:30")
	overlay._set_progress(0.5)
	assert_eq(overlay.shown_time(), "03:30", "halfway through the night")
	overlay._set_progress(1.0)
	assert_eq(overlay.shown_time(), "07:30")
	overlay.skip()


func test_a_scene_with_no_span_shows_no_clock() -> void:
	var overlay := _overlay()
	overlay.play("Everything goes dark…", 0, 0)
	assert_false((overlay.get_node("%Clock") as Label).visible)
	overlay.skip()


# --- in the world ---------------------------------------------------------------------------------

func _go_to_bed_tired() -> void:
	var home := Game.player.home_location
	Game.player.interior = home
	var inside := Game.world.interior_for(home)
	Game.player.position = DistrictMap.cell_to_world(Vector2i(3, 2))
	_view.show_current_area()
	_view.player_body().place_at(DistrictMap.cell_to_world(Vector2i(3, 2)))
	_view.player_body().face(Vector2i.LEFT)
	Game.clock.advance(posmod(23 * 60 - Game.clock.minute_of_day(), 1440))
	Game.player.stats.sleep = 0.2
	assert_true(inside != null)


func test_sleeping_plays_the_scene_holds_the_player_and_shows_the_message_after() -> void:
	_go_to_bed_tired()
	var slept := _view.interact()
	assert_ok(slept)
	var overlay := _overlay()
	assert_true(overlay.is_playing())
	assert_eq(overlay.shown_title(), "Sleeping…")
	assert_eq(overlay.shown_time(), "23:00", "it shows the night that just went by, from when you lay down")
	assert_false(_view.player_body().input_enabled, "no walking about during it")
	assert_true(Game.clock.paused)
	assert_eq(_view.hud().message_text(), "", "the message waits for the morning")
	overlay.skip()
	assert_true(_view.player_body().input_enabled)
	assert_true(_view.hud().message_text().begins_with("You sleep, and wake at"), _view.hud().message_text())
	assert_eq(Game.clock.minute_of_day(), Game.WAKE_MINUTE, "the world was already in the morning")


func test_a_refused_bed_plays_nothing() -> void:
	_go_to_bed_tired()
	Game.player.stats.sleep = 1.0
	assert_err(_view.interact(), "not_tired")
	assert_false(_overlay().is_playing())
	assert_true(_view.hud().message_text() != "", "the refusal is said at once")


func test_a_long_walk_between_districts_plays_the_scene() -> void:
	Game.world.set_flag("heard_about_old_town")
	Game.move_player(DistrictMap.cell_to_world(Vector2i(44, 0)))
	var overlay := _overlay()
	assert_true(overlay.is_playing())
	assert_eq(overlay.shown_title(), "Walking to Old Town…")
	overlay.skip()
	assert_true(_view.player_body().input_enabled)


func test_a_collapse_plays_the_scene_without_a_clock() -> void:
	Game.player.stats.health = 0.01
	Game.player.stats.hunger = 1.0
	Game.advance_time(120)
	var overlay := _overlay()
	assert_true(overlay.is_playing())
	assert_eq(overlay.shown_title(), "Everything goes dark…")
	overlay.skip()
