extends TestCase
## Consequences for illicit dealing (M8 step 10, D-086): one predicate, not
## one per commodity — an item's own heat carries the difference; the
## keeper is never a witness of their own sale; an ordinary shop is never
## watched for it at all.

var _committed: Array[String] = []


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_committed = []
	Events.crime_committed.connect(_on_committed)


func after_each() -> void:
	Events.crime_committed.disconnect(_on_committed)
	if Game.is_shopping():
		Game.close_shop()


func _on_committed(fact_id: String, _location: String) -> void:
	_committed.append(fact_id)


# --- ItemRules.heat_of -------------------------------------------------------

func test_heat_defaults_by_kind() -> void:
	assert_eq(ItemRules.heat_of({"kind": "drug"}), 0.4)
	assert_eq(ItemRules.heat_of({"kind": "weapon"}), 0.5)
	assert_eq(ItemRules.heat_of({"kind": "food"}), 0.25)
	assert_eq(ItemRules.heat_of({}), 0.25)


func test_an_authored_heat_overrides_the_kind_default() -> void:
	assert_eq(ItemRules.heat_of({"kind": "drug", "heat": 0.9}), 0.9)
	assert_eq(ItemRules.heat_of({"kind": "misc", "heat": 1.5}), 1.0, "clamped")


# --- Reputation and CrimeDirector --------------------------------------------

func test_dealing_is_a_crime_the_police_act_on() -> void:
	assert_has(CrimeDirector.CRIME_PREDICATES, "dealt_illicit")


func test_reputation_weighs_dealing_and_vouching_by_scope() -> void:
	assert_lt(float(Reputation.DEFAULT_WEIGHTS["dealt_illicit"]), 0.0)
	assert_gt(float(Reputation.DEFAULT_WEIGHTS["vouched_for"]), 0.0)
	var criminal: Dictionary = Reputation.SCOPE_MODIFIERS["criminal"]
	var police: Dictionary = Reputation.SCOPE_MODIFIERS["police"]
	assert_gt(float(criminal["dealt_illicit"]), float(Reputation.DEFAULT_WEIGHTS["dealt_illicit"]), "criminals mind it less")
	assert_lt(float(police["dealt_illicit"]), float(Reputation.DEFAULT_WEIGHTS["dealt_illicit"]), "the police mind it more")
	assert_gt(float(criminal["vouched_for"]), float(Reputation.DEFAULT_WEIGHTS["vouched_for"]), "means more from one of their own")


# --- through the game ---------------------------------------------------------

## The next draw from the "deal" stream notices (`true`) or misses (`false`)
## each watcher in turn, same rigging trick `test_theft.gd` uses for "theft".
func _rig_deal(rolls: Array[bool]) -> void:
	var stream := Game.rng.stream("deal")
	for seed_value in range(1, 20000):
		stream.seed = seed_value
		var fits := true
		for notices in rolls:
			var roll := stream.randf()
			fits = fits and (roll < 0.05 if notices else roll > 0.95)
		if fits:
			stream.seed = seed_value
			return
	assert_true(false, "no seed gives that sequence")


## Rauno alone on Dock Street, indiscreet enough that a bystander's chance
## of noticing sits well clear of the floor — the point is a reliable roll,
## not a realistic dealer.
func _deal_with_rauno() -> void:
	for npc_id: String in Game.npcs.living_ids():
		var npc := Game.npcs.get_npc(npc_id)
		npc.location = npc.home
	var rauno := Game.npcs.get_npc("npc_rauno")
	rauno.location = "loc_dock_street"
	rauno.activity = "idle"
	rauno.nature["discretion"] = 0.0
	Game.player.wallet.cash = 500
	assert_ok(Game.open_deal_shop("npc_rauno", "shop_warehouse_stash"))


func test_the_keeper_alone_leaves_no_trace() -> void:
	_deal_with_rauno()
	var item_id: String = Game.shops.items_for_sale("shop_warehouse_stash")[0]
	assert_ok(Game.buy(item_id))
	assert_eq(_committed, [] as Array[String], "a dealer is never a witness of their own sale")


func test_a_bystander_who_misses_leaves_no_trace() -> void:
	_deal_with_rauno()
	var elias := Game.npcs.get_npc("npc_elias")
	elias.location = "loc_dock_street"
	elias.activity = "idle"
	_rig_deal([false])
	var item_id: String = Game.shops.items_for_sale("shop_warehouse_stash")[0]
	assert_ok(Game.buy(item_id))
	assert_eq(_committed, [] as Array[String])


func test_a_witnessed_deal_is_a_crime_the_keeper_never_reports() -> void:
	_deal_with_rauno()
	var elias := Game.npcs.get_npc("npc_elias")
	elias.location = "loc_dock_street"
	elias.activity = "idle"
	_rig_deal([true])
	var item_id: String = Game.shops.items_for_sale("shop_warehouse_stash")[0]
	assert_ok(Game.buy(item_id))
	assert_eq(_committed.size(), 1)
	var known := Game.knowledge.what_is_known_about("npc_elias", PlayerState.ID)
	assert_eq(known[0]["predicate"], "dealt_illicit")
	assert_eq(Game.knowledge.what_is_known_about("npc_rauno", PlayerState.ID), [] as Array[Dictionary],
		"the dealer is never a witness of their own sale")


func test_a_legal_shop_is_never_watched_for_it() -> void:
	for npc_id: String in Game.npcs.living_ids():
		var npc := Game.npcs.get_npc(npc_id)
		npc.location = npc.home
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	var elias := Game.npcs.get_npc("npc_elias")
	elias.location = "loc_corner_shop"
	elias.activity = "idle"
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))
	assert_ok(Game.open_shop())
	assert_ok(Game.buy("item_sandwich"))
	assert_eq(_committed, [] as Array[String])
