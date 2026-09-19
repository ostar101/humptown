class_name QuestRules
extends RefCounted
## When a quest's stage is done (D-044). Pure: a stage's condition, what has
## been counted towards it so far, and a deed or a look at the world in; the
## new count, and whether it is met, out.
##
## Progress comes from *deeds* — things the player did that Godot already
## decided and carried out, announced as `Events.player_deed(kind, data)`:
## worked_shift {job}, gave_money {npc, amount}, talked {npc, kind, subject},
## texted {npc, kind, subject} (as talked, by phone), met {npc, location} (a
## meeting kept), hired {job}, bought
## {item, shop, quantity}, entered {location},
## errand_done {errand, npc}. A model never advances a quest; at most, words
## a model read become an intent the rules judged, which became a deed.
##
## A stage's `when`:
##   {"deed": kind, "match": {field: value}}                  — once
##   {"deed": kind, "match": {...}, "count": n}               — n times
##   {"deed": kind, "match": {...}, "sum": field, "at_least": n} — adding up
##   {"feeling": {"npc", "dimension", "at_least"}}            — a relationship
##   {"open": true}                                           — never: a thread
##                                                              that continues later

## Every deed the game announces; a quest may wait only on these.
const DEEDS: Array[String] = ["worked_shift", "gave_money", "talked", "texted", "met", "hired", "bought", "entered", "errand_done"]


## Counts a deed towards a stage. Returns the new progress ({"count", "sum"})
## — the same when the deed does not match.
static func count_deed(when: Dictionary, progress: Dictionary, kind: String, data: Dictionary) -> Dictionary:
	if str(when.get("deed", "")) != kind or not matches(when.get("match", {}), data):
		return progress
	var out := progress.duplicate()
	out["count"] = int(out.get("count", 0)) + 1
	var field := str(when.get("sum", ""))
	if field != "":
		out["sum"] = int(out.get("sum", 0)) + int(data.get(field, 0))
	return out


## Whether a stage is met, from its progress and — for feelings — how one
## person feels about the player (`feeling(npc_id, dimension) -> float`).
static func is_met(when: Dictionary, progress: Dictionary, feeling: Callable) -> bool:
	if bool(when.get("open", false)):
		return false
	if when.has("feeling"):
		var f: Dictionary = when["feeling"]
		return float(feeling.call(str(f.get("npc", "")), str(f.get("dimension", "")))) >= float(f.get("at_least", 1.0))
	if str(when.get("sum", "")) != "":
		return int(progress.get("sum", 0)) >= int(when.get("at_least", 1))
	return int(progress.get("count", 0)) >= int(when.get("count", 1))


## How far along a stage is, for the log: {"have", "need"}, or {} when the
## stage is not a count worth showing.
static func progress_of(when: Dictionary, progress: Dictionary) -> Dictionary:
	if str(when.get("sum", "")) != "":
		return {"have": int(progress.get("sum", 0)), "need": int(when.get("at_least", 1))}
	if int(when.get("count", 1)) > 1:
		return {"have": int(progress.get("count", 0)), "need": int(when.get("count", 1))}
	return {}


static func matches(pattern: Dictionary, data: Dictionary) -> bool:
	for field in pattern:
		if str(data.get(field, "")) != str(pattern[field]):
			return false
	return true


## Whether an errand can be offered now: not already running, not done too
## recently. `last_done` is the day it was last done, -1 for never.
static func errand_available(active: bool, last_done: int, every_days: int, today: int) -> bool:
	return not active and (last_done < 0 or today - last_done >= every_days)
