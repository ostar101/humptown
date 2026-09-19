class_name CombatText
extends RefCounted
## The words for a fight (D-054): each structured log entry said in the
## player's language, and how it ended. Verbs agree with "you", so an entry
## has one wording when the player did it and another when it was done to them.


static func name_of(combatant_id: String) -> String:
	if combatant_id == PlayerState.ID:
		return Localization.t("ui.combat.you")
	return Game.dialogue.display_name(combatant_id, Game.data)


## One log entry, as a sentence.
static func line(entry: Dictionary) -> String:
	var kind := str(entry.get("kind", ""))
	var actor := str(entry.get("actor", ""))
	var target := str(entry.get("target", ""))
	var by_player := actor == PlayerState.ID if actor != "" else target == PlayerState.ID
	var key := "ui.combat.log.%s.%s" % [kind, "you" if by_player else "them"]
	return Localization.t(key, {
		"actor": name_of(actor), "target": name_of(target), "percent": int(round(float(entry.get("damage", 0.0)) * 100.0)),
	})


static func result(outcome: String) -> String:
	return Localization.t("ui.combat.result." + outcome)


static func state_word(state: String) -> String:
	return Localization.t("ui.combat.state." + state) if state != "up" else ""
