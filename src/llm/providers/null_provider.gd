class_name NullProvider
extends LlmProvider
## The provider used when there is no key, no network, or the player has
## turned AI dialogue off.
##
## It is not an error path bolted on afterwards — it is a first-class
## provider, which is what guarantees the rest of the game never has to ask
## whether the LLM exists. Every call still returns a well-formed response;
## the dialogue layer sees `error_code == "disabled"` and falls back to
## authored lines.

func id() -> String:
	return "none"


func display_name() -> String:
	return "Offline (no AI dialogue)"


func suggested_models() -> Dictionary:
	return {"main": [], "cheap": []}


func build_http(_request: LlmRequest, _model: String, _api_key: String) -> Dictionary:
	return {}


func parse_http(_status: int, _body_text: String, _model: String) -> LlmResponse:
	return LlmResponse.failure("disabled", "No LLM provider configured")
