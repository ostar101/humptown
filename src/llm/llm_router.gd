class_name LlmRouter
extends RefCounted
## Decides which model — if any — handles a request, and remembers answers.
##
## The cost rule from the design brief lives here: use no model when rules
## suffice, the cheap model for classification and small reactions, the main
## model only for conversation that matters. Routing is a pure function of
## purpose and mode, so it is fully unit-testable without a network.

const MODEL_CLASS_NONE := "none"
const MODEL_CLASS_CHEAP := "cheap"
const MODEL_CLASS_MAIN := "main"

## Baseline: which class each purpose wants when the player has not tilted
## the routing mode either way.
const BASE_ROUTING := {
	LlmRequest.Purpose.INTENT: MODEL_CLASS_CHEAP,
	LlmRequest.Purpose.REACTION: MODEL_CLASS_CHEAP,
	LlmRequest.Purpose.EXTRACT: MODEL_CLASS_CHEAP,
	LlmRequest.Purpose.SUMMARISE: MODEL_CLASS_CHEAP,
	LlmRequest.Purpose.DIALOGUE: MODEL_CLASS_MAIN,
	LlmRequest.Purpose.KEY_DIALOGUE: MODEL_CLASS_MAIN,
	LlmRequest.Purpose.NARRATIVE: MODEL_CLASS_MAIN,
}

## cheap_first saves money by demoting ordinary chat; quality promotes the
## cheap tasks that benefit most from a better model. KEY_DIALOGUE is never
## demoted — the scenes that matter always get the good model.
const MODE_ADJUSTMENTS := {
	"cheap_first": {
		LlmRequest.Purpose.DIALOGUE: MODEL_CLASS_CHEAP,
		LlmRequest.Purpose.NARRATIVE: MODEL_CLASS_CHEAP,
	},
	"quality": {
		LlmRequest.Purpose.REACTION: MODEL_CLASS_MAIN,
		LlmRequest.Purpose.EXTRACT: MODEL_CLASS_MAIN,
	},
	"balanced": {},
}

## Seconds a cached answer stays usable.
const CACHE_TTL := 900.0
const CACHE_LIMIT := 256

var routing_mode: String = "balanced"
var main_model: String = ""
var cheap_model: String = ""

var _cache: Dictionary = {}          # key -> {response, at}
var _cache_order: Array[String] = []


func configure(mode: String, p_main_model: String, p_cheap_model: String) -> void:
	routing_mode = mode if MODE_ADJUSTMENTS.has(mode) else "balanced"
	main_model = p_main_model
	cheap_model = p_cheap_model


## Which model class should serve this request.
func model_class_for(request: LlmRequest) -> String:
	if not request.force_model_class.is_empty():
		return request.force_model_class
	var adjustments: Dictionary = MODE_ADJUSTMENTS.get(routing_mode, {})
	if adjustments.has(request.purpose):
		return adjustments[request.purpose]
	return BASE_ROUTING.get(request.purpose, MODEL_CLASS_MAIN)


## The concrete model name, falling back sensibly when only one is configured.
func resolve_model(request: LlmRequest) -> String:
	var wanted := model_class_for(request)
	if wanted == MODEL_CLASS_CHEAP:
		return cheap_model if not cheap_model.is_empty() else main_model
	return main_model if not main_model.is_empty() else cheap_model


## Whether a model is needed at all. Deterministic logic is always preferred:
## an empty or trivially short player utterance never justifies a call.
func should_call(request: LlmRequest) -> bool:
	if resolve_model(request).is_empty():
		return false
	if request.messages.is_empty():
		return false
	var last := str(request.messages[request.messages.size() - 1].get("content", "")).strip_edges()
	if request.purpose == LlmRequest.Purpose.INTENT and last.length() < 2:
		return false
	return true


# --- caching ----------------------------------------------------------------

func cached(request: LlmRequest, provider_id: String, model: String, now_seconds: float) -> LlmResponse:
	if not request.is_cacheable():
		return null
	var key := request.cache_key(provider_id, model)
	var entry: Variant = _cache.get(key)
	if entry == null:
		return null
	if now_seconds - float(entry["at"]) > CACHE_TTL:
		_cache.erase(key)
		_cache_order.erase(key)
		return null
	var hit: LlmResponse = entry["response"]
	hit.from_cache = true
	return hit


func store(request: LlmRequest, provider_id: String, model: String, response: LlmResponse, now_seconds: float) -> void:
	if not request.is_cacheable() or not response.ok:
		return
	var key := request.cache_key(provider_id, model)
	if not _cache.has(key):
		_cache_order.append(key)
	_cache[key] = {"response": response, "at": now_seconds}
	while _cache_order.size() > CACHE_LIMIT:
		var evicted: String = _cache_order.pop_front()
		_cache.erase(evicted)


func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()


func cache_size() -> int:
	return _cache.size()
