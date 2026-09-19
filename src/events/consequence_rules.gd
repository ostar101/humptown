class_name ConsequenceRules
extends RefCounted
## When what the player did comes back for them (D-055). Pure: what someone
## knows in, what the world does about it out. No dice — a consequence should
## be a matter of who knows what and how they feel, so it can be read, tested
## and, in play, seen coming.

## Below this weight of what an employer believes, a person keeps their job.
const DISMISSAL_WEIGHT := 0.30
## An account she is not sure of is not grounds either (the police's bar).
const DISMISSAL_EVIDENCE_MIN := PoliceRules.EVIDENCE_MIN

## A grudge goes warning, then a named time and place, then again — and then
## lets go for a while. Days between one step and the next; how many times
## they will ask you to meet; how long they leave it.
const GAP_DAYS := 2
const MAX_CONFRONTATIONS := 2
const REST_DAYS := 12
## Someone this hurt is not going to start anything yet.
const FIT_TO_CONFRONT := 0.5


## Whether an employer who believes these things about the player lets them
## go. Each entry: {"severity", "strength"}.
static func dismissal_due(offences: Array) -> bool:
	for entry: Dictionary in offences:
		if float(entry["strength"]) >= DISMISSAL_EVIDENCE_MIN \
				and float(entry["severity"]) * float(entry["strength"]) >= DISMISSAL_WEIGHT:
			return true
	return false


## What a holder of a grudge does today, from where things stand: "warn",
## "confront", "rest" (they have said their piece; let it lie) or "" (not
## today). `state` = {"warnings", "confrontations", "last_day", "quiet_until"};
## `warnings_before` is how many warnings come before anyone is sent — one for
## a grudge, more for a creditor, who is more patient and more thorough.
static func next_step(state: Dictionary, today: int, warnings_before: int = 1) -> String:
	if today < int(state.get("quiet_until", 0)):
		return ""
	if int(state.get("warnings", 0)) == 0:
		return "warn"
	if today - int(state.get("last_day", 0)) < GAP_DAYS:
		return ""
	if int(state.get("warnings", 0)) < warnings_before:
		return "warn"
	if int(state.get("confrontations", 0)) < MAX_CONFRONTATIONS:
		return "confront"
	return "rest"


## Whether a holder is in a state to make good on it.
static func fit_to_confront(health: float) -> bool:
	return health >= FIT_TO_CONFRONT
