class_name PhoneState
extends RefCounted
## What is on the player's phone (D-045): the people whose number they have,
## and the messages between them. Plain data — `PhoneRules` says who may
## write and when, `PhoneDirector` carries it out. Messages keep a locale key
## and its arguments, not finished words, so a change of language reaches
## messages already received. Saved as the `phone` section.

const MAX_MESSAGES := 200

## npc id -> day the number was added
var contacts: Dictionary = {}
## Oldest first: {"id", "npc", "from": "npc" | "player", "kind", "key", "args",
## "minute", "read", "action": {} | {"do", ...}, "answer": "" | "accepted" | "declined"}
var messages: Array[Dictionary] = []
## npc id -> minute of the last message *they* started
var last_started: Dictionary = {}
## Messages with a reason that are waiting for a better hour: {"cause", "queued"}
var pending: Array[Dictionary] = []
var _next_id := 1


func add_contact(npc_id: String, day: int) -> bool:
	if contacts.has(npc_id):
		return false
	contacts[npc_id] = day
	return true


func is_contact(npc_id: String) -> bool:
	return contacts.has(npc_id)


## Adds a message and returns it. `from_npc` false is the player's own.
func add_message(npc_id: String, from_npc: bool, kind: String, key: String, args: Dictionary,
		minute: int, action: Dictionary = {}) -> Dictionary:
	var message := {
		"id": _next_id, "npc": npc_id, "from": "npc" if from_npc else "player", "kind": kind,
		"key": key, "args": args, "minute": minute, "read": not from_npc, "action": action, "answer": "",
	}
	_next_id += 1
	messages.append(message)
	if from_npc:
		last_started[npc_id] = minute
	_trim()
	return message


func get_message(message_id: int) -> Dictionary:
	for message in messages:
		if int(message["id"]) == message_id:
			return message
	return {}


## Every message with one person, oldest first.
func thread(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for message in messages:
		if message["npc"] == npc_id:
			out.append(message)
	return out


## People with a thread, most recent first.
func threads() -> Array[String]:
	var seen: Array[String] = []
	for i in range(messages.size() - 1, -1, -1):
		var npc_id := str(messages[i]["npc"])
		if not seen.has(npc_id):
			seen.append(npc_id)
	return seen


func unread_count(npc_id: String = "") -> int:
	var n := 0
	for message in messages:
		if not bool(message["read"]) and (npc_id == "" or message["npc"] == npc_id):
			n += 1
	return n


## Marks a thread read; returns how many it changed.
func mark_read(npc_id: String) -> int:
	var n := 0
	for message in messages:
		if message["npc"] == npc_id and not bool(message["read"]):
			message["read"] = true
			n += 1
	return n


## How many messages people started at or after `minute`.
func started_since(minute: int) -> int:
	var n := 0
	for message in messages:
		if message["from"] == "npc" and int(message["minute"]) >= minute:
			n += 1
	return n


## Minutes since this person last started a message, or -1 for never.
func minutes_since_started(npc_id: String, now: int) -> int:
	return now - int(last_started[npc_id]) if last_started.has(npc_id) else -1


func answer(message_id: int, how: String) -> void:
	var message := get_message(message_id)
	if not message.is_empty():
		message["answer"] = how


## A question still waiting on the player.
func is_open(message: Dictionary) -> bool:
	return not (message.get("action", {}) as Dictionary).is_empty() and str(message.get("answer", "")) == ""


func to_dict() -> Dictionary:
	return {"contacts": contacts.duplicate(), "messages": messages.duplicate(true),
		"last_started": last_started.duplicate(), "pending": pending.duplicate(true), "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	contacts = {}
	var raw_contacts: Dictionary = d.get("contacts", {})
	for npc_id in raw_contacts:
		contacts[str(npc_id)] = int(raw_contacts[npc_id])
	messages = []
	for raw: Dictionary in d.get("messages", []):
		messages.append({
			"id": int(raw.get("id", 0)), "npc": str(raw.get("npc", "")), "from": str(raw.get("from", "npc")),
			"kind": str(raw.get("kind", "")), "key": str(raw.get("key", "")), "args": raw.get("args", {}),
			"minute": int(raw.get("minute", 0)), "read": bool(raw.get("read", true)),
			"action": raw.get("action", {}), "answer": str(raw.get("answer", "")),
		})
	last_started = {}
	var raw_started: Dictionary = d.get("last_started", {})
	for npc_id in raw_started:
		last_started[str(npc_id)] = int(raw_started[npc_id])
	pending = []
	for raw: Dictionary in d.get("pending", []):
		pending.append({"cause": raw.get("cause", {}), "queued": int(raw.get("queued", 0))})
	_next_id = int(d.get("next_id", 1))
	for message in messages:
		_next_id = maxi(_next_id, int(message["id"]) + 1)


## Old, read messages go first; an unanswered question is never dropped.
func _trim() -> void:
	var i := 0
	while messages.size() > MAX_MESSAGES and i < messages.size():
		if bool(messages[i]["read"]) and not is_open(messages[i]):
			messages.remove_at(i)
		else:
			i += 1
