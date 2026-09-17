class_name LlmResponse
extends RefCounted
## The result of a model call, normalised across providers.

var ok: bool = false
var text: String = ""
var finish_reason: String = ""
var prompt_tokens: int = 0
var completion_tokens: int = 0
var model: String = ""
var provider: String = ""
## "" on success; otherwise one of: no_key, network, timeout, rate_limited,
## auth, server, bad_response, budget_exceeded, circuit_open, disabled.
var error_code: String = ""
var error_message: String = ""
var latency_ms: int = 0
var from_cache: bool = false
var request_id: String = ""


static func success(text: String, model: String, provider: String) -> LlmResponse:
	var r := LlmResponse.new()
	r.ok = true
	r.text = text
	r.model = model
	r.provider = provider
	return r


static func failure(code: String, message: String = "") -> LlmResponse:
	var r := LlmResponse.new()
	r.ok = false
	r.error_code = code
	r.error_message = message
	return r


func total_tokens() -> int:
	return prompt_tokens + completion_tokens


## Whether retrying this failure could plausibly succeed.
func is_retryable() -> bool:
	return error_code in ["network", "timeout", "rate_limited", "server"]


## Parses the response as JSON when the call asked for structured output.
## Tolerates models that wrap JSON in prose or a code fence, because they do.
func as_json() -> Variant:
	if text.is_empty():
		return null
	var direct: Variant = SafeJson.parse(text)
	if direct != null:
		return direct
	var start := text.find("{")
	var end := text.rfind("}")
	if start >= 0 and end > start:
		return SafeJson.parse(text.substr(start, end - start + 1))
	start = text.find("[")
	end = text.rfind("]")
	if start >= 0 and end > start:
		return SafeJson.parse(text.substr(start, end - start + 1))
	return null


func to_debug_dict() -> Dictionary:
	return {
		"ok": ok, "provider": provider, "model": model,
		"prompt_tokens": prompt_tokens, "completion_tokens": completion_tokens,
		"latency_ms": latency_ms, "cached": from_cache,
		"error": error_code, "finish": finish_reason,
	}
