class_name MeetingRules
extends RefCounted
## What may happen to a meeting (D-047). Pure: a meeting and the state of
## things in, a verdict out. Whether you kept one is a fact of the simulation —
## where you and they stand — never something anyone said.

## Minutes a meeting lasts.
const DURATION := 90
## People are at the place this long before it starts…
const GATHER_LEAD := 30
## …and it is settled this long after it starts: arrive by then or you missed it.
const GRACE := 20
## The player is reminded this long before.
const REMINDER_LEAD := 60
## The least notice a meeting can be accepted with.
const MIN_NOTICE := 30
## Two meetings need this long between them.
const BUFFER := 60
## The hours (of the day) a meeting may start at.
const FIRST_START_HOUR := 12
const START_HOURS := 8


## Whether the player may accept. `state` = {"now", "clash": bool}.
## Codes: `already_answered`, `too_late`, `clash`.
static func judge_accept(meeting: Dictionary, state: Dictionary) -> Result:
	if meeting.is_empty():
		return Result.failure("already_answered")
	if meeting["status"] == "lapsed":
		return Result.failure("too_late")
	if meeting["status"] != "proposed":
		return Result.failure("already_answered")
	if int(meeting["start"]) - int(state.get("now", 0)) < MIN_NOTICE:
		return Result.failure("too_late")
	if bool(state.get("clash", false)):
		return Result.failure("clash")
	return Result.success()


## How a meeting went, from where everyone stood when it was settled.
## `state` = {"player_here", "npc_here", "late": bool} — `late` is a check that
## only got made long after the time (the player slept or skipped through it).
## "kept" · "missed" (you were not there, or you skipped through it) ·
## "stood_up" (they were not there).
static func judge_attendance(state: Dictionary) -> String:
	if bool(state.get("late", false)):
		return "missed"   # nobody can say where they were
	if not bool(state.get("npc_here", false)):
		return "stood_up"
	return "kept" if bool(state.get("player_here", false)) else "missed"


## The hour someone would suggest for a day: spread out by a hash.
static func start_hour(npc_id: String, day: int) -> int:
	return FIRST_START_HOUR + posmod(("meet/%s/%d" % [npc_id, day]).hash(), START_HOURS)


## Whether a place can hold a meeting starting at this minute of the day:
## open when people arrive and when it ends.
static func open_throughout(open_at: Callable, start_minute_of_day: int) -> bool:
	return bool(open_at.call(posmod(start_minute_of_day - GATHER_LEAD, 1440))) \
		and bool(open_at.call((start_minute_of_day + DURATION) % 1440))
