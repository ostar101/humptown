class_name LlmBudget
extends RefCounted
## Spend control and failure containment for model calls.
##
## Three separate jobs, kept in one place because they all answer the same
## question — "should this call happen right now?":
##
##   budget        a daily request cap and token accounting, so a long session
##                 cannot quietly cost the player a fortune
##   rate limiting a minimum gap between calls, so a chatty scene does not
##                 trip provider throttling
##   circuit break after repeated failures, stop calling entirely for a while
##                 instead of hammering a dead endpoint every time the player
##                 talks to someone

enum CircuitState { CLOSED, OPEN, HALF_OPEN }

## Consecutive failures before the circuit opens.
const FAILURE_THRESHOLD := 4
## Seconds the circuit stays open before allowing one probe call.
const OPEN_SECONDS := 30.0
## Minimum real seconds between outgoing calls.
const MIN_INTERVAL := 0.35

var daily_request_cap: int = 600
var requests_today: int = 0
var day_index: int = 0

var session_prompt_tokens: int = 0
var session_completion_tokens: int = 0
var session_requests: int = 0
var cache_hits: int = 0

var circuit: CircuitState = CircuitState.CLOSED
var consecutive_failures: int = 0

var _opened_at: float = 0.0
var _last_call_at: float = -999.0

## Approximate USD per million tokens, for the developer cost readout only.
## Wrong numbers here cost nothing but a misleading debug line; they are a
## rough guide, not billing.
const PRICE_PER_MTOK := {
	"default": {"in": 1.0, "out": 4.0},
	"mini": {"in": 0.15, "out": 0.6},
	"haiku": {"in": 0.8, "out": 4.0},
	"flash": {"in": 0.1, "out": 0.4},
	"sonnet": {"in": 3.0, "out": 15.0},
	"opus": {"in": 15.0, "out": 75.0},
	"gpt-4o": {"in": 2.5, "out": 10.0},
	"gpt-4.1": {"in": 2.0, "out": 8.0},
}


## Whether a call may proceed. Returns a Result whose failure code is one of
## budget_exceeded | circuit_open | rate_limited.
func allow(now_seconds: float) -> Result:
	_maybe_close_circuit(now_seconds)
	if circuit == CircuitState.OPEN:
		return Result.failure("circuit_open", "provider temporarily unavailable")
	if requests_today >= daily_request_cap:
		return Result.failure("budget_exceeded", "daily request cap reached")
	if now_seconds - _last_call_at < MIN_INTERVAL:
		return Result.failure("rate_limited", "calls are too close together")
	return Result.success()


## Records that a call is going out.
func on_request_sent(now_seconds: float) -> void:
	_last_call_at = now_seconds
	requests_today += 1
	session_requests += 1


func on_success(response: LlmResponse) -> void:
	consecutive_failures = 0
	circuit = CircuitState.CLOSED
	session_prompt_tokens += response.prompt_tokens
	session_completion_tokens += response.completion_tokens


func on_failure(now_seconds: float, response: LlmResponse) -> void:
	# A refusal we generated ourselves is not evidence the provider is down.
	if response.error_code in ["disabled", "budget_exceeded", "circuit_open"]:
		return
	consecutive_failures += 1
	if consecutive_failures >= FAILURE_THRESHOLD and circuit != CircuitState.OPEN:
		circuit = CircuitState.OPEN
		_opened_at = now_seconds
		Log.warn("llm", "Circuit opened after repeated failures", {
			"failures": consecutive_failures, "last_error": response.error_code,
		})
		Events.llm_unavailable.emit(response.error_code)


func on_cache_hit() -> void:
	cache_hits += 1


## Resets the daily counter when the world date rolls over.
func on_new_day(new_day_index: int) -> void:
	if new_day_index == day_index:
		return
	day_index = new_day_index
	requests_today = 0


func force_close_circuit() -> void:
	circuit = CircuitState.CLOSED
	consecutive_failures = 0


func estimated_session_cost_usd(model: String) -> float:
	var price: Dictionary = PRICE_PER_MTOK["default"]
	var lowered := model.to_lower()
	for key in PRICE_PER_MTOK:
		if key != "default" and lowered.contains(key):
			price = PRICE_PER_MTOK[key]
			break
	return (float(session_prompt_tokens) / 1_000_000.0) * float(price["in"]) \
		+ (float(session_completion_tokens) / 1_000_000.0) * float(price["out"])


## Snapshot for the developer overlay.
func stats(model: String = "") -> Dictionary:
	return {
		"requests_session": session_requests,
		"requests_today": requests_today,
		"daily_cap": daily_request_cap,
		"prompt_tokens": session_prompt_tokens,
		"completion_tokens": session_completion_tokens,
		"cache_hits": cache_hits,
		"circuit": ["closed", "open", "half_open"][int(circuit)],
		"consecutive_failures": consecutive_failures,
		"est_cost_usd": estimated_session_cost_usd(model),
	}


func _maybe_close_circuit(now_seconds: float) -> void:
	if circuit == CircuitState.OPEN and now_seconds - _opened_at >= OPEN_SECONDS:
		circuit = CircuitState.HALF_OPEN
		Log.info("llm", "Circuit half-open; allowing a probe call")
