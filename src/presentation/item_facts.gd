class_name ItemFacts
extends RefCounted
## What examine says about a thing (M8 step 5, D-081): generated from the
## item's own data, the same way for all 115 items — kind, weight, value,
## what it does when used, how hard it hits (banded; a raw `damage` is never
## printed), where it is worn, what it needs, what it leaves behind — plus an
## optional authored sentence at `item.<slug>.desc` for the ones data alone
## cannot speak for.
##
## Pure, like `ItemRules`: returns `{key, args}` rather than finished
## strings, so the window localises every fact the same way everything else
## on screen is.

## (damage at or above this, fact key), checked highest first.
const DAMAGE_BANDS := [
	[0.14, "ui.items.fact.damage.heavy"],
	[0.07, "ui.items.fact.damage.moderate"],
	[0.0, "ui.items.fact.damage.light"],
]
## (item field, positive-delta key, negative-delta key). Only meters items
## actually carry — `intoxication` and the rest, never a made-up one.
const METER_FACTS := [
	["hunger", "ui.items.fact.hunger.more", "ui.items.fact.hunger.less"],
	["sleep", "ui.items.fact.sleep.more", "ui.items.fact.sleep.less"],
	["health", "ui.items.fact.health.more", "ui.items.fact.health.less"],
	["stress", "ui.items.fact.stress.more", "ui.items.fact.stress.less"],
	["intoxication", "ui.items.fact.intoxication.more", "ui.items.fact.intoxication.less"],
]


## The generated facts for an item, most useful first.
static func facts_of(item: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"key": "ui.items.fact.kind", "args": {"kind": Localization.t("ui.items.kind." + str(item.get("kind", "")))}})
	var weight := float(item.get("weight", 0.0))
	out.append({"key": "ui.items.fact.weight", "args": {"weight": ("%.2f" if weight < 0.1 else "%.1f") % weight}})
	var value := int(item.get("value", 0))
	if value > 0:
		out.append({"key": "ui.items.fact.value", "args": {"value": value}})

	for rule: Array in METER_FACTS:
		var field := str(rule[0])
		if item.has(field):
			out.append({"key": str(rule[1] if float(item[field]) > 0.0 else rule[2]), "args": {}})

	var damage := ItemRules.damage_of(item)
	if damage > 0.0:
		out.append({"key": _damage_band(damage), "args": {}})

	var slot := str(item.get("slot", ""))
	if not slot.is_empty():
		out.append({"key": "ui.items.fact.slot." + slot, "args": {}})

	if ItemRules.armour_of(item) > 0.0:
		out.append({"key": "ui.items.fact.armour", "args": {}})

	if float(item.get("capacity_bonus", 0.0)) > 0.0:
		out.append({"key": "ui.items.fact.capacity", "args": {}})

	if not (item.get("needs_any", []) as Array).is_empty():
		out.append({"key": "ui.items.fact.needs_fire", "args": {}})

	var leaves := str(item.get("leaves", ""))
	if not leaves.is_empty():
		out.append({"key": "ui.items.fact.leaves", "args": {"item": ItemIcons.name_of(leaves)}})

	if str(item.get("kind", "")) == "drug":
		out.append({"key": "ui.items.fact.illicit", "args": {}})

	return out


static func _damage_band(damage: float) -> String:
	for band: Array in DAMAGE_BANDS:
		if damage >= float(band[0]):
			return str(band[1])
	return "ui.items.fact.damage.light"


## The authored sentence at `item.<slug>.desc`, or "" when there is none —
## deliberately true of most of the 115 (only ~30 are worth authoring by
## hand); never treated as an error.
static func description_of(item: Dictionary) -> String:
	var name_key := str(item.get("name_key", ""))
	if name_key.is_empty():
		return ""
	var key := name_key + ".desc"
	var text := Localization.t(key)
	return text if text != key else ""
