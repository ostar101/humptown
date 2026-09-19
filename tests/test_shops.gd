extends TestCase
## Shops (D-039): what they stock and charge, the rules of buying and
## selling, restocking at midnight, saving, and the counter window — all
## decided by Game and ShopRules, never by the window.

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
	Game.saves.delete_slot("test_shops")


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


## Into the corner shop with Ida behind the counter, and money to spend.
func _at_idas_counter(cash: int = 100) -> void:
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	Game.player.wallet.cash = cash
	Game.player.wallet.bank = 0
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))


# --- the rules -------------------------------------------------------------------------

func _buy_facts(overrides: Dictionary = {}) -> Dictionary:
	var facts := {"serving": true, "sells": true, "stock": 5, "quantity": 1, "price": 5,
		"money": 20, "free_weight": 10.0, "weight": 0.3}
	facts.merge(overrides, true)
	return facts


func test_buying_needs_someone_serving_stock_money_and_room() -> void:
	assert_ok(ShopRules.judge_buy(_buy_facts()))
	assert_eq(ShopRules.judge_buy(_buy_facts({"quantity": 3})).value["total"], 15)
	assert_err(ShopRules.judge_buy(_buy_facts({"serving": false})), "nobody_serving")
	assert_err(ShopRules.judge_buy(_buy_facts({"quantity": 0})), "bad_quantity")
	assert_err(ShopRules.judge_buy(_buy_facts({"sells": false})), "not_sold_here")
	assert_err(ShopRules.judge_buy(_buy_facts({"quantity": 6})), "out_of_stock")
	assert_err(ShopRules.judge_buy(_buy_facts({"money": 4})), "not_enough_money")
	assert_err(ShopRules.judge_buy(_buy_facts({"weight": 11.0})), "too_heavy")


func test_selling_needs_the_thing_a_buyer_and_a_till() -> void:
	var facts := {"serving": true, "buys": true, "owned": 2, "quantity": 2, "price": 3, "till": 10}
	assert_eq(ShopRules.judge_sell(facts).value["total"], 6)
	var not_owned := facts.duplicate()
	not_owned["quantity"] = 3
	assert_err(ShopRules.judge_sell(not_owned), "not_owned")
	var not_bought := facts.duplicate()
	not_bought["buys"] = false
	assert_err(ShopRules.judge_sell(not_bought), "not_bought_here")
	var short := facts.duplicate()
	short["till"] = 5
	assert_err(ShopRules.judge_sell(short), "till_short")


# --- prices and stock ---------------------------------------------------------------

func test_prices_follow_the_items_value_and_the_shops_markup() -> void:
	var shops := Game.shops
	assert_eq(shops.shop_at("loc_corner_shop"), "shop_corner")
	assert_eq(shops.buy_price("shop_corner", "item_sandwich"), 5, "the corner shop sells at value")
	assert_eq(shops.buy_price("shop_kaisla", "item_coffee"), 4, "the café charges for the cup: 3 × 1.2")
	assert_eq(shops.sell_price("shop_corner", "item_beer"), 2, "buys back at 40%, rounded down")
	assert_false(shops.buys("shop_corner", "item_keys"), "nothing worthless is bought")
	assert_false(shops.buys("shop_kaisla", "item_beer"), "a café buys nothing")
	assert_eq(shops.shop_at("loc_clinic"), "", "a counter is not always a shop")


# --- through the game ------------------------------------------------------------------

func test_buying_moves_money_goods_and_stock() -> void:
	_at_idas_counter(20)
	assert_ok(Game.open_shop())
	var stock_before := Game.shops.stock_of("shop_corner", "item_sandwich")
	var till_before := Game.shops.till("shop_corner")
	var bought := Game.buy("item_sandwich", 2)
	assert_ok(bought)
	assert_eq(bought.value["total"], 10)
	assert_eq(Game.player.wallet.cash, 10)
	assert_eq(Game.player.inventory.count_of("item_sandwich"), 2)
	assert_eq(Game.shops.stock_of("shop_corner", "item_sandwich"), stock_before - 2)
	assert_eq(Game.shops.till("shop_corner"), till_before + 10)


func test_a_card_pays_what_cash_cannot() -> void:
	_at_idas_counter(2)
	Game.player.wallet.bank = 50
	assert_ok(Game.open_shop())
	assert_ok(Game.buy("item_sandwich"))
	assert_eq(Game.player.wallet.cash, 0)
	assert_eq(Game.player.wallet.bank, 47)


func test_refusals_change_nothing_and_are_announced() -> void:
	_at_idas_counter(3)
	assert_ok(Game.open_shop())
	assert_err(Game.buy("item_sandwich"), "not_enough_money")
	assert_err(Game.buy("item_toolbox"), "not_sold_here")
	assert_err(Game.sell("item_sandwich"), "not_owned")
	assert_eq(Game.player.wallet.cash, 3)
	assert_eq(Game.player.inventory.count_of("item_sandwich"), 0)
	assert_eq(_rejected, ["not_enough_money", "not_sold_here", "not_owned"])


func test_selling_pays_from_the_till() -> void:
	_at_idas_counter(0)
	Game.player.inventory.add("item_beer", 3)
	assert_ok(Game.open_shop())
	var sold := Game.sell("item_beer", 3)
	assert_ok(sold)
	assert_eq(Game.player.wallet.cash, 6)
	assert_eq(Game.player.inventory.count_of("item_beer"), 0)
	var view := Game.shop_view()
	assert_eq(view["cash"], 6)


func test_no_counter_no_shopping() -> void:
	_at_idas_counter()
	Game.npcs.get_npc("npc_ida").activity = "eat"
	assert_err(Game.open_shop(), "nobody_serving")
	assert_false(Game.is_shopping())
	assert_err(Game.buy("item_sandwich"), "not_shopping")


func test_time_stands_still_while_shopping_and_is_paid_on_leaving() -> void:
	_at_idas_counter()
	Game.pause_time(false)
	assert_ok(Game.open_shop())
	var started := Game.clock.total_minutes
	assert_true(Game.clock.paused)
	assert_ok(Game.buy("item_coffee"))
	assert_ok(Game.buy("item_coffee"))
	assert_ok(Game.close_shop())
	assert_eq(Game.clock.total_minutes, started + 2, "a minute a deal")
	assert_false(Game.clock.paused, "the clock goes back to how it was")


func test_shelves_and_till_are_restored_at_midnight() -> void:
	_at_idas_counter(200)
	assert_ok(Game.open_shop())
	assert_ok(Game.buy("item_bandage", 6))
	assert_err(Game.buy("item_bandage"), "out_of_stock")
	assert_ok(Game.close_shop())
	Game.advance_time(GameClock.MINUTES_PER_DAY)
	assert_eq(Game.shops.stock_of("shop_corner", "item_bandage"), 6)
	assert_eq(Game.shops.till("shop_corner"), 300)


func test_shelves_and_tills_are_saved() -> void:
	_at_idas_counter(50)
	assert_ok(Game.open_shop())
	assert_ok(Game.buy("item_notebook", 2))
	assert_ok(Game.close_shop())
	var stock := Game.shops.stock_of("shop_corner", "item_notebook")
	var till := Game.shops.till("shop_corner")
	assert_ok(Game.save_game("test_shops"))
	assert_ok(Game.load_game("test_shops"))
	Game.pause_time(true)
	assert_eq(Game.shops.stock_of("shop_corner", "item_notebook"), stock)
	assert_eq(Game.shops.till("shop_corner"), till)


func test_a_version_2_save_gains_fresh_shops() -> void:
	var migrated := SaveMigrations.migrate({"schema_version": 2, "memories": {"books": {}}})
	assert_ok(migrated)
	assert_eq(migrated.value["shops"], {"shops": {}})
	var shops := ShopRegistry.new()
	var data := DataRegistry.new()
	data.load_all()
	shops.setup(data)
	shops.from_dict(migrated.value["shops"])
	assert_eq(shops.stock_of("shop_corner", "item_sandwich"), 12, "a shop the save never saw opens as usual")


# --- the counter window --------------------------------------------------------------------

func test_the_window_lists_the_shelves_and_buys_through_the_rules() -> void:
	_at_idas_counter(5)
	var window: ShopWindow = (load("res://scenes/ui/shop_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	assert_ok(window.open())
	assert_true(window.is_open())
	assert_has(window.row_texts(), "Sandwich|€5|12 left")
	assert_ok(window.buy("item_sandwich"))
	assert_eq(window.message(), "You bought Sandwich for €5.")
	assert_has(window.row_texts(), "Sandwich|€5|11 left")
	assert_err(window.buy("item_beer"), "not_enough_money")
	assert_eq(window.message(), "You can't afford that.")
	window.show_selling(true)
	assert_has(window.row_texts(), "Sandwich|€2|You have 1")
	window.close()
	assert_false(Game.is_shopping())
	window.free()
