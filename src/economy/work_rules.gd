class_name WorkRules
extends RefCounted
## Whether the player may start a shift, be hired, and what a shift pays
## (D-042). Pure: the caller gathers the facts and applies the outcome.
##
## A job (data): occupation, workplace, employer ("" for casual work),
## casual, days ("all" | "weekday" | "weekend" | [weekday numbers, 0 =
## Sunday]), shift_start and shift_end (minutes of the day), wage (a full
## shift), pay_to ("cash" | "bank"), skills, difficulty, strain ({meter:
## delta} over a full shift), requires ({"flag", "or_skill": {skill: level},
## "familiarity"}).

## A shift can be started this long before it begins — you wait at work.
const EARLY_MINUTES := 60
## Starting more than this late counts as late.
const LATE_MINUTES := 15
## Past this much of the shift gone, it is not worth starting.
const LAST_START_FRACTION := 0.5
## Drunk or dead on your feet: sent home.
const TOO_DRUNK := 0.5
const TOO_EXHAUSTED := 0.05


static func works_on(days: Variant, weekday: int) -> bool:
	if typeof(days) == TYPE_ARRAY:
		for d in days:
			if int(d) == weekday:
				return true
		return false
	match str(days):
		"weekday":
			return weekday >= 1 and weekday <= 5
		"weekend":
			return weekday == 0 or weekday == 6
	return true


## Facts: job (Dictionary), employed_here (the player holds this job, or it
## is casual), at_workplace, weekday, minute (of the day), day, last_worked_day,
## intoxication, sleep. Ok: {"minutes", "fraction", "late"}. Refused:
## no_job, not_at_work, not_a_work_day, too_early, too_late, already_worked,
## too_drunk, too_exhausted.
static func judge_shift(facts: Dictionary) -> Result:
	var job: Dictionary = facts.get("job", {})
	if job.is_empty() or not bool(facts.get("employed_here", false)):
		return Result.failure("no_job")
	if not bool(facts.get("at_workplace", false)):
		return Result.failure("not_at_work")
	if not works_on(job.get("days", "all"), int(facts.get("weekday", 0))):
		return Result.failure("not_a_work_day")
	if int(facts.get("last_worked_day", -1)) == int(facts.get("day", 0)):
		return Result.failure("already_worked")
	var start := int(job.get("shift_start", 0))
	var end := int(job.get("shift_end", 0))
	var now := int(facts.get("minute", 0))
	if now < start - EARLY_MINUTES:
		return Result.failure("too_early")
	var length := maxi(end - start, 1)
	var from := maxi(now, start)
	if float(end - from) / float(length) < 1.0 - LAST_START_FRACTION:
		return Result.failure("too_late")
	if float(facts.get("intoxication", 0.0)) >= TOO_DRUNK:
		return Result.failure("too_drunk")
	if float(facts.get("sleep", 1.0)) <= TOO_EXHAUSTED:
		return Result.failure("too_exhausted")
	return Result.success({
		"minutes": end - now,
		"fraction": float(end - from) / float(length),
		"late": now > start + LATE_MINUTES,
	})


## What a shift pays: the wage for the part of it worked, scaled a little by
## how well the player could work (condition, 0.2..1.15), never below half.
static func pay(wage: int, fraction: float, effectiveness: float) -> int:
	return int(round(wage * clampf(fraction, 0.0, 1.0) * clampf(effectiveness, 0.5, 1.1)))


## Whether the player could be hired for this job: its requirements, from
## the facts flags ([String]), skills ({id: level}) and familiarity (how
## well the employer knows them). Ok, or refused `not_qualified` or
## `do_not_know_you`.
static func judge_hire(job: Dictionary, flags: Array, skills: Dictionary, familiarity: float) -> Result:
	var needs: Dictionary = job.get("requires", {})
	if float(needs.get("familiarity", 0.0)) > familiarity:
		return Result.failure("do_not_know_you")
	var flag := str(needs.get("flag", ""))
	var skill_needs: Dictionary = needs.get("or_skill", {})
	if flag == "" and skill_needs.is_empty():
		return Result.success()
	if flag != "" and flags.has(flag):
		return Result.success()
	for skill_id in skill_needs:
		if int(skills.get(skill_id, 0)) >= int(skill_needs[skill_id]):
			return Result.success()
	return Result.failure("not_qualified")
