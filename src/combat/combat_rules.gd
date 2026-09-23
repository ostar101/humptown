class_name CombatRules
extends RefCounted
## The arithmetic of a fight (D-054). Pure: given two people's numbers and a
## roll, what happens. Kept small and readable on purpose — this is a JRPG
## exchange of blows, not a tactical simulation: who hits whom is a chance from
## skill and agility, how hard from strength, and what a hit leaves behind is
## a wound that lasts. Everything is on the same 0..1 health bar the rest of
## the game uses (`Stats.health`), so a fight and a bad week are the same kind
## of thing.
##
## A combatant is a Dictionary: id, name, side ("player" | "foe"), health and
## stamina (0..1), strength, agility, resolve, skill (brawling),
## intimidation, weapon (a damage bonus), armour (a damage reduction, 0.0 by
## default so no existing combatant dict has to change), effectiveness
## (condition, 0.2..1.15), defending (bool),
## state ("up" | "down" | "fled" | "yielded"), traits.

const ACTIONS: Array[String] = ["attack", "heavy", "defend", "intimidate", "item", "flee", "yield"]

const BASE_HIT := 0.60
const SKILL_HIT := 0.004
const AGILITY_HIT := 0.03
const DEFENDING_HIT := -0.25
const HEAVY_HIT := -0.20
const TIRED_STAMINA := 0.2
const TIRED_HIT_FACTOR := 0.8

const BASE_DAMAGE := 0.22
const STRENGTH_DAMAGE := 0.015
const HEAVY_FACTOR := 1.5
const DEFENDING_FACTOR := 0.6
const CRIT_ROLL := 0.94
const CRIT_FACTOR := 1.5
const SPREAD_LOW := 0.6
## Armour softens a blow but never stops it outright.
const ARMOUR_CAP := 0.6

const STAMINA_ATTACK := 0.05
const STAMINA_HEAVY := 0.2
const STAMINA_INTIMIDATE := 0.1
const STAMINA_DEFEND := -0.10

const BANDAGE_WEIGHT := 1.0
## What a fight's wounds are, by how hard the blow.
const CRACKED_RIB_AT := 0.26
const BRUISE_AT := 0.18
## Health an NPC gets back per hour once it is over.
const RECOVERY_PER_HOUR := 0.03


## The chance an attack lands.
static func hit_chance(attacker: Dictionary, defender: Dictionary, heavy: bool = false) -> float:
	var chance := BASE_HIT + float(int(attacker["skill"]) - int(defender["skill"])) * SKILL_HIT \
		+ float(int(attacker["agility"]) - int(defender["agility"])) * AGILITY_HIT
	if bool(defender.get("defending", false)):
		chance += DEFENDING_HIT
	if heavy:
		chance += HEAVY_HIT
	if float(attacker["stamina"]) < TIRED_STAMINA:
		chance *= TIRED_HIT_FACTOR
	chance *= clampf(float(attacker.get("effectiveness", 1.0)), 0.5, 1.0)
	return clampf(chance, 0.10, 0.95)


## How much a landed blow takes off, from strength, any weapon, a roll for the
## spread (0..1), a bracing defender, and worn armour (M8 step 4, D-080). A
## roll past CRIT_ROLL is a crit.
static func damage(attacker: Dictionary, defender: Dictionary, heavy: bool, roll: float) -> float:
	var base := BASE_DAMAGE + float(int(attacker["strength"]) - 5) * STRENGTH_DAMAGE + float(attacker.get("weapon", 0.0))
	var dealt := base * lerpf(SPREAD_LOW, 1.0, clampf(roll, 0.0, 1.0))
	if heavy:
		dealt *= HEAVY_FACTOR
	if roll > CRIT_ROLL:
		dealt *= CRIT_FACTOR
	if bool(defender.get("defending", false)):
		dealt *= DEFENDING_FACTOR
	dealt *= 1.0 - clampf(float(defender.get("armour", 0.0)), 0.0, ARMOUR_CAP)
	return maxf(dealt, 0.01)


static func is_crit(roll: float) -> bool:
	return roll > CRIT_ROLL


static func stamina_cost(action: String) -> float:
	match action:
		"attack":
			return STAMINA_ATTACK
		"heavy":
			return STAMINA_HEAVY
		"intimidate":
			return STAMINA_INTIMIDATE
		"defend":
			return STAMINA_DEFEND
	return 0.0


## Of the times someone losing gives up, the share that try to run rather than
## back down.
const FLEE_SHARE := 0.35


## The chance of getting away: quick against the quickest of those after you.
static func flee_chance(fleer: Dictionary, quickest_pursuer_agility: int) -> float:
	var chance := 0.5 + float(int(fleer["agility"]) - quickest_pursuer_agility) * 0.06
	chance *= clampf(float(fleer.get("effectiveness", 1.0)), 0.5, 1.0)
	return clampf(chance, 0.10, 0.90)


## The chance a hard look makes them back down: the player's intimidation
## against how much fight is left in them — resolve, and how hurt they are.
static func intimidate_chance(intimidation: int, target: Dictionary) -> float:
	var will := float(int(target["resolve"])) * 4.0 - (1.0 - float(target["health"])) * 30.0
	var gap := float(intimidation) - will
	return clampf(1.0 / (1.0 + exp(-gap * 0.15)), 0.05, 0.90)


## The wound a blow leaves on the player, or {} for a knock too light to
## last: {"id", "part", "severity", "days"}.
static func injury_from(dealt: float, roll: float) -> Dictionary:
	if dealt >= CRACKED_RIB_AT:
		return {"id": "cracked_rib", "part": "torso", "severity": 0.3, "days": 5}
	if dealt >= BRUISE_AT:
		return {"id": "bruise", "part": "arm" if roll < 0.5 else "torso", "severity": 0.12, "days": 2}
	return {}


## What an NPC does on its turn, from how it feels and who it is. `roll` is
## 0..1. Returns "attack" | "heavy" | "defend" | "flee" | "yield".
static func npc_action(self_c: Dictionary, roll: float) -> String:
	var health := float(self_c["health"])
	var resolve := int(self_c["resolve"])
	if health < 0.3:
		# Someone who is losing gives in more often than they bolt, and bolting
		# is tried, not granted: `Combat` rolls it against the player's legs
		# the way the player's own attempt is rolled (D-090). It used to be two
		# rounds in three, and always got away, just as the player was winning.
		var give_up := clampf(0.55 - float(resolve - 5) * 0.06, 0.15, 0.75)
		if roll < give_up * FLEE_SHARE:
			return "flee"
		if roll < give_up:
			return "yield"
	if float(self_c["stamina"]) < TIRED_STAMINA:
		return "defend"
	if roll > 0.82:
		return "defend"
	if int(self_c["strength"]) >= 7 and roll > 0.66 and float(self_c["stamina"]) >= STAMINA_HEAVY:
		return "heavy"
	return "attack"


## Health an NPC has recovered by now, from how long ago the fight was.
static func recovered(health: float, minutes: int) -> float:
	return minf(1.0, health + float(maxi(minutes, 0)) / 60.0 * RECOVERY_PER_HOUR)
