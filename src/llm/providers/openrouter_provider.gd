class_name OpenRouterProvider
extends LlmProvider
## OpenRouter adapter. The wire format is OpenAI-compatible, so this reuses
## that shape and adds the attribution headers OpenRouter asks for.

const ENDPOINT := "https://openrouter.ai/api/v1/chat/completions"
const APP_TITLE := "Humptown"
const APP_URL := "https://github.com/"


func id() -> String:
	return "openrouter"


func display_name() -> String:
	return "OpenRouter"


func suggested_models() -> Dictionary:
	return {
		"main": [
			"anthropic/claude-sonnet-4.5",
			"openai/gpt-4.1",
			"google/gemini-2.5-pro",
			"meta-llama/llama-3.3-70b-instruct",
		],
		"cheap": [
			"anthropic/claude-haiku-4.5",
			"openai/gpt-4.1-mini",
			"google/gemini-2.5-flash",
			"mistralai/mistral-small",
		],
	}


func build_http(request: LlmRequest, model: String, api_key: String) -> Dictionary:
	var body := {
		"model": model,
		"messages": LlmProvider.with_system_message(request.system, request.messages),
		"temperature": request.temperature,
		"max_tokens": LlmProvider.output_cap(request, model),
	}
	if LlmProvider.may_reason(model):
		# Models that do not reason ignore this; the ones that do keep it short.
		body["reasoning"] = {"effort": "low"}
	return {
		"url": ENDPOINT,
		"method": HTTPClient.METHOD_POST,
		"headers": PackedStringArray([
			"Content-Type: application/json",
			"Authorization: Bearer " + api_key,
			"HTTP-Referer: " + APP_URL,
			"X-Title: " + APP_TITLE,
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
	# OpenRouter reports upstream failures with HTTP 200 and an error body.
	if parsed.has("error") and not parsed.has("choices"):
		return LlmResponse.failure("server", LlmProvider.error_text(body_text))

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
