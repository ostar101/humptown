class_name ClinicRules
extends RefCounted
## What the clinic does for an injury (D-055). Pure. A nurse cannot make a
## wound vanish, but she can dress it, set it and tell you what not to do: the
## rest of the healing takes a third of the time, and you are a little better
## for it today. It costs, per wound, up to a limit.

const FEE_PER_INJURY := 20
const MAX_FEE := 60
## What is left to heal is this fraction of what it was.
const REMAINING_FRACTION := 0.3
const HEALTH_GAINED := 0.15
const MINUTES_TAKEN := 30
## Someone this well with nothing wrong has no business here.
const WELL_ENOUGH := 0.9


static func fee(injury_count: int) -> int:
	return mini(injury_count * FEE_PER_INJURY, MAX_FEE)


## Facts: injuries (how many), health (0..1), money. Ok: {"fee"}. Refused:
## `nothing_to_treat`, `not_enough_money`.
static func judge_treatment(facts: Dictionary) -> Result:
	var count := int(facts.get("injuries", 0))
	if count == 0 and float(facts.get("health", 1.0)) >= WELL_ENOUGH:
		return Result.failure("nothing_to_treat")
	var owed := fee(count)
	if int(facts.get("money", 0)) < owed:
		return Result.failure("not_enough_money")
	return Result.success({"fee": owed})
