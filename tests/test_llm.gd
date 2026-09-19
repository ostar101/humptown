extends TestCase
## The LLM stack, tested without a network or an API key.
##
## Providers are pure request-builders and response-parsers, which is exactly
## what makes this possible: every wire format, every error path and every
## routing decision is checked here, offline, every run.

# --- routing ----------------------------------------------------------------

func _router(mode: String = "balanced") -> LlmRouter:
	var router := LlmRouter.new()
	router.configure(mode, "main-model", "cheap-model")
	return router


func _request(purpose: LlmRequest.Purpose) -> LlmRequest:
	return LlmRequest.simple(purpose, "system", "hello there")


func test_cheap_work_uses_the_cheap_model() -> void:
	var router := _router()
	assert_eq(router.resolve_model(_request(LlmRequest.Purpose.INTENT)), "cheap-model")
	assert_eq(router.resolve_model(_request(LlmRequest.Purpose.EXTRACT)), "cheap-model")
	assert_eq(router.resolve_model(_request(LlmRequest.Purpose.SUMMARISE)), "cheap-model")


func test_conversation_uses_the_main_model() -> void:
	var router := _router()
	assert_eq(router.resolve_model(_request(LlmRequest.Purpose.DIALOGUE)), "main-model")
	assert_eq(router.resolve_model(_request(LlmRequest.Purpose.KEY_DIALOGUE)), "main-model")


func test_cheap_first_demotes_ordinary_chat() -> void:
	var router := _router("cheap_first")
	assert_eq(router.resolve_model(_request(LlmRequest.Purpose.DIALOGUE)), "cheap-model")


func test_cheap_first_never_demotes_the_scenes_that_matter() -> void:
	var router := _router("cheap_first")
	assert_eq(router.resolve_model(_request(LlmRequest.Purpose.KEY_DIALOGUE)), "main-model")


func test_quality_mode_promotes_small_tasks() -> void:
	var router := _router("quality")
	assert_eq(router.resolve_model(_request(LlmRequest.Purpose.REACTION)), "main-model")


func test_unknown_routing_mode_falls_back_to_balanced() -> void:
	var router := _router("nonsense")
	assert_eq(router.routing_mode, "balanced")


func test_a_request_can_force_its_class() -> void:
	var router := _router()
	var request := _request(LlmRequest.Purpose.DIALOGUE)
	request.force_model_class = "cheap"
	assert_eq(router.resolve_model(request), "cheap-model")


func test_missing_cheap_model_falls_back_to_main() -> void:
	var router := LlmRouter.new()
	router.configure("balanced", "main-model", "")
	assert_eq(router.resolve_model(_request(LlmRequest.Purpose.INTENT)), "main-model")


func test_no_models_configured_means_no_call() -> void:
	var router := LlmRouter.new()
	router.configure("balanced", "", "")
	assert_false(router.should_call(_request(LlmRequest.Purpose.DIALOGUE)))


func test_trivial_input_does_not_justify_a_call() -> void:
	var router := _router()
	var request := LlmRequest.simple(LlmRequest.Purpose.INTENT, "s", " ")
	assert_false(router.should_call(request), "deterministic logic handles nothing")


func test_empty_message_list_does_not_justify_a_call() -> void:
	var router := _router()
	var request := LlmRequest.create(LlmRequest.Purpose.DIALOGUE, "s", [])
	assert_false(router.should_call(request))


# --- caching ----------------------------------------------------------------

func test_classification_results_are_cached() -> void:
	var router := _router()
	var request := _request(LlmRequest.Purpose.INTENT)
	router.store(request, "openai", "cheap-model", LlmResponse.success("persuade", "m", "openai"), 100.0)
	var hit := router.cached(request, "openai", "cheap-model", 200.0)
	assert_not_null(hit)
	assert_eq(hit.text, "persuade")
	assert_true(hit.from_cache)


func test_conversation_is_never_cached() -> void:
	var router := _router()
	var request := _request(LlmRequest.Purpose.DIALOGUE)
	router.store(request, "openai", "main-model", LlmResponse.success("hi", "m", "openai"), 100.0)
	assert_null(router.cached(request, "openai", "main-model", 101.0),
		"replies must not repeat verbatim")


func test_cache_expires() -> void:
	var router := _router()
	var request := _request(LlmRequest.Purpose.INTENT)
	router.store(request, "openai", "cheap-model", LlmResponse.success("x", "m", "openai"), 100.0)
	assert_null(router.cached(request, "openai", "cheap-model", 100.0 + LlmRouter.CACHE_TTL + 1.0))


func test_failures_are_not_cached() -> void:
	var router := _router()
	var request := _request(LlmRequest.Purpose.INTENT)
	router.store(request, "openai", "cheap-model", LlmResponse.failure("server"), 100.0)
	assert_null(router.cached(request, "openai", "cheap-model", 101.0))


func test_cache_keys_separate_different_prompts_and_models() -> void:
	var a := LlmRequest.simple(LlmRequest.Purpose.INTENT, "s", "one")
	var b := LlmRequest.simple(LlmRequest.Purpose.INTENT, "s", "two")
	assert_ne(a.cache_key("openai", "m"), b.cache_key("openai", "m"))
	assert_ne(a.cache_key("openai", "m"), a.cache_key("openai", "other"))
	assert_ne(a.cache_key("openai", "m"), a.cache_key("google", "m"))


func test_cache_is_bounded() -> void:
	var router := _router()
	for i in range(LlmRouter.CACHE_LIMIT + 50):
		var request := LlmRequest.simple(LlmRequest.Purpose.INTENT, "s", "prompt %d" % i)
		router.store(request, "openai", "cheap-model", LlmResponse.success("x", "m", "openai"), 100.0)
	assert_lt(float(router.cache_size()), float(LlmRouter.CACHE_LIMIT + 1))


# --- budget and circuit breaker --------------------------------------------

func test_daily_cap_is_enforced() -> void:
	var budget := LlmBudget.new()
	budget.daily_request_cap = 2
	budget.on_request_sent(0.0)
	budget.on_request_sent(10.0)
	assert_err(budget.allow(20.0), "budget_exceeded")


func test_daily_cap_resets_with_the_world_date() -> void:
	var budget := LlmBudget.new()
	budget.daily_request_cap = 1
	budget.on_request_sent(0.0)
	assert_err(budget.allow(10.0), "budget_exceeded")
	budget.on_new_day(1)
	assert_ok(budget.allow(20.0))


func test_calls_are_rate_limited() -> void:
	var budget := LlmBudget.new()
	budget.on_request_sent(100.0)
	assert_err(budget.allow(100.0 + LlmBudget.MIN_INTERVAL * 0.5), "rate_limited")
	assert_ok(budget.allow(100.0 + LlmBudget.MIN_INTERVAL * 2.0))


func test_circuit_opens_after_repeated_failures() -> void:
	var budget := LlmBudget.new()
	for _i in range(LlmBudget.FAILURE_THRESHOLD):
		budget.on_failure(0.0, LlmResponse.failure("server"))
	assert_eq(budget.circuit, LlmBudget.CircuitState.OPEN)
	assert_err(budget.allow(1.0), "circuit_open")


func test_circuit_reopens_for_a_probe_then_closes_on_success() -> void:
	var budget := LlmBudget.new()
	for _i in range(LlmBudget.FAILURE_THRESHOLD):
		budget.on_failure(0.0, LlmResponse.failure("server"))
	assert_ok(budget.allow(LlmBudget.OPEN_SECONDS + 1.0))
	assert_eq(budget.circuit, LlmBudget.CircuitState.HALF_OPEN)
	budget.on_success(LlmResponse.success("ok", "m", "p"))
	assert_eq(budget.circuit, LlmBudget.CircuitState.CLOSED)


func test_our_own_refusals_do_not_trip_the_breaker() -> void:
	# "No key configured" is not evidence that the provider is down.
	var budget := LlmBudget.new()
	for _i in range(LlmBudget.FAILURE_THRESHOLD * 2):
		budget.on_failure(0.0, LlmResponse.failure("disabled"))
	assert_eq(budget.circuit, LlmBudget.CircuitState.CLOSED)


func test_token_accounting() -> void:
	var budget := LlmBudget.new()
	var response := LlmResponse.success("x", "m", "p")
	response.prompt_tokens = 1000
	response.completion_tokens = 200
	budget.on_success(response)
	assert_eq(budget.session_prompt_tokens, 1000)
	assert_gt(budget.estimated_session_cost_usd("gpt-4.1"), 0.0)


# --- provider request building ---------------------------------------------

func test_anthropic_puts_system_at_the_top_level() -> void:
	var provider := AnthropicProvider.new()
	var request := LlmRequest.simple(LlmRequest.Purpose.DIALOGUE, "You are Ida.", "hello")
	var spec := provider.build_http(request, "claude-sonnet-4-5", "sk-test")
	var body: Dictionary = JSON.parse_string(spec["body"])
	assert_eq(body["system"], "You are Ida.")
	assert_eq(body["messages"].size(), 1, "system is not a message turn here")
	assert_has(spec["headers"], "x-api-key: sk-test")
	assert_has(spec["headers"], "anthropic-version: " + AnthropicProvider.API_VERSION)


func test_current_claude_models_get_no_sampling_parameters() -> void:
	var provider := AnthropicProvider.new()
	var request := LlmRequest.simple(LlmRequest.Purpose.DIALOGUE, "s", "hello")
	request.max_output_tokens = 160
	for model in ["claude-opus-5", "claude-sonnet-5", "claude-fable-5-1", "claude-opus-4-8", "claude-opus-4-7"]:
		var body: Dictionary = JSON.parse_string(provider.build_http(request, model, "k")["body"])
		assert_false(body.has("temperature"), "%s answers temperature with a 400" % model)
		assert_eq(body["output_config"]["effort"], "low", model)
	var unknown: Dictionary = JSON.parse_string(provider.build_http(request, "claude-something-new", "k")["body"])
	assert_false(unknown.has("temperature"), "an unknown model goes without, to be safe")


func test_older_claude_models_keep_temperature_and_haiku_gets_no_effort() -> void:
	var provider := AnthropicProvider.new()
	var request := LlmRequest.simple(LlmRequest.Purpose.DIALOGUE, "s", "hello")
	request.temperature = 0.8
	var haiku: Dictionary = JSON.parse_string(provider.build_http(request, "claude-haiku-4-5", "k")["body"])
	assert_almost(float(haiku["temperature"]), 0.8, 0.001)
	assert_false(haiku.has("output_config"), "Haiku 4.5 answers effort with an error")
	var sonnet: Dictionary = JSON.parse_string(provider.build_http(request, "claude-sonnet-4-5-20250929", "k")["body"])
	assert_true(sonnet.has("temperature"), "a dated id belongs to its family")


func test_models_that_think_by_default_get_room_to_think() -> void:
	var provider := AnthropicProvider.new()
	var request := LlmRequest.simple(LlmRequest.Purpose.DIALOGUE, "s", "hello")
	request.max_output_tokens = 160
	var opus: Dictionary = JSON.parse_string(provider.build_http(request, "claude-opus-5", "k")["body"])
	assert_eq(int(opus["max_tokens"]), 160 + AnthropicProvider.THINKING_HEADROOM,
		"thinking and answer share max_tokens; a tight cap would cut the answer off")
	var haiku: Dictionary = JSON.parse_string(provider.build_http(request, "claude-haiku-4-5", "k")["body"])
	assert_eq(int(haiku["max_tokens"]), 160)


func test_anthropic_suggests_current_models() -> void:
	var models := AnthropicProvider.new().suggested_models()
	assert_eq(models["main"][0], "claude-opus-5")
	assert_has(models["cheap"], "claude-haiku-4-5")


func test_openai_puts_system_in_the_message_list() -> void:
	var provider := OpenAiProvider.new()
	var request := LlmRequest.simple(LlmRequest.Purpose.DIALOGUE, "You are Ida.", "hello")
	var spec := provider.build_http(request, "gpt-4.1", "sk-test")
	var body: Dictionary = JSON.parse_string(spec["body"])
	assert_eq(body["messages"][0]["role"], "system")
	assert_eq(body["messages"][1]["content"], "hello")
	assert_has(body, "max_tokens")


func test_openai_uses_the_new_token_field_for_newer_models() -> void:
	var provider := OpenAiProvider.new()
	var request := LlmRequest.simple(LlmRequest.Purpose.DIALOGUE, "s", "hello")
	var body: Dictionary = JSON.parse_string(provider.build_http(request, "gpt-5", "k")["body"])
	assert_has(body, "max_completion_tokens")
	assert_false(body.has("max_tokens"))


func test_google_uses_its_own_shape_and_header_auth() -> void:
	var provider := GoogleProvider.new()
	var request := LlmRequest.create(LlmRequest.Purpose.DIALOGUE, "You are Ida.", [
		{"role": "user", "content": "hello"},
		{"role": "assistant", "content": "hi"},
	])
	var spec := provider.build_http(request, "gemini-2.5-flash", "sk-test")
	var body: Dictionary = JSON.parse_string(spec["body"])
	assert_eq(body["contents"][1]["role"], "model", "assistant is called model here")
	assert_eq(body["systemInstruction"]["parts"][0]["text"], "You are Ida.")
	assert_has(spec["headers"], "x-goog-api-key: sk-test")
	assert_false(str(spec["url"]).contains("sk-test"), "the key must never ride in the URL")


func test_openrouter_sends_attribution_headers() -> void:
	var provider := OpenRouterProvider.new()
	var spec := provider.build_http(
		LlmRequest.simple(LlmRequest.Purpose.DIALOGUE, "s", "hi"), "anthropic/claude-haiku-4.5", "k")
	assert_has(spec["headers"], "X-Title: " + OpenRouterProvider.APP_TITLE)


func test_reasoning_models_on_every_provider_get_room_to_think() -> void:
	var request := LlmRequest.simple(LlmRequest.Purpose.DIALOGUE, "s", "hello")
	request.max_output_tokens = 200
	var reserve := LlmProvider.REASONING_HEADROOM
	var router: Dictionary = JSON.parse_string(OpenRouterProvider.new().build_http(request, "google/gemini-3.8-flash", "k")["body"])
	assert_eq(int(router["max_tokens"]), 200 + reserve, "Gemini thinks; a tight cap is eaten by the thinking")
	assert_eq(router["reasoning"]["effort"], "low")
	var plain: Dictionary = JSON.parse_string(OpenRouterProvider.new().build_http(request, "openai/gpt-4.1", "k")["body"])
	assert_eq(int(plain["max_tokens"]), 200)
	assert_false(plain.has("reasoning"))
	var google: Dictionary = JSON.parse_string(GoogleProvider.new().build_http(request, "gemini-2.5-flash", "k")["body"])
	assert_eq(int(google["generationConfig"]["maxOutputTokens"]), 200 + reserve)
	var gpt5: Dictionary = JSON.parse_string(OpenAiProvider.new().build_http(request, "gpt-5-mini", "k")["body"])
	assert_eq(int(gpt5["max_completion_tokens"]), 200 + reserve)


func test_a_length_stop_is_recognised() -> void:
	var response := OpenRouterProvider.new().parse_http(200, JSON.stringify({
		"choices": [{"message": {"content": "Hei, mitä kuuluu? Minä olen"}, "finish_reason": "length"}],
	}), "google/gemini-3.8-flash")
	assert_true(response.hit_length_limit())


# --- provider response parsing ---------------------------------------------

func test_anthropic_response_parsing() -> void:
	var provider := AnthropicProvider.new()
	var response := provider.parse_http(200, JSON.stringify({
		"content": [{"type": "text", "text": "Well, look who it is."}],
		"stop_reason": "end_turn", "model": "claude-sonnet-4-5",
		"usage": {"input_tokens": 120, "output_tokens": 18},
	}), "claude-sonnet-4-5")
	assert_true(response.ok)
	assert_eq(response.text, "Well, look who it is.")
	assert_eq(response.prompt_tokens, 120)
	assert_eq(response.completion_tokens, 18)
	assert_eq(response.finish_reason, "end_turn")


func test_an_anthropic_refusal_is_a_failure_not_a_line() -> void:
	var provider := AnthropicProvider.new()
	var response := provider.parse_http(200, JSON.stringify({
		"content": [{"type": "text", "text": "I"}],
		"stop_reason": "refusal", "model": "claude-opus-5",
		"usage": {"input_tokens": 120, "output_tokens": 1},
	}), "claude-opus-5")
	assert_false(response.ok)
	assert_eq(response.error_code, "refused")
	assert_false(response.is_retryable(), "asking again gets the same answer")


func test_openai_response_parsing() -> void:
	var provider := OpenAiProvider.new()
	var response := provider.parse_http(200, JSON.stringify({
		"choices": [{"message": {"content": "Mm."}, "finish_reason": "stop"}],
		"usage": {"prompt_tokens": 90, "completion_tokens": 3},
		"model": "gpt-4.1",
	}), "gpt-4.1")
	assert_true(response.ok)
	assert_eq(response.text, "Mm.")
	assert_eq(response.total_tokens(), 93)


func test_google_response_parsing() -> void:
	var provider := GoogleProvider.new()
	var response := provider.parse_http(200, JSON.stringify({
		"candidates": [{"content": {"parts": [{"text": "Aye."}]}, "finishReason": "STOP"}],
		"usageMetadata": {"promptTokenCount": 40, "candidatesTokenCount": 2},
	}), "gemini-2.5-flash")
	assert_true(response.ok)
	assert_eq(response.text, "Aye.")
	assert_eq(response.prompt_tokens, 40)


func test_google_safety_block_is_reported_not_crashed() -> void:
	var provider := GoogleProvider.new()
	var response := provider.parse_http(200, JSON.stringify({
		"candidates": [], "promptFeedback": {"blockReason": "SAFETY"},
	}), "gemini-2.5-flash")
	assert_false(response.ok)
	assert_eq(response.error_code, "bad_response")
	assert_eq(response.error_message, "SAFETY")


func test_openrouter_reports_upstream_errors_sent_with_http_200() -> void:
	var provider := OpenRouterProvider.new()
	var response := provider.parse_http(200, JSON.stringify({
		"error": {"message": "upstream model is down"},
	}), "anthropic/claude-haiku-4.5")
	assert_false(response.ok)
	assert_eq(response.error_code, "server")


func test_http_status_classification_is_shared() -> void:
	var provider := OpenAiProvider.new()
	assert_eq(provider.parse_http(401, "{}", "m").error_code, "auth")
	assert_eq(provider.parse_http(429, "{}", "m").error_code, "rate_limited")
	assert_eq(provider.parse_http(503, "{}", "m").error_code, "server")
	assert_eq(provider.parse_http(400, "{}", "m").error_code, "bad_request")


func test_malformed_bodies_fail_cleanly() -> void:
	for provider in [OpenAiProvider.new(), AnthropicProvider.new(), GoogleProvider.new(), OpenRouterProvider.new()]:
		var response: LlmResponse = provider.parse_http(200, "this is not json", "m")
		assert_false(response.ok)
		assert_eq(response.error_code, "bad_response")


func test_error_messages_never_echo_the_request() -> void:
	var provider := OpenAiProvider.new()
	var response := provider.parse_http(401, JSON.stringify({
		"error": {"message": "Incorrect API key provided"},
	}), "gpt-4.1")
	assert_false(response.error_message.contains("sk-"))


func test_retryable_errors_are_identified() -> void:
	assert_true(LlmResponse.failure("timeout").is_retryable())
	assert_true(LlmResponse.failure("rate_limited").is_retryable())
	assert_true(LlmResponse.failure("server").is_retryable())
	assert_false(LlmResponse.failure("auth").is_retryable())
	assert_false(LlmResponse.failure("disabled").is_retryable())


# --- offline behaviour ------------------------------------------------------

func test_the_null_provider_answers_instead_of_crashing() -> void:
	var provider := NullProvider.new()
	assert_eq(provider.build_http(LlmRequest.simple(LlmRequest.Purpose.DIALOGUE, "s", "hi"), "m", "k").size(), 0)
	var response := provider.parse_http(0, "", "m")
	assert_false(response.ok)
	assert_eq(response.error_code, "disabled")


func test_every_configured_provider_can_be_constructed() -> void:
	for provider_id in LlmClient.available_provider_ids():
		var provider := LlmClient.make_provider(provider_id)
		assert_not_null(provider)
		assert_eq(provider.id(), provider_id)


func test_unknown_provider_ids_degrade_to_offline() -> void:
	assert_eq(LlmClient.make_provider("not_a_provider").id(), "none")


# --- structured output ------------------------------------------------------

func test_json_is_recovered_from_a_fenced_reply() -> void:
	var response := LlmResponse.success(
		"Sure:\n```json\n{\"intent\": \"persuade\", \"target\": \"npc_ida\"}\n```", "m", "p")
	var parsed: Variant = response.as_json()
	assert_not_null(parsed)
	assert_eq(parsed["intent"], "persuade")


func test_json_array_is_recovered() -> void:
	var response := LlmResponse.success("Here you go: [1, 2, 3]", "m", "p")
	assert_eq((response.as_json() as Array).size(), 3)


func test_unparseable_replies_return_null_rather_than_throwing() -> void:
	assert_null(LlmResponse.success("no structure here at all", "m", "p").as_json())


func test_token_estimate_scales_with_prompt_size() -> void:
	var small := LlmRequest.simple(LlmRequest.Purpose.DIALOGUE, "s", "hi")
	var large := LlmRequest.simple(LlmRequest.Purpose.DIALOGUE, "s".repeat(4000), "hi")
	assert_gt(float(large.estimate_prompt_tokens()), float(small.estimate_prompt_tokens()))


func test_redaction_keeps_only_the_tail() -> void:
	assert_eq(Log.redact("sk-proj-abcdefgh1234"), "****1234")
	assert_eq(Log.redact("abc"), "****")
	assert_eq(Log.redact(""), "<empty>")
