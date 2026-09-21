class_name FollowRules
extends RefCounted
## When someone can walk with the player, and for how long (D-057).
##
## Pure, like `NpcSchedule`: a person can come along only while nothing in
## their own day is due — a shift or the night's sleep. It is decided from the
## routine, not from anything a model said.

## The longest one invitation lasts. After this they go back to their day and
## the player may ask again.
const MAX_MINUTES := 240
## The longest a one-off trip somewhere on the player's say lasts (D-061).
const GO_MINUTES := 120
## Less free time than this and there is no point setting out.
const MIN_MINUTES := 30
## Blocks that end an outing when they begin.
const STOPPING: Array[String] = ["work", "sleep"]


## How many minutes this person is free to come along, 0 when they are on a
## shift or asleep now. `schedule` may be null (someone with no routine).
static func free_minutes(schedule: NpcSchedule, total_minutes: int, weekday: int) -> int:
	if schedule == null:
		return MAX_MINUTES
	var minute_of_day := total_minutes % NpcSchedule.MINUTES_PER_DAY
	if str(schedule.resolve(weekday, minute_of_day).get("activity", "")) in STOPPING:
		return 0
	var next := schedule.next_start_of(STOPPING, weekday, minute_of_day)
	if next < 0:
		return MAX_MINUTES
	return mini(next - minute_of_day, MAX_MINUTES)
