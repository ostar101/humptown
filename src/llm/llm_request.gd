class_name LlmRequest
extends RefCounted
## A model call, described independently of any provider.
##
## Purpose is the important field: it is what the router uses to decide
## between the cheap model, the main model, and no model at all.

## What this call is for. Drives routing, caching and budget priority.
enum Purpose {
	INTENT,          ## classify what the player is trying to do — cheap
	REACTION,        ## a one-line NPC reaction — cheap
	EXTRACT,         ## pull structured facts out of text — cheap
	SUMMARISE,       ## compress memories — cheap
	DIALOGUE,        ## ordinary conversation — main
	KEY_DIALOGUE,    ## a scene that matters — main
	NARRATIVE,       ## propose new world content for validation — main
}

const PURPOSE_NAMES := [
	"intent", "reaction", "extract", "summarise",
	"dialogue", "key_dialogue", "narrative",
]

## Purposes whose answers are stable enough to reuse from cache.
const CACHEABLE := [Purpose.INTENT, Purpose.EXTRACT, Purpose.SUMMARISE]

var id: String = ""
var purpose: Purpose = Purpose.DIALOGUE
var system: String = ""
## [{role: "user"|"assistant", content: String}]
var messages: Array[Dictionary] = []
var max_output_tokens: int = 400
var temperature: float = 0.8
## When true the caller wants tokens as they arrive.
var stream: bool = false
## Free-form context for debug display and for the response handler.
var meta: Dictionary = {}
## Forces a model class instead of letting the router decide.
var force_model_class: String = ""   # "" | "cheap" | "main"
## Higher runs first when the budget is tight.
var priority: int = 0


static func create(purpose: Purpose, system: String, messages: Array[Dictionary]) -> LlmRequest:
	var r := LlmRequest.new()
	r.purpose = purpose
	r.system = system
	r.messages = messages
	r.id = "llm_%s_%d" % [PURPOSE_NAMES[purpose], Time.get_ticks_usec()]
	return r


## Convenience for single-turn calls.
static func simple(purpose: Purpose, system: String, user_text: String) -> LlmRequest:
	return create(purpose, system, [{"role": "user", "content": user_text}])


func purpose_name() -> String:
	return PURPOSE_NAMES[purpose]


func is_cacheable() -> bool:
	return purpose in CACHEABLE and not stream


## Stable key for response caching and in-flight deduplication.
func cache_key(provider: String, model: String) -> String:
	var payload := JSON.stringify({
		"p": provider, "m": model, "s": system,
		"msgs": messages, "t": temperature, "max": max_output_tokens,
	})
	return payload.sha256_text()


## Rough token estimate (~4 characters per token) used for budgeting before
## the real usage figures come back.
func estimate_prompt_tokens() -> int:
	var characters := system.length()
	for message in messages:
		characters += str(message.get("content", "")).length() + 8
	return int(ceil(float(characters) / 4.0))


func to_debug_dict() -> Dictionary:
	return {
		"id": id,
		"purpose": purpose_name(),
		"messages": messages.size(),
		"est_prompt_tokens": estimate_prompt_tokens(),
		"max_output_tokens": max_output_tokens,
		"temperature": temperature,
	}
