class_name EquipRules
extends RefCounted
## Whether a carried thing can be worn or wielded (M8 step 4, D-080). Pure:
## the caller gathers the facts, this answers with a Result, and nothing
## changes on a refusal. Equipping is a pointer, not a move — the thing
## stays in the bag and still weighs what it always did; wearing something
## else in the same slot just moves the pointer, no unequip needed first.
##
## Six slots, no more: head, body, legs, feet, hand, back.
##
## judge_equip facts: owned (bool), slot (the item's own `slot` field, "" if
## it has none). Refusals: not_owned, not_equipable.
## judge_unequip facts: worn (bool, whether that slot holds this item).
## Refusals: not_worn.

const SLOTS: Array[String] = ["head", "body", "legs", "feet", "hand", "back"]


static func judge_equip(facts: Dictionary) -> Result:
	if not bool(facts.get("owned", false)):
		return Result.failure("not_owned")
	var slot := str(facts.get("slot", ""))
	if slot.is_empty() or not SLOTS.has(slot):
		return Result.failure("not_equipable")
	return Result.success({"slot": slot})


static func judge_unequip(facts: Dictionary) -> Result:
	if not bool(facts.get("worn", false)):
		return Result.failure("not_worn")
	return Result.success()
