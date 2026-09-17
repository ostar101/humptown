class_name AnthropicProvider
extends LlmProvider
## Anthropic Messages API adapter.
##
## Anthropic takes the system prompt as a top-level field rather than a
## message turn, and returns content as a list of blocks.

const ENDPOINT := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2023-06-01"


func id() -> String:
	return "anthropic"


func display_name() -> String:
	return "Anthropic"


func suggested_models() -> Dictionary:
	return {
		"main": ["claude-sonnet-4-5", "claude-opus-4-1"],
		"cheap": ["claude-haiku-4-5", "claude-3-5-haiku-latest"],
	}


func build_http(request: LlmRequest, model: String, api_key: String) -> Dictionary:
	var turns: Array = []
	for message in request.messages:
		var role := str(message.get("role", "user"))
		turns.append({
			"role": "assistant" if role == "assistant" else "user",
			"content": str(message.get("content", "")),
		})

	var body := {
		"model": model,
		"max_tokens": request.max_output_tokens,
		"temperature": request.temperature,
		"messages": turns,
	}
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
