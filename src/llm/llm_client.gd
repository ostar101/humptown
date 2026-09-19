class_name LlmClient
extends Node
## Transport for model calls: the only place in the game that touches the network.
##
## Everything policy-shaped (which model, may we call, what did we already
## ask) lives in LlmRouter and LlmBudget; this class does HTTP, timeouts,
## retries with backoff, and in-flight deduplication. Keeping it thin is what
## lets the whole LLM stack be tested headless.
##
## Failure is never fatal. Every path returns a well-formed LlmResponse, so
## callers branch on `ok` and fall back to authored content — the game stays
## playable with no key, no network, or a dead provider.

const MAX_CONCURRENT := 4
const BACKOFF_BASE := 0.6

var provider: LlmProvider = NullProvider.new()
var router := LlmRouter.new()
var budget := LlmBudget.new()
var secrets := SecretStore.new()
## True in the test runner: whatever the settings say, no real provider is
## built, so no test can reach a network, spend money or send a key (D-036).
var sandboxed := false

## Captured request/response pairs for the developer overlay. Never contains
## the API key: only the provider id ever reaches this.
var debug_log: Array[Dictionary] = []
const DEBUG_LOG_LIMIT := 40

var _in_flight: Dictionary = {}      # cache key -> Array of callables awaiting
var _active := 0

const PROVIDERS := {
	"openai": "res://src/llm/providers/openai_provider.gd",
	"anthropic": "res://src/llm/providers/anthropic_provider.gd",
	"google": "res://src/llm/providers/google_provider.gd",
	"openrouter": "res://src/llm/providers/openrouter_provider.gd",
}

signal response_received(request_id: String, response: LlmResponse)


func _ready() -> void:
	reconfigure()
	Events.settings_changed.connect(_on_settings_changed)


## Rebuilds the provider and routing from current settings.
func reconfigure() -> void:
	var provider_id := str(Settings.get_value("llm_provider", "none"))
	provider = make_provider("none" if sandboxed else provider_id)
	router.configure(
		str(Settings.get_value("llm_routing_mode", "balanced")),
		str(Settings.get_value("llm_main_model", "")),
		str(Settings.get_value("llm_cheap_model", "")))
	budget.daily_request_cap = int(Settings.get_value("llm_daily_request_cap", 600))
	Log.info("llm", "LLM configured", {
		"provider": provider.id(),
		"main": router.main_model,
		"cheap": router.cheap_model,
		"mode": router.routing_mode,
		"has_key": secrets.has_key(provider.id()),
	})


static func make_provider(provider_id: String) -> LlmProvider:
	if not PROVIDERS.has(provider_id):
		return NullProvider.new()
	var script: GDScript = load(PROVIDERS[provider_id])
	return script.new()


static func available_provider_ids() -> Array[String]:
	var out: Array[String] = ["none"]
	for id in PROVIDERS:
		out.append(str(id))
	return out


## True when a real model could answer right now.
func is_available() -> bool:
	return provider.id() != "none" \
		and secrets.has_key(provider.id()) \
		and not router.resolve_model(LlmRequest.simple(LlmRequest.Purpose.DIALOGUE, "", "x")).is_empty()


## Sends a request. Always returns an LlmResponse; never throws, never hangs
## past the configured timeout. Await this.
func send(request: LlmRequest) -> LlmResponse:
	var started := Time.get_ticks_msec()
	var response := await _send_inner(request)
	response.latency_ms = Time.get_ticks_msec() - started
	response.request_id = request.id
	_record_debug(request, response)
	Events.llm_request_finished.emit(request.id, response.ok, response.to_debug_dict())
	response_received.emit(request.id, response)
	return response


func _send_inner(request: LlmRequest) -> LlmResponse:
	if provider.id() == "none":
		return LlmResponse.failure("disabled", "No LLM provider configured")

	var api_key := secrets.get_key(provider.id())
	if api_key.is_empty():
		return LlmResponse.failure("no_key", "No API key stored for " + provider.display_name())

	if not router.should_call(request):
		return LlmResponse.failure("disabled", "Routing declined the call")

	var model := router.resolve_model(request)
	var now := Time.get_ticks_msec() / 1000.0

	var hit := router.cached(request, provider.id(), model, now)
	if hit != null:
		budget.on_cache_hit()
		return hit

	# Deduplicate identical concurrent requests: the second caller waits for
	# the first rather than paying for the same answer twice.
	var key := request.cache_key(provider.id(), model)
	if _in_flight.has(key):
		await (_in_flight[key] as Node).tree_exited
		var deduped := router.cached(request, provider.id(), model, Time.get_ticks_msec() / 1000.0)
		if deduped != null:
			budget.on_cache_hit()
			return deduped

	var gate := budget.allow(now)
	if gate.is_err():
		return LlmResponse.failure(gate.code, gate.message)

	while _active >= MAX_CONCURRENT:
		await get_tree().process_frame

	var marker := Node.new()
	add_child(marker)
	_in_flight[key] = marker
	_active += 1

	Events.llm_request_started.emit(request.id, request.purpose_name())
	var response := await _send_with_retries(request, model, api_key)

	_active -= 1
	_in_flight.erase(key)
	marker.queue_free()

	if response.ok:
		budget.on_success(response)
		router.store(request, provider.id(), model, response, Time.get_ticks_msec() / 1000.0)
	else:
		budget.on_failure(Time.get_ticks_msec() / 1000.0, response)
	return response


func _send_with_retries(request: LlmRequest, model: String, api_key: String) -> LlmResponse:
	var max_retries := int(Settings.get_value("llm_max_retries", 2))
	var attempt := 0
	var last := LlmResponse.failure("network", "not attempted")

	while attempt <= max_retries:
		if attempt > 0:
			# Exponential backoff with jitter, so several NPCs failing at once
			# do not retry in lockstep.
			var wait := BACKOFF_BASE * pow(2.0, float(attempt - 1))
			wait += randf() * 0.3
			await get_tree().create_timer(wait).timeout

		budget.on_request_sent(Time.get_ticks_msec() / 1000.0)
		last = await _perform(request, model, api_key)
		if last.ok or not last.is_retryable():
			return last
		Log.debug("llm", "Retrying after failure", {
			"attempt": attempt + 1, "error": last.error_code,
		})
		attempt += 1

	return last


func _perform(request: LlmRequest, model: String, api_key: String) -> LlmResponse:
	var spec := provider.build_http(request, model, api_key)
	if spec.is_empty():
		return LlmResponse.failure("disabled", "Provider produced no request")

	var http := HTTPRequest.new()
	http.timeout = float(Settings.get_value("llm_timeout_seconds", 20.0))
	http.accept_gzip = true
	add_child(http)

	var error := http.request(
		str(spec["url"]),
		spec["headers"],
		spec.get("method", HTTPClient.METHOD_POST),
		str(spec.get("body", "")))
	if error != OK:
		http.queue_free()
		return LlmResponse.failure("network", "request could not be started (%d)" % error)

	var outcome: Array = await http.request_completed
	http.queue_free()

	var result := int(outcome[0])
	var status := int(outcome[1])
	var body: PackedByteArray = outcome[3]

	if result == HTTPRequest.RESULT_TIMEOUT:
		return LlmResponse.failure("timeout", "provider did not answer in time")
	if result != HTTPRequest.RESULT_SUCCESS:
		return LlmResponse.failure("network", "transport error %d" % result)

	return provider.parse_http(status, body.get_string_from_utf8(), model)


func _record_debug(request: LlmRequest, response: LlmResponse) -> void:
	if not bool(Settings.get_value("llm_debug_capture", false)):
		return
	debug_log.append({
		"request": request.to_debug_dict(),
		"response": response.to_debug_dict(),
	})
	while debug_log.size() > DEBUG_LOG_LIMIT:
		debug_log.remove_at(0)


func _on_settings_changed(key: String) -> void:
	if key.begins_with("llm_") or key == "*":
		reconfigure()


## Snapshot for the developer overlay.
func stats() -> Dictionary:
	var out := budget.stats(router.main_model)
	out["provider"] = provider.id()
	out["main_model"] = router.main_model
	out["cheap_model"] = router.cheap_model
	out["routing_mode"] = router.routing_mode
	out["cache_entries"] = router.cache_size()
	out["available"] = is_available()
	return out
