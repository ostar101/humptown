class_name TheftRules
extends RefCounted
## Taking something without paying (D-051). Pure: who might notice, whether
## they do, and what a witness makes of it. The caller gathers who is there
## and rolls the dice from the game's seeded stream (so a reloaded save is
## seen, or not, the same way); nothing changes on a refusal.
##
## Everyone present might notice. Someone on duty behind the counter is
## watching; a bystander less so. Their character moves it — Ida is
## observant, Pirjo cannot see far — and the player's stealth and condition
## move it back. Someone on duty who notices stops it: the item is not taken.
## Anyone else who notices lets it happen and remembers.
##
## Facts (`judge`): serving, sells, stock, weight, free_weight, and
## `watchers` — [{"id", "is_staff", "chance", "roll"}], `roll` being 0..1 and
## noticing when it falls under `chance`. Refusals: nobody_serving,
## not_sold_here, out_of_stock, too_heavy. Ok: {"noticed_by": [ids],
## "caught": bool, "taken": bool}.

const STAFF_ATTENTION := 0.7
const BYSTANDER_ATTENTION := 0.3
const TRAIT_ATTENTION := {
	"observant": 0.15, "hears_everything": 0.08, "by_the_book": 0.05, "notices_injuries": 0.03,
	"poor_eyesight": -0.25, "drinks_too_much": -0.10, "tired": -0.08, "restless": -0.05,
}
## How much each level of the player's stealth takes off.
const STEALTH_WEIGHT := 0.007
const MIN_NOTICE := 0.04
const MAX_NOTICE := 0.95

## What being seen costs, in how the witness feels about the player.
const AFFECTION_HIT := -0.15
const TRUST_HIT := -0.20

## Skill experience for trying, by how it went.
const XP_CLEAN := 14.0
const XP_SEEN := 8.0
const XP_CAUGHT := 4.0
const SKILL_DIFFICULTY := 10

## Someone reports when their urge to reaches this.
const REPORT_THRESHOLD := 0.4
const REPORT_TRAIT_URGE := {"by_the_book": 0.25, "discreet": -0.10, "generous_when_useful": -0.10}
const REPORT_MIN_DELAY := 20
const REPORT_DELAY_SPREAD := 70


## The chance one person notices, in [MIN_NOTICE, MAX_NOTICE].
static func notice_chance(is_staff: bool, traits: Array, stealth_level: int, condition: float = 1.0) -> float:
	var attention := STAFF_ATTENTION if is_staff else BYSTANDER_ATTENTION
	for t in traits:
		attention += float(TRAIT_ATTENTION.get(str(t), 0.0))
	attention -= float(stealth_level) * STEALTH_WEIGHT
	attention /= clampf(condition, 0.5, 1.0)
	return clampf(attention, MIN_NOTICE, MAX_NOTICE)


static func judge(facts: Dictionary) -> Result:
	if not bool(facts.get("serving", false)):
		return Result.failure("nobody_serving")
	if not bool(facts.get("sells", false)):
		return Result.failure("not_sold_here")
	if int(facts.get("stock", 0)) < 1:
		return Result.failure("out_of_stock")
	if float(facts.get("weight", 0.0)) > float(facts.get("free_weight", 0.0)) + 0.0001:
		return Result.failure("too_heavy")
	var noticed: Array[String] = []
	var caught := false
	for watcher: Dictionary in facts.get("watchers", []):
		if float(watcher["roll"]) < float(watcher["chance"]):
			noticed.append(str(watcher["id"]))
			caught = caught or bool(watcher["is_staff"])
	return Result.success({"noticed_by": noticed, "caught": caught, "taken": not caught})


## How much it matters, from what it was worth: a bun is petty, a tool is not.
static func severity(value: int) -> float:
	return clampf(0.25 + float(value) / 250.0, 0.25, 0.85)


static func xp(caught: bool, noticed: bool) -> float:
	if caught:
		return XP_CAUGHT
	return XP_SEEN if noticed else XP_CLEAN


## How strongly a witness wants to tell the police: what it was, whether they
## stopped it themselves, how fond they are of the player, and who they are.
static func report_urge(severity_of_it: float, caught: bool, affection: float, traits: Array) -> float:
	var urge := severity_of_it + (0.2 if caught else 0.0) - clampf(affection, 0.0, 1.0) * 0.45
	for t in traits:
		urge += float(REPORT_TRAIT_URGE.get(str(t), 0.0))
	return urge


static func will_report(urge: float) -> bool:
	return urge >= REPORT_THRESHOLD


## Minutes before they get round to it, spread by a hash so it is not always
## the same.
static func report_delay(reporter_id: String, fact_id: String) -> int:
	return REPORT_MIN_DELAY + posmod(("%s/%s" % [reporter_id, fact_id]).hash(), REPORT_DELAY_SPREAD)
