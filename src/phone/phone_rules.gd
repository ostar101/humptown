class_name PhoneRules
extends RefCounted
## Who may write to the player, and when (D-045). Pure: a cause and the state
## of things in, a Result out. Nobody texts at random — a message needs a
## reason the simulation produced (an errand they need done, a shift you
## missed, a deadline coming up, a friend thinking of you), and then it still
## has to get past these rules, so the phone never becomes spam.
##
## Reason codes on refusal: `unknown_kind`, `no_phone`, `not_a_contact`,
## `asleep`, `quiet_hours`, `too_soon`, `daily_cap`.

## Familiarity at which someone has your number and you have theirs: you have
## been introduced, or talked twice.
const CONTACT_FAMILIARITY := 0.1

## At most this many people start a conversation with the player per day.
const DAILY_CAP := 3
## People do not text before this hour or from this one.
const FIRST_HOUR := 7
const LAST_HOUR := 22

## The least time, in minutes, before the same person may start another
## message. Every kind a cause may have is listed here.
const MIN_GAP := {
	"errand_offer": 2 * 24 * 60,
	"quest_nudge": 24 * 60,
	"missed_shift": 24 * 60,
	"check_in": 5 * 24 * 60,
}

## Days before a deadline at which its giver starts nudging.
const NUDGE_DAYS := 3
## How warmly someone must feel about the player to check in on them.
const CHECK_IN_AFFECTION := 0.2
const CHECK_IN_FAMILIARITY := 0.25


## `cause` = {"npc", "kind"}. `state` = {"has_phone", "is_contact", "npc_awake",
## "hour", "minutes_since" (-1 never), "started_today"}.
static func judge_outreach(cause: Dictionary, state: Dictionary) -> Result:
	var kind := str(cause.get("kind", ""))
	if not MIN_GAP.has(kind):
		return Result.failure("unknown_kind")
	if not bool(state.get("has_phone", false)):
		return Result.failure("no_phone")
	if not bool(state.get("is_contact", false)):
		return Result.failure("not_a_contact")
	if not bool(state.get("npc_awake", false)):
		return Result.failure("asleep")
	var hour := int(state.get("hour", 12))
	if hour < FIRST_HOUR or hour >= LAST_HOUR:
		return Result.failure("quiet_hours")
	var since := int(state.get("minutes_since", -1))
	if since >= 0 and since < int(MIN_GAP[kind]):
		return Result.failure("too_soon")
	if int(state.get("started_today", 0)) >= DAILY_CAP:
		return Result.failure("daily_cap")
	return Result.success(kind)


## Whether the player may answer a message's question, and how. `answer` is
## "accept" or "decline"; `state` = {"has_phone", "open", "still_possible"}.
## Codes: `no_phone`, `no_such_answer`, `already_answered`, `no_longer_possible`.
static func judge_answer(message: Dictionary, answer: String, state: Dictionary) -> Result:
	if not bool(state.get("has_phone", false)):
		return Result.failure("no_phone")
	if message.is_empty() or (message.get("action", {}) as Dictionary).is_empty():
		return Result.failure("no_such_answer")
	if not bool(state.get("open", false)):
		return Result.failure("already_answered")
	if answer != "accept" and answer != "decline":
		return Result.failure("no_such_answer")
	if answer == "accept" and not bool(state.get("still_possible", false)):
		return Result.failure("no_longer_possible")
	return Result.success(answer)
