class_name AnthropicProvider
extends LlmProvider
## Anthropic Messages API adapter.
##
## Anthropic takes the system prompt as a top-level field rather than a
## message turn, and returns content as a list of blocks.
##
## The request surface differs by model family (D-036). The current models
## (Opus 5, Sonnet 5, Fable, Opus 4.7/4.8) reject `temperature` with a 400,
## so it is sent only to the older families known to accept it. Opus 5,
## Sonnet 5 and Fable think by default, and `max_tokens` caps thinking plus
## text together: those get headroom above the caller's budget for the answer,
## and every model that takes an `effort` is asked for a low one — a line of
## dialogue is not a research project.

const ENDPOINT := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2023-06-01"
## Extra room for thinking on models that think by default. Only generated
## tokens are billed; the cap exists so an answer is never cut off mid-thought.
const THINKING_HEADROOM := LlmProvider.REASONING_HEADROOM

## Families that accept `temperature`. Anything else — including a model this
## code has never heard of — goes without, because a missing sampling
## parameter costs nothing and a rejected one costs the whole reply.
const SAMPLING_FAMILIES: Array[String] = [
	"claude-3", "claude-haiku-4", "claude-sonnet-4",
	"claude-opus-4-0", "claude-opus-4-1", "claude-opus-4-5", "claude-opus-4-6",
]
const THINKING_FAMILIES: Array[String] = ["claude-opus-5", "claude-sonnet-5", "claude-fable"]
const EFFORT_FAMILIES: Array[String] = [
	"claude-opus-5", "claude-sonnet-5", "claude-fable",
	"claude-opus-4-5", "claude-opus-4-6", "claude-opus-4-7", "claude-opus-4-8", "claude-sonnet-4-6",
]


func id() -> String:
	return "anthropic"


func display_name() -> String:
	return "Anthropic"


func suggested_models() -> Dictionary:
	return {
		"main": ["claude-opus-5", "claude-sonnet-5"],
		"cheap": ["claude-haiku-4-5"],
	}


static func accepts_temperature(model: String) -> bool:
	return _in_family(model, SAMPLING_FAMILIES)


static func thinks_by_default(model: String) -> bool:
	return _in_family(model, THINKING_FAMILIES)


static func accepts_effort(model: String) -> bool:
	return _in_family(model, EFFORT_FAMILIES)


func build_http(request: LlmRequest, model: String, api_key: String) -> Dictionary:
	var turns: Array = []
	for message in request.messages:
		var role := str(message.get("role", "user"))
		turns.append({
			"role": "assistant" if role == "assistant" else "user",
			"content": str(message.get("content", "")),
		})

	var max_tokens := request.max_output_tokens
	if thinks_by_default(model):
		max_tokens += THINKING_HEADROOM
	var body := {
		"model": model,
		"max_tokens": max_tokens,
		"messages": turns,
	}
	if accepts_temperature(model):
		body["temperature"] = request.temperature
	if accepts_effort(model):
		body["output_config"] = {"effort": "low"}
	if not request.system.is_empty():
		body["system"] = request.system

	return {
		"url": ENDPOINT,
		"method": HTTPClient.METHOD_POST,
		"headers": PackedStringArray([
			"Content-Type: application/json",
			"x-api-key: " + api_key,
			"anthropic-version: " + API_VERSION,
		]),
		"body": JSON.stringify(body),
	}


func parse_http(status: int, body_text: String, model: String) -> LlmResponse:
	var code := LlmProvider.classify_status(status)
	if not code.is_empty():
		return LlmResponse.failure(code, LlmProvider.error_text(body_text))

	var parsed: Variant = SafeJson.parse(body_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return LlmResponse.failure("bad_response", "response was not JSON")

	# A safety classifier may decline with a normal 200; whatever text came
	# before it is not an answer.
	if str(parsed.get("stop_reason", "")) == "refusal":
		return LlmResponse.failure("refused", "the model declined")

	var blocks: Array = parsed.get("content", [])
	var text := ""
	for block in blocks:
		if typeof(block) == TYPE_DICTIONARY and str(block.get("type", "")) == "text":
			text += str(block.get("text", ""))
	if text.is_empty() and blocks.is_empty():
		return LlmResponse.failure("bad_response", "no content returned")

	var response := LlmResponse.success(text, str(parsed.get("model", model)), id())
	response.finish_reason = str(parsed.get("stop_reason", ""))
	var usage: Dictionary = parsed.get("usage", {})
	response.prompt_tokens = int(usage.get("input_tokens", 0))
	response.completion_tokens = int(usage.get("output_tokens", 0))
	return response


static func _in_family(model: String, families: Array[String]) -> bool:
	for family in families:
		if model == family or model.begins_with(family + "-") or model.begins_with(family + "."):
			return true
	return false
