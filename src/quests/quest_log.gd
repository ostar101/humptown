class_name QuestLog
extends RefCounted
## The player's quests (D-044): authored story threads from
## `data/quests.json`, and errands — small jobs people need doing — from
## `data/errands.json`. This holds where each one stands and moves it on;
## `QuestRules` says when a stage is met, and `Game` carries out what
## finishing or failing one does. Saved as the `quests` section.

var _data: DataRegistry = null
## quest id -> {"stage": int, "progress": {}, "started_day": int, "deadline_day": int,
## "extra_need": int} — `extra_need` is what has been added to a sum the stage
## asks for (interest, D-053).
var active: Dictionary = {}
## quest id -> "done" | "failed", in the order they ended
var finished: Dictionary = {}
## quest id -> where a quest that failed stood when it did: {"paid", "extra_need"}
## — what had already been put towards a sum, and what had been added to it. A
## debt let fail is still owed, less what was paid and plus its interest
## (D-090).
var lapsed: Dictionary = {}
## errand id -> {"taken_day": int}
var errands: Dictionary = {}
## errand id -> day last done
var errands_done: Dictionary = {}


func setup(data: DataRegistry) -> void:
	_data = data


func definition(quest_id: String) -> Dictionary:
	return _data.get_entry("quests", quest_id) if _data != null else {}


func errand(errand_id: String) -> Dictionary:
	return _data.get_entry("errands", errand_id) if _data != null else {}


func start(quest_id: String, day: int) -> bool:
	if active.has(quest_id) or finished.has(quest_id) or definition(quest_id).is_empty():
		return false
	var days := int(definition(quest_id).get("deadline_days", 0))
	active[quest_id] = {"stage": 0, "progress": {}, "started_day": day, "deadline_day": day + days if days > 0 else -1,
		"extra_need": 0}
	return true


## The stage a quest is on, as data.
func current_stage(quest_id: String) -> Dictionary:
	var stages: Array = definition(quest_id).get("stages", [])
	var at := int(active.get(quest_id, {}).get("stage", 0))
	return stages[at] if at < stages.size() else {}


## A deed towards every active quest. Returns the quests it moved:
## [{"quest", "status": "advanced" | "done"}].
func on_deed(kind: String, data: Dictionary, feeling: Callable) -> Array[Dictionary]:
	var moved: Array[Dictionary] = []
	for quest_id in active.keys():
		var state: Dictionary = active[quest_id]
		var when: Dictionary = current_stage(quest_id).get("when", {})
		state["progress"] = QuestRules.count_deed(when, state["progress"], kind, data)
		var status := _advance_while_met(quest_id, feeling)
		if status != "":
			moved.append({"quest": quest_id, "status": status})
	return moved


## Looks again at stages that wait on the world rather than a deed (how
## someone feels). Returns the quests it moved, as `on_deed` does.
func recheck(feeling: Callable) -> Array[Dictionary]:
	var moved: Array[Dictionary] = []
	for quest_id in active.keys():
		var status := _advance_while_met(quest_id, feeling)
		if status != "":
			moved.append({"quest": quest_id, "status": status})
	return moved


## Moves a quest's deadline, earlier or later (D-053). No effect on a quest
## without one, or not under way.
func extend_deadline(quest_id: String, days: int) -> void:
	if active.has(quest_id) and int(active[quest_id].get("deadline_day", -1)) >= 0:
		active[quest_id]["deadline_day"] = int(active[quest_id]["deadline_day"]) + days


## Adds to the sum a stage asks for: a debt that has grown.
func raise_requirement(quest_id: String, amount: int) -> void:
	if active.has(quest_id):
		active[quest_id]["extra_need"] = int(active[quest_id].get("extra_need", 0)) + amount


## Quests whose deadline has passed by `day`: failed, and returned.
func expire(day: int) -> Array[String]:
	var failed: Array[String] = []
	for quest_id in active.keys():
		var deadline := int(active[quest_id].get("deadline_day", -1))
		if deadline >= 0 and day > deadline:
			var state: Dictionary = active[quest_id]
			lapsed[quest_id] = {"paid": int((state.get("progress", {}) as Dictionary).get("sum", 0)),
				"extra_need": int(state.get("extra_need", 0))}
			active.erase(quest_id)
			finished[quest_id] = "failed"
			failed.append(str(quest_id))
	return failed


# --- errands ------------------------------------------------------------------------

## The errand this person could ask for today, or "".
func errand_offered_by(npc_id: String, today: int) -> String:
	if _data == null:
		return ""
	for errand_id in _data.ids("errands"):
		var e := errand(errand_id)
		if str(e.get("giver", "")) == npc_id and QuestRules.errand_available(
				errands.has(errand_id), int(errands_done.get(errand_id, -1)), int(e.get("every_days", 7)), today):
			return str(errand_id)
	return ""


## The errand this person is waiting on, or "".
func errand_running_for(npc_id: String) -> String:
	for errand_id in errands:
		if str(errand(errand_id).get("giver", "")) == npc_id:
			return str(errand_id)
	return ""


func take_errand(errand_id: String, day: int) -> void:
	errands[errand_id] = {"taken_day": day}


func finish_errand(errand_id: String, day: int) -> void:
	errands.erase(errand_id)
	errands_done[errand_id] = day


func to_dict() -> Dictionary:
	return {"active": active.duplicate(true), "finished": finished.duplicate(), "lapsed": lapsed.duplicate(true),
		"errands": errands.duplicate(true), "errands_done": errands_done.duplicate()}


## Restores what the save says, dropping anything the data no longer has.
func from_dict(d: Dictionary) -> void:
	active = {}
	var raw_active: Dictionary = d.get("active", {})
	for quest_id in raw_active:
		if not definition(str(quest_id)).is_empty():
			var raw: Dictionary = raw_active[quest_id]
			active[str(quest_id)] = {
				"stage": int(raw.get("stage", 0)), "progress": raw.get("progress", {}),
				"started_day": int(raw.get("started_day", 0)), "deadline_day": int(raw.get("deadline_day", -1)),
				"extra_need": int(raw.get("extra_need", 0)),
			}
	finished = {}
	var raw_finished: Dictionary = d.get("finished", {})
	for quest_id in raw_finished:
		finished[str(quest_id)] = str(raw_finished[quest_id])
	lapsed = {}
	var raw_lapsed: Dictionary = d.get("lapsed", {})
	for quest_id in raw_lapsed:
		var raw: Dictionary = raw_lapsed[quest_id]
		lapsed[str(quest_id)] = {"paid": int(raw.get("paid", 0)), "extra_need": int(raw.get("extra_need", 0))}
	errands = {}
	var raw_errands: Dictionary = d.get("errands", {})
	for errand_id in raw_errands:
		if not errand(str(errand_id)).is_empty():
			errands[str(errand_id)] = {"taken_day": int((raw_errands[errand_id] as Dictionary).get("taken_day", 0))}
	errands_done = {}
	var raw_done: Dictionary = d.get("errands_done", {})
	for errand_id in raw_done:
		errands_done[str(errand_id)] = int(raw_done[errand_id])


func _advance_while_met(quest_id: String, feeling: Callable) -> String:
	var status := ""
	var stages: Array = definition(quest_id).get("stages", [])
	while active.has(quest_id):
		var state: Dictionary = active[quest_id]
		var when: Dictionary = current_stage(quest_id).get("when", {})
		if when.is_empty() or not QuestRules.is_met(when, state["progress"], feeling, int(state.get("extra_need", 0))):
			break
		state["stage"] = int(state["stage"]) + 1
		state["progress"] = {}
		status = "advanced"
		if int(state["stage"]) >= stages.size():
			active.erase(quest_id)
			finished[quest_id] = "done"
			status = "done"
	return status
