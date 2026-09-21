extends TestCase
## The street's bins (D-069): rolled when first searched, kept, refilled only
## when they have stood empty, searched from the pavement beside them, saved.

var _rejected: Array[String] = []


func before_each() -> void:
	Game.new_game("bg_trained", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_rejected = []
	Events.action_rejected.connect(_on_rejected)


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)
	Game.saves.delete_slot("test_bins")
	if Game.is_running():
		Game.close_bin()


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


# --- helpers ---------------------------------------------------------------------

## The first bin on the street and a cell beside it the player can stand on.
func _bin() -> Dictionary:
	var map := Game.current_map()
	for cell: Vector2i in map.furniture:
		if str(map.furniture[cell]["kind"]) != "trash":
			continue
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not map.is_blocked(cell + step):
				return {"cell": cell, "id": str(map.furniture[cell]["id"]), "beside": cell + step}
	return {}


func _stand_by_the_bin() -> Dictionary:
	var bin := _bin()
	assert_false(bin.is_empty(), "the town has a bin to stand by")
	Game.player.interior = ""
	assert_ok(Game.move_player(DistrictMap.cell_to_world(bin["beside"])))
	return bin


func _open() -> Dictionary:
	var bin := _stand_by_the_bin()
	var opened := Game.interact_at(bin["cell"])
	assert_ok(opened)
	return bin


# --- what is in it -----------------------------------------------------------------

func test_a_bin_is_rolled_the_first_time_and_then_kept() -> void:
	var first := Game.bins.contents("bin_x", 3)
	var same := Game.bins.contents("bin_x", 3)
	assert_true(first == same, "the same bin, the same contents object")
	assert_true(Game.bins.was_searched("bin_x"))
	assert_false(Game.bins.was_searched("bin_y"))


func test_what_a_bin_holds_comes_from_the_table_and_the_seed() -> void:
	var loot: Array = Game.data.get_entry("bins", Bins.DEFINITION)["loot"]
	var allowed: Array[String] = []
	for entry: Dictionary in loot:
		allowed.append(str(entry["item"]))
	var total := 0
	for i in 20:
		var inv := Game.bins.contents("bin_%d" % i, 1)
		for item_id in inv.item_ids():
			assert_has(allowed, item_id, "%s is in the table" % item_id)
			total += inv.count_of(item_id)
	assert_gt(float(total), 0.0, "twenty bins are not all empty")
	# The same world seed rolls the same bins.
	Game.new_game("bg_trained", 7)
	var again := 0
	for i in 20:
		var inv := Game.bins.contents("bin_%d" % i, 1)
		for item_id in inv.item_ids():
			again += inv.count_of(item_id)
	assert_eq(again, total, "seeded, not random")


func test_an_emptied_bin_is_refilled_after_a_while_and_a_used_one_never() -> void:
	var days: int = int(Game.data.get_entry("bins", Bins.DEFINITION)["refill_days"])
	var inv := Game.bins.contents("bin_a", 0)
	inv.clear()
	assert_true(Game.bins.contents("bin_a", days - 1).stacks.is_empty(), "not yet")
	var refilled := false
	for day in range(days, days + 30):   # a roll can come up empty: it is tried again later
		var again := Game.bins.contents("bin_a", day)
		if not again.stacks.is_empty():
			refilled = true
			break
	assert_true(refilled, "somebody threw something in")
	var kept := Game.bins.contents("bin_b", 0)
	kept.clear()
	assert_ok(kept.add("item_notebook", 1))
	assert_eq(Game.bins.contents("bin_b", 400).count_of("item_notebook"), 1, "what you left stays")
	assert_eq(Game.bins.contents("bin_b", 400).stacks.size(), 1, "and nothing is added to it")


# --- in the world --------------------------------------------------------------------

func test_the_bin_can_be_looked_in_from_beside_it() -> void:
	var bin := _stand_by_the_bin()
	assert_eq(Game.interaction_at(bin["cell"])["kind"], "bin")
	var opened := Game.interact_at(bin["cell"])
	assert_ok(opened)
	assert_eq(opened.value["kind"], "bin")
	assert_eq(Game.open_bin, bin["id"])
	assert_not_null(Game.bin_contents())


func test_a_hydrant_is_not_something_to_search() -> void:
	var map := Game.current_map()
	for cell: Vector2i in map.furniture:
		if str(map.furniture[cell]["kind"]) == "hydrant":
			assert_eq(Game.interaction_at(cell), {})
			return
	assert_true(false, "the town has a hydrant")


func test_putting_something_in_and_taking_something_out() -> void:
	_open()
	Game.player.inventory.add("item_bandage", 2)
	var there := Game.bin_contents().count_of("item_bandage")
	assert_ok(Game.bin_put("item_bandage", 2))
	assert_eq(Game.bin_contents().count_of("item_bandage"), there + 2)
	var carried := Game.player.inventory.count_of("item_bandage")
	var in_bin := Game.bin_contents().count_of("item_bandage")
	assert_ok(Game.bin_take("item_bandage", 1))
	assert_eq(Game.player.inventory.count_of("item_bandage"), carried + 1)
	assert_eq(Game.bin_contents().count_of("item_bandage"), in_bin - 1)


func test_the_bin_has_limits_and_says_so() -> void:
	_open()
	Game.bin_contents().clear()
	assert_err(Game.bin_take("item_toolbox"), "not_owned")
	assert_err(Game.bin_put("item_toolbox"), "not_owned")
	assert_err(Game.bin_put("item_bandage", 0), "bad_quantity")
	Game.player.inventory.clear()
	Game.player.inventory.add("item_toolbox", 1)
	Game.bin_contents().base_capacity = 1.0
	assert_err(Game.bin_put("item_toolbox"), "bin_full")
	Game.bin_contents().base_capacity = 30.0
	assert_ok(Game.bin_put("item_toolbox"))
	Game.player.inventory.base_capacity = 0.5
	assert_err(Game.bin_take("item_toolbox"), "too_heavy")
	assert_eq(_rejected, ["not_owned", "not_owned", "bad_quantity", "bin_full", "too_heavy"])


func test_walking_away_from_the_bin_ends_the_search() -> void:
	var bin := _open()
	Game.player.inventory.add("item_bandage", 1)
	var away: Vector2i = bin["beside"] + (bin["beside"] - bin["cell"]) * 3
	assert_ok(Game.move_player(DistrictMap.cell_to_world(away)))
	assert_err(Game.bin_put("item_bandage"), "not_at_bin")
	assert_err(Game.bin_take("item_bandage"), "not_at_bin")


func test_a_bin_and_what_was_put_in_it_survive_a_save() -> void:
	var bin := _open()
	Game.player.inventory.add("item_notebook", 1)
	assert_ok(Game.bin_put("item_notebook", 1))
	var before := Game.bin_contents().count_of("item_notebook")
	assert_ok(Game.save_game("test_bins"))
	assert_ok(Game.load_game("test_bins"))
	assert_true(Game.bins.was_searched(bin["id"]))
	assert_eq(Game.bins.contents(bin["id"], 0).count_of("item_notebook"), before)
	assert_eq(Game.bins.contents(bin["id"], 0).capacity(), float(Game.data.get_entry("bins", Bins.DEFINITION)["capacity"]))


func test_an_older_save_has_looked_in_no_bin() -> void:
	var migrated := SaveMigrations.migrate({"schema_version": 10, "player": {}})
	assert_ok(migrated)
	assert_eq(migrated.value["bins"], {"bins": {}})
	assert_eq(migrated.value["schema_version"], SaveMigrations.CURRENT_VERSION)


# --- the window -------------------------------------------------------------------------

func test_pressing_the_button_opens_a_window_of_what_is_in_the_bin() -> void:
	var packed: PackedScene = load("res://scenes/world/world.tscn")
	var view: WorldView = packed.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	var bin := _stand_by_the_bin()
	view.player_body().place_at(DistrictMap.cell_to_world(bin["beside"]))
	view.player_body().face(bin["cell"] - bin["beside"])
	Game.bins.contents(bin["id"], 0).clear()
	assert_ok(Game.bins.contents(bin["id"], 0).add("item_cigarettes", 2))
	var pressed := view.interact()
	assert_ok(pressed)
	assert_true(view.bin_window().is_open())
	assert_false(view.stash_window().is_open())
	assert_true(view.bin_window().stored_texts()[0].contains("2"), str(view.bin_window().stored_texts()))
	view.bin_window().close()
	assert_eq(Game.open_bin, "", "closing the window ends the search")
	view.free()
