class_name CraftRules
extends RefCounted
## What putting things together makes (D-070). Pure, like `ShopRules`: the
## crafting window proposes the things on its grid, `Game.craft()` asks here what
## they make and applies it.
##
## Recipes are shapeless, as in a workbench's first days: what matters is *which*
## things and how many, not where on the grid they lie. A recipe's `inputs` is
## exactly what must be on the grid; `keeps` names inputs that are needed but not
## used up (a lighter, a grinder); `outputs` is what comes out; `minutes` is
## how long it takes. Two recipes may not share the same inputs, so the grid
## always means one thing (`DataRegistry` checks it).

## Refusals, as `Game.craft()` reports them: `no_recipe` (these do not make
## anything), `not_owned` (the grid holds more than the bag), `too_heavy` (the
## result would not fit), `busy`, `no_world`.


## {item_id: count} of what is on the grid; empty slots ("") do not count.
static func tally(placed: Array) -> Dictionary:
	var out := {}
	for entry: Variant in placed:
		var item_id := str(entry)
		if item_id != "":
			out[item_id] = int(out.get(item_id, 0)) + 1
	return out


## A recipe's inputs as {item_id: int}.
static func inputs_of(recipe: Dictionary) -> Dictionary:
	return _counts(recipe.get("inputs", {}))


static func outputs_of(recipe: Dictionary) -> Dictionary:
	return _counts(recipe.get("outputs", {}))


static func _counts(raw: Variant) -> Dictionary:
	var out := {}
	if typeof(raw) == TYPE_DICTIONARY:
		var things: Dictionary = raw
		for item_id: Variant in things:
			out[str(item_id)] = int(things[item_id])
	return out


## The recipe whose inputs are exactly what is on the grid, or {} when none is.
static func find(recipes: Dictionary, placed: Array) -> Dictionary:
	var laid := tally(placed)
	if laid.is_empty():
		return {}
	for recipe_id: Variant in recipes:
		var recipe: Dictionary = recipes[recipe_id]
		if _same(inputs_of(recipe), laid):
			return recipe
	return {}


static func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key: Variant in a:
		if int(b.get(key, 0)) != int(a[key]):
			return false
	return true


## Ok: {"recipe": id, "consumed": {item: n}, "outputs": {item: n}, "minutes": int}.
## Refused: `not_owned` when the bag has less than the recipe asks for.
static func judge(recipe: Dictionary, owned: Dictionary) -> Result:
	var inputs := inputs_of(recipe)
	var consumed := {}
	var kept: Array = recipe.get("keeps", [])
	for item_id: String in inputs:
		if int(owned.get(item_id, 0)) < int(inputs[item_id]):
			return Result.failure("not_owned", item_id)
		if not kept.has(item_id):
			consumed[item_id] = inputs[item_id]
	return Result.success({
		"recipe": str(recipe.get("id", "")),
		"consumed": consumed,
		"outputs": outputs_of(recipe),
		"minutes": maxi(int(recipe.get("minutes", 1)), 0),
	})


## Recipes the bag holds every ingredient of, that are not yet known: the way a
## recipe reaches the book without being tried first.
static func unlockable(recipes: Dictionary, owned: Dictionary, known: Array) -> Array[String]:
	var out: Array[String] = []
	for recipe_id: Variant in recipes:
		if known.has(recipe_id):
			continue
		var inputs := inputs_of(recipes[recipe_id])
		var has_all := true
		for item_id: String in inputs:
			if int(owned.get(item_id, 0)) < int(inputs[item_id]):
				has_all = false
				break
		if has_all:
			out.append(str(recipe_id))
	return out
