class_name Stats
extends RefCounted
## Base attributes and the physical/mental condition meters.
##
## Attributes grow slowly from general character XP; condition moves hour to
## hour. Kept deliberately small — six attributes and seven meters — because
## the brief's warning about stat complexity is the right one: every extra
## number is one more thing the player must model in their head.

const ATTRIBUTES := ["strength", "agility", "endurance", "wits", "charisma", "resolve"]

## General character level, raised by broad XP rather than by any one skill.
var character_level: int = 1
var character_xp: float = 0.0

var attributes: Dictionary = {
	"strength": 5, "agility": 5, "endurance": 5,
	"wits": 5, "charisma": 5, "resolve": 5,
}
## Unspent points awarded on character level-up.
var attribute_points: int = 0

# --- condition meters -------------------------------------------------------
var health: float = 1.0
var stamina: float = 1.0
var hunger: float = 0.0
var sleep: float = 1.0
var stress: float = 0.0
var mood: float = 0.5
var intoxication: float = 0.0

## Persistent injuries: [{id, part, severity, heals_at_minute}]
var injuries: Array[Dictionary] = []

const XP_PER_CHARACTER_LEVEL := 1500.0
## Going without (D-041): past these, the body starts sending the bill.
const STARVING := 0.95
const EXHAUSTED := 0.05
## Hours for starving to empty health from full, and for exhaustion to.
const STARVING_HOURS := 36.0
const EXHAUSTED_HOURS := 72.0
## A body that is fed and rested mends by itself (D-090): a good night's sleep
## gives back about a third of full health, a waking day about a quarter. Only
## up to what open wounds allow (`health_cap()`): a cracked rib is not slept off
## before it has healed.
const MEND_ASLEEP_HOURS := 24.0
const MEND_AWAKE_HOURS := 60.0
## Nobody mends while this hungry or this tired.
const MEND_HUNGER_BELOW := 0.8
const MEND_SLEEP_ABOVE := 0.2
## Hours asleep for hunger to go from nothing to full: slower than awake, so a
## night's sleep makes you want breakfast, not starve (it was 14 h — a night
## after a light supper woke you starving, and starving costs health).
const HUNGER_ASLEEP_HOURS := 24.0


func attribute(name: String) -> int:
	return int(attributes.get(name, 5))


func modifier(name: String) -> float:
	# Attribute 5 is average and gives no bonus; each point is worth ~4%.
	return float(attribute(name) - 5) * 0.04


func award_character_xp(amount: float) -> void:
	if amount <= 0.0:
		return
	character_xp += amount
	var target := 1 + int(character_xp / XP_PER_CHARACTER_LEVEL)
	while character_level < target:
		character_level += 1
		attribute_points += 1
		Log.info("stats", "Character level up", {"level": character_level})


func spend_attribute_point(name: String) -> Result:
	if attribute_points <= 0:
		return Result.failure("no_points")
	if not (name in ATTRIBUTES):
		return Result.failure("unknown_attribute", name)
	attributes[name] = attribute(name) + 1
	attribute_points -= 1
	return Result.success(attributes[name])


# --- condition --------------------------------------------------------------

## Advances condition by `minutes`. Batched-friendly: called once after a
## time skip rather than per minute.
func drift(minutes: int, activity: String = "idle") -> void:
	var m := float(minutes)
	match activity:
		"sleep":
			sleep = minf(1.0, sleep + m / (7.5 * 60.0))
			stamina = minf(1.0, stamina + m / (5.0 * 60.0))
			stress = maxf(0.0, stress - m / (10.0 * 60.0))
			hunger = minf(1.0, hunger + m / (HUNGER_ASLEEP_HOURS * 60.0))
		_:
			sleep = maxf(0.0, sleep - m / (17.0 * 60.0))
			# Hungry again after ten waking hours: two or three meals a day.
			hunger = minf(1.0, hunger + m / (10.0 * 60.0))
			stamina = minf(1.0, stamina + m / (3.0 * 60.0))
	intoxication = maxf(0.0, intoxication - m / 120.0)
	# The body keeps accounts. Going without food or sleep costs health, and
	# exhaustion frays the nerves; health at zero is a collapse (Game).
	if hunger >= STARVING:
		health = maxf(0.0, health - m / (STARVING_HOURS * 60.0))
	if sleep <= EXHAUSTED:
		health = maxf(0.0, health - m / (EXHAUSTED_HOURS * 60.0))
		stress = minf(1.0, stress + m / (8.0 * 60.0))
	# ...and a body that is fed and rested pays itself back (D-090). Before
	# this, health lost to one hungry night stayed lost until the clinic.
	if hunger < MEND_HUNGER_BELOW and sleep > MEND_SLEEP_ABOVE and health < health_cap():
		var hours := MEND_ASLEEP_HOURS if activity == "sleep" else MEND_AWAKE_HOURS
		health = minf(health_cap(), health + m / (hours * 60.0))
	_recompute_mood()
	_notify()


## How healthy the body can get while its wounds are open: each takes off what
## it took when it was dealt (`add_injury`), until it heals.
func health_cap() -> float:
	var cap := 1.0
	for injury in injuries:
		cap -= float(injury.get("severity", 0.0)) * 0.5
	return clampf(cap, 0.1, 1.0)


func modify(meter: String, delta: float) -> void:
	match meter:
		"health": health = clampf(health + delta, 0.0, 1.0)
		"stamina": stamina = clampf(stamina + delta, 0.0, 1.0)
		"hunger": hunger = clampf(hunger + delta, 0.0, 1.0)
		"sleep": sleep = clampf(sleep + delta, 0.0, 1.0)
		"stress": stress = clampf(stress + delta, 0.0, 1.0)
		"intoxication": intoxication = clampf(intoxication + delta, 0.0, 1.0)
		_:
			Log.warn("stats", "Unknown meter", {"meter": meter})
			return
	_recompute_mood()
	Events.condition_changed.emit(meter, get_meter(meter))


func get_meter(meter: String) -> float:
	match meter:
		"health": return health
		"stamina": return stamina
		"hunger": return hunger
		"sleep": return sleep
		"stress": return stress
		"mood": return mood
		"intoxication": return intoxication
	return 0.0


func is_incapacitated() -> bool:
	return health <= 0.0


# --- injuries ---------------------------------------------------------------

## Adds a lasting injury. `severity` in [0,1]; `heals_at` is a world minute.
func add_injury(id: String, part: String, severity: float, heals_at: int) -> void:
	injuries.append({
		"id": id, "part": part,
		"severity": clampf(severity, 0.0, 1.0), "heals_at": heals_at,
	})
	modify("health", -severity * 0.5)
	Log.info("stats", "Injury sustained", {"injury": id, "part": part})


func heal_expired_injuries(now: int) -> int:
	var before := injuries.size()
	injuries = injuries.filter(func(i: Dictionary) -> bool: return int(i.get("heals_at", 0)) > now)
	return before - injuries.size()


func heal_all() -> void:
	injuries.clear()
	health = 1.0


## Multiplier applied to actions using a body part, e.g. "arm", "leg".
## A broken arm does not block climbing outright; it makes it much likelier
## to go badly, which reads as a consequence rather than a locked door.
func injury_penalty(part: String) -> float:
	var penalty := 0.0
	for injury in injuries:
		if str(injury.get("part", "")) == part or str(injury.get("part", "")) == "body":
			penalty += float(injury.get("severity", 0.0))
	return clampf(1.0 - penalty, 0.1, 1.0)


func has_injury_to(part: String) -> bool:
	for injury in injuries:
		if str(injury.get("part", "")) == part:
			return true
	return false


## Overall capability multiplier from condition, used by action resolution.
func effectiveness() -> float:
	var value := 1.0
	value *= lerpf(0.55, 1.0, health)
	value *= lerpf(0.75, 1.0, sleep)
	value *= lerpf(0.85, 1.0, 1.0 - hunger)
	value *= lerpf(0.85, 1.0, 1.0 - stress)
	value *= lerpf(1.0, 0.7, intoxication)
	return clampf(value, 0.2, 1.15)


func describe() -> String:
	var parts: Array[String] = []
	if health < 0.4: parts.append("hurt")
	if sleep < 0.3: parts.append("exhausted")
	if hunger > 0.7: parts.append("hungry")
	if stress > 0.7: parts.append("on edge")
	if intoxication > 0.4: parts.append("drunk")
	return ", ".join(parts) if not parts.is_empty() else "alright"


func _recompute_mood() -> void:
	mood = clampf(
		0.5 + (health - 0.5) * 0.3 + (sleep - 0.5) * 0.25
		- stress * 0.4 - hunger * 0.2,
		0.0, 1.0)


func _notify() -> void:
	Events.condition_changed.emit("*", mood)


func to_dict() -> Dictionary:
	return {
		"character_level": character_level, "character_xp": character_xp,
		"attributes": attributes, "attribute_points": attribute_points,
		"health": health, "stamina": stamina, "hunger": hunger, "sleep": sleep,
		"stress": stress, "mood": mood, "intoxication": intoxication,
		"injuries": injuries,
	}


func from_dict(d: Dictionary) -> void:
	character_level = int(d.get("character_level", 1))
	character_xp = float(d.get("character_xp", 0.0))
	attributes = d.get("attributes", attributes)
	attribute_points = int(d.get("attribute_points", 0))
	health = float(d.get("health", 1.0))
	stamina = float(d.get("stamina", 1.0))
	hunger = float(d.get("hunger", 0.0))
	sleep = float(d.get("sleep", 1.0))
	stress = float(d.get("stress", 0.0))
	mood = float(d.get("mood", 0.5))
	intoxication = float(d.get("intoxication", 0.0))
	var inj: Array[Dictionary] = []
	for i in d.get("injuries", []):
		inj.append(i)
	injuries = inj
