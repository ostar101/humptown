extends TestCase
## Theft and its witnesses (D-051): who might notice, what a witness does
## about it, and how far it gets — a crime is only what someone saw.

var _rejected: Array[String] = []
var _committed: Array[String] = []
var _reported: Array[String] = []
var _deeds: Array[String] = []


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_rejected = []
	_committed = []
	_reported = []
	_deeds = []
	Events.action_rejected.connect(_on_rejected)
	Events.crime_committed.connect(_on_committed)
	Events.crime_reported.connect(_on_reported)
	Events.player_deed.connect(_on_deed)


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)
	Events.crime_committed.disconnect(_on_committed)
	Events.crime_reported.disconnect(_on_reported)
	Events.player_deed.disconnect(_on_deed)
	if Game.is_shopping():
		Game.close_shop()


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


func _on_committed(fact_id: String, _location: String) -> void:
	_committed.append(fact_id)


func _on_reported(_fact_id: String, reporter: String, officer: String) -> void:
	_reported.append("%s>%s" % [reporter, officer])


func _on_deed(kind: String, _data: Dictionary) -> void:
	_deeds.append(kind)


## Into the corner shop with Ida behind the counter and nobody else about.
func _at_idas_counter() -> void:
	for npc_id: String in Game.npcs.living_ids():
		var npc := Game.npcs.get_npc(npc_id)
		npc.location = npc.home
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))
	assert_ok(Game.open_shop())


func _also_here(npc_id: String) -> void:
	var npc := Game.npcs.get_npc(npc_id)
	npc.location = "loc_corner_shop"
	npc.activity = "idle"


## The next dice fall as told: `true` is a roll that notices anything above
## the floor chance, `false` one that misses everything below the ceiling.
func _rig(rolls: Array[bool]) -> void:
	var stream := Game.rng.stream("theft")
	for seed_value in range(1, 20000):
		stream.seed = seed_value
		var fits := true
		for notices in rolls:
			var roll := stream.randf()
			fits = fits and (roll < 0.03 if notices else roll > 0.96)
		if fits:
			stream.seed = seed_value
			return
	assert_true(false, "no seed gives that sequence")


# --- the rules ---------------------------------------------------------------------------------

func test_who_notices_depends_on_their_post_their_character_and_your_skill() -> void:
	var staff := TheftRules.notice_chance(true, [], 1)
	var bystander := TheftRules.notice_chance(false, [], 1)
	assert_gt(staff, bystander, "someone on duty is watching")
	assert_gt(TheftRules.notice_chance(true, ["observant"], 1), staff)
	assert_lt(TheftRules.notice_chance(false, ["poor_eyesight"], 1), bystander)
	assert_lt(TheftRules.notice_chance(true, [], 60), staff, "practice helps")
	assert_gt(TheftRules.notice_chance(true, [], 1, 0.5), staff, "drunk or exhausted hands are clumsier")
	assert_eq(TheftRules.notice_chance(true, [], 99), TheftRules.MIN_NOTICE, "floored")
	assert_true(TheftRules.notice_chance(true, ["observant", "by_the_book"], 1, 0.5) <= TheftRules.MAX_NOTICE, "and never certain")
	assert_true(TheftRules.notice_chance(false, ["poor_eyesight"], 99) >= TheftRules.MIN_NOTICE, "nor ever impossible")


func _facts(watchers: Array[Dictionary], overrides: Dictionary = {}) -> Dictionary:
	var facts := {"serving": true, "sells": true, "stock": 3, "weight": 0.3, "free_weight": 5.0, "watchers": watchers}
	facts.merge(overrides, true)
	return facts


func test_theft_is_judged_against_who_saw() -> void:
	var nobody: Array[Dictionary] = [
		{"id": "npc_ida", "is_staff": true, "chance": 0.5, "roll": 0.9},
		{"id": "npc_elias", "is_staff": false, "chance": 0.3, "roll": 0.9},
	]
	var clean: Dictionary = TheftRules.judge(_facts(nobody)).value
	assert_eq(clean, {"noticed_by": [], "caught": false, "taken": true})
	var bystander: Array[Dictionary] = [
		{"id": "npc_ida", "is_staff": true, "chance": 0.5, "roll": 0.9},
		{"id": "npc_elias", "is_staff": false, "chance": 0.3, "roll": 0.1},
	]
	var seen: Dictionary = TheftRules.judge(_facts(bystander)).value
	assert_eq(seen["noticed_by"], ["npc_elias"])
	assert_false(seen["caught"])
	assert_true(seen["taken"], "a bystander does not stop you")
	var behind_the_counter: Array[Dictionary] = [
		{"id": "npc_ida", "is_staff": true, "chance": 0.5, "roll": 0.1},
		{"id": "npc_elias", "is_staff": false, "chance": 0.3, "roll": 0.1},
	]
	var caught: Dictionary = TheftRules.judge(_facts(behind_the_counter)).value
	assert_true(caught["caught"])
	assert_false(caught["taken"], "the one on duty stops it")
	assert_eq(caught["noticed_by"].size(), 2, "and everyone who saw remembers")


func test_theft_refusals() -> void:
	var none: Array[Dictionary] = []
	assert_err(TheftRules.judge(_facts(none, {"serving": false})), "nobody_serving")
	assert_err(TheftRules.judge(_facts(none, {"sells": false})), "not_sold_here")
	assert_err(TheftRules.judge(_facts(none, {"stock": 0})), "out_of_stock")
	assert_err(TheftRules.judge(_facts(none, {"weight": 9.0})), "too_heavy")
	assert_eq(TheftRules.judge(_facts(none, {"stock": 0})).code, "out_of_stock")


func test_what_a_theft_is_worth_and_who_tells() -> void:
	assert_lt(TheftRules.severity(5), TheftRules.severity(80), "a bun is petty, a tool is not")
	assert_true(TheftRules.severity(5) >= 0.25 and TheftRules.severity(5000) <= 0.85)
	var petty := TheftRules.severity(5)
	assert_false(TheftRules.will_report(TheftRules.report_urge(petty, false, 0.0, [])), "a bystander shrugs at a bun")
	assert_true(TheftRules.will_report(TheftRules.report_urge(petty, true, 0.0, [])), "the one who stopped you tells")
	assert_false(TheftRules.will_report(TheftRules.report_urge(petty, true, 0.6, [])), "unless they are fond of you")
	assert_true(TheftRules.will_report(TheftRules.report_urge(petty, false, 0.0, ["by_the_book"])), "or go by the book")
	assert_false(TheftRules.will_report(TheftRules.report_urge(petty, true, 0.2, ["discreet"])), "or keep things to themselves")
	assert_true(TheftRules.will_report(TheftRules.report_urge(TheftRules.severity(150), false, 0.0, [])), "a costly thing is not a shrug")
	for i in 20:
		var delay := TheftRules.report_delay("npc_ida", "fact_%d" % i)
		assert_true(delay >= TheftRules.REPORT_MIN_DELAY and delay < TheftRules.REPORT_MIN_DELAY + TheftRules.REPORT_DELAY_SPREAD)


# --- at the counter ----------------------------------------------------------------------------

func test_unseen_leaves_nothing_behind() -> void:
	_at_idas_counter()
	_rig([false])
	var stock := Game.shops.stock_of("shop_corner", "item_sandwich")
	var cash := Game.player.wallet.cash
	var affection := Game.relationships.peek("npc_ida", PlayerState.ID)
	var before := affection.affection if affection != null else 0.0
	var stole := Game.steal("item_sandwich")
	assert_ok(stole)
	assert_true(stole.value["taken"])
	assert_false(stole.value["caught"])
	assert_eq(Game.player.inventory.count_of("item_sandwich"), 1)
	assert_eq(Game.shops.stock_of("shop_corner", "item_sandwich"), stock - 1, "it came off the shelf")
	assert_eq(Game.player.wallet.cash, cash, "and nothing was paid")
	assert_eq(_committed, [] as Array[String], "no one saw, so no crime happened")
	assert_eq(Game.knowledge.what_is_known_about("npc_ida", PlayerState.ID), [] as Array[Dictionary])
	var after := Game.relationships.peek("npc_ida", PlayerState.ID)
	assert_eq(after.affection if after != null else 0.0, before)
	assert_has(_deeds, "stole")


func test_being_caught_leaves_the_item_and_a_witness() -> void:
	_at_idas_counter()
	Game.relationships.get_edge("npc_ida", PlayerState.ID).affection = 0.0
	_rig([true])
	var trust := Game.relationships.get_edge("npc_ida", PlayerState.ID).trust
	var stole := Game.steal("item_sandwich")
	assert_ok(stole)
	assert_true(stole.value["caught"])
	assert_false(stole.value["taken"])
	assert_eq(Game.player.inventory.count_of("item_sandwich"), 0)
	assert_eq(Game.shops.stock_of("shop_corner", "item_sandwich"), 12, "it goes back on the shelf")
	var known := Game.knowledge.what_is_known_about("npc_ida", PlayerState.ID)
	assert_eq(known[0]["predicate"], "stole_from")
	assert_true(known[0]["firsthand"], "she saw it herself")
	assert_lt(Game.relationships.peek("npc_ida", PlayerState.ID).affection, 0.0)
	assert_lt(Game.relationships.peek("npc_ida", PlayerState.ID).trust, trust)
	assert_eq(_committed.size(), 1)
	assert_false(Game.memories.recall("npc_ida", Game.clock.total_minutes, func(_l: String) -> String: return "").is_empty(), "and she remembers")


func test_a_bystander_who_sees_lets_it_happen_and_does_not_tell() -> void:
	_at_idas_counter()
	_also_here("npc_elias")
	var order: Array[String] = []
	for w in Game.crime.watchers("loc_corner_shop", "npc_ida", 1, 1.0):
		order.append(str(w["id"]))
	assert_eq(order, ["npc_elias", "npc_ida"], "dice fall in a fixed order")
	_rig([true, false])   # Elias notices, Ida does not
	var stole := Game.steal("item_sandwich")
	assert_true(stole.value["taken"])
	assert_false(stole.value["caught"])
	assert_eq(Game.knowledge.what_is_known_about("npc_elias", PlayerState.ID)[0]["predicate"], "stole_from")
	assert_eq(Game.knowledge.what_is_known_about("npc_ida", PlayerState.ID), [] as Array[Dictionary], "the shopkeeper never knew")
	var reports := Game.events_queue.pending().filter(func(e: WorldEventQueue.QueuedEvent) -> bool: return e.kind == "crime_report")
	assert_eq(reports.size(), 0, "a bun is not worth a bystander's trip to the police post")


func test_the_one_who_stopped_you_tells_the_police_later_and_they_come_to_know() -> void:
	_at_idas_counter()
	Game.relationships.get_edge("npc_ida", PlayerState.ID).affection = 0.0
	_rig([true])
	Game.steal("item_sandwich")
	var reports := Game.events_queue.pending().filter(func(e: WorldEventQueue.QueuedEvent) -> bool: return e.kind == "crime_report")
	assert_eq(reports.size(), 1)
	var fact_id := str(reports[0].payload["fact"])
	assert_false(Game.knowledge.knows("npc_marika", fact_id), "not yet")
	Game.pause_time(false)
	Game.clock.advance_to(reports[0].at + 1)
	Game.pause_time(true)
	assert_true(Game.knowledge.knows("npc_marika", fact_id), "the constable has been told")
	assert_eq(_reported, ["npc_ida>npc_marika"] as Array[String])
	var belief := Game.knowledge.belief_of("npc_marika", fact_id)
	assert_false(belief.is_firsthand(), "she has it from Ida, not from the shop")
	assert_lt(belief.confidence, 1.0, "and is a little less sure for it")
	assert_eq(Game.knowledge.what_is_known_about("npc_marika", PlayerState.ID)[0]["predicate"], "stole_from")


func test_a_friend_who_caught_you_lets_it_go() -> void:
	_at_idas_counter()
	Game.relationships.get_edge("npc_ida", PlayerState.ID).affection = 0.7
	_rig([true])
	Game.steal("item_sandwich")
	assert_true(Game.knowledge.knows("npc_ida", Game.knowledge.known_fact_ids("npc_ida")[0]), "she saw")
	var reports := Game.events_queue.pending().filter(func(e: WorldEventQueue.QueuedEvent) -> bool: return e.kind == "crime_report")
	assert_eq(reports.size(), 0, "but she is fond of you")


func test_an_officer_who_sees_it_needs_no_report() -> void:
	_at_idas_counter()
	_also_here("npc_marika")
	assert_eq(Game.crime.officers(), ["npc_marika"] as Array[String])
	var order: Array[String] = []
	for w in Game.crime.watchers("loc_corner_shop", "npc_ida", 1, 1.0):
		order.append(str(w["id"]))
	assert_eq(order, ["npc_ida", "npc_marika"])
	_rig([false, true])   # Ida misses, Marika sees
	Game.steal("item_sandwich")
	var known := Game.knowledge.what_is_known_about("npc_marika", PlayerState.ID)
	assert_eq(known[0]["predicate"], "stole_from")
	assert_true(known[0]["firsthand"], "she saw it herself")
	var reports := Game.events_queue.pending().filter(func(e: WorldEventQueue.QueuedEvent) -> bool: return e.kind == "crime_report")
	assert_eq(reports.size(), 0)


func test_practice_improves_the_odds_and_what_it_takes() -> void:
	_at_idas_counter()
	var level := Game.player.skills.level_of("stealth")
	var xp := Game.player.skills.xp_of("stealth")
	_rig([false])
	Game.steal("item_sandwich")
	assert_gt(Game.player.skills.xp_of("stealth"), xp, "a clean lift teaches the most")
	assert_true(Game.player.skills.level_of("stealth") >= level)
	var clean_xp := Game.player.skills.xp_of("stealth") - xp
	var mark := Game.player.skills.xp_of("stealth")
	_rig([true])
	Game.steal("item_sandwich")
	assert_lt(Game.player.skills.xp_of("stealth") - mark, clean_xp, "and being caught the least")


func test_the_counter_refuses_what_it_cannot_do() -> void:
	assert_eq(Game.steal("item_sandwich").code, "not_shopping")
	_at_idas_counter()
	assert_eq(Game.steal("item_crowbar").code, "not_sold_here")
	Game.shops.sold("shop_corner", "item_sandwich", 12, 0)
	assert_eq(Game.steal("item_sandwich").code, "out_of_stock")
	Game.npcs.get_npc("npc_ida").activity = "idle"
	assert_eq(Game.steal("item_beer").code, "nobody_serving")
	assert_eq(_rejected, ["not_shopping", "not_sold_here", "out_of_stock", "nobody_serving"] as Array[String])


func test_the_dice_are_the_games_and_a_reload_lifts_the_same() -> void:
	_at_idas_counter()
	_rig([false])
	var first := Game.rng.stream("theft").randf()
	_rig([false])
	assert_eq(Game.rng.stream("theft").randf(), first, "the same stream, the same throw")


# --- the window --------------------------------------------------------------------------------------

func test_the_window_offers_it_and_says_only_what_you_can_tell() -> void:
	_at_idas_counter()
	Game.close_shop()
	var window: ShopWindow = (load("res://scenes/ui/shop_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	assert_ok(window.open())
	_rig([false])
	assert_ok(window.steal("item_sandwich"))
	assert_eq(window.message(), "You slip the Sandwich into your pocket.")
	Game.relationships.get_edge("npc_ida", PlayerState.ID).affection = 0.0
	_rig([true])
	assert_ok(window.steal("item_sandwich"))
	assert_true(window.message().begins_with("Shopkeeper catches your hand"), window.message())   # you have not been introduced
	assert_err(window.steal("item_crowbar"))
	assert_eq(window.message(), "They don't sell that here.")
	window.close()
	window.free()
