extends TestCase
## What examine says about a thing (M8 step 5, D-081): generated facts for
## every item, banded damage rather than a raw number, and the optional
## authored sentence.


func before_each() -> void:
	Game.new_game("", 7)
	Localization.set_locale("en")


func _item(id: String) -> Dictionary:
	return Game.data.get_entry("items", id)


func test_every_item_gets_kind_weight_and_a_fact() -> void:
	for item_id in Game.data.ids("items"):
		var facts := ItemFacts.facts_of(Game.data.get_entry("items", item_id))
		assert_gt(float(facts.size()), 1.0, "%s has almost nothing to say" % item_id)
		assert_eq(str(facts[0]["key"]), "ui.items.fact.kind")
		assert_eq(str(facts[1]["key"]), "ui.items.fact.weight")


func test_value_is_omitted_when_worthless() -> void:
	var facts := ItemFacts.facts_of(_item("item_keys"))   # value: 0
	for fact: Dictionary in facts:
		assert_ne(str(fact["key"]), "ui.items.fact.value")


func test_food_feeds_you() -> void:
	var facts := ItemFacts.facts_of(_item("item_sandwich"))
	var keys := facts.map(func(f: Dictionary) -> String: return str(f["key"]))
	assert_has(keys, "ui.items.fact.hunger.less")


func test_damage_is_banded_never_a_raw_number() -> void:
	var puukko := ItemFacts.facts_of(_item("item_puukko"))   # damage 0.13
	var keys := puukko.map(func(f: Dictionary) -> String: return str(f["key"]))
	assert_has(keys, "ui.items.fact.damage.moderate")
	for fact: Dictionary in puukko:
		assert_false(str(fact["key"]).contains("0.13"))
		assert_false(str(fact["args"]).contains("0.13"))
	var stick := ItemFacts.facts_of(_item("item_stick"))   # damage 0.03
	assert_has(stick.map(func(f: Dictionary) -> String: return str(f["key"])), "ui.items.fact.damage.light")
	var axe := ItemFacts.facts_of(_item("item_axe"))   # damage 0.14
	assert_has(axe.map(func(f: Dictionary) -> String: return str(f["key"])), "ui.items.fact.damage.heavy")


func test_a_non_weapon_has_no_damage_fact() -> void:
	var facts := ItemFacts.facts_of(_item("item_sandwich"))
	for fact: Dictionary in facts:
		assert_false(str(fact["key"]).begins_with("ui.items.fact.damage"))


func test_the_slot_says_where_it_is_worn() -> void:
	var boots := ItemFacts.facts_of(_item("item_work_boots"))
	var keys := boots.map(func(f: Dictionary) -> String: return str(f["key"]))
	assert_has(keys, "ui.items.fact.slot.feet")
	assert_has(keys, "ui.items.fact.armour")
	var puukko := ItemFacts.facts_of(_item("item_puukko"))
	assert_has(puukko.map(func(f: Dictionary) -> String: return str(f["key"])), "ui.items.fact.slot.hand")


func test_the_backpack_says_it_widens_the_bag() -> void:
	var facts := ItemFacts.facts_of(_item("item_backpack"))
	assert_has(facts.map(func(f: Dictionary) -> String: return str(f["key"])), "ui.items.fact.capacity")


func test_something_that_needs_a_light_says_so() -> void:
	var facts := ItemFacts.facts_of(_item("item_joint"))
	assert_has(facts.map(func(f: Dictionary) -> String: return str(f["key"])), "ui.items.fact.needs_fire")


func test_something_that_leaves_a_thing_behind_names_it() -> void:
	var facts := ItemFacts.facts_of(_item("item_vodka"))
	var leaves := facts.filter(func(f: Dictionary) -> bool: return str(f["key"]) == "ui.items.fact.leaves")
	assert_eq(leaves.size(), 1)
	assert_eq(Localization.t(str(leaves[0]["key"]), leaves[0]["args"]), "Leaves Empty bottle behind.")


func test_a_drug_warns_you() -> void:
	var facts := ItemFacts.facts_of(_item("item_heroin_bag"))
	assert_has(facts.map(func(f: Dictionary) -> String: return str(f["key"])), "ui.items.fact.illicit")
	var sandwich := ItemFacts.facts_of(_item("item_sandwich"))
	assert_false(sandwich.map(func(f: Dictionary) -> String: return str(f["key"])).has("ui.items.fact.illicit"))


# --- the authored sentence ----------------------------------------------------------

func test_an_authored_item_has_its_own_sentence() -> void:
	assert_eq(ItemFacts.description_of(_item("item_puukko")),
		"A Finn's everyday knife, worn on the belt more often than it is used.")


func test_most_items_have_no_authored_sentence() -> void:
	assert_eq(ItemFacts.description_of(_item("item_tomato")), "")


func test_around_thirty_items_are_authored() -> void:
	var authored := 0
	for item_id in Game.data.ids("items"):
		if ItemFacts.description_of(Game.data.get_entry("items", item_id)) != "":
			authored += 1
	assert_gt(float(authored), 24.0, "fewer than expected are authored")
	assert_lt(float(authored), 40.0, "more than the plan called for — check nothing doubled up")
