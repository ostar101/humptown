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
	}
	if not LlmProvider.rejects_temperature(model):
		body["temperature"] = request.temperature
	# Newer reasoning-capable models renamed the output cap.
	if _uses_completion_tokens(model):
		body["max_completion_tokens"] = LlmProvider.output_cap(request, model)
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
	return LlmProvider.parse_chat_completion(parsed, model, id())


func _uses_completion_tokens(model: String) -> bool:
	return model.begins_with("gpt-5") or model.begins_with("o1") or model.begins_with("o3") or model.begins_with("o4")
