class_name DialogueModel
extends RefCounted
## Whatever answers as a person in conversation (D-036).
##
## The base answers nothing, which is exactly the offline game: every reply
## comes from authored lines. `LlmDialogueModel` puts the game's `LlmClient`
## behind the same two calls; tests put a scripted stand-in there instead, so
## the whole conversation path is exercised without a network or a key.


## True when asking would plausibly get an answer — a provider, a key and a
## model are configured. Not a promise: `send` can still fail, and callers
## fall back when it does.
func is_available() -> bool:
	return false


## Await this. Always returns a response, never throws.
func send(_request: LlmRequest) -> LlmResponse:
	return LlmResponse.failure("disabled", "No model answers in conversation")
