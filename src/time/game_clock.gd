class_name GameClock
extends RefCounted
## World time.
##
## Time is a single integer: minutes elapsed since the world's epoch. Calendar
## fields (year, month, weekday) are derived on demand from a real Gregorian
## calendar via Godot's Time singleton, so month lengths, leap years and
## weekday names are correct for free and there is no bespoke calendar code.
##
## Two advancement modes, per the performance rule that an eight-hour sleep
## must not cost eight hours of ticks:
##
##   tick(delta)      continuous play. Emits minute_passed for each minute.
##   advance(n)       batched jump (sleep, travel, cutscene). Steps to each
##                    queued world event in order so those events observe the
##                    correct time, emits hour/day boundaries, and emits a
##                    single time_skipped at the end. No per-minute signals.

const MINUTES_PER_HOUR := 60
const HOURS_PER_DAY := 24
const MINUTES_PER_DAY := 1440
const DAYS_PER_WEEK := 7

## A jump longer than this stops emitting per-hour signals (still emits days).
const MAX_DETAILED_SKIP_HOURS := 72

const WEEKDAY_KEYS := [
	"weekday.sunday", "weekday.monday", "weekday.tuesday", "weekday.wednesday",
	"weekday.thursday", "weekday.friday", "weekday.saturday",
]

## Default world start: Monday 2 March 2026, 07:00.
const DEFAULT_EPOCH := {"year": 2026, "month": 3, "day": 2, "hour": 0, "minute": 0, "second": 0}
const DEFAULT_START_MINUTE := 7 * 60

var epoch_unix: int = 0
var total_minutes: int = 0
## Optional. When set, batched advancement resolves due events at their time.
var event_queue: WorldEventQueue = null
## Game minutes elapsed per real second during continuous play.
var minutes_per_real_second: float = 1.0
var paused: bool = false

var _accumulator: float = 0.0

signal minute_passed(total_minutes: int)
signal hour_passed(hour: int)
signal day_passed(day_index: int)
signal time_skipped(from_minutes: int, to_minutes: int)


func _init(p_epoch: Dictionary = DEFAULT_EPOCH, p_start_minute: int = DEFAULT_START_MINUTE) -> void:
	epoch_unix = int(Time.get_unix_time_from_datetime_dict(p_epoch))
	total_minutes = p_start_minute


# --- derived fields ---------------------------------------------------------

func unix_time() -> int:
	return epoch_unix + total_minutes * 60


func datetime() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(unix_time())


## Whole days elapsed since epoch. Day 0 is the first day.
func day_index() -> int:
	return total_minutes / MINUTES_PER_DAY


func minute_of_day() -> int:
	return total_minutes % MINUTES_PER_DAY


func hour() -> int:
	return minute_of_day() / MINUTES_PER_HOUR


func minute() -> int:
	return minute_of_day() % MINUTES_PER_HOUR


## 0 = Sunday .. 6 = Saturday, matching Godot's Time.WEEKDAY_* values.
func weekday() -> int:
	return int(datetime().get("weekday", 0))


func weekday_key() -> String:
	return WEEKDAY_KEYS[weekday()]


func is_weekend() -> bool:
	var w := weekday()
	return w == 0 or w == 6


## "07:30"
func format_time() -> String:
	return "%02d:%02d" % [hour(), minute()]


## "Mon 2 Mar 2026"
func format_date() -> String:
	var dt := datetime()
	return "%s %d.%d.%d" % [tr(weekday_key()), dt["day"], dt["month"], dt["year"]]


## Absolute minute of the next occurrence of a given time of day.
func next_time_of_day(target_minute_of_day: int) -> int:
	var today := day_index() * MINUTES_PER_DAY + target_minute_of_day
	return today if today > total_minutes else today + MINUTES_PER_DAY


# --- advancement ------------------------------------------------------------

## Continuous play. Call from _process with the frame delta.
func tick(delta: float) -> void:
	if paused:
		return
	_accumulator += delta * minutes_per_real_second
	if _accumulator < 1.0:
		return
	var whole := int(_accumulator)
	_accumulator -= float(whole)
	for _i in whole:
		_step_one_minute()


## Batched jump used by sleep, travel and scene transitions.
func advance(minutes: int) -> void:
	if minutes <= 0:
		return
	advance_to(total_minutes + minutes)


## Batched jump to an absolute world minute. Safe to call with a past value
## (it is ignored) so callers need not guard.
func advance_to(target: int) -> void:
	if target <= total_minutes:
		return
	var origin := total_minutes
	var detailed := (target - origin) <= MAX_DETAILED_SKIP_HOURS * MINUTES_PER_HOUR

	# Walk to each due world event so its handler observes the correct time.
	while event_queue != null:
		var next_at := event_queue.peek_time()
		if next_at < 0 or next_at > target:
			break
		if next_at > total_minutes:
			_jump_to(next_at, detailed)
		event_queue.drain_due(total_minutes)

	_jump_to(target, detailed)
	time_skipped.emit(origin, total_minutes)


## Sets the clock without emitting anything. Load-time use only.
func set_absolute(minutes: int) -> void:
	total_minutes = maxi(0, minutes)
	_accumulator = 0.0


func _step_one_minute() -> void:
	var prev_hour := hour()
	var prev_day := day_index()
	total_minutes += 1
	minute_passed.emit(total_minutes)
	if hour() != prev_hour:
		hour_passed.emit(hour())
	if day_index() != prev_day:
		day_passed.emit(day_index())
	if event_queue != null:
		event_queue.drain_due(total_minutes)


## Moves to `target` emitting only boundary signals, never per-minute ones.
func _jump_to(target: int, detailed: bool) -> void:
	if target <= total_minutes:
		return
	var prev_hour_abs := total_minutes / MINUTES_PER_HOUR
	var prev_day_abs := total_minutes / MINUTES_PER_DAY
	total_minutes = target
	var new_hour_abs := total_minutes / MINUTES_PER_HOUR
	var new_day_abs := total_minutes / MINUTES_PER_DAY

	if detailed:
		for h in range(prev_hour_abs + 1, new_hour_abs + 1):
			hour_passed.emit(h % HOURS_PER_DAY)
	for d in range(prev_day_abs + 1, new_day_abs + 1):
		day_passed.emit(d)


func to_dict() -> Dictionary:
	return {
		"epoch_unix": epoch_unix,
		"total_minutes": total_minutes,
		"minutes_per_real_second": minutes_per_real_second,
	}


func from_dict(d: Dictionary) -> void:
	epoch_unix = int(d.get("epoch_unix", epoch_unix))
	total_minutes = int(d.get("total_minutes", 0))
	minutes_per_real_second = float(d.get("minutes_per_real_second", 1.0))
	_accumulator = 0.0
