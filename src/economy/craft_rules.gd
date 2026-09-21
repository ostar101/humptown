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
##
## `"fire": true` means the recipe also wants a light: one lighter or one box of
## matches laid on the grid beside its inputs, needed but not used up. It saves
## writing every cooking recipe twice.

const FIRE: Array[String] = ["item_lighter", "item_matches"]

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


## The light on the grid — the lighter if both are there — or "".
static func fire_in(laid: Dictionary) -> String:
	for source in FIRE:
		if int(laid.get(source, 0)) > 0:
			return source
	return ""


## Everything a recipe needs laid out, its light included (as a lighter).
static func ingredients_of(recipe: Dictionary) -> Dictionary:
	var out := inputs_of(recipe)
	if bool(recipe.get("fire", false)):
		out[FIRE[0]] = 1
	return out


## The recipe whose inputs are exactly what is on the grid, or {} when none is.
static func find(recipes: Dictionary, placed: Array) -> Dictionary:
	var laid := tally(placed)
	if laid.is_empty():
		return {}
	var fire := fire_in(laid)
	var without_fire := laid.duplicate()
	if fire != "":
		without_fire[fire] = int(without_fire[fire]) - 1
		if int(without_fire[fire]) == 0:
			without_fire.erase(fire)
	for recipe_id: Variant in recipes:
		var recipe: Dictionary = recipes[recipe_id]
		if bool(recipe.get("fire", false)):
			if fire != "" and _same(inputs_of(recipe), without_fire):
				return recipe
		elif _same(inputs_of(recipe), laid):
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
## Refused: `not_owned` when the bag has less than the recipe asks for. `placed`
## is the grid, which says which light a `fire` recipe uses.
static func judge(recipe: Dictionary, owned: Dictionary, placed: Array = []) -> Result:
	var inputs := inputs_of(recipe)
	var consumed := {}
	var kept: Array = recipe.get("keeps", [])
	if bool(recipe.get("fire", false)):
		var fire := fire_in(tally(placed))
		if fire == "":
			fire = FIRE[0]
		if int(owned.get(fire, 0)) < 1:
			return Result.failure("not_owned", fire)
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
		if bool((recipes[recipe_id] as Dictionary).get("fire", false)) and fire_in(owned) == "":
			continue
		for item_id: String in inputs:
			if int(owned.get(item_id, 0)) < int(inputs[item_id]):
				has_all = false
				break
		if has_all:
			out.append(str(recipe_id))
	return out
