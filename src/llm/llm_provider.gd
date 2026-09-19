class_name LlmProvider
extends RefCounted
## Base class for model providers.
##
## Providers are pure: they translate an LlmRequest into an HTTP call and an
## HTTP reply back into an LlmResponse, and they perform no I/O themselves.
## Transport lives in LlmClient. Two things fall out of that split — adding a
## provider is one small file with no engine coupling, and every adapter can
## be unit-tested headless without a network or an API key.

## Stable id used in settings and the secret store.
func id() -> String:
	return "base"


func display_name() -> String:
	return "Base"


## Models offered in the settings dropdown. The player may also type their own.
## { "main": [...], "cheap": [...] }
func suggested_models() -> Dictionary:
	return {"main": [], "cheap": []}


## Builds the HTTP call. Returns {url, method, headers: PackedStringArray, body}.
func build_http(_request: LlmRequest, _model: String, _api_key: String) -> Dictionary:
	push_error("LlmProvider.build_http must be overridden")
	return {}


## Turns an HTTP reply into a normalised response.
func parse_http(_status: int, _body_text: String, _model: String) -> LlmResponse:
	push_error("LlmProvider.parse_http must be overridden")
	return LlmResponse.failure("bad_response")


# --- shared helpers ---------------------------------------------------------

## Extra output room for models that think before they answer: the output cap
## covers thinking and answer together, so a tight cap is spent on thinking and
## the answer is cut off or comes back empty. Only generated tokens are billed.
const REASONING_HEADROOM := 1024
## Name fragments of models that think by default (matched anywhere in the id,
## so `google/gemini-3-flash` and `gemini-2.5-flash` both count).
const REASONING_MARKERS: Array[String] = [
	"gemini-2.5", "gemini-3", "gpt-5", "/o1", "/o3", "/o4", "o1-", "o3-", "o4-",
	"deepseek-r1", "qwen3", "grok-3-mini", "grok-4", ":thinking", "-thinking",
	"claude-opus-5", "claude-sonnet-5", "claude-fable",
]


static func may_reason(model: String) -> bool:
	var lower := model.to_lower()
	if lower.begins_with("o1") or lower.begins_with("o3") or lower.begins_with("o4"):
		return true
	for marker in REASONING_MARKERS:
		if lower.contains(marker):
			return true
	return false


## The output cap to send: the caller's budget for the answer, plus room to
## think when the model is one that does.
static func output_cap(request: LlmRequest, model: String) -> int:
	return request.max_output_tokens + (REASONING_HEADROOM if may_reason(model) else 0)


## Maps an HTTP status to one of our error codes.
static func classify_status(status: int) -> String:
	if status == 401 or status == 403:
		return "auth"
	if status == 429:
		return "rate_limited"
	if status >= 500:
		return "server"
	if status >= 400:
		return "bad_request"
	return ""


## Extracts a provider error message without ever echoing credentials.
static func error_text(body_text: String) -> String:
	var parsed: Variant = SafeJson.parse(body_text)
	if typeof(parsed) == TYPE_DICTIONARY:
		var error: Variant = parsed.get("error")
		if typeof(error) == TYPE_DICTIONARY:
			return str(error.get("message", ""))
		if typeof(error) == TYPE_STRING:
			return str(error)
		if parsed.has("message"):
			return str(parsed["message"])
	return body_text.substr(0, 200)


## Splits our messages into the OpenAI-style array with a leading system turn.
static func with_system_message(system: String, messages: Array[Dictionary]) -> Array:
	var out: Array = []
	if not system.is_empty():
		out.append({"role": "system", "content": system})
	for message in messages:
		out.append({"role": str(message.get("role", "user")), "content": str(message.get("content", ""))})
	return out
