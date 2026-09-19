class_name LlmDialogueModel
extends DialogueModel
## The game's LLM client as the voice of the people in it (D-036). All the
## routing, budget, retries and circuit breaking live in `LlmClient`; this
## only adapts it to what a conversation needs.

var client: LlmClient = null


func _init(p_client: LlmClient = null) -> void:
	client = p_client


func is_available() -> bool:
	return client != null and client.is_available()


func send(request: LlmRequest) -> LlmResponse:
	if client == null:
		return LlmResponse.failure("disabled", "No LLM client")
	return await client.send(request)
