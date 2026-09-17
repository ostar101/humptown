class_name GoogleProvider
extends LlmProvider
## Google Gemini generateContent adapter.
##
## The key goes in the x-goog-api-key header rather than the documented query
## parameter, so it cannot leak into a URL that ends up in a log or an error.

const ENDPOINT_TEMPLATE := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"


func id() -> String:
	return "google"


func display_name() -> String:
	return "Google"


func suggested_models() -> Dictionary:
	return {
		"main": ["gemini-2.5-pro", "gemini-2.0-flash"],
		"cheap": ["gemini-2.5-flash", "gemini-2.0-flash-lite"],
	}


func build_http(request: LlmRequest, model: String, api_key: String) -> Dictionary:
	var contents: Array = []
	for message in request.messages:
		var role := str(message.get("role", "user"))
		contents.append({
			"role": "model" if role == "assistant" else "user",
			"parts": [{"text": str(message.get("content", ""))}],
		})

	var body := {
		"contents": contents,
		"generationConfig": {
			"temperature": request.temperature,
			"maxOutputTokens": request.max_output_tokens,
		},
	}
	if not request.system.is_empty():
		body["systemInstruction"] = {"parts": [{"text": request.system}]}

	return {
		"url": ENDPOINT_TEMPLATE % model,
		"method": HTTPClient.METHOD_POST,
		"headers": PackedStringArray([
			"Content-Type: application/json",
			"x-goog-api-key: " + api_key,
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

	var candidates: Array = parsed.get("candidates", [])
	if candidates.is_empty():
		# Gemini returns an empty candidate list when safety filters trip.
		var feedback: Dictionary = parsed.get("promptFeedback", {})
		var reason := str(feedback.get("blockReason", "no candidates returned"))
		return LlmResponse.failure("bad_response", reason)

	var first: Dictionary = candidates[0]
	var content: Dictionary = first.get("content", {})
	var text := ""
	for part in content.get("parts", []):
		if typeof(part) == TYPE_DICTIONARY:
			text += str(part.get("text", ""))

	var response := LlmResponse.success(text, model, id())
	response.finish_reason = str(first.get("finishReason", ""))
	var usage: Dictionary = parsed.get("usageMetadata", {})
	response.prompt_tokens = int(usage.get("promptTokenCount", 0))
	response.completion_tokens = int(usage.get("candidatesTokenCount", 0))
	return response
