extends TestCase
## Haggling against the skill (D-040): who is hard to talk down, the odds,
## what a roll means, and what winning or losing does at the counter.

var _rejected: Array[String] = []


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_rejected = []
	Events.action_rejected.connect(_on_rejected)


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)
	if Game.is_shopping():
		Game.close_shop()


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


func _at_the_counter(location_id: String, npc_id: String) -> void:
	var keeper := Game.npcs.get_npc(npc_id)
	keeper.location = location_id
	keeper.activity = "work"
	Game.player.wallet.cash = 100
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of(location_id))))
	assert_ok(Game.interact_at(map.buildings[location_id]["door"]))
	assert_ok(Game.open_shop())


func _difficulty_of(npc_id: String) -> int:
	var npc := Game.npcs.get_npc(npc_id)
	return HaggleRules.difficulty(Game.data.get_entry("occupations", npc.occupation).get("skills", []), npc.traits)


# --- the rules ------------------------------------------------------------------------

func test_some_people_are_harder_to_talk_down() -> void:
	var ida := _difficulty_of("npc_ida")
	var leena := _difficulty_of("npc_leena")
	var tuomas := _difficulty_of("npc_tuomas")
	assert_gt(ida, leena, "Ida keeps accounts; Leena is cheerful")
	assert_gt(leena, tuomas, "haggling is a shopkeeper's trade, not a barkeep's")
	assert_eq(tuomas, HaggleRules.BASE_DIFFICULTY)


func test_the_odds_follow_skill_and_feeling() -> void:
	var novice := HaggleRules.chance(1, 30, 0.0)
	var expert := HaggleRules.chance(60, 30, 0.0)
	assert_lt(novice, 0.1)
	assert_gt(expert, 0.9)
	assert_gt(HaggleRules.chance(20, 20, 0.8), HaggleRules.chance(20, 20, 0.0), "a friend gives way")
	assert_true(HaggleRules.chance(99, 1, 1.0) <= 0.95 and HaggleRules.chance(1, 99, -1.0) >= 0.05,
		"never certain, never hopeless")


func test_a_roll_under_the_odds_wins_and_the_margin_sets_the_deal() -> void:
	var facts := {"serving": true, "sells": true, "tried": false, "chance": 0.5}
	facts["roll"] = 0.49
	var close_call: Dictionary = HaggleRules.judge(facts).value
	assert_true(close_call["won"])
	assert_almost(float(close_call["discount"]), HaggleRules.MIN_DISCOUNT, 0.011)
	facts["roll"] = 0.0
	assert_almost(float(HaggleRules.judge(facts).value["discount"]), HaggleRules.MAX_DISCOUNT, 0.001)
	facts["roll"] = 0.5
	assert_false(HaggleRules.judge(facts).value["won"])


func test_haggling_needs_someone_to_haggle_with_and_one_try_a_day() -> void:
	var facts := {"serving": false, "sells": true, "tried": false, "chance": 0.5, "roll": 0.1}
	assert_err(HaggleRules.judge(facts), "nobody_serving")
	facts["serving"] = true
	facts["sells"] = false
	assert_err(HaggleRules.judge(facts), "not_sold_here")
	facts["sells"] = true
	facts["tried"] = true
	assert_err(HaggleRules.judge(facts), "already_haggled")


# --- at the counter -----------------------------------------------------------------------

func test_a_won_discount_lasts_the_day() -> void:
	assert_eq(Game.shops.buy_price("shop_corner", "item_sandwich"), 5)
	Game.shops.record_haggle("shop_corner", "item_sandwich", true, 0.2)
	assert_eq(Game.shops.buy_price("shop_corner", "item_sandwich"), 4)
	Game.shops.restock()
	assert_eq(Game.shops.buy_price("shop_corner", "item_sandwich"), 5, "back to full price at midnight")


func test_haggling_at_the_counter_either_way() -> void:
	_at_the_counter("loc_cafe_kaisla", "npc_leena")
	var price_before := Game.shops.buy_price("shop_kaisla", "item_sandwich")
	var xp_before := Game.player.skills.xp_of("haggling")
	var tried := Game.haggle("item_sandwich")
	assert_ok(tried)
	var outcome: Dictionary = tried.value
	if outcome["won"]:
		assert_true(Game.shops.buy_price("shop_kaisla", "item_sandwich") <= price_before)
		assert_gt(float(outcome["discount"]), 0.0)
	else:
		assert_lt(Game.relationships.peek("npc_leena", PlayerState.ID).affection, 0.0, "a little put out")
	assert_gt(Game.player.skills.xp_of("haggling"), xp_before, "the skill learns either way")
	assert_err(Game.haggle("item_sandwich"), "already_haggled")
	assert_eq(_rejected, ["already_haggled"])


func test_a_master_nearly_always_talks_leena_down() -> void:
	Game.player.skills.levels["haggling"] = 99
	Game.player.skills.xp["haggling"] = Skills.xp_for_level(99)
	_at_the_counter("loc_cafe_kaisla", "npc_leena")
	var won := 0
	for item_id in ["item_sandwich", "item_cinnamon_bun"]:
		if Game.haggle(item_id).value["won"]:
			won += 1
	assert_true(won >= 1, "odds of 0.95 twice; this seed wins at least once")


func test_the_window_offers_haggling_and_says_how_it_went() -> void:
	_at_the_counter("loc_corner_shop", "npc_ida")
	Game.close_shop()
	var window: ShopWindow = (load("res://scenes/ui/shop_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	assert_ok(window.open())
	var tried := window.haggle("item_sandwich")
	assert_ok(tried)
	var expected := "won't budge on the Sandwich." if not tried.value["won"] else "% off the Sandwich."
	assert_true(window.message().contains(expected), window.message())
	window.haggle("item_sandwich")
	assert_eq(window.message(), "You've already haggled over that today.")
	window.close()
	window.free()
