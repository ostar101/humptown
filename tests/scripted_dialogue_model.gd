class_name ScriptedDialogueModel
extends DialogueModel
## A stand-in model for tests: answers from a script, and remembers what it
## was asked. Readings of what the player meant (INTENT requests) and lines
## of speech (DIALOGUE requests) come from separate queues, so a test scripts
## only the one it is about; an empty queue answers like a dropped network,
## and the game falls back as it would in play. Nothing here touches a
## network.

var available := true
## Answers to INTENT requests: JSON text, or a failure.
var intents: Array[LlmResponse] = []
## Answers to DIALOGUE requests.
var replies: Array[LlmResponse] = []
var requests: Array[LlmRequest] = []


func is_available() -> bool:
	return available


func send(request: LlmRequest) -> LlmResponse:
	requests.append(request)
	var queue := intents if request.purpose == LlmRequest.Purpose.INTENT else replies
	if queue.is_empty():
		return LlmResponse.failure("network", "nothing scripted")
	return queue.pop_front()


func requests_for(purpose: LlmRequest.Purpose) -> Array[LlmRequest]:
	var out: Array[LlmRequest] = []
	for request in requests:
		if request.purpose == purpose:
			out.append(request)
	return out


static func say(text: String) -> LlmResponse:
	return LlmResponse.success(text, "scripted", "test")


static func meaning(kind: String, fields: Dictionary = {}) -> LlmResponse:
	var answer := {"intent": kind, "person": "", "place": "", "amount": 0, "name": ""}
	answer.merge(fields, true)
	return LlmResponse.success(JSON.stringify(answer), "scripted", "test")
