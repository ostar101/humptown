extends TestCase
## What you hit with (D-070): the best thing you carry is in your hand, its
## damage is what the data says, and the fight window shows it.


func before_each() -> void:
	Game.new_game("bg_returning", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	var model := ScriptedDialogueModel.new()
	model.available = false
	Game.dialogue.model = model
	Game.player.inventory.clear()
	for npc_id: String in Game.npcs.living_ids():
		var npc := Game.npcs.get_npc(npc_id)
		npc.location = npc.home
		npc.activity = "idle"


func after_each() -> void:
	Game.fights.roll_source = Callable()


func _fight() -> Combat:
	var npc := Game.npcs.get_npc("npc_elias")
	npc.location = Game.player.location
	assert_ok(Game.start_fight("npc_elias"))
	return Game.fights.combat


func test_bare_handed_by_default() -> void:
	assert_eq(Game.fights.wielded_weapon(), "")
	var combat := _fight()
	assert_eq(combat.player()["weapon"], 0.0)
	assert_eq(combat.player()["weapon_item"], "")


func test_the_best_thing_you_carry_is_what_you_hit_with() -> void:
	assert_ok(Game.player.inventory.add("item_crowbar", 1))
	assert_eq(Game.fights.wielded_weapon(), "item_crowbar")
	assert_ok(Game.player.inventory.add("item_puukko", 1))
	assert_ok(Game.player.inventory.add("item_hammer", 1))
	assert_eq(Game.fights.wielded_weapon(), "item_puukko", "the most damage wins")
	var combat := _fight()
	assert_almost(float(combat.player()["weapon"]), 0.13, 0.0001)
	assert_eq(combat.player()["weapon_item"], "item_puukko")


func test_the_crowbar_still_does_what_it_did() -> void:
	assert_ok(Game.player.inventory.add("item_crowbar", 1))
	assert_almost(float(_fight().player()["weapon"]), 0.06, 0.0001)


func test_a_weapon_makes_a_blow_harder_and_a_better_one_harder_still() -> void:
	var me := {"strength": 5, "weapon": 0.0}
	var them := {"defending": false}
	var bare := CombatRules.damage(me, them, false, 0.5)
	me["weapon"] = 0.08
	var stick := CombatRules.damage(me, them, false, 0.5)
	me["weapon"] = 0.14
	var axe := CombatRules.damage(me, them, false, 0.5)
	assert_gt(stick, bare)
	assert_gt(axe, stick)


func test_the_weapons_are_ranked_by_what_they_are() -> void:
	var damage := func(id: String) -> float: return ItemRules.damage_of(Game.data.get_entry("items", id))
	assert_gt(damage.call("item_puukko"), damage.call("item_kitchen_knife"))
	assert_gt(damage.call("item_nail_bat"), damage.call("item_bat"), "nails make it worse")
	assert_gt(damage.call("item_bat"), damage.call("item_screwdriver"))
	assert_eq(damage.call("item_sandwich"), 0.0, "food is no weapon")
	assert_eq(ItemRules.damage_of({"damage": -1.0}), 0.0, "and damage is never negative")


func test_every_weapon_is_a_real_thing_to_carry() -> void:
	var weapons := Game.data.find_by("items", "kind", "weapon")
	assert_gt(float(weapons.size()), 8.0)
	for item in weapons:
		assert_gt(ItemRules.damage_of(item), 0.0, "%s does no damage" % item["id"])
		assert_false(bool(item.get("stackable", true)), "%s should be one at a time" % item["id"])


func test_the_fight_window_shows_what_you_hold() -> void:
	var packed: PackedScene = load("res://scenes/world/world.tscn")
	var view: WorldView = packed.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	assert_ok(Game.player.inventory.add("item_puukko", 1))
	var npc := Game.npcs.get_npc("npc_elias")
	npc.location = Game.player.location
	var window := view.get_node("Combat") as CombatWindow
	assert_ok(window.open("npc_elias"))
	assert_eq(window.weapon_text(), "Puukko")
	Game.fights.combat = null
	Game.fights.last = null
	view.free()
