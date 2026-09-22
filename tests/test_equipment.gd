extends TestCase
## Worn and wielded (M8 step 4, D-080): six slots, no more; equipping is a
## pointer, not a move; a worn backpack widens the bag, never the cupboard;
## armour softens a blow; a fight's weapon still falls back to the best
## carried thing when nothing is in the hand.


func before_each() -> void:
	Game.new_game("bg_returning", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	Game.player.inventory.clear()


func after_each() -> void:
	Game.saves.delete_slot("test_equipment")


# --- equip / unequip ---------------------------------------------------------

func test_equipping_a_weapon_puts_it_in_the_hand() -> void:
	Game.player.inventory.add("item_puukko", 1)
	var equipped := Game.equip("item_puukko")
	assert_ok(equipped)
	assert_eq(equipped.value["slot"], "hand")
	assert_eq(Game.player.equipment["hand"], "item_puukko")


func test_equipping_something_not_owned_is_refused() -> void:
	assert_err(Game.equip("item_puukko"), "not_owned")


func test_equipping_something_with_no_slot_is_refused() -> void:
	Game.player.inventory.add("item_sandwich", 1)
	assert_err(Game.equip("item_sandwich"), "not_equipable")


func test_unequipping_an_empty_slot_is_refused() -> void:
	assert_err(Game.unequip("hand"), "not_worn")


func test_unequipping_clears_the_slot_but_keeps_the_thing_in_the_bag() -> void:
	Game.player.inventory.add("item_puukko", 1)
	Game.equip("item_puukko")
	var taken_off := Game.unequip("hand")
	assert_ok(taken_off)
	assert_eq(taken_off.value["item"], "item_puukko")
	assert_false(Game.player.equipment.has("hand"))
	assert_eq(Game.player.inventory.count_of("item_puukko"), 1, "still in the bag")


func test_wearing_something_else_in_the_same_slot_just_moves_the_pointer() -> void:
	Game.player.inventory.add("item_puukko", 1)
	Game.player.inventory.add("item_axe", 1)
	Game.equip("item_puukko")
	assert_ok(Game.equip("item_axe"))
	assert_eq(Game.player.equipment["hand"], "item_axe")
	assert_eq(Game.player.inventory.count_of("item_puukko"), 1, "the puukko is not lost, only unworn")


func test_only_six_slots_exist() -> void:
	assert_eq(EquipRules.SLOTS, ["head", "body", "legs", "feet", "hand", "back"] as Array[String])


# --- the leak: losing an equipped thing some other way -----------------------

func test_selling_or_giving_away_a_worn_thing_clears_its_slot() -> void:
	Game.player.inventory.add("item_work_boots", 1)
	Game.equip("item_work_boots")
	assert_eq(Game.player.equipment["feet"], "item_work_boots")
	Game.player.inventory.remove("item_work_boots", 1)   # the way a sale or a gift leaves the bag
	assert_false(Game.player.equipment.has("feet"), "the leak is closed by reconcile_equipment")


# --- the backpack's capacity bonus: inventory only, never the stash ----------

func test_a_worn_backpack_widens_the_bag() -> void:
	Game.player.inventory.add("item_backpack", 1)
	var before := Game.player.inventory.capacity()
	Game.equip("item_backpack")
	assert_almost(Game.player.inventory.capacity(), before + 10.0, 0.001)
	Game.unequip("back")
	assert_almost(Game.player.inventory.capacity(), before, 0.001)


## The capacity bonus must apply to PlayerState.inventory only, never stash:
## a backpack sitting unworn in the cupboard does nothing for what the
## cupboard holds (mirrors the guard on tests/test_home.gd:78-79).
func test_a_backpack_in_the_stash_does_not_widen_the_stash() -> void:
	Game.player.stash.add("item_backpack", 1)
	assert_almost(Game.player.stash.capacity(), PlayerState.STASH_CAPACITY, 0.001)


# --- armour: one multiplicative, capped term ----------------------------------

func test_armour_softens_a_blow() -> void:
	var attacker := {"strength": 5, "weapon": 0.0}
	var bare := {"defending": false}
	var armoured := {"defending": false, "armour": 0.2}
	var against_bare := CombatRules.damage(attacker, bare, false, 0.5)
	var against_armoured := CombatRules.damage(attacker, armoured, false, 0.5)
	assert_lt(against_armoured, against_bare)


func test_armour_never_stops_a_blow_outright() -> void:
	var attacker := {"strength": 5, "weapon": 0.0}
	var heavily_armoured := {"defending": false, "armour": 5.0}
	assert_gt(CombatRules.damage(attacker, heavily_armoured, false, 0.5), 0.0)


func test_worn_boots_soften_what_the_player_takes_in_a_fight() -> void:
	var npc := Game.npcs.get_npc("npc_elias")
	npc.location = Game.player.location
	assert_ok(Game.start_fight("npc_elias"))
	assert_eq(Game.fights.combat.player()["armour"], 0.0, "nothing worn yet")
	Game.fights.combat = null
	Game.fights.last = null
	Game.player.inventory.add("item_work_boots", 1)
	Game.equip("item_work_boots")
	assert_ok(Game.start_fight("npc_elias"))
	assert_almost(Game.fights.combat.player()["armour"], 0.05, 0.0001)


# --- wielded_weapon(): the hand slot first, the scan as a fallback -----------

func test_wielded_weapon_prefers_the_hand_slot_over_a_harder_hitting_bag() -> void:
	Game.player.inventory.add("item_hammer", 1)   # damage 0.07
	Game.player.inventory.add("item_puukko", 1)   # damage 0.13, would win the scan
	Game.equip("item_hammer")
	assert_eq(Game.fights.wielded_weapon(), "item_hammer", "what is in the hand, deliberately chosen")


func test_wielded_weapon_falls_back_to_the_scan_with_an_empty_hand() -> void:
	Game.player.inventory.add("item_hammer", 1)
	Game.player.inventory.add("item_puukko", 1)
	assert_eq(Game.fights.wielded_weapon(), "item_puukko", "the best carried thing, same as before equipment existed")


func test_wielded_weapon_falls_back_when_the_worn_weapon_left_the_bag() -> void:
	Game.player.inventory.add("item_puukko", 1)
	Game.equip("item_puukko")
	Game.player.inventory.remove("item_puukko", 1)
	Game.player.inventory.add("item_hammer", 1)
	assert_eq(Game.fights.wielded_weapon(), "item_hammer", "the hand slot cleared itself; the scan takes over")


# --- persistence --------------------------------------------------------------

func test_equipment_is_saved() -> void:
	Game.player.inventory.add("item_puukko", 1)
	Game.player.inventory.add("item_work_boots", 1)
	Game.equip("item_puukko")
	Game.equip("item_work_boots")
	assert_ok(Game.save_game("test_equipment"))
	Game.player.equipment.clear()
	assert_ok(Game.load_game("test_equipment"))
	assert_eq(Game.player.equipment["hand"], "item_puukko")
	assert_eq(Game.player.equipment["feet"], "item_work_boots")


func test_an_older_save_has_nothing_equipped() -> void:
	var migrated := SaveMigrations.migrate({"schema_version": 12, "player": {"display_name": "X"}})
	assert_ok(migrated)
	assert_eq(migrated.value["player"]["equipment"], {})
	assert_eq(migrated.value["schema_version"], SaveMigrations.CURRENT_VERSION)
	var bare := SaveMigrations.migrate({"schema_version": 12})
	assert_ok(bare)
	assert_eq(bare.value["player"]["equipment"], {})
