class_name Conversation
extends RefCounted
## One conversation while it lasts: who, what was said, and by whom.
##
## Transient on purpose. What a person *remembers* of it is a separate,
## saved thing (`MemoryBook`, D-038) written from `things` when it ends; the
## transcript itself is not world state and is gone with the conversation.

var npc_id: String = ""
var started_minute: int = 0
## [{"speaker": "player" | npc id, "text": String, "source": "authored" | "model" | "player"}]
var lines: Array[Dictionary] = []
## The player's turns taken. Each costs a minute of game time, paid when the
## conversation ends (time stands still while two people talk).
var exchanges: int = 0
## Set once the person has said goodbye; nothing more is said after it.
var over: bool = false
## How much this conversation has already warmed them toward the player,
## against `ConversationRules.WARMTH_CAP` (D-037).
var warmth: float = 0.0
## Where it happened: the person's location when it started.
var place: String = ""
## What the player did in it, as the person will remember it — phrases that
## follow "they", from what the rules judged (D-038). No repeats.
var things: Array[String] = []
## How much it mattered: the weightiest thing in it.
var weight: float = 0.1


func _init(p_npc_id: String = "", p_started_minute: int = 0) -> void:
	npc_id = p_npc_id
	started_minute = p_started_minute


func remember(thing: String, thing_weight: float) -> void:
	if thing != "" and not things.has(thing):
		things.append(thing)
	weight = maxf(weight, thing_weight)


func add(speaker: String, text: String, source: String) -> void:
	lines.append({"speaker": speaker, "text": text, "source": source})
