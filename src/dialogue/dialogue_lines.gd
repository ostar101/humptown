class_name DialogueLines
extends RefCounted
## Authored lines, for when no model is answering (D-035).
##
## A line is a locale key, `dialogue.<npc id>.<topic>.<n>`, numbered from 1
## with no gaps, so adding a line is a locale edit and nothing else. Someone
## with no line of their own for a topic falls back to `dialogue.generic`,
## which is also everything a background person says.
##
## A person's greeting may be about their job, and then it is authored twice: as
## `greet_work`, said where they work, and as `greet`, said anywhere else.

const GENERIC := "generic"
const MAX_LINES := 8


## Every key that could answer this topic for this person, their own first.
static func keys_for(npc_id: String, topic: String) -> Array[String]:
	var own := _numbered("dialogue.%s.%s." % [npc_id, topic])
	return own if not own.is_empty() else _numbered("dialogue.%s.%s." % [GENERIC, topic])


## One key, chosen from the person, the topic and how far into the
## conversation it is — varied, but the same conversation always goes the
## same way.
static func pick(npc_id: String, topic: String, turn: int) -> String:
	var keys := keys_for(npc_id, topic)
	if keys.is_empty():
		keys = keys_for(npc_id, "unknown")
	if keys.is_empty():
		return ""
	return keys[posmod(("%s/%s" % [npc_id, topic]).hash() + turn, keys.size())]


static func has_own(npc_id: String, topic: String) -> bool:
	return not _numbered("dialogue.%s.%s." % [npc_id, topic]).is_empty()


static func _numbered(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for n in range(1, MAX_LINES + 1):
		var key := prefix + str(n)
		if String(TranslationServer.translate(key)) == key:
			break
		out.append(key)
	return out
