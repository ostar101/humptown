extends TestCase
## Putting things together (D-070): what a grid makes, what is refused and
## why, the chain from a spoon to a used syringe, using what comes out, the
## recipe book and its save.

var _rejected: Array[String] = []


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	Game.player.inventory.clear()
	_rejected = []
	Events.action_rejected.connect(_on_rejected)


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)
	Game.saves.delete_slot("test_crafting")


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


func _bag(item_id: String, count: int = 1) -> void:
	assert_ok(Game.player.inventory.add(item_id, count))


func _has(item_id: String) -> int:
	return Game.player.inventory.count_of(item_id)


# --- the rules ------------------------------------------------------------------------------

func test_a_grid_matches_by_what_is_on_it_not_where() -> void:
	var recipes := Game.data.table("recipes")
	var a := CraftRules.find(recipes, ["item_cannabis_bud", "", "item_rolling_papers"])
	var b := CraftRules.find(recipes, ["", "", "", "item_rolling_papers", "", "", "item_cannabis_bud", "", ""])
	assert_eq(a["id"], "rcp_joint_from_bud")
	assert_eq(b["id"], "rcp_joint_from_bud")


func test_the_grid_must_hold_exactly_what_the_recipe_takes() -> void:
	var recipes := Game.data.table("recipes")
	assert_true(CraftRules.find(recipes, []).is_empty(), "an empty grid makes nothing")
	assert_true(CraftRules.find(recipes, ["item_cannabis_bud"]).is_empty(), "one ingredient of two")
	assert_true(CraftRules.find(recipes, ["item_cannabis_bud", "item_rolling_papers", "item_lighter"]).is_empty(),
		"a stray extra thing spoils it")
	assert_true(CraftRules.find(recipes, ["item_bat", "item_nails"]).is_empty(), "three nails, not one")
	assert_eq(CraftRules.find(recipes, ["item_bat", "item_nails", "item_nails", "item_nails"])["id"], "rcp_nail_bat")


func test_a_recipe_asks_the_bag_and_says_what_is_used_up() -> void:
	var recipe := Game.data.get_entry("recipes", "rcp_grind_bud")
	assert_err(CraftRules.judge(recipe, {"item_cannabis_bud": 1}), "not_owned")
	var judged := CraftRules.judge(recipe, {"item_cannabis_bud": 1, "item_grinder": 1})
	assert_ok(judged)
	assert_eq(judged.value["consumed"], {"item_cannabis_bud": 1}, "the grinder is kept")
	assert_eq(judged.value["outputs"], {"item_cannabis_ground": 1})


func test_a_recipe_becomes_known_when_you_hold_all_of_it() -> void:
	var recipes := Game.data.table("recipes")
	var owned := {"item_cannabis_bud": 1, "item_rolling_papers": 2, "item_grinder": 1}
	var found := CraftRules.unlockable(recipes, owned, [])
	assert_has(found, "rcp_joint_from_bud")
	assert_has(found, "rcp_grind_bud")
	assert_false(found.has("rcp_joint_from_ground"), "no ground cannabis yet")
	assert_false(CraftRules.unlockable(recipes, owned, ["rcp_grind_bud"]).has("rcp_grind_bud"), "not twice")


func test_the_recipe_data_is_sound() -> void:
	assert_eq(Game.data.validate_references(), [] as Array[String])
	assert_gt(float(Game.data.table("recipes").size()), 10.0)


func test_the_data_check_catches_bad_recipes() -> void:
	var data := DataRegistry.new()
	data.load_all()
	data.tables["recipes"]["rcp_bad_item"] = {"id": "rcp_bad_item", "name_key": "x", "inputs": {"item_nowhere": 1}, "outputs": {"item_joint": 1}}
	data.tables["recipes"]["rcp_bad_keep"] = {"id": "rcp_bad_keep", "name_key": "x", "inputs": {"item_bat": 1, "item_hammer": 1}, "keeps": ["item_axe"], "outputs": {"item_joint": 1}}
	data.tables["recipes"]["rcp_twin"] = {"id": "rcp_twin", "name_key": "x", "inputs": {"item_cannabis_bud": 1, "item_rolling_papers": 1}, "outputs": {"item_cigarette": 1}}
	var problems := "\n".join(data.validate_references())
	assert_true(problems.contains("unknown item 'item_nowhere'"), problems)
	assert_true(problems.contains("keeps 'item_axe'"), problems)
	assert_true(problems.contains("take the same things"), problems)


# --- making things ---------------------------------------------------------------------------

func test_rolling_a_joint_uses_the_bud_and_the_paper_and_takes_time() -> void:
	_bag("item_cannabis_bud")
	_bag("item_rolling_papers", 2)
	var before := Game.clock.total_minutes
	Game.pause_time(false)
	var made := Game.craft(["item_cannabis_bud", "item_rolling_papers"])
	assert_ok(made)
	assert_eq(made.value["outputs"], {"item_joint": 1})
	assert_eq(_has("item_joint"), 1)
	assert_eq(_has("item_cannabis_bud"), 0)
	assert_eq(_has("item_rolling_papers"), 1)
	assert_eq(Game.clock.total_minutes - before, 3, "three minutes at the bench")


func test_a_tool_is_needed_but_not_used_up() -> void:
	_bag("item_cannabis_bud")
	_bag("item_grinder")
	assert_ok(Game.craft(["item_grinder", "item_cannabis_bud"]))
	assert_eq(_has("item_cannabis_ground"), 1)
	assert_eq(_has("item_grinder"), 1, "still there")


func test_a_recipe_can_make_several_things() -> void:
	_bag("item_heroin_bag")
	_bag("item_spoon")
	assert_ok(Game.craft(["item_heroin_bag", "item_spoon"]))
	assert_eq(_has("item_spoon_powder"), 1)
	assert_eq(_has("item_baggie"), 1, "the empty bag is left")
	_bag("item_cigarettes")
	assert_ok(Game.craft(["item_cigarettes"]))
	assert_eq(_has("item_cigarette"), 10)


func test_what_makes_nothing_is_refused_and_nothing_changes() -> void:
	_bag("item_cannabis_bud")
	_bag("item_lighter")
	assert_err(Game.craft(["item_cannabis_bud", "item_lighter"]), "no_recipe")
	assert_err(Game.craft([]), "no_recipe")
	assert_eq(_has("item_cannabis_bud"), 1)
	assert_eq(_has("item_lighter"), 1)
	assert_eq(_rejected, ["no_recipe", "no_recipe"] as Array[String])


func test_you_cannot_use_what_you_do_not_have() -> void:
	_bag("item_cannabis_bud")
	assert_err(Game.craft(["item_cannabis_bud", "item_rolling_papers"]), "not_owned")
	assert_eq(_has("item_cannabis_bud"), 1, "nothing was taken")
	_bag("item_rolling_papers")
	assert_err(Game.craft(["item_cannabis_bud", "item_cannabis_bud", "item_rolling_papers"]), "no_recipe")


func test_a_result_that_will_not_fit_is_refused_whole() -> void:
	_bag("item_bat")
	_bag("item_nails", 3)
	Game.player.inventory.bonus_capacity = 0.0
	Game.player.inventory.base_capacity = Game.player.inventory.total_weight() + 0.05   # a nail bat weighs 0.14 more
	assert_err(Game.craft(["item_bat", "item_nails", "item_nails", "item_nails"]), "too_heavy")
	assert_eq(_has("item_bat"), 1)
	assert_eq(_has("item_nails"), 3)
	assert_eq(_has("item_nail_bat"), 0)


func test_a_bottle_can_be_smashed_into_something_to_hit_with() -> void:
	_bag("item_empty_bottle")
	assert_ok(Game.craft(["item_empty_bottle"]))
	assert_eq(_has("item_broken_bottle"), 1)
	assert_gt(ItemRules.damage_of(Game.data.get_entry("items", "item_broken_bottle")), 0.0)


func test_bandages_and_a_first_aid_kit_are_built_up() -> void:
	_bag("item_cloth", 2)
	_bag("item_antiseptic", 2)
	_bag("item_plasters")
	assert_ok(Game.craft(["item_cloth", "item_cloth", "item_antiseptic"]))
	assert_eq(_has("item_bandage"), 2)
	assert_ok(Game.craft(["item_bandage", "item_bandage", "item_plasters", "item_antiseptic"]))
	assert_eq(_has("item_first_aid_kit"), 1)
	assert_eq(_has("item_antiseptic"), 0)


# --- the long way round: a spoon to a used syringe -----------------------------------------------

func test_from_a_bag_to_a_loaded_syringe_step_by_step() -> void:
	_bag("item_heroin_bag")
	_bag("item_spoon")
	_bag("item_water")
	_bag("item_lighter")
	_bag("item_syringe")
	assert_err(Game.use_item("item_heroin_bag"), "not_usable")   # raw, it is nothing to take
	assert_ok(Game.craft(["item_spoon", "item_heroin_bag"]))
	assert_eq(_has("item_spoon_powder"), 1)
	assert_ok(Game.craft(["item_spoon_powder", "item_water"]))
	assert_eq(_has("item_spoon_liquid"), 1)
	assert_eq(_has("item_water"), 1, "the water is only a splash")
	assert_ok(Game.craft(["item_spoon_liquid", "item_lighter"]))
	assert_eq(_has("item_spoon_cooked"), 1)
	assert_eq(_has("item_lighter"), 1)
	assert_err(Game.craft(["item_spoon_cooked", "item_lighter"]), "no_recipe")
	assert_ok(Game.craft(["item_spoon_cooked", "item_syringe"]))
	assert_eq(_has("item_syringe_loaded"), 1)
	assert_eq(_has("item_spoon"), 1, "the spoon comes back")
	var before := Game.player.stats.get_meter("intoxication")
	var health := Game.player.stats.get_meter("health")
	assert_ok(Game.use_item("item_syringe_loaded"))
	assert_gt(Game.player.stats.get_meter("intoxication"), before)
	assert_lt(Game.player.stats.get_meter("health"), health, "it costs")
	assert_eq(_has("item_syringe_used"), 1, "the syringe is left")
	assert_eq(_has("item_syringe_loaded"), 0)


func test_matches_heat_a_spoon_too() -> void:
	_bag("item_spoon_liquid")
	_bag("item_matches")
	assert_ok(Game.craft(["item_matches", "item_spoon_liquid"]))
	assert_eq(_has("item_spoon_cooked"), 1)
	assert_eq(_has("item_matches"), 1)


# --- using what was made -----------------------------------------------------------------------------

func test_a_joint_and_a_cigarette_need_a_flame() -> void:
	_bag("item_joint")
	_bag("item_cigarette", 2)
	assert_err(Game.use_item("item_joint"), "needs_fire")
	assert_err(Game.use_item("item_cigarette"), "needs_fire")
	assert_eq(_has("item_joint"), 1, "refused, so not used up")
	_bag("item_matches")
	assert_ok(Game.use_item("item_joint"))
	assert_ok(Game.use_item("item_cigarette"))
	assert_eq(_has("item_joint"), 0)
	assert_eq(_has("item_cigarette"), 1)
	assert_eq(_has("item_matches"), 1, "a light is not used up")
	assert_gt(Game.player.stats.get_meter("intoxication"), 0.0)


func test_what_is_used_leaves_something_behind() -> void:
	_bag("item_vodka")
	assert_ok(Game.use_item("item_vodka"))
	assert_eq(_has("item_vodka"), 0)
	assert_eq(_has("item_empty_bottle"), 1)
	_bag("item_pipe_loaded")
	_bag("item_lighter")
	assert_ok(Game.use_item("item_pipe_loaded"))
	assert_eq(_has("item_pipe"), 1, "the pipe stays")


func test_medicine_and_the_rest_do_what_the_data_says() -> void:
	Game.player.stats.health = 0.5
	_bag("item_naloxone")
	_bag("item_painkillers")
	assert_ok(Game.use_item("item_painkillers"))
	assert_almost(Game.player.stats.get_meter("health"), 0.62, 0.001)
	assert_ok(Game.use_item("item_naloxone"))
	assert_gt(Game.player.stats.get_meter("health"), 0.8)
	Game.player.stats.health = 1.0
	_bag("item_painkillers")
	assert_err(Game.use_item("item_painkillers"), "not_hurt")


func test_drugs_can_be_used_only_if_they_have_an_effect() -> void:
	for item_id: String in Game.data.ids("items"):
		var item := Game.data.get_entry("items", item_id)
		if str(item.get("kind", "")) == "drug":
			var usable := not ItemRules.effects_of(item).is_empty()
			var judged := ItemRules.judge_use(item, 1, {"hunger": 0.5, "health": 0.5}, ["item_lighter"])
			assert_eq(judged.is_ok(), usable, item_id)


# --- the book and the save -----------------------------------------------------------------------

func test_holding_the_makings_finds_the_recipe() -> void:
	assert_eq(Game.refresh_recipes(), [] as Array[String])
	_bag("item_cannabis_bud")
	_bag("item_rolling_papers")
	assert_has(Game.refresh_recipes(), "rcp_joint_from_bud")
	assert_has(Game.player.known_recipes, "rcp_joint_from_bud")
	assert_eq(Game.refresh_recipes(), [] as Array[String], "told once")


func test_making_something_teaches_the_recipe_and_what_is_left_may_teach_more() -> void:
	_bag("item_cannabis_bud", 2)
	_bag("item_grinder")
	_bag("item_rolling_papers")
	var made := Game.craft(["item_cannabis_bud", "item_grinder"])
	assert_ok(made)
	assert_true(made.value["learned"])
	assert_has(Game.player.known_recipes, "rcp_grind_bud")
	assert_has(Game.player.known_recipes, "rcp_joint_from_ground", "the ground cannabis and the paper are both in the bag now")
	assert_false(Game.craft(["item_cannabis_bud", "item_grinder"]).value["learned"], "not new the second time")


func test_the_book_is_saved() -> void:
	_bag("item_cannabis_bud")
	_bag("item_rolling_papers")
	Game.refresh_recipes()
	assert_ok(Game.save_game("test_crafting"))
	Game.player.known_recipes.clear()
	assert_ok(Game.load_game("test_crafting"))
	assert_has(Game.player.known_recipes, "rcp_joint_from_bud")


func test_an_older_save_knows_no_recipes() -> void:
	var migrated := SaveMigrations.migrate({"schema_version": 11, "player": {"display_name": "X"}})
	assert_ok(migrated)
	assert_eq(migrated.value["player"]["known_recipes"], [])
	assert_eq(migrated.value["schema_version"], SaveMigrations.CURRENT_VERSION)
	var bare := SaveMigrations.migrate({"schema_version": 11})
	assert_ok(bare)
	assert_eq(bare.value["player"]["known_recipes"], [])


# --- where things come from ------------------------------------------------------------------------

func test_the_shops_and_bins_stock_the_new_things() -> void:
	var corner: Dictionary = Game.data.get_entry("shops", "shop_corner")["stock"]
	assert_true(corner.has("item_lighter") and corner.has("item_rolling_papers"))
	var pawn := Game.data.get_entry("shops", "shop_pawn")
	assert_true((pawn["stock"] as Dictionary).has("item_puukko"))
	assert_has(pawn["buys"], "weapon")
	var found := {}
	for entry: Dictionary in Game.data.get_entry("bins", Bins.DEFINITION)["loot"]:
		found[str(entry["item"])] = true
	assert_true(found.has("item_syringe") and found.has("item_empty_bottle"))


# --- a light on the grid (D-070) --------------------------------------------------------------------

func test_a_recipe_that_wants_fire_takes_either_light_and_keeps_it() -> void:
	_bag("item_potato", 2)
	_bag("item_lighter")
	_bag("item_matches")
	var recipes := Game.data.table("recipes")
	assert_eq(CraftRules.find(recipes, ["item_potato", "item_lighter"])["id"], "rcp_baked_potato")
	assert_eq(CraftRules.find(recipes, ["item_matches", "item_potato"])["id"], "rcp_baked_potato")
	assert_ok(Game.craft(["item_potato", "item_lighter"]))
	assert_ok(Game.craft(["item_potato", "item_matches"]))
	assert_eq(_has("item_baked_potato"), 2)
	assert_eq(_has("item_lighter"), 1, "a light is not used up")
	assert_eq(_has("item_matches"), 1)


func test_without_a_light_there_is_no_fire_recipe() -> void:
	var recipes := Game.data.table("recipes")
	assert_true(CraftRules.find(recipes, ["item_potato"]).is_empty())
	assert_true(CraftRules.find(recipes, ["item_potato", "item_lighter", "item_matches"]).is_empty(), "one light, not two")
	_bag("item_potato")
	assert_err(Game.craft(["item_potato", "item_lighter"]), "not_owned", "the grid says lighter but the bag has none")
	assert_eq(_has("item_potato"), 1)


func test_a_fire_recipe_is_only_found_when_you_hold_a_light() -> void:
	var recipes := Game.data.table("recipes")
	assert_false(CraftRules.unlockable(recipes, {"item_potato": 1}, []).has("rcp_baked_potato"))
	assert_has(CraftRules.unlockable(recipes, {"item_potato": 1, "item_matches": 1}, []), "rcp_baked_potato")


func test_the_kitchen_from_shopping_to_plate() -> void:
	for item_id: String in ["item_flour", "item_sugar", "item_butter", "item_eggs", "item_milk", "item_frying_pan", "item_lighter"]:
		_bag(item_id)
	assert_ok(Game.craft(["item_flour", "item_eggs", "item_milk", "item_frying_pan", "item_lighter"]))
	assert_eq(_has("item_pancakes"), 3)
	assert_eq(_has("item_frying_pan"), 1, "the pan stays")
	Game.player.stats.hunger = 0.9
	assert_ok(Game.use_item("item_pancakes"))
	assert_lt(Game.player.stats.get_meter("hunger"), 0.9)


func test_cannabis_butter_and_brownies_are_a_chain_through_a_pan() -> void:
	for item_id: String in ["item_butter", "item_cannabis_ground", "item_frying_pan", "item_matches", "item_flour", "item_sugar", "item_eggs"]:
		_bag(item_id)
	assert_ok(Game.craft(["item_butter", "item_cannabis_ground", "item_frying_pan", "item_matches"]))
	assert_eq(_has("item_cannabis_butter"), 1)
	assert_ok(Game.craft(["item_cannabis_butter", "item_flour", "item_sugar", "item_eggs", "item_frying_pan", "item_matches"]))
	assert_eq(_has("item_cannabis_brownie"), 3)
	assert_ok(Game.use_item("item_cannabis_brownie"))
	assert_gt(Game.player.stats.get_meter("intoxication"), 0.0)


func test_the_bong_and_the_spliff() -> void:
	for item_id: String in ["item_empty_bottle", "item_pipe", "item_cannabis_bud", "item_lighter", "item_cigarette", "item_cannabis_ground"]:
		_bag(item_id)
	assert_ok(Game.craft(["item_empty_bottle", "item_pipe"]))
	assert_ok(Game.craft(["item_bong", "item_cannabis_bud"]))
	assert_ok(Game.use_item("item_bong_loaded"))
	assert_eq(_has("item_bong"), 1, "the bong stays")
	assert_ok(Game.craft(["item_cigarette", "item_cannabis_ground"]))
	assert_ok(Game.use_item("item_spliff"))


func test_a_spoon_can_be_wiped_clean_at_any_step() -> void:
	for step: String in ["item_spoon_powder", "item_spoon_liquid", "item_spoon_cooked"]:
		Game.player.inventory.clear()
		_bag(step)
		_bag("item_cloth")
		assert_ok(Game.craft([step, "item_cloth"]))
		assert_eq(_has("item_spoon"), 1, step)
		assert_eq(_has("item_cloth"), 0)


func test_weapons_you_make_are_weapons() -> void:
	for item_id: String in ["item_stick", "item_tape", "item_nails", "item_nails", "item_nails", "item_kitchen_knife", "item_screwdriver", "item_iron_pipe", "item_sock", "item_brick"]:
		_bag(item_id)
	assert_ok(Game.craft(["item_stick", "item_nails", "item_nails", "item_nails"]))
	assert_ok(Game.craft(["item_screwdriver", "item_tape"]))
	assert_ok(Game.craft(["item_sock", "item_brick"]))
	for made: String in ["item_nail_club", "item_shiv", "item_sock_brick"]:
		assert_eq(_has(made), 1, made)
		assert_gt(ItemRules.damage_of(Game.data.get_entry("items", made)), 0.05, made)
	assert_eq(Game.fights.wielded_weapon(), "item_nail_club", "the best of them is in your hand")


func test_every_ingredient_can_be_found_somewhere() -> void:
	var obtainable := {}
	for shop_id: String in Game.data.ids("shops"):
		for item_id: String in Game.data.get_entry("shops", shop_id)["stock"]:
			obtainable[item_id] = true
	for entry: Dictionary in Game.data.get_entry("bins", Bins.DEFINITION)["loot"]:
		obtainable[str(entry["item"])] = true
	for background_id: String in Game.data.ids("backgrounds"):
		for entry: Dictionary in Game.data.get_entry("backgrounds", background_id).get("items", []):
			obtainable[str(entry["id"])] = true
	for recipe_id: String in Game.data.ids("recipes"):
		for item_id: String in CraftRules.outputs_of(Game.data.get_entry("recipes", recipe_id)):
			obtainable[item_id] = true
	for recipe_id: String in Game.data.ids("recipes"):
		var recipe := Game.data.get_entry("recipes", recipe_id)
		for item_id: String in CraftRules.ingredients_of(recipe):
			assert_true(obtainable.has(item_id), "%s needs %s, which nothing gives" % [recipe_id, item_id])
		for item_id: String in CraftRules.outputs_of(recipe):
			assert_true(Game.data.has_entry("items", item_id))


func test_no_two_recipes_make_the_grid_ambiguous() -> void:
	# every recipe, laid out as its own ingredients, finds itself
	var recipes := Game.data.table("recipes")
	for recipe_id: String in recipes:
		var laid: Array = []
		var ingredients := CraftRules.ingredients_of(recipes[recipe_id])
		for item_id: String in ingredients:
			for n in int(ingredients[item_id]):
				laid.append(item_id)
		assert_eq(CraftRules.find(recipes, laid).get("id", ""), recipe_id, "%s does not find itself" % recipe_id)
