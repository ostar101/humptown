class_name MemoryBook
extends RefCounted
## What people remember of their own dealings with the player (D-038).
##
## `KnowledgeNetwork` is what someone believes *happened*; this is how it
## *went* between the two of them — each conversation as an episode, told
## from their side: "they asked you about Tuomas, and gave you 20 in cash".
## Episodes are written by rule from what the rules judged, never from what a
## model said, so a memory cannot hold anything that did not happen.
##
## Hierarchical and bounded: the last few episodes are kept whole, everything
## older is folded into a short summary — by rule at once, and rewritten by
## the cheap model when one is available. A long game grows neither a prompt
## nor a save without limit.

## Past this many episodes, the oldest are folded into the summary…
const MAX_EPISODES := 6
## …leaving this many whole.
const KEEP_EPISODES := 4
const SUMMARY_MAX_CHARS := 480
## Recalled into a prompt: the summary and at most this many episodes.
const RECALL_EPISODES := 4

## knower id -> {"episodes": [{at, place, things: [String], weight}],
##               "summary": [{text, weight}], "folds": int}
var _books: Dictionary = {}


## Records one conversation. `things` are what the player did, as phrases
## that follow "they": "asked about your work", "gave you 20 in cash". An
## empty list is still a memory — they stopped for a chat.
func add_episode(knower_id: String, at_minute: int, place: String, things: Array[String], weight: float) -> void:
	var book := _book(knower_id)
	(book["episodes"] as Array).append({
		"at": at_minute, "place": place, "things": things.duplicate(), "weight": weight,
	})


func episodes(knower_id: String) -> Array:
	return _books.get(knower_id, {}).get("episodes", [])


func summary(knower_id: String) -> String:
	var points: Array = _books.get(knower_id, {}).get("summary", [])
	return " ".join(points.map(func(p: Dictionary) -> String: return str(p["text"])))


## How many times this person's memory has been folded; a model's summary is
## accepted only for the fold it was asked about.
func folds(knower_id: String) -> int:
	return int(_books.get(knower_id, {}).get("folds", 0))


func needs_folding(knower_id: String) -> bool:
	return episodes(knower_id).size() > MAX_EPISODES


## Folds the oldest episodes into the summary by rule: each becomes a
## timeless sentence, and while the summary is too long the least important
## sentence goes. Returns the folded sentences, for a model to rewrite.
func fold_by_rule(knower_id: String, place_name: Callable) -> Array[String]:
	var folded: Array[String] = []
	if not needs_folding(knower_id):
		return folded
	var book := _book(knower_id)
	var all: Array = book["episodes"]
	var old := all.slice(0, all.size() - KEEP_EPISODES)
	book["episodes"] = all.slice(all.size() - KEEP_EPISODES)
	var points: Array = book["summary"]
	for episode: Dictionary in old:
		var sentence := "Once, at %s, they %s." % [place_name.call(str(episode["place"])), _joined(episode["things"])]
		folded.append(sentence)
		points.append({"text": sentence, "weight": float(episode["weight"])})
	while points.size() > 1 and _length(points) > SUMMARY_MAX_CHARS:
		var weakest := 0
		for i in points.size():
			if float(points[i]["weight"]) < float(points[weakest]["weight"]):
				weakest = i
		points.remove_at(weakest)
	book["folds"] = int(book["folds"]) + 1
	return folded


## A rewritten summary, accepted only if it answers the latest fold and is
## fit to keep: not empty, not too long, no ids.
func set_summary(knower_id: String, text: String, for_fold: int) -> Result:
	if folds(knower_id) != for_fold:
		return Result.failure("stale_summary")
	var clean := text.strip_edges()
	if clean.is_empty():
		return Result.failure("empty_summary")
	if clean.contains("npc_") or clean.contains("loc_") or clean.contains("item_"):
		return Result.failure("summary_has_ids")
	if clean.length() > SUMMARY_MAX_CHARS:
		var cut := clean.substr(0, SUMMARY_MAX_CHARS)
		var end := maxi(cut.rfind(". "), maxi(cut.rfind("! "), cut.rfind("? ")))
		if end < 40:
			return Result.failure("summary_too_long")
		clean = cut.substr(0, end + 1)
	_book(knower_id)["summary"] = [{"text": clean, "weight": 1.0}]
	return Result.success(clean)


## What they remember of the player, as sentences for a prompt: the summary
## first, then the latest episodes with how long ago they were.
func recall(knower_id: String, now_minute: int, place_name: Callable) -> Array[String]:
	var out: Array[String] = []
	var gist := summary(knower_id)
	if gist != "":
		out.append(gist)
	var recent := episodes(knower_id)
	for episode: Dictionary in recent.slice(maxi(recent.size() - RECALL_EPISODES, 0)):
		out.append("%s, at %s: they %s." % [
			when(int(episode["at"]), now_minute), place_name.call(str(episode["place"])), _joined(episode["things"])])
	return out


static func when(at_minute: int, now_minute: int) -> String:
	var days := int(now_minute / GameClock.MINUTES_PER_DAY) - int(at_minute / GameClock.MINUTES_PER_DAY)
	if days <= 0:
		return "Earlier today"
	if days == 1:
		return "Yesterday"
	if days < 7:
		return "%d days ago" % days
	if days < 14:
		return "Last week"
	if days < 60:
		return "A few weeks ago"
	return "A long time ago"


func forget(knower_id: String) -> void:
	_books.erase(knower_id)


func knower_count() -> int:
	return _books.size()


func to_dict() -> Dictionary:
	return {"books": _books.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	_books = {}
	var books: Dictionary = d.get("books", {})
	for knower_id in books:
		var raw: Dictionary = books[knower_id]
		var book := {"episodes": [], "summary": [], "folds": int(raw.get("folds", 0))}
		for episode in raw.get("episodes", []):
			if typeof(episode) != TYPE_DICTIONARY:
				continue
			var things: Array[String] = []
			for thing in episode.get("things", []):
				things.append(str(thing))
			(book["episodes"] as Array).append({
				"at": int(episode.get("at", 0)), "place": str(episode.get("place", "")),
				"things": things, "weight": float(episode.get("weight", 0.1)),
			})
		for point in raw.get("summary", []):
			if typeof(point) == TYPE_DICTIONARY:
				(book["summary"] as Array).append({"text": str(point.get("text", "")), "weight": float(point.get("weight", 0.1))})
		_books[str(knower_id)] = book


func _book(knower_id: String) -> Dictionary:
	if not _books.has(knower_id):
		_books[knower_id] = {"episodes": [], "summary": [], "folds": 0}
	return _books[knower_id]


static func _joined(things: Array) -> String:
	if things.is_empty():
		return "stopped for a chat"
	if things.size() == 1:
		return str(things[0])
	return ", ".join(things.slice(0, things.size() - 1).map(func(t: Variant) -> String: return str(t))) \
		+ ", and " + str(things[-1])


static func _length(points: Array) -> int:
	var total := 0
	for point: Dictionary in points:
		total += str(point["text"]).length() + 1
	return total
