class_name HaggleRules
extends RefCounted
## Haggling against the skill (D-040). Pure: how hard a shopkeeper is to
## talk down, the chance of doing it, and what a roll of the dice means.
##
## Difficulty is a level on the same 1–99 scale as the player's `haggling`
## skill: anyone behind a counter holds out a little, someone whose trade is
## haggling holds out more, and their character moves it — Ida keeps
## accounts, Leena is cheerful. How they feel about the player moves the
## chance, not the difficulty: a friend gives way more easily. The roll comes
## from the game's seeded random streams, so a reloaded save haggles the
## same way.

const BASE_DIFFICULTY := 8
## Added when haggling is one of their occupation's skills.
const TRADE_DIFFICULTY := 14
const TRAIT_DIFFICULTY := {
	"keeps_accounts": 8, "calculating": 10, "observant": 4, "by_the_book": 6, "blunt": 2,
	"cheerful": -5, "talks_to_everyone": -4, "generous_when_useful": -3, "patient": -2, "eager": -3,
}
## How far disposition (-1..1) moves the chance.
const DISPOSITION_WEIGHT := 0.15
const MIN_DISCOUNT := 0.05
const MAX_DISCOUNT := 0.20
## What a failed haggle costs in their feeling toward the player.
const SOURED_AFFECTION := -0.02
## Skill experience for trying, at the difficulty tried.
const XP_WON := 12.0
const XP_LOST := 5.0


static func difficulty(occupation_skills: Array, traits: Array) -> int:
	var level := BASE_DIFFICULTY
	if occupation_skills.has("haggling"):
		level += TRADE_DIFFICULTY
	for t in traits:
		level += int(TRAIT_DIFFICULTY.get(str(t), 0))
	return clampi(level, 1, Skills.MAX_LEVEL)


## The chance of talking them down, from the player's level against theirs,
## how they feel about the player, and the player's condition (hungry,
## tired or drunk people haggle worse, D-041). Same curve as
## `Skills.success_chance`: never certain, never hopeless.
static func chance(skill_level: int, against: int, disposition: float, condition: float = 1.0) -> float:
	var gap := float(skill_level - against)
	var base := 1.0 / (1.0 + exp(-gap * 0.22))
	var odds := (base + clampf(disposition, -1.0, 1.0) * DISPOSITION_WEIGHT) * clampf(condition, 0.5, 1.0)
	return clampf(odds, 0.05, 0.95)


## Facts: serving, sells, tried (already haggled over this item today),
## chance, roll (0..1). Ok: {"won": bool, "discount": float}. Refused:
## nobody_serving, not_sold_here, already_haggled.
static func judge(facts: Dictionary) -> Result:
	if not bool(facts.get("serving", false)):
		return Result.failure("nobody_serving")
	if not bool(facts.get("sells", false)):
		return Result.failure("not_sold_here")
	if bool(facts.get("tried", false)):
		return Result.failure("already_haggled")
	var odds := float(facts.get("chance", 0.0))
	var roll := float(facts.get("roll", 1.0))
	if roll >= odds:
		return Result.success({"won": false, "discount": 0.0})
	# The further under the odds the roll, the better the deal.
	var margin := clampf((odds - roll) / maxf(odds, 0.001), 0.0, 1.0)
	return Result.success({"won": true, "discount": snappedf(lerpf(MIN_DISCOUNT, MAX_DISCOUNT, margin), 0.01)})
