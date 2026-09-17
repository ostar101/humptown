class_name OpenAiProvider
extends LlmProvider
## OpenAI Chat Completions adapter.

const ENDPOINT := "https://api.openai.com/v1/chat/completions"


func id() -> String:
	return "openai"


func display_name() -> String:
	return "OpenAI"


func suggested_models() -> Dictionary:
	return {
		"main": ["gpt-4.1", "gpt-4o", "gpt-5"],
		"cheap": ["gpt-4.1-mini", "gpt-4o-mini", "gpt-5-mini"],
	}


func build_http(request: LlmRequest, model: String, api_key: String) -> Dictionary:
	var body := {
		"model": model,
		"messages": LlmProvider.with_system_message(request.system, request.messages),
		"temperature": request.temperature,
	}
	# Newer reasoning-capable models renamed the output cap.
	if _uses_completion_tokens(model):
		body["max_completion_tokens"] = request.max_output_tokens
	else:
		body["max_tokens"] = request.max_output_tokens

	return {
		"url": ENDPOINT,
		"method": HTTPClient.METHOD_POST,
		"headers": PackedStringArray([
			"Content-Type: application/json",
			"Authorization: Bearer " + api_key,
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
	var choices: Array = parsed.get("choices", [])
	if choices.is_empty():
		return LlmResponse.failure("bad_response", "no choices returned")

	var first: Dictionary = choices[0]
	var message: Dictionary = first.get("message", {})
	var response := LlmResponse.success(str(message.get("content", "")), str(parsed.get("model", model)), id())
	response.finish_reason = str(first.get("finish_reason", ""))
	var usage: Dictionary = parsed.get("usage", {})
	response.prompt_tokens = int(usage.get("prompt_tokens", 0))
	response.completion_tokens = int(usage.get("completion_tokens", 0))
	return response


func _uses_completion_tokens(model: String) -> bool:
	return model.begins_with("gpt-5") or model.begins_with("o1") or model.begins_with("o3") or model.begins_with("o4")
