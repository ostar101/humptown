extends TestCase
## Meals and the condition loop (D-041): using what you carry, the body
## keeping accounts, collapsing when health runs out, and the HUD and bag
## saying how you are.

var _collapses: Array[Dictionary] = []


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_collapses = []
	Events.player_collapsed.connect(_on_collapsed)


func after_each() -> void:
	Events.player_collapsed.disconnect(_on_collapsed)


func _on_collapsed(woke_at: String, bill: int) -> void:
	_collapses.append({"at": woke_at, "bill": bill})


func _item(id: String) -> Dictionary:
	return Game.data.get_entry("items", id)


# --- the rules --------------------------------------------------------------------------

func test_what_can_be_used_and_what_it_does() -> void:
	var fed := {"hunger": 0.5, "health": 1.0}
	var sandwich := ItemRules.judge_use(_item("item_sandwich"), 1, fed)
	assert_ok(sandwich)
	assert_eq(sandwich.value["effects"], {"hunger": -0.4})
	assert_eq(sandwich.value["minutes"], 10)
	assert_err(ItemRules.judge_use(_item("item_sandwich"), 0, fed), "not_owned")
	assert_err(ItemRules.judge_use(_item("item_crowbar"), 1, fed), "not_usable")
	assert_err(ItemRules.judge_use(_item("item_sandwich"), 1, {"hunger": 0.05}), "not_hungry")
	assert_err(ItemRules.judge_use(_item("item_bandage"), 1, {"health": 1.0}), "not_hurt")
	assert_ok(ItemRules.judge_use(_item("item_coffee"), 1, {"hunger": 0.0}), "coffee is not food for the stomach")


# --- through the game ----------------------------------------------------------------------

func test_eating_feeds_you_uses_it_up_and_takes_a_while() -> void:
	Game.player.inventory.add("item_sandwich", 2)
	Game.player.stats.hunger = 0.7
	var started := Game.clock.total_minutes
	assert_ok(Game.use_item("item_sandwich"))
	assert_almost(Game.player.stats.hunger, 0.3, 0.01)
	assert_eq(Game.player.inventory.count_of("item_sandwich"), 1)
	assert_eq(Game.clock.total_minutes, started + 10)


func test_not_now_while_talking_or_shopping() -> void:
	Game.player.inventory.add("item_sandwich")
	Game.player.stats.hunger = 0.7
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))
	assert_ok(Game.open_shop())
	assert_err(Game.use_item("item_sandwich"), "busy")
	Game.close_shop()
	assert_ok(Game.use_item("item_sandwich"))


func test_hunger_comes_back_over_a_waking_day() -> void:
	var stats := Stats.new()
	stats.hunger = 0.0
	stats.drift(300, "idle")
	assert_almost(stats.hunger, 0.5, 0.01, "half-hungry after five hours")


func test_going_without_costs_health_and_nerves() -> void:
	var stats := Stats.new()
	stats.hunger = 1.0
	stats.drift(360, "idle")
	assert_lt(stats.health, 1.0, "starving hurts")
	var tired := Stats.new()
	tired.sleep = 0.0
	tired.drift(240, "idle")
	assert_gt(tired.stress, 0.4, "exhaustion frays the nerves")
	assert_lt(tired.health, 1.0)


## Played: health lost to one hungry evening never came back, so every hungry
## night after it ended at the clinic (D-090).
func test_a_fed_body_mends_itself_and_a_night_mends_it_most() -> void:
	var awake := Stats.new()
	awake.health = 0.4
	awake.drift(300, "idle")
	assert_gt(awake.health, 0.45, "five waking hours, fed: better")
	var slept := Stats.new()
	slept.health = 0.4
	slept.hunger = 0.3
	slept.sleep = 0.4
	slept.drift(480, "sleep")
	assert_gt(slept.health, 0.7, "a night's sleep gives back most")
	var starving := Stats.new()
	starving.health = 0.4
	starving.hunger = 1.0
	starving.drift(480, "sleep")
	assert_lt(starving.health, 0.4, "nobody mends while starving")


func test_an_open_wound_caps_what_rest_can_give_back() -> void:
	var stats := Stats.new()
	stats.add_injury("cracked_rib", "torso", 0.3, 10_000)
	assert_almost(stats.health_cap(), 0.85, 0.001)
	stats.health = 0.5
	stats.drift(600, "sleep")
	assert_almost(stats.health, 0.85, 0.001, "mended as far as the rib allows")
	stats.heal_expired_injuries(20_000)
	stats.hunger = 0.0
	stats.drift(120, "sleep")
	assert_gt(stats.health, 0.85, "and past it once it has healed")


func test_a_night_after_a_light_supper_is_not_a_night_of_starving() -> void:
	var stats := Stats.new()
	stats.hunger = 0.55   # hungry-ish at bedtime
	stats.drift(8 * 60, "sleep")
	assert_lt(stats.hunger, Stats.STARVING, "wakes wanting breakfast, not starving")
	assert_eq(stats.health, 1.0, "and none the worse for it")


func test_weak_is_not_hurt() -> void:
	Game.player.stats.health = 0.5
	assert_eq(StatusText.condition(), "Weak", "no wound, so no injury")
	Game.player.stats.health = 0.2
	assert_eq(StatusText.condition(), "Very weak")
	Game.player.stats.add_injury("bruise", "arm", 0.12, Game.clock.total_minutes + 60)
	assert_eq(StatusText.condition(), "Badly hurt", "a wound is an injury")


func test_running_out_of_health_wakes_you_in_the_clinic_billed() -> void:
	Game.player.wallet.cash = 100
	Game.player.wallet.bank = 0
	Game.player.stats.health = 0.01
	Game.player.stats.hunger = 1.0
	Game.advance_time(120)
	assert_eq(_collapses.size(), 1, "once")
	assert_eq(_collapses[0]["at"], Game.CLINIC)
	assert_eq(Game.player.interior, Game.CLINIC)
	assert_eq(Game.clock.minute_of_day(), Game.COLLAPSE_WAKE_MINUTE, "the next morning")
	assert_almost(Game.player.stats.health, 0.35, 0.001)
	assert_eq(Game.player.wallet.cash, 100 - Game.CLINIC_BILL)


func test_the_clinic_takes_only_what_you_have() -> void:
	Game.player.wallet.cash = 12
	Game.player.wallet.bank = 0
	Game.player.stats.health = 0.001
	Game.player.stats.hunger = 1.0
	Game.advance_time(60)
	assert_eq(_collapses.size(), 1)
	assert_eq(_collapses[0]["bill"], 12)
	assert_eq(Game.player.wallet.cash, 0)


func test_a_hungry_tired_haggler_haggles_worse() -> void:
	assert_lt(HaggleRules.chance(20, 20, 0.0, 0.6), HaggleRules.chance(20, 20, 0.0, 1.0))


# --- what you see -----------------------------------------------------------------------------

func test_the_status_says_when_where_money_and_only_what_matters() -> void:
	Game.player.wallet.cash = 23
	assert_true(StatusText.line().contains("07:00"), StatusText.line())
	assert_true(StatusText.line().contains("€23"), StatusText.line())
	assert_eq(StatusText.condition(), "", "fine is not worth saying")
	Game.player.stats.hunger = 0.8
	Game.player.stats.sleep = 0.2
	assert_eq(StatusText.condition(), "Hungry · Tired")
	Game.player.stats.hunger = 0.97
	assert_true(StatusText.condition().begins_with("Starving"), "the worse word, once")


func test_the_hud_keeps_the_status_current() -> void:
	var hud: Hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	Game.player.wallet.add_cash(5)
	assert_true(hud.status_text().contains("€%d" % Game.player.wallet.cash), hud.status_text())
	Game.player.stats.modify("hunger", 0.9)
	assert_true(hud.status_text().contains("Hungry") or hud.status_text().contains("Starving"), hud.status_text())
	hud.free()


func test_the_bag_lists_what_you_carry_and_uses_it() -> void:
	Game.player.inventory.add("item_sandwich", 2)
	Game.player.stats.hunger = 0.5
	var bag: ItemsWindow = (load("res://scenes/ui/items_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(bag)
	Game.pause_time(false)
	bag.open()
	assert_true(Game.clock.paused, "time stands still in the bag")
	assert_has(bag.row_texts(), "Sandwich|× 2|0.6 kg")
	assert_ok(bag.use("item_sandwich"))
	assert_eq(bag.message(), "You eat the Sandwich.")
	assert_has(bag.row_texts(), "Sandwich|× 1|0.3 kg")
	assert_err(bag.use("item_sandwich"), "not_hungry")
	assert_eq(bag.message(), "You're not hungry.")
	bag.close()
	assert_false(Game.clock.paused, "and moves again when it closes")
	bag.free()
