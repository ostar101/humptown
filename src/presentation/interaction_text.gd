class_name InteractionText
extends RefCounted
## The player-facing words for interactions: the prompt before, the line
## after. Kept apart from the rules that decide (Game.interact_at) and from the
## HUD that shows them, so wording can change without touching either.

## Refusals the player should be told about. Others (out_of_reach,
## nothing_there, no_world) cannot come from pressing the button and say
## nothing.
const EXPLAINED_REFUSALS: Array[String] = [
	"locked", "private", "closed", "no_interior", "nobody_serving", "not_your_bed", "not_tired",
	"asleep", "on_their_way", "nobody_there", "already_talking",
	"not_a_work_day", "too_early", "too_late", "already_worked", "too_drunk", "too_exhausted", "busy",
	"not_your_stash", "nothing_to_treat", "not_enough_money",
]


## What pressing the interact button would do here, or empty.
static func prompt_for(interaction: Dictionary) -> String:
	var target := str(interaction.get("target", ""))
	match str(interaction.get("kind", "")):
		"door":
			return Localization.t("ui.prompt.enter", {"place": place_name(target)})
		"exit":
			return Localization.t("ui.prompt.leave", {"place": place_name(target)})
		"counter":
			return Localization.t("ui.prompt.counter")
		"bed":
			return Localization.t("ui.prompt.sleep")
		"sign":
			return Localization.t("ui.prompt.read")
		"stash":
			return Localization.t("ui.prompt.stash")
		"atm":
			return Localization.t("ui.prompt.atm")
		"work":
			var job := Game.data.get_entry("jobs", target) if Game.is_running() else {}
			return Localization.t("ui.prompt.work", {"wage": job.get("wage", 0)})
		"person":
			# A name only once the player knows it (D-035).
			if Game.is_running() and Game.dialogue.knows_name(target):
				var npc := Game.npcs.get_npc(target)
				return Localization.t("ui.prompt.talk", {"name": npc.name if npc != null else target})
			return Localization.t("ui.prompt.talk_stranger")
	return ""


## The line shown after an interaction, or empty when the change speaks for
## itself (walking through a door).
static func outcome_text(interaction: Dictionary, result: Result) -> String:
	if not result.is_ok():
		if not (result.code in EXPLAINED_REFUSALS):
			return ""
		var place := str(interaction.get("target", ""))
		var location: Location = Game.world.get_location(place) if Game.is_running() else null
		return Localization.t("ui.msg.refused." + result.code, {
			"place": place_name(place),
			"from": _clock_text(location.open_from if location != null else 0),
			"until": _clock_text(location.open_until if location != null else 0),
		})
	var outcome: Dictionary = result.value
	match str(outcome.get("kind", "")):
		"served":
			var npc := Game.npcs.get_npc(str(outcome.get("npc", "")))
			return Localization.t("ui.msg.served", {"name": npc.name if npc != null else "?"})
		"slept":
			var key := "ui.msg.slept_saved" if outcome.get("saved", false) else "ui.msg.slept"
			return Localization.t(key, {"time": Game.clock.format_time()})
		"read":
			return Localization.t(str(outcome.get("text_key", "")))
		"treated":
			var nurse := Game.dialogue.display_name(str(outcome.get("npc", "")), Game.data)
			return Localization.t("ui.msg.treated", {"name": nurse, "fee": outcome.get("fee", 0)})
		"desk":
			var officer := Game.npcs.get_npc(str(outcome.get("officer", "")))
			var who := Game.dialogue.display_name(str(outcome.get("officer", "")), Game.data) if officer != null else ""
			if str(outcome["outcome"]) == "arrest":
				return ""   # the night in the cells says its own
			return Localization.t("ui.msg.desk." + str(outcome["outcome"]), {"name": who, "fine": outcome.get("fine", 0)})
		"worked":
			var key := "ui.msg.worked_bank" if outcome.get("pay_to") == "bank" else "ui.msg.worked_cash"
			if outcome.get("late", false):
				key += "_late"
			return Localization.t(key, {"time": outcome.get("until", ""), "pay": outcome.get("pay", 0)})
	return ""


static func place_name(location_id: String) -> String:
	if not Game.is_running():
		return location_id
	var location := Game.world.get_location(location_id)
	return location.display_name() if location != null else location_id


static func _clock_text(minute_of_day: int) -> String:
	var m := posmod(minute_of_day, GameClock.MINUTES_PER_DAY)
	return "%02d:%02d" % [m / 60, m % 60]
