class_name PhoneText
extends RefCounted
## The words for the phone (D-045). Messages are stored as a key and its
## arguments; this turns them into text in the language the player has now.


static func npc_name(npc_id: String) -> String:
	var npc := Game.npcs.get_npc(npc_id) if Game.is_running() else null
	return npc.name if npc != null else npc_id


## What one message says.
static func render(message: Dictionary) -> String:
	if str(message.get("text", "")) != "":
		return str(message["text"])
	var args: Dictionary = (message.get("args", {}) as Dictionary).duplicate()
	if args.has("item"):
		args["item"] = Localization.t(str(Game.data.get_entry("items", str(args["item"])).get("name_key", "")))
	if args.has("quest_key"):
		args["quest"] = Localization.t(str(args["quest_key"]))
	if args.has("place"):
		args["place"] = InteractionText.place_name(str(args["place"]))
	return Localization.t(str(message.get("key", "")), args)


## What they do, for the contact list: "Dockhand", or "" when it is not worth saying.
static func occupation(npc_id: String) -> String:
	var npc := Game.npcs.get_npc(npc_id) if Game.is_running() else null
	if npc == null or npc.occupation == "":
		return ""
	var entry := Game.data.get_entry("occupations", npc.occupation)
	return Localization.t(str(entry.get("name_key", ""))) if not entry.is_empty() else ""


## When it was sent: "18:40", "Yesterday 18:40", "Tue 18:40".
static func stamp(minute: int) -> String:
	var clock := Game.clock
	var time := "%02d:%02d" % [(minute % GameClock.MINUTES_PER_DAY) / 60, minute % 60]
	var days_ago := clock.day_index() - minute / GameClock.MINUTES_PER_DAY
	if days_ago <= 0:
		return Localization.t("ui.phone.stamp.today", {"time": time})
	if days_ago == 1:
		return Localization.t("ui.phone.stamp.yesterday", {"time": time})
	var weekday := posmod(clock.weekday() - days_ago, 7)
	return Localization.t("ui.phone.stamp.day", {"day": Localization.t(GameClock.WEEKDAY_KEYS[weekday]), "time": time})


## The one-line summary of a thread, for the list of them.
static func preview(npc_id: String) -> String:
	var thread := Game.phone.thread(npc_id)
	if thread.is_empty():
		return ""
	var last := thread[thread.size() - 1]
	var text := render(last)
	return (Localization.t("ui.phone.you") + ": " + text) if last["from"] == "player" else text


static func new_message_line(npc_id: String) -> String:
	return Localization.t("ui.msg.phone.new", {"name": npc_name(npc_id)})


static func unread_line() -> String:
	if not Game.is_running():
		return ""
	var unread := Game.phone.unread_count()
	return Localization.t("ui.status.unread", {"n": unread}) if unread > 0 else ""
