class_name QuestText
extends RefCounted
## The words for quests (D-044): the log's entries and the HUD's one-liners.
## Goals say what to do, never how to get there — no routes, no markers.


## The log, under way first (quests, then errands), then what is behind you:
## [{"title", "from", "goal", "when", "status"}].
static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not Game.is_running():
		return out
	var book := Game.quests
	for quest_id in book.active:
		var quest := book.definition(quest_id)
		var state: Dictionary = book.active[quest_id]
		var stage := book.current_stage(quest_id)
		var goal := Localization.t(str(stage.get("goal_key", "")))
		var done := QuestRules.progress_of(stage.get("when", {}), state.get("progress", {}))
		if not done.is_empty():
			goal += " " + Localization.t("ui.quests.progress", done)
		out.append({
			"title": Localization.t(str(quest.get("name_key", quest_id))), "from": _giver(str(quest.get("giver", ""))),
			"goal": goal, "when": deadline_text(int(state.get("deadline_day", -1))), "status": "active",
		})
	for errand_id in book.errands:
		out.append({
			"title": Localization.t(str(book.errand(errand_id).get("name_key", errand_id))),
			"from": _giver(str(book.errand(errand_id).get("giver", ""))),
			"goal": errand_goal(errand_id), "when": "", "status": "errand",
		})
	for quest_id in book.finished:
		var quest := book.definition(quest_id)
		out.append({
			"title": Localization.t(str(quest.get("name_key", quest_id))), "from": _giver(str(quest.get("giver", ""))),
			"goal": Localization.t("ui.quests." + str(book.finished[quest_id])), "when": "", "status": str(book.finished[quest_id]),
		})
	return out


static func errand_goal(errand_id: String) -> String:
	var errand := Game.quests.errand(errand_id)
	var item := Game.data.get_entry("items", str(errand.get("item", "")))
	return Localization.t("ui.quests.errand_goal", {
		"name": _giver(str(errand.get("giver", ""))), "count": int(errand.get("count", 1)),
		"item": Localization.t(str(item.get("name_key", ""))), "reward": int(errand.get("reward", 0)),
	})


## "3 days left", "Last day", or "" without a deadline.
static func deadline_text(deadline_day: int) -> String:
	if deadline_day < 0 or not Game.is_running():
		return ""
	var left := deadline_day - Game.clock.day_index()
	return Localization.t("ui.quests.last_day") if left <= 0 else Localization.t("ui.quests.days_left", {"days": left})


## The HUD's line when a quest or errand moves.
static func update_message(quest_id: String, status: String) -> String:
	if not Game.is_running():
		return ""
	var errand := Game.quests.errand(quest_id)
	var title := Localization.t(str((errand if not errand.is_empty() else Game.quests.definition(quest_id)).get("name_key", quest_id)))
	match status:
		"advanced":
			var stage := Game.quests.current_stage(quest_id)
			return Localization.t("ui.msg.quest.advanced", {"title": title, "goal": Localization.t(str(stage.get("goal_key", "")))})
		"errand_done":
			return Localization.t("ui.msg.quest.errand_done", {"title": title, "reward": int(errand.get("reward", 0))})
	return Localization.t("ui.msg.quest." + status, {"title": title})


static func _giver(npc_id: String) -> String:
	return Game.dialogue.display_name(npc_id, Game.data) if npc_id != "" else ""
