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
##
## Everything that passes between the two of them goes in the same book, in the
## order it happened (D-059): conversations in person, calls, texts either
## way, and things done. An episode has a `channel` and, besides what the
## player did, a short `excerpt` of the actual words, so "do you remember what
## we talked about?" and "did you get my message?" have something to be
## answered from.

## Past this many episodes, the oldest are folded into the summary…
const MAX_EPISODES := 6
## …leaving this many whole.
const KEEP_EPISODES := 4
const SUMMARY_MAX_CHARS := 480
## Recalled into a prompt: the summary and at most this many episodes.
const RECALL_EPISODES := 4

## Recalled into a prompt: the actual words of only the latest few entries.
const RECALL_WITH_WORDS := 2
const EXCERPT_LINES := 6
const EXCERPT_LINE_CHARS := 110
## Texts within this many minutes of each other are one exchange.
const TEXT_EXCHANGE_MINUTES := 90

## The ways two people can deal with each other.
const CHANNELS: Array[String] = ["in_person", "call", "text", "event"]

## knower id -> {"episodes": [{at, place, channel, things: [String],
##               excerpt: [{who: "you" | "they", text}], weight}],
##               "summary": [{text, weight}], "folds": int}
var _books: Dictionary = {}


## Records one dealing. `things` are what the player did, as phrases that
## follow "they": "asked about your work", "gave you 20 in cash". An empty
## list is still a memory — they stopped for a chat. `excerpt` is the words,
## each `{"who": "you" | "they", "text"}` (the person is "you", the player
## "they", as in the prompt); only the last few, cut short, are kept.
func add_episode(knower_id: String, at_minute: int, place: String, things: Array[String], weight: float,
		channel: String = "in_person", excerpt: Array = []) -> void:
	var book := _book(knower_id)
	(book["episodes"] as Array).append({
		"at": at_minute, "place": place, "channel": channel, "things": things.duplicate(),
		"excerpt": _trimmed(excerpt), "weight": weight,
	})


## Texts, either way, join the exchange already going if it is recent: a
## message and its answer are one thing to remember, not two.
func add_text(knower_id: String, at_minute: int, lines: Array, things: Array[String] = [], weight: float = 0.1) -> void:
	var book := _book(knower_id)
	var all: Array = book["episodes"]
	if not all.is_empty():
		var last: Dictionary = all[-1]
		if last["channel"] == "text" and at_minute - int(last["at"]) <= TEXT_EXCHANGE_MINUTES:
			last["excerpt"] = _trimmed((last["excerpt"] as Array) + lines)
			for thing in things:
				if not (last["things"] as Array).has(thing):
					(last["things"] as Array).append(thing)
			last["at"] = at_minute
			last["weight"] = maxf(float(last["weight"]), weight)
			return
	add_episode(knower_id, at_minute, "", things, weight, "text", lines)


## Something done, told as a phrase that follows "they". One line, no words.
func add_event(knower_id: String, at_minute: int, place: String, thing: String, weight: float) -> void:
	add_episode(knower_id, at_minute, place, [thing], weight, "event")


## When they last dealt with each other, or -1.
func last_at(knower_id: String) -> int:
	var all := episodes(knower_id)
	return int(all[-1]["at"]) if not all.is_empty() else -1


## A text of theirs the player has not answered: the newest entry is a text
## exchange that ends on the person's own words, no older than `within`
## minutes. The words, or "" when there is none.
func unanswered_text(knower_id: String, now_minute: int, within: int) -> String:
	var all := episodes(knower_id)
	if all.is_empty():
		return ""
	var last: Dictionary = all[-1]
	if last["channel"] != "text" or now_minute - int(last["at"]) > within:
		return ""
	var words: Array = last["excerpt"]
	if words.is_empty() or words[-1]["who"] != "you":
		return ""
	return str(words[-1]["text"])


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
		var sentence := "Once, %s, they %s." % [_where(episode, place_name), _doing(episode)]
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
## first, then the latest dealings with how long ago they were, in order —
## and, for the last few, what was actually said.
func recall(knower_id: String, now_minute: int, place_name: Callable) -> Array[String]:
	var out: Array[String] = []
	var gist := summary(knower_id)
	if gist != "":
		out.append(gist)
	var recent := episodes(knower_id)
	var shown := recent.slice(maxi(recent.size() - RECALL_EPISODES, 0))
	for i in shown.size():
		var episode: Dictionary = shown[i]
		var line := "%s, %s: they %s." % [when(int(episode["at"]), now_minute), _where(episode, place_name), _doing(episode)]
		var words: Array = episode["excerpt"]
		if not words.is_empty() and i >= shown.size() - RECALL_WITH_WORDS:
			line += " What was said — " + " / ".join(words.map(func(w: Dictionary) -> String:
				return "%s: \"%s\"" % [w["who"], w["text"]]))
		out.append(line)
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
			var channel := str(episode.get("channel", "in_person"))
			(book["episodes"] as Array).append({
				"at": int(episode.get("at", 0)), "place": str(episode.get("place", "")),
				"channel": channel if channel in CHANNELS else "in_person",
				"things": things, "excerpt": _trimmed(episode.get("excerpt", [])),
				"weight": float(episode.get("weight", 0.1)),
			})
		for point in raw.get("summary", []):
			if typeof(point) == TYPE_DICTIONARY:
				(book["summary"] as Array).append({"text": str(point.get("text", "")), "weight": float(point.get("weight", 0.1))})
		_books[str(knower_id)] = book


func _book(knower_id: String) -> Dictionary:
	if not _books.has(knower_id):
		_books[knower_id] = {"episodes": [], "summary": [], "folds": 0}
	return _books[knower_id]


## Where, as words that follow "Once," or "Yesterday,": at a place, on the
## phone, by text.
static func _where(episode: Dictionary, place_name: Callable) -> String:
	match str(episode.get("channel", "in_person")):
		"call":
			return "on the phone"
		"text":
			return "by text"
	var place := str(episode.get("place", ""))
	return "at %s" % place_name.call(place) if place != "" else "in person"


## What they did, as words that follow "they".
static func _doing(episode: Dictionary) -> String:
	var things: Array = episode["things"]
	if not things.is_empty():
		return _joined(things)
	match str(episode.get("channel", "in_person")):
		"call":
			return "called you and talked"
		"text":
			return "exchanged texts with you"
	return "stopped for a chat"


## The last few lines of words, each cut short: [{"who", "text"}].
static func _trimmed(words: Array) -> Array:
	var out: Array = []
	for word in words.slice(maxi(words.size() - EXCERPT_LINES, 0)):
		if typeof(word) != TYPE_DICTIONARY:
			continue
		var text := str(word.get("text", "")).strip_edges().replace("\n", " ")
		if text == "":
			continue
		if text.length() > EXCERPT_LINE_CHARS:
			text = text.substr(0, EXCERPT_LINE_CHARS - 1).strip_edges() + "…"
		out.append({"who": "you" if str(word.get("who", "")) == "you" else "they", "text": text})
	return out


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
