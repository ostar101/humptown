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

## The longest text the player may send, as the longest line they may say.
const MAX_TEXT_LENGTH := 280
## Texts to one person that have not been read yet, at most.
const MAX_WAITING := 3
## Minutes before someone gets to a text, by what they are doing.
const READ_DELAY := {"work": 45}
const READ_DELAY_DEFAULT := 5
## When they cannot read it yet, they look again after this many minutes.
const READ_RETRY := 30

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


## Whether the player may send this text. `state` = {"has_phone", "is_contact",
## "waiting"} — how many of theirs this person has not read. Codes: `no_phone`,
## `not_a_contact`, `empty`, `too_long`, `too_many_waiting`.
static func judge_send(line: String, state: Dictionary) -> Result:
	if not bool(state.get("has_phone", false)):
		return Result.failure("no_phone")
	if not bool(state.get("is_contact", false)):
		return Result.failure("not_a_contact")
	var text := line.strip_edges()
	if text.is_empty():
		return Result.failure("empty")
	if text.length() > MAX_TEXT_LENGTH:
		return Result.failure("too_long")
	if int(state.get("waiting", 0)) >= MAX_WAITING:
		return Result.failure("too_many_waiting")
	return Result.success(text)


## Minutes until someone gets to a text, from what they are doing.
static func reading_delay(activity: String) -> int:
	return int(READ_DELAY.get(activity, READ_DELAY_DEFAULT))


## Whether a person can read a text now: awake, and not in the small hours.
## `state` = {"npc_awake", "hour"}. Codes: `asleep`, `quiet_hours`.
static func judge_reading(state: Dictionary) -> Result:
	if not bool(state.get("npc_awake", false)):
		return Result.failure("asleep")
	var hour := int(state.get("hour", 12))
	if hour < FIRST_HOUR or hour >= LAST_HOUR:
		return Result.failure("quiet_hours")
	return Result.success()
