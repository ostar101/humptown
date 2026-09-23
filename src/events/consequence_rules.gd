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

## A grudge goes one warning, then a named time and place, then again — and
## then it is over (D-090): had out at a meeting or in any fight between them,
## or let go after asking twice. It used to rest twelve days and start again,
## for ever, from the same old blow. Days between one step and the next; how
## many times they will ask you to meet.
const GAP_DAYS := 2
const MAX_CONFRONTATIONS := 2
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


## A debt let fail (D-090) goes: a summons to come and talk, a threat of harm,
## a last warning naming who will come — and then that person comes looking.
## `step` counts what has been done: 0 nothing, 1 summoned, 2 threatened,
## 3 warned for the last time, 4 (and on) hunting.
const HUNT_STEP := 4
## Days between one step of a collection and the next — the phone's own gap
## for a demand (`PhoneRules.MIN_GAP`), so no demand is held back and lost.
const COLLECTION_GAP_DAYS := 3
## Days a collector leaves it after a beating either way: after taking what
## you had, or after being seen off.
const AFTER_TAKING_DAYS := 4
const AFTER_BEATEN_DAYS := 6
## The hours a collector goes looking: not in the small hours, when the player
## is at home anyway and the streets are empty.
const HUNT_FROM_HOUR := 9
const HUNT_UNTIL_HOUR := 22


## What a collector does today: "summon", "threaten", "final", "hunt" or "".
## `state` = {"step", "last_day", "quiet_until"}.
static func collection_step(state: Dictionary, today: int) -> String:
	if today < int(state.get("quiet_until", 0)):
		return ""
	var step := int(state.get("step", 0))
	if step == 0:
		return "summon"
	if step >= HUNT_STEP or today - int(state.get("last_day", 0)) < COLLECTION_GAP_DAYS:
		return ""
	return ["", "threaten", "final", "hunt"][step]


## Whether a collector who is hunting may find the player now: in the hours
## they look, when the player is out where they can be found — not at home,
## not at the police post or the clinic — and not already busy with something.
static func can_be_found(state: Dictionary) -> bool:
	var hour := int(state.get("hour", 0))
	return hour >= HUNT_FROM_HOUR and hour < HUNT_UNTIL_HOUR and bool(state.get("exposed", false)) \
		and not bool(state.get("busy", false))


## Whether a grudge has been made up: the holder has come to like the player
## as much as a friend who would step into a fight for them
## (`FightDirector.JOIN_AFFECTION`). Friends do not name a time and a place.
static func made_up(affection: float) -> bool:
	return affection >= FightDirector.JOIN_AFFECTION


## Whether a holder is in a state to make good on it.
static func fit_to_confront(health: float) -> bool:
	return health >= FIT_TO_CONFRONT
