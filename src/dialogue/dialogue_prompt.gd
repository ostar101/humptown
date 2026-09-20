class_name DialoguePrompt
extends RefCounted
## What the model is told when it speaks as someone (D-036).
##
## A pure function of a context dictionary that `DialogueDirector` assembles
## from world state, so what goes into a prompt is testable without a model:
## identity, the present moment, how they feel about the player, who they
## know, and only what *they* believe — never what the world knows and they
## do not. The rules at the end are the anti-hallucination rule of the design
## plan in the model's own terms: it may talk, it may not invent.
##
## Context keys:
##   npc          {name, age, occupation, bio, voice, traits}
##   now          {place, part_of_day, weekday, doing}
##   player       {name ("" when they do not know it), pronouns}
##   relationship {trust, affection, respect, fear, familiarity}
##   people       ["Ida Lahtinen (friend)", ...]
##   knows        ["sentence", ...]   — what they believe about the player
##   memories     ["sentence", ...]   — what they remember of the player (D-038)
##   history      [{"speaker": "player" | "npc", "text": String}, ...]
##   happened     what the player's last line actually did, as the rules
##                judged it (D-037) — "" when it did nothing worth saying
##   language     "en" | "fi" — the language the game is being played in

const MAX_HISTORY_LINES := 12
## Finnish takes roughly twice the tokens of English for the same sentence.
const MAX_OUTPUT_TOKENS := 200
const TEMPERATURE := 0.8
## A reply longer than this is cut at the last sentence that fits. People in
## this town do not make speeches.
const MAX_REPLY_CHARS := 420

## Added to the rules when they have any memory of the player (D-059).
const RULE_REMEMBER := """
- What is written under "What you remember of them" really happened between you: you remember it, including your own texts and calls. If they mention an earlier talk, a call or a text, go along with it as written there. If it is not written there, you do not remember it, and you say so instead of guessing."""

const LANGUAGE_NAMES := {"en": "English", "fi": "Finnish"}

static var _stage_directions := RegEx.create_from_string("\\*[^*]*\\*|\\([^)]*\\)")


static func build(context: Dictionary) -> LlmRequest:
	var messages: Array[Dictionary] = []
	var opening: Array[String] = []
	for line: Dictionary in _recent(context.get("history", [])):
		var role := "user" if line.get("speaker") == "player" else "assistant"
		var text := str(line.get("text", ""))
		if messages.is_empty() and role == "assistant":
			opening.append(text)   # every API wants the player to speak first
			continue
		if not messages.is_empty() and messages[-1]["role"] == role:
			messages[-1]["content"] = str(messages[-1]["content"]) + "\n" + text
		else:
			messages.append({"role": role, "content": text})
	var request := LlmRequest.create(LlmRequest.Purpose.DIALOGUE, system_text(context, opening), messages)
	request.max_output_tokens = MAX_OUTPUT_TOKENS
	request.temperature = TEMPERATURE
	request.meta = {"npc": str((context.get("npc", {}) as Dictionary).get("name", ""))}
	return request


static func system_text(context: Dictionary, opening: Array[String] = []) -> String:
	var npc: Dictionary = context.get("npc", {})
	var now: Dictionary = context.get("now", {})
	var player: Dictionary = context.get("player", {})
	var name := str(npc.get("name", "someone"))
	var parts: Array[String] = []

	var channel := str(context.get("channel", "in_person"))
	var texting := channel == "text"
	var meeting := "Someone has stopped to talk to you, face to face."
	if texting:
		meeting = "Someone has sent you a text message on your phone; you are not with them."
	elif channel == "call":
		meeting = "You are on the phone with someone; you can hear them but not see them."
	parts.append("You are %s, %s, %s in Harbourside, the harbour district of a small Finnish port town. %s" % [
		name, str(npc.get("age", "")), str(npc.get("occupation", "a local")), meeting])
	if str(npc.get("bio", "")) != "":
		parts.append("Who you are: " + str(npc["bio"]))
	if str(npc.get("voice", "")) != "":
		parts.append("How you speak: " + str(npc["voice"]))
	var traits: Array = npc.get("traits", [])
	if not traits.is_empty():
		parts.append("Your character: " + ", ".join(traits.map(func(t: Variant) -> String: return str(t).replace("_", " "))) + ".")

	parts.append("Right now it is %s on a %s. You are at %s, %s." % [
		str(now.get("part_of_day", "day")), str(now.get("weekday", "weekday")),
		str(now.get("place", "somewhere in Harbourside")), str(now.get("doing", "going about your day"))])

	var who := str(player.get("name", ""))
	var pronouns := str(player.get("pronouns", "they"))
	parts.append("The person talking to you: %s (%s). %s" % [
		who if who != "" else "someone whose name you do not know",
		_pronoun_text(pronouns), relationship_words(context.get("relationship", {}))])

	var people: Array = context.get("people", [])
	if not people.is_empty():
		parts.append("People you know: " + ", ".join(people) + ".")
	var knows: Array = context.get("knows", [])
	parts.append("What you know about this person:" + ("\n- " + "\n- ".join(knows) if not knows.is_empty() else " nothing beyond what you can see."))
	var memories: Array = context.get("memories", [])
	if not memories.is_empty():
		parts.append("What you remember of them, oldest first (talks in person, calls, and texts you wrote or got, with the words that were said):\n- " + "\n- ".join(memories))
	if not opening.is_empty():
		parts.append("You have just said: \"%s\"" % " ".join(opening))
	var happened := str(context.get("happened", ""))
	if happened != "":
		parts.append("What just happened: " + happened)

	var language: String = LANGUAGE_NAMES.get(str(context.get("language", "en")), "English")
	parts.append("""Rules for how you answer:
- Speak only as %s: the words you say out loud, in the first person. No narration, no actions, no quotation marks.
- Keep it short, one to three sentences, the way people really talk.
- You know only what is written above and ordinary everyday things. If you are asked about a person, place or event that is not written above, you do not know it — say so in your own way. Never make up people, places, events, prices, or anything about the person in front of you.
- You cannot hand over or promise things you do not have, and nothing you say makes anything happen by itself.
- What is written under "What just happened" is true. React to it; never contradict it or pretend something else happened.
- Answer in the language the other person writes in. The game is being played in %s.
- Never say you are an AI, a model or a character in a game.%s""" % [name, language, RULE_REMEMBER if not memories.is_empty() else ""])
	if texting:
		parts.append("This is a text message: write it as one. You cannot see them or hand them anything.")
	elif channel == "call":
		parts.append("This is a phone call: speak, do not write. You cannot see them or hand them anything.")
	return "\n\n".join(parts)


## Asks the cheap model to rewrite what someone remembers of the player into
## a short summary, from what the rules recorded and nothing else (D-038).
static func summary_request(npc_name: String, summary: String, folded: Array[String]) -> LlmRequest:
	var system := """You keep the memory of %s, a character in a life-simulation game. Below is what %s remembers of one person. Rewrite it as at most three short sentences, from %s's point of view: call %s "you" and the person "they". Keep what matters most — money, threats, insults, kindness, names — and drop small talk. Use only what is written; never add anything. Answer with the sentences only.""" % [npc_name, npc_name, npc_name, npc_name]
	var lines: Array[String] = []
	if summary != "":
		lines.append(summary)
	lines.append_array(folded)
	var request := LlmRequest.create(LlmRequest.Purpose.SUMMARISE, system,
		[{"role": "user", "content": "\n".join(lines)}])
	request.max_output_tokens = 200
	request.temperature = 0.2
	request.meta = {"npc": npc_name}
	return request


## Plain words for how someone feels about the player, from the relationship
## numbers — the model is told a feeling, not a score.
static func relationship_words(relationship: Dictionary) -> String:
	var familiarity := float(relationship.get("familiarity", 0.0))
	var words: Array[String] = []
	if familiarity < 0.05:
		words.append("You have never talked to them before.")
	elif familiarity < 0.3:
		words.append("You have talked a few times; you do not know them well.")
	elif familiarity < 0.7:
		words.append("You know them fairly well.")
	else:
		words.append("You know them well.")
	var affection := float(relationship.get("affection", 0.0))
	if affection > 0.4:
		words.append("You like them.")
	elif affection < -0.4:
		words.append("You dislike them.")
	var trust := float(relationship.get("trust", 0.0))
	if trust > 0.4:
		words.append("You trust them.")
	elif trust < -0.3:
		words.append("You do not trust them.")
	var respect := float(relationship.get("respect", 0.0))
	if respect > 0.5:
		words.append("You respect them.")
	elif respect < -0.4:
		words.append("You think little of them.")
	if float(relationship.get("fear", 0.0)) > 0.4:
		words.append("They frighten you a little.")
	return " ".join(words)


## What the model said, made fit to be shown as a line of speech: no speaker
## label, no stage directions, no wrapping quotes, not a speech. Empty when
## nothing sayable is left, which the caller treats as a failed reply.
static func clean_reply(text: String, npc_name: String, truncated: bool = false) -> String:
	var out := text.strip_edges()
	# Only their own name is stripped as a label: "Listen: …" is speech.
	for prefix in [npc_name + ":", npc_name.split(" ")[0] + ":"]:
		if out.begins_with(prefix):
			out = out.substr(prefix.length())
	out = _stage_directions.sub(out, "", true)
	out = out.strip_edges()
	for quote in ["\"", "“", "”", "'"]:
		if out.begins_with(quote):
			out = out.substr(1)
		if out.ends_with(quote):
			out = out.substr(0, out.length() - 1)
	out = " ".join(out.split(" ", false)).strip_edges()
	if truncated:
		out = _last_whole_sentence(out)
	if out.length() > MAX_REPLY_CHARS:
		var cut := out.substr(0, MAX_REPLY_CHARS)
		var end := maxi(cut.rfind(". "), maxi(cut.rfind("! "), cut.rfind("? ")))
		out = cut.substr(0, end + 1) if end > 40 else cut.strip_edges() + "…"
	return out


## A reply the model ran out of room for ends mid-word; keep the sentences
## that were finished. With no finished sentence there is nothing better to
## do than show what there is, marked as unfinished.
static func _last_whole_sentence(text: String) -> String:
	var end := -1
	for mark in [".", "!", "?", "…"]:
		end = maxi(end, text.rfind(mark))
	if end >= 1:
		return text.substr(0, end + 1)
	return text + "…"


static func part_of_day(minute_of_day: int) -> String:
	var hour := minute_of_day / 60
	if hour >= 5 and hour < 11:
		return "morning"
	if hour >= 11 and hour < 17:
		return "afternoon"
	if hour >= 17 and hour < 22:
		return "evening"
	return "night"


## A locale string in English whatever language the game is in: the prompt is
## written in English, and a Finnish word in the middle of it helps nobody.
static func english(key: String, args: Dictionary = {}) -> String:
	var translation := TranslationServer.get_translation_object("en")
	var text := String(translation.get_message(key)) if translation != null else key
	if text == "":
		text = key
	for placeholder in args:
		text = text.replace("{%s}" % placeholder, str(args[placeholder]))
	return text


static func _pronoun_text(pronouns: String) -> String:
	match pronouns:
		"she":
			return "she/her"
		"he":
			return "he/him"
	return "they/them"


static func _recent(history: Array) -> Array:
	return history.slice(maxi(history.size() - MAX_HISTORY_LINES, 0))
