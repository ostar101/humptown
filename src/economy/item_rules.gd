class_name ItemRules
extends RefCounted
## Whether the player can use a thing they carry, and what it does (D-041).
##
## Pure, like `ShopRules`. What an item does is in its data: `hunger`,
## `sleep`, `intoxication`, `health`, `stress` are changes to the condition
## meters, and `use_minutes` how long it takes (by kind when absent). Only
## food, drink, medical things and drugs are used this way; tools and clothes
## are for later systems. A sandwich on a full stomach, or a bandage with
## nothing to bandage, is refused rather than wasted.
##
## Two more fields arrived with drugs (D-070): `needs_any`, a list of items of
## which one must be carried (a cigarette wants a lighter or matches) and
## `leaves`, what is left behind when it is used (an empty bottle, a used
## syringe). A weapon has `damage`, a bonus added to every blow it lands.

const METERS: Array[String] = ["hunger", "sleep", "intoxication", "health", "stress"]
const USABLE_KINDS: Array[String] = ["food", "drink", "medical", "drug"]
const MINUTES_BY_KIND := {"food": 10, "drink": 5, "medical": 5, "drug": 10}
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


## Ok: {"effects": {meter: delta}, "minutes": int, "leaves": item id or ""}.
## Refused: `not_owned`, `not_usable`, `needs_fire`, `not_hungry`, `not_hurt`.
## `meters` is the player's condition as {meter: value}; `carried` the ids of
## what else they have on them, for `needs_any`.
static func judge_use(item: Dictionary, owned: int, meters: Dictionary, carried: Array = []) -> Result:
	if owned < 1:
		return Result.failure("not_owned")
	var kind := str(item.get("kind", ""))
	var effects := effects_of(item)
	if not USABLE_KINDS.has(kind) or effects.is_empty():
		return Result.failure("not_usable")
	var needs: Array = item.get("needs_any", [])
	if not needs.is_empty() and not needs.any(func(need: Variant) -> bool: return carried.has(need)):
		return Result.failure("needs_fire")
	if effects.keys() == ["hunger"] and float(meters.get("hunger", 0.0)) < NOT_HUNGRY:
		return Result.failure("not_hungry")
	if effects.keys() == ["health"] and float(meters.get("health", 1.0)) >= NOT_HURT:
		return Result.failure("not_hurt")
	return Result.success({
		"effects": effects,
		"minutes": int(item.get("use_minutes", MINUTES_BY_KIND.get(kind, 5))),
		"leaves": str(item.get("leaves", "")),
	})


## What a thing adds to every blow that lands when it is in the hand: 0 for
## anything that is not a weapon.
static func damage_of(item: Dictionary) -> float:
	return maxf(float(item.get("damage", 0.0)), 0.0)
