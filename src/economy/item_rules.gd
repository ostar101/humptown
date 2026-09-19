class_name ItemRules
extends RefCounted
## Whether the player can use a thing they carry, and what it does (D-041).
##
## Pure, like `ShopRules`. What an item does is in its data: `hunger`,
## `sleep`, `intoxication`, `health`, `stress` are changes to the condition
## meters, and `use_minutes` how long it takes (by kind when absent). Only
## food, drink and medical things are used this way; tools and clothes are
## for later systems. A sandwich on a full stomach, or a bandage with
## nothing to bandage, is refused rather than wasted.

const METERS: Array[String] = ["hunger", "sleep", "intoxication", "health", "stress"]
const USABLE_KINDS: Array[String] = ["food", "drink", "medical"]
const MINUTES_BY_KIND := {"food": 10, "drink": 5, "medical": 5}
## Below this, food that only feeds is refused: you are not hungry.
const NOT_HUNGRY := 0.15
## At or above this, medicine that only heals is refused: you are not hurt.
const NOT_HURT := 0.99


## What using one does: {meter: delta}, from the item's data.
static func effects_of(item: Dictionary) -> Dictionary:
	var out := {}
	for meter in METERS:
		if item.has(meter):
			out[meter] = float(item[meter])
	return out


## Ok: {"effects": {meter: delta}, "minutes": int}. Refused: `not_owned`,
## `not_usable`, `not_hungry`, `not_hurt`. `meters` is the player's
## condition as {meter: value}.
static func judge_use(item: Dictionary, owned: int, meters: Dictionary) -> Result:
	if owned < 1:
		return Result.failure("not_owned")
	var kind := str(item.get("kind", ""))
	var effects := effects_of(item)
	if not USABLE_KINDS.has(kind) or effects.is_empty():
		return Result.failure("not_usable")
	if effects.keys() == ["hunger"] and float(meters.get("hunger", 0.0)) < NOT_HUNGRY:
		return Result.failure("not_hungry")
	if effects.keys() == ["health"] and float(meters.get("health", 1.0)) >= NOT_HURT:
		return Result.failure("not_hurt")
	return Result.success({
		"effects": effects,
		"minutes": int(item.get("use_minutes", MINUTES_BY_KIND.get(kind, 5))),
	})
