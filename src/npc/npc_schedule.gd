class_name NpcSchedule
extends RefCounted
## A data-driven daily routine, resolved as a pure function of time.
##
## This is the single most important performance decision in the NPC system.
## Because resolve() is pure — given a weekday and a minute of day it returns
## where someone is and what they are doing — a dormant NPC needs no ticking
## at all. Their position is *computed on demand*, not simulated. A town of
## two thousand people costs nothing until you look at them.
##
## Data shape (res://data/schedules.json):
##   {
##     "id": "sched_shopkeeper",
##     "blocks": [
##       {"start": 0,   "days": "all",     "location": "home",  "activity": "sleep"},
##       {"start": 450, "days": "weekday", "location": "shop",  "activity": "work"},
##       {"start": 1020,"days": "weekday", "location": "bar",   "activity": "socialise"}
##     ]
##   }
##
## `start` is minutes from midnight. `days` is "all" | "weekday" | "weekend"
## | an array of weekday numbers (0 = Sunday). A block runs until the next
## applicable block begins, wrapping across midnight and across days.
##
## A block's location may be a literal location id or a symbolic token —
## "@home" or "@work" — resolved per NPC by NpcRegistry. Tokens are what let
## one routine serve every dockhand in the town instead of needing a
## near-identical schedule per person.

class Block extends RefCounted:
	var start: int = 0
	var location: String = ""
	var activity: String = "idle"
	var days: Variant = "all"
	## Higher priority wins when two blocks start at the same minute.
	var priority: int = 0

	func applies_on(weekday: int) -> bool:
		if typeof(days) == TYPE_STRING:
			match days:
				"all": return true
				"weekday": return weekday >= 1 and weekday <= 5
				"weekend": return weekday == 0 or weekday == 6
				_: return true
		if typeof(days) == TYPE_ARRAY:
			for d in days:
				if int(d) == weekday:
					return true
			return false
		return true


## A temporary replacement for the normal routine: a meeting, an injury, a
## police summons. Overrides are what let events bend a life without
## rewriting the schedule data.
class Override extends RefCounted:
	var from_minutes: int = 0
	var to_minutes: int = 0
	var location: String = ""
	var activity: String = ""
	var reason: String = ""

	func covers(total_minutes: int) -> bool:
		return total_minutes >= from_minutes and total_minutes < to_minutes

	func to_dict() -> Dictionary:
		return {
			"from": from_minutes, "to": to_minutes, "location": location,
			"activity": activity, "reason": reason,
		}

	static func from_dict(d: Dictionary) -> Override:
		var o := Override.new()
		o.from_minutes = int(d.get("from", 0))
		o.to_minutes = int(d.get("to", 0))
		o.location = str(d.get("location", ""))
		o.activity = str(d.get("activity", ""))
		o.reason = str(d.get("reason", ""))
		return o


const MINUTES_PER_DAY := 1440

## Symbolic locations resolved against the individual NPC.
const TOKEN_HOME := "@home"
const TOKEN_WORK := "@work"


static func is_token(location: String) -> bool:
	return location.begins_with("@")


var id: String
var blocks: Array[Block] = []
## Where this routine falls back to when nothing matches.
var default_location: String = ""
var default_activity: String = "idle"


static func from_data(d: Dictionary) -> NpcSchedule:
	var s := NpcSchedule.new()
	s.id = str(d.get("id", ""))
	s.default_activity = str(d.get("default_activity", "idle"))
	s.default_location = str(d.get("default_location", ""))
	var parsed: Array[Block] = []
	for raw in d.get("blocks", []):
		var b := Block.new()
		b.start = clampi(int(raw.get("start", 0)), 0, MINUTES_PER_DAY - 1)
		b.location = str(raw.get("location", ""))
		b.activity = str(raw.get("activity", "idle"))
		b.days = raw.get("days", "all")
		b.priority = int(raw.get("priority", 0))
		parsed.append(b)
	parsed.sort_custom(func(a: Block, b: Block) -> bool:
		if a.start != b.start:
			return a.start < b.start
		return a.priority > b.priority)
	s.blocks = parsed
	return s


## Resolves the active block for a weekday and minute of day.
## Pure: no state is read or written. Returns {location, activity, start}.
func resolve(weekday: int, minute_of_day: int) -> Dictionary:
	# Latest applicable block that has already begun today.
	var best: Block = null
	for b in blocks:
		if b.start > minute_of_day:
			break
		if b.applies_on(weekday):
			best = b
	if best != null:
		return {"location": best.location, "activity": best.activity, "start": best.start}

	# Nothing yet today: the person is still inside yesterday's last block.
	for back in range(1, 8):
		var day := (weekday - back + 7) % 7
		var last: Block = null
		for b in blocks:
			if b.applies_on(day):
				last = b
		if last != null:
			return {
				"location": last.location,
				"activity": last.activity,
				"start": last.start - back * MINUTES_PER_DAY,
			}

	return {"location": default_location, "activity": default_activity, "start": 0}


## Resolves from an absolute world minute, honouring an override if present.
func resolve_at(total_minutes: int, weekday: int, override: Override = null) -> Dictionary:
	if override != null and override.covers(total_minutes):
		return {
			"location": override.location,
			"activity": override.activity,
			"start": override.from_minutes,
			"overridden": true,
			"reason": override.reason,
		}
	var out := resolve(weekday, total_minutes % MINUTES_PER_DAY)
	out["overridden"] = false
	return out


## Absolute-minute offset of the next block boundary, so a caller can schedule
## one re-evaluation instead of polling every minute. It reports the next
## boundary, not necessarily a behavioural change: two consecutive blocks may
## resolve to the same place, and re-evaluating once is cheaper than proving
## they do not. Returns -1 for a schedule with no blocks.
func next_change_after(weekday: int, minute_of_day: int) -> int:
	for b in blocks:
		if b.start > minute_of_day and b.applies_on(weekday):
			return b.start
	for back in range(1, 8):
		var day := (weekday + back) % 7
		for b in blocks:
			if b.applies_on(day):
				return b.start + back * MINUTES_PER_DAY
	return -1


## Like `next_change_after`, but only for blocks whose activity is one of
## `activities`: when does the next shift or the next night's sleep begin?
## Minutes from midnight today, so it may be past 1440. -1 when there is none.
func next_start_of(activities: Array, weekday: int, minute_of_day: int) -> int:
	for b in blocks:
		if b.start > minute_of_day and b.applies_on(weekday) and b.activity in activities:
			return b.start
	for back in range(1, 8):
		var day := (weekday + back) % 7
		for b in blocks:
			if b.applies_on(day) and b.activity in activities:
				return b.start + back * MINUTES_PER_DAY
	return -1
