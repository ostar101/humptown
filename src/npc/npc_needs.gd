class_name NpcNeeds
extends RefCounted
## Lightweight drives that give NPCs a reason to deviate from routine.
##
## Deliberately shallow: four floats in [0,1] that drift with time. This is
## not a survival sim, it is just enough state for "she skipped work because
## she was ill" to be expressible, and it costs a multiply per coarse tick.

var energy: float = 1.0
var hunger: float = 0.0
var social: float = 0.5
var stress: float = 0.0

## Per-game-minute drift while awake.
const ENERGY_DRAIN := 1.0 / (16.0 * 60.0)
const HUNGER_GAIN := 1.0 / (5.0 * 60.0)
const SOCIAL_DECAY := 1.0 / (24.0 * 60.0)
const STRESS_DECAY := 1.0 / (12.0 * 60.0)


## Advances needs by `minutes`. Cheap enough to run on coarse background ticks.
func drift(minutes: int, activity: String) -> void:
	var m := float(minutes)
	match activity:
		"sleep":
			energy = minf(1.0, energy + m / (7.0 * 60.0))
			hunger = minf(1.0, hunger + m * HUNGER_GAIN * 0.4)
			stress = maxf(0.0, stress - m * STRESS_DECAY * 1.5)
		"eat", "lunch":
			hunger = maxf(0.0, hunger - m / 30.0)
			energy = minf(1.0, energy + m / (8.0 * 60.0))
		"socialise":
			social = minf(1.0, social + m / 90.0)
			stress = maxf(0.0, stress - m * STRESS_DECAY)
			energy = maxf(0.0, energy - m * ENERGY_DRAIN)
		"work":
			energy = maxf(0.0, energy - m * ENERGY_DRAIN * 1.3)
			hunger = minf(1.0, hunger + m * HUNGER_GAIN)
			stress = minf(1.0, stress + m / (10.0 * 60.0))
			social = maxf(0.0, social - m * SOCIAL_DECAY)
		_:
			energy = maxf(0.0, energy - m * ENERGY_DRAIN)
			hunger = minf(1.0, hunger + m * HUNGER_GAIN)
			social = maxf(0.0, social - m * SOCIAL_DECAY)
			stress = maxf(0.0, stress - m * STRESS_DECAY)


## The most pressing need, or "" when nothing is urgent. Drives deviations.
func dominant_need(threshold: float = 0.8) -> String:
	var candidates := {
		"rest": 1.0 - energy,
		"food": hunger,
		"company": 1.0 - social,
		"relief": stress,
	}
	var best := ""
	var best_value := threshold
	for key in candidates:
		if candidates[key] > best_value:
			best = key
			best_value = candidates[key]
	return best


## Short descriptor used in LLM context, e.g. "tired, hungry".
func describe() -> String:
	var parts: Array[String] = []
	if energy < 0.3: parts.append("tired")
	if hunger > 0.7: parts.append("hungry")
	if social < 0.25: parts.append("lonely")
	if stress > 0.7: parts.append("stressed")
	return ", ".join(parts) if not parts.is_empty() else "fine"


func to_dict() -> Dictionary:
	return {"energy": energy, "hunger": hunger, "social": social, "stress": stress}


func from_dict(d: Dictionary) -> void:
	energy = float(d.get("energy", 1.0))
	hunger = float(d.get("hunger", 0.0))
	social = float(d.get("social", 0.5))
	stress = float(d.get("stress", 0.0))
