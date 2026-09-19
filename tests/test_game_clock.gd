extends TestCase
## Time advancement: the continuous path, the batched path, and the calendar.

var clock: GameClock


func before_each() -> void:
	clock = GameClock.new()


## Lambdas here that read `clock` hold this test, and the clock holds them:
## let go of the clock so the cycle does not outlive the run.
func after_each() -> void:
	clock = null


func test_starts_at_configured_time() -> void:
	assert_eq(clock.hour(), 7)
	assert_eq(clock.minute(), 0)
	assert_eq(clock.day_index(), 0)
	assert_eq(clock.format_time(), "07:00")


func test_epoch_is_a_monday() -> void:
	# Schedules use weekday numbers; a shifted epoch would silently move
	# everyone's working week.
	assert_eq(clock.weekday(), 1, "world starts on a Monday")


func test_tick_accumulates_partial_minutes() -> void:
	clock.minutes_per_real_second = 1.0
	clock.tick(0.4)
	assert_eq(clock.total_minutes, 420, "less than a minute changes nothing")
	clock.tick(0.7)
	assert_eq(clock.total_minutes, 421, "the fractions add up to one minute")


func test_tick_respects_pause() -> void:
	clock.paused = true
	clock.tick(10.0)
	assert_eq(clock.total_minutes, 420)


func test_minute_signal_fires_once_per_minute() -> void:
	# Counters live in arrays throughout this suite: GDScript lambdas capture
	# locals by value, so incrementing a captured int updates a copy and the
	# assertion silently passes against zero.
	var count := [0]
	clock.minute_passed.connect(func(_t: int) -> void: count[0] += 1)
	clock.minutes_per_real_second = 60.0
	clock.tick(1.0)
	assert_eq(count[0], 60)


func test_advance_does_not_emit_per_minute() -> void:
	# The whole point of batched advancement: an eight-hour sleep must not
	# cost 480 signal dispatches and 480 NPC ticks.
	var minutes := [0]
	var hours := [0]
	clock.minute_passed.connect(func(_t: int) -> void: minutes[0] += 1)
	clock.hour_passed.connect(func(_h: int) -> void: hours[0] += 1)
	clock.advance(480)
	assert_eq(minutes[0], 0, "batched advance emits no per-minute signals")
	assert_eq(hours[0], 8, "but still reports each hour boundary")
	assert_eq(clock.total_minutes, 900)


func test_advance_emits_day_boundaries() -> void:
	var days: Array[int] = []
	clock.day_passed.connect(func(d: int) -> void: days.append(d))
	clock.advance(60 * 24 * 3)
	assert_eq(days.size(), 3)
	assert_eq(clock.day_index(), 3)


func test_very_long_skip_drops_hour_detail() -> void:
	var hours := [0]
	var days := [0]
	clock.hour_passed.connect(func(_h: int) -> void: hours[0] += 1)
	clock.day_passed.connect(func(_d: int) -> void: days[0] += 1)
	clock.advance(60 * 24 * 10)
	assert_eq(hours[0], 0, "a ten-day skip must not emit 240 hour signals")
	assert_eq(days[0], 10)


func test_time_skipped_reports_the_interval() -> void:
	var seen := []
	clock.time_skipped.connect(func(a: int, b: int) -> void:
		seen.append(a)
		seen.append(b))
	clock.advance(120)
	assert_eq(seen[0], 420)
	assert_eq(seen[1], 540)


func test_advance_to_the_past_is_ignored() -> void:
	clock.advance_to(100)
	assert_eq(clock.total_minutes, 420)


func test_advance_resolves_queued_events_at_their_own_time() -> void:
	# An event scheduled mid-skip must observe the clock as it was when the
	# event was due, not as it is at the end of the jump.
	var queue := WorldEventQueue.new()
	clock.event_queue = queue
	var observed: Array[int] = []
	queue.event_due.connect(func(_e: WorldEventQueue.QueuedEvent) -> void:
		observed.append(clock.total_minutes))
	queue.schedule(480, "a")
	queue.schedule(600, "b")
	clock.advance(480)   # 420 -> 900
	assert_eq(observed.size(), 2)
	assert_eq(observed[0], 480, "first event saw 08:00")
	assert_eq(observed[1], 600, "second event saw 10:00")


func test_continuous_tick_drains_events() -> void:
	var queue := WorldEventQueue.new()
	clock.event_queue = queue
	var fired := [0]
	queue.event_due.connect(func(_e: WorldEventQueue.QueuedEvent) -> void: fired[0] += 1)
	queue.schedule(422, "soon")
	clock.minutes_per_real_second = 60.0
	clock.tick(0.1)
	assert_eq(fired[0], 1)


func test_weekend_detection() -> void:
	assert_false(clock.is_weekend(), "Monday is not the weekend")
	clock.advance(60 * 24 * 5)   # -> Saturday
	assert_true(clock.is_weekend())


func test_next_time_of_day_rolls_to_tomorrow() -> void:
	# 07:00 now; 06:00 is tomorrow, 09:00 is today.
	assert_eq(clock.next_time_of_day(9 * 60), 540)
	assert_eq(clock.next_time_of_day(6 * 60), 1440 + 360)


func test_round_trip_through_save() -> void:
	clock.advance(1234)
	var restored := GameClock.new()
	restored.from_dict(clock.to_dict())
	assert_eq(restored.total_minutes, clock.total_minutes)
	assert_eq(restored.format_date(), clock.format_date())
