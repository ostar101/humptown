class_name AskRules
extends RefCounted
## Talking someone round (D-053). Pure: the chance of it, and what a roll of
## the dice means. An ask is graded, not won or lost — the point of settling
## something by talking is that it can go half well, cost something, or make
## things worse:
##
## - success: they give you what you asked
## - partial: they give you some of it, and it costs you
## - failure: nothing changes, and they are a little put out
## - backfire: you pushed too hard, and it is worse than before
##
## The chance is the player's skill against how hard they are to move, shifted
## by how they feel about the player and by the player's condition (a tired or
## drunk person argues worse, D-041); never certain, never hopeless. The roll
## comes from the game's seeded stream, so a reloaded save asks the same way.

const GRADES: Array[String] = ["success", "partial", "failure", "backfire"]
## How far disposition (-1..1) moves the chance.
const DISPOSITION_WEIGHT := 0.15
## Success takes the better half of the chance; partial the rest of it. Of the
## remainder, this share is plain failure and the rest backfires.
const SUCCESS_SHARE := 0.5
const FAILURE_SHARE := 0.7
const DEFAULT_COOLDOWN_DAYS := 3
const XP := {"success": 14.0, "partial": 10.0, "failure": 6.0, "backfire": 4.0}


static func chance(skill_level: int, difficulty: int, disposition: float, condition: float = 1.0) -> float:
	var gap := float(skill_level - difficulty)
	var base := 1.0 / (1.0 + exp(-gap * 0.22))
	var odds := (base + clampf(disposition, -1.0, 1.0) * DISPOSITION_WEIGHT) * clampf(condition, 0.5, 1.0)
	return clampf(odds, 0.05, 0.95)


## What a roll (0..1) comes to at this chance.
static func grade(odds: float, roll: float) -> String:
	if roll < odds * SUCCESS_SHARE:
		return "success"
	if roll < odds:
		return "partial"
	if roll < odds + (1.0 - odds) * FAILURE_SHARE:
		return "failure"
	return "backfire"


## Facts: has_ask (there is something to ask this person), on_cooldown,
## chance, roll. Ok: {"grade"}. Refused: `nothing_to_ask`, `already_asked`.
static func judge(facts: Dictionary) -> Result:
	if not bool(facts.get("has_ask", false)):
		return Result.failure("nothing_to_ask")
	if bool(facts.get("on_cooldown", false)):
		return Result.failure("already_asked")
	return Result.success({"grade": grade(float(facts.get("chance", 0.0)), float(facts.get("roll", 1.0)))})


static func xp(grade_reached: String) -> float:
	return float(XP.get(grade_reached, 0.0))
