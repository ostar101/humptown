extends TestCase
## Schedule resolution. This is a pure function, and it is what makes an
## unobserved population free, so it gets tested hard.

const WEEKDAY_MONDAY := 1
const WEEKDAY_SATURDAY := 6
const WEEKDAY_SUNDAY := 0

var schedule: NpcSchedule


func before_each() -> void:
	schedule = NpcSchedule.from_data({
		"id": "sched_test",
		"blocks": [
			{"start": 0,    "days": "all",     "location": "@home", "activity": "sleep"},
			{"start": 420,  "days": "weekday", "location": "@work", "activity": "work"},
			{"start": 720,  "days": "weekday", "location": "cafe",  "activity": "lunch"},
			{"start": 780,  "days": "weekday", "location": "@work", "activity": "work"},
			{"start": 1020, "days": "weekday", "location": "@home", "activity": "idle"},
			{"start": 600,  "days": "weekend", "location": "park",  "activity": "walk"},
			{"start": 1320, "days": "all",     "location": "@home", "activity": "sleep"},
		],
	})


func test_blocks_are_sorted_by_start() -> void:
	var previous := -1
	for block in schedule.blocks:
		assert_true(block.start >= previous)
		previous = block.start


func test_resolves_the_active_block() -> void:
	assert_eq(schedule.resolve(WEEKDAY_MONDAY, 500)["activity"], "work")
	assert_eq(schedule.resolve(WEEKDAY_MONDAY, 730)["activity"], "lunch")
	assert_eq(schedule.resolve(WEEKDAY_MONDAY, 900)["activity"], "work")
	assert_eq(schedule.resolve(WEEKDAY_MONDAY, 1100)["activity"], "idle")


func test_boundary_minute_belongs_to_the_new_block() -> void:
	assert_eq(schedule.resolve(WEEKDAY_MONDAY, 419)["activity"], "sleep")
	assert_eq(schedule.resolve(WEEKDAY_MONDAY, 420)["activity"], "work")


func test_weekday_blocks_do_not_apply_at_the_weekend() -> void:
	assert_eq(schedule.resolve(WEEKDAY_SATURDAY, 500)["activity"], "sleep",
		"no work block applies, so Saturday morning is still the night block")
	assert_eq(schedule.resolve(WEEKDAY_SATURDAY, 700)["activity"], "walk")


func test_before_the_first_block_wraps_to_yesterday() -> void:
	# 05:00 Sunday: nothing has started today, so the person is still inside
	# Saturday's last block. Getting this wrong teleports everyone home at
	# midnight.
	var resolved := schedule.resolve(WEEKDAY_SUNDAY, 300)
	assert_eq(resolved["activity"], "sleep")


func test_explicit_day_lists() -> void:
	var weekly := NpcSchedule.from_data({
		"id": "s", "blocks": [
			{"start": 600, "days": [3], "location": "hall", "activity": "meeting"},
			{"start": 0, "days": "all", "location": "@home", "activity": "sleep"},
		]})
	assert_eq(weekly.resolve(3, 700)["activity"], "meeting")
	assert_eq(weekly.resolve(4, 700)["activity"], "sleep")


func test_empty_schedule_falls_back_to_defaults() -> void:
	var empty := NpcSchedule.from_data({
		"id": "s", "blocks": [], "default_location": "nowhere", "default_activity": "loiter"})
	var resolved := empty.resolve(WEEKDAY_MONDAY, 600)
	assert_eq(resolved["location"], "nowhere")
	assert_eq(resolved["activity"], "loiter")


func test_resolution_is_pure() -> void:
	# Same inputs, same answer, no accumulated state. This is the property
	# that lets a dormant NPC's position be computed instead of simulated.
	var first := schedule.resolve(WEEKDAY_MONDAY, 800)
	for _i in range(50):
		schedule.resolve(WEEKDAY_SATURDAY, 100)
	var second := schedule.resolve(WEEKDAY_MONDAY, 800)
	assert_eq(second["activity"], first["activity"])
	assert_eq(second["location"], first["location"])


func test_override_takes_precedence() -> void:
	var override := NpcSchedule.Override.new()
	override.from_minutes = 1000
	override.to_minutes = 1100
	override.location = "police_post"
	override.activity = "questioned"
	override.reason = "witness_statement"

	var inside := schedule.resolve_at(1050, WEEKDAY_MONDAY, override)
	assert_eq(inside["activity"], "questioned")
	assert_true(inside["overridden"])
	assert_eq(inside["reason"], "witness_statement")


func test_override_expires() -> void:
	var override := NpcSchedule.Override.new()
	override.from_minutes = 1000
	override.to_minutes = 1100
	override.location = "police_post"
	override.activity = "questioned"

	var after := schedule.resolve_at(1100, WEEKDAY_MONDAY, override)
	assert_false(after["overridden"])
	assert_eq(after["activity"], "idle")


func test_override_round_trips() -> void:
	var override := NpcSchedule.Override.new()
	override.from_minutes = 10
	override.to_minutes = 20
	override.location = "x"
	override.activity = "y"
	override.reason = "z"
	var restored := NpcSchedule.Override.from_dict(override.to_dict())
	assert_eq(restored.from_minutes, 10)
	assert_eq(restored.reason, "z")
	assert_true(restored.covers(15))
	assert_false(restored.covers(20))


func test_next_change_lets_us_schedule_instead_of_poll() -> void:
	assert_eq(schedule.next_change_after(WEEKDAY_MONDAY, 500), 720)
	assert_eq(schedule.next_change_after(WEEKDAY_MONDAY, 1330), 1440,
		"past the last block of today it reports tomorrow's first boundary")


func test_tokens_are_recognised() -> void:
	assert_true(NpcSchedule.is_token("@home"))
	assert_true(NpcSchedule.is_token("@work"))
	assert_false(NpcSchedule.is_token("loc_harbour"))
