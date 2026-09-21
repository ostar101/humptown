extends TestCase
## DayNight and the lighting it drives (D-032): the tint over the world by
## time of day, street lamps that come on as it gets dark, and a building's
## inside that is never darkened.

const WORLD_SCENE := "res://scenes/world/world.tscn"


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)


func test_the_middle_of_the_day_is_untinted() -> void:
	for minute in [600, 720, 900]:
		assert_eq(DayNight.tint_at(minute), Color.WHITE, "%d" % minute)


func test_the_night_is_darker_than_dusk_and_leans_blue() -> void:
	var midnight := DayNight.tint_at(0)
	var dusk := DayNight.tint_at(1110)
	assert_lt(midnight.get_luminance(), dusk.get_luminance())
	assert_lt(dusk.get_luminance(), Color.WHITE.get_luminance())
	assert_gt(midnight.b, midnight.r, "moonlight, not a brown-out")


## Time advances a minute at a time; a tint that jumped between two minutes
## would flash on screen.
func test_the_tint_never_jumps_between_one_minute_and_the_next() -> void:
	var worst := 0.0
	for minute in GameClock.MINUTES_PER_DAY:
		var a := DayNight.tint_at(minute)
		var b := DayNight.tint_at(minute + 1)
		worst = maxf(worst, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
	assert_lt(worst, 0.02, "the largest per-minute change is %f" % worst)


func test_the_tint_wraps_round_midnight() -> void:
	assert_eq(DayNight.tint_at(1440 + 30), DayNight.tint_at(30))
	assert_eq(DayNight.tint_at(-60), DayNight.tint_at(1380))


func test_the_keyframes_start_at_midnight_and_are_in_order() -> void:
	assert_eq(int(DayNight.KEYS[0][0]), 0)
	for i in range(1, DayNight.KEYS.size()):
		assert_gt(float(DayNight.KEYS[i][0]), float(DayNight.KEYS[i - 1][0]))
	assert_lt(float(DayNight.KEYS[DayNight.KEYS.size() - 1][0]), float(GameClock.MINUTES_PER_DAY))


func test_the_lamps_are_off_by_day_on_by_night_and_warming_up_at_dusk() -> void:
	assert_eq(DayNight.lamp_energy_at(720), 0.0, "noon")
	assert_eq(DayNight.lamp_energy_at(0), 1.0, "midnight")
	var dusk := DayNight.lamp_energy_at(1140)
	assert_gt(dusk, 0.0, "coming on at 19:00")
	assert_lt(dusk, 1.0, "not yet full at 19:00")


func test_no_lamp_ever_burns_in_full_daylight() -> void:
	for minute in range(0, GameClock.MINUTES_PER_DAY, 5):
		if DayNight.tint_at(minute) == Color.WHITE:
			assert_eq(DayNight.lamp_energy_at(minute), 0.0, "lit at %d in daylight" % minute)


# --- RegionView ----------------------------------------------------------

func _view_at(cell: Vector2i) -> RegionView:
	var view := RegionView.new()
	view.show_map(Game.world.map_for("harbourside"))
	view.focus_on(DistrictMap.cell_to_world(cell))
	return view


func test_every_street_lamp_carries_a_light_and_nothing_else_does() -> void:
	var view := _view_at(Vector2i(20, 30))
	var lamps := 0
	for chunk_root: Node in view.get_children():
		for child in chunk_root.get_children():
			if child is Sprite2D and str((child as Sprite2D).texture.resource_path).ends_with("lamp.png"):
				lamps += 1
				assert_not_null(child.get_node_or_null("Light"), "a lamp has its light")
	assert_eq(view.lamp_lights().size(), lamps)
	if not StreetProps.available():
		assert_eq(lamps, 0, "art not installed on this machine; no lamps, no lights")
	view.free()


func test_lamps_are_disabled_by_day_and_lit_by_night() -> void:
	var view := _view_at(Vector2i(20, 30))
	if view.lamp_lights().is_empty():
		assert_true(true, "art not installed on this machine; nothing to light")
		view.free()
		return
	view.set_lamp_energy(0.0)
	for light in view.lamp_lights():
		assert_false(light.enabled, "a lamp at zero costs nothing to draw")
	view.set_lamp_energy(1.0)
	for light in view.lamp_lights():
		assert_true(light.enabled)
		assert_almost(light.energy, RegionView.LAMP_LIGHT_ENERGY, 0.001)
	view.free()


func test_every_lit_lamp_shines_a_beam_as_well_as_a_pool() -> void:
	var view := _view_at(Vector2i(20, 30))
	if view.lamp_lights().is_empty():
		assert_true(true, "art not installed on this machine; nothing to light")
		view.free()
		return
	view.set_lamp_energy(1.0)
	for light in view.lamp_lights():
		var beam := light.get_node_or_null("Beam") as PointLight2D
		assert_not_null(beam, "a lamp has a beam")
		assert_true(beam.enabled)
		assert_almost(beam.energy, RegionView.LAMP_BEAM_ENERGY, 0.001)
		assert_lt(beam.position.y, 0.0, "the beam's middle is above the ground, its tip at the lamp head")
	view.set_lamp_energy(0.0)
	for light in view.lamp_lights():
		assert_false((light.get_node("Beam") as PointLight2D).enabled, "off by day")
	view.free()


func test_the_beam_is_a_cone_narrow_at_the_lamp_and_wide_below_it() -> void:
	var image := RegionView._lamp_beam_texture().get_image()
	var width := func(y: int) -> int:
		var lit := 0
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.08:
				lit += 1
		return lit
	assert_lt(width.call(8), width.call(60), "wider halfway down")
	assert_lt(width.call(60), width.call(image.get_height() - 30), "wider still near the ground")
	assert_gt(image.get_pixel(image.get_width() / 2, 4).a, 0.3, "bright on the axis near the head")
	assert_eq(image.get_pixel(0, 60).a, 0.0, "nothing far off to the side")


func test_a_chunk_streamed_in_after_dark_is_lit_as_it_appears() -> void:
	var view := _view_at(Vector2i(4, 4))
	view.set_lamp_energy(1.0)
	var before := view.lamp_lights().size()
	view.focus_on(DistrictMap.cell_to_world(Vector2i(80, 44)))
	var lit := view.lamp_lights()
	if lit.is_empty():
		assert_eq(before, 0, "art not installed on this machine; nothing to light")
		view.free()
		return
	for light in lit:
		assert_true(light.enabled, "a lamp in a newly streamed chunk is already on")
	view.free()


# --- the world scene ------------------------------------------------------

func _spawn_world() -> WorldView:
	var packed: PackedScene = load(WORLD_SCENE)
	var view: WorldView = packed.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	return view


func test_the_world_darkens_as_the_clock_reaches_night() -> void:
	var view := _spawn_world()
	var morning := view.daylight().color
	Game.advance_time(16 * 60)   # 07:00 -> 23:00
	var night := view.daylight().color
	assert_lt(night.get_luminance(), morning.get_luminance(), "the tint follows the clock")
	assert_eq(night, DayNight.tint_at(Game.clock.minute_of_day()))
	assert_eq(view.region_view().lamp_energy, 1.0, "the street lamps are on")
	view.free()


func test_indoors_is_never_darkened() -> void:
	var view := _spawn_world()
	Game.advance_time(16 * 60)
	var map := Game.current_map()
	var door: Vector2i = map.buildings["loc_player_flat"]["door"]
	assert_ok(Game.move_player(DistrictMap.cell_to_world(door + Vector2i.DOWN)))
	assert_ok(Game.interact_at(door))
	view.show_current_area()
	assert_true(Game.current_map().is_interior())
	assert_eq(view.daylight().color, Color.WHITE, "the lights are on inside")
	view.free()
