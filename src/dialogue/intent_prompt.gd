class_name IntentPrompt
extends RefCounted
## Asks the cheap model what the player meant — only that (D-037).
##
## The answer is a small JSON object. It says what the player is trying to
## do and which person, place, amount or name they mentioned, as they said
## it. It never contains an id: Godot resolves names to people and places
## itself, so a model cannot point at something that does not exist, and
## `ConversationRules` decides what, if anything, happens.

const MAX_OUTPUT_TOKENS := 120
## Anything longer than this is not a kind, it is the model talking.
const MAX_KIND_LENGTH := 32
const MAX_KIND_WORDS := 3

const KIND_HELP := {
	"greet": "saying hello",
	"farewell": "saying goodbye or leaving",
	"thanks": "thanking them",
	"about_self": "asking who they are or their name",
	"about_work": "asking about their work",
	"about_person": "asking about another person (put the name in person)",
	"about_place": "asking about a place (put the name in place)",
	"introduce_self": "telling their own name (put it in name)",
	"compliment": "praising or being kind to them",
	"flirt": "flirting with them",
	"apologize": "apologising",
	"insult": "insulting or mocking them",
	"threaten": "threatening them",
	"give_money": "actually handing them money now (put the number in amount)",
}

static var _kind_shape := RegEx.create_from_string("^[a-z][a-z_]*$")


static func build(line: String, npc_name: String) -> LlmRequest:
	var kinds: Array[String] = []
	for kind: String in ConversationRules.KINDS:
		kinds.append("- %s: %s" % [kind, KIND_HELP.get(kind, kind)])
	var system := """You read one thing a player said to %s, a character in a life-simulation game, and report what the player is trying to do. You do not answer them.

Reply with one JSON object and nothing else:
{"intent": "...", "person": "", "place": "", "amount": 0, "name": ""}

intent — the best fit from this list:
%s
If none fits, use a short snake_case word of your own, such as persuade, negotiate, ask_favor, offer_help or lie. Use small_talk for anything else.

person, place — a person's or place's name exactly as the player wrote it, if the line is about one; else "".
amount — a whole number of money the player is handing over right now; else 0. Offering, refusing, joking or asking about money is not handing it over.
name — the name the player gives for themselves, if they do; else "".
The player may write in any language.""" % [npc_name, "\n".join(kinds)]
	var request := LlmRequest.create(LlmRequest.Purpose.INTENT, system, [{"role": "user", "content": line}])
	request.max_output_tokens = MAX_OUTPUT_TOKENS
	request.temperature = 0.0
	request.meta = {"npc": npc_name}
	return request


## The model's answer as an intent: {"kind", "person", "place", "amount",
## "name"} with names still as said; {} when the answer is not usable, and
## the caller falls back to the offline reading.
static func parse(response: LlmResponse) -> Dictionary:
	if response == null or not response.ok:
		return {}
	var parsed: Variant = response.as_json()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var answer: Dictionary = parsed
	var said := str(answer.get("intent", "")).strip_edges().to_lower()
	if said.split(" ", false).size() > MAX_KIND_WORDS:
		return {}
	var kind := said.replace(" ", "_").replace("-", "_")
	if kind.length() > MAX_KIND_LENGTH or _kind_shape.search(kind) == null:
		return {}
	var amount := 0
	var raw_amount: Variant = answer.get("amount", 0)
	if typeof(raw_amount) in [TYPE_INT, TYPE_FLOAT]:
		amount = int(raw_amount)
	elif typeof(raw_amount) == TYPE_STRING and str(raw_amount).is_valid_int():
		amount = int(str(raw_amount))
	return {
		"kind": kind,
		"person": _text(answer.get("person", "")),
		"place": _text(answer.get("place", "")),
		"amount": amount,
		"name": _text(answer.get("name", "")),
	}


static func _text(value: Variant) -> String:
	return str(value).strip_edges().left(60) if typeof(value) == TYPE_STRING else ""
