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
