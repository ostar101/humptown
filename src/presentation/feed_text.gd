class_name FeedText
extends RefCounted
## The words for the event feed (D-059): what just happened to the player's
## money and bag, in a line. Reads the reason a wallet recorded ("gift:npc_ida",
## "buy:item_sandwich") and never decides anything.


## One line for a movement of money, or "" when there is nothing to say.
static func money(amount: int, kind: String, reason: String) -> String:
	if amount == 0:
		return ""
	var n := absi(amount)
	if kind == "deposit":
		return Localization.t("ui.feed.deposit", {"amount": n})
	if kind == "withdraw":
		return Localization.t("ui.feed.withdraw", {"amount": n})
	var head := reason.get_slice(":", 0)
	var arg := reason.get_slice(":", 1) if reason.contains(":") else ""
	var args := {"amount": n, "who": PhoneText.npc_name(arg) if arg.begins_with("npc_") else arg,
		"what": _item_name(arg)}
	var group := "paid" if amount < 0 else "got"
	var known: Array[String] = []
	known.append_array(["gift", "transfer", "buy", "clinic", "fine"] if amount < 0 else ["wage", "sell", "errand", "quest", "ask"])
	return Localization.t("ui.feed.%s.%s" % [group, head if head in known else "generic"], args)


## One line for items gained or lost, or "".
static func item(item_id: String, delta: int) -> String:
	if delta == 0:
		return ""
	return Localization.t("ui.feed.item.gain" if delta > 0 else "ui.feed.item.loss",
		{"what": _item_name(item_id), "count": absi(delta)})


static func skill_up(skill_id: String, level: int) -> String:
	var entry: Dictionary = Game.data.get_entry("skills", skill_id) if Game.is_running() else {}
	return Localization.t("ui.feed.skill_up", {"skill": Localization.t(str(entry.get("name_key", skill_id))), "level": level})


static func follow(npc_id: String, following: bool) -> String:
	return Localization.t("ui.feed.follow.start" if following else "ui.feed.follow.stop", {"name": PhoneText.npc_name(npc_id)})


static func _item_name(item_id: String) -> String:
	if not item_id.begins_with("item_") or not Game.is_running():
		return item_id
	var entry: Dictionary = Game.data.get_entry("items", item_id)
	return Localization.t(str(entry.get("name_key", item_id)))
