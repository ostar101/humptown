extends TestCase
## The home as a base (D-043): a cupboard in your own flat that keeps what
## you do not want to carry, saved with you, and nobody else's to open.

const STASH_CELL := Vector2i(6, 2)
const IN_FRONT := Vector2i(6, 3)

var _rejected: Array[String] = []


func before_each() -> void:
	Game.new_game("bg_trained", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_rejected = []
	Events.action_rejected.connect(_on_rejected)


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)
	Game.saves.delete_slot("test_home")


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


func _go_home() -> void:
	var outside := Game.current_map()
	var home := Game.player.home_location
	assert_ok(Game.move_player(DistrictMap.cell_to_world(outside.anchor_of(home))))
	assert_ok(Game.interact_at(outside.buildings[home]["door"]))
	assert_ok(Game.move_player(DistrictMap.cell_to_world(IN_FRONT)))


func test_the_flat_has_a_cupboard_to_open() -> void:
	_go_home()
	assert_eq(Game.interaction_at(STASH_CELL)["kind"], "stash")
	var opened := Game.interact_at(STASH_CELL)
	assert_ok(opened)
	assert_eq(opened.value["kind"], "stash")


func test_putting_away_and_taking_back() -> void:
	_go_home()
	var carried := Game.player.inventory.count_of("item_bandage")
	assert_ok(Game.store("item_bandage", 2))
	assert_eq(Game.player.inventory.count_of("item_bandage"), carried - 2)
	assert_eq(Game.player.stash.count_of("item_bandage"), 2)
	assert_ok(Game.take("item_bandage", 1))
	assert_eq(Game.player.stash.count_of("item_bandage"), 1)
	assert_eq(Game.player.inventory.count_of("item_bandage"), carried - 1)


func test_the_cupboard_has_limits() -> void:
	_go_home()
	assert_err(Game.store("item_toolbox"), "not_owned")
	assert_err(Game.take("item_toolbox"), "not_owned")
	assert_err(Game.store("item_bandage", 0), "bad_quantity")
	Game.player.stash.add("item_toolbox", 1)
	Game.player.inventory.base_capacity = Game.player.inventory.total_weight() + 1.0
	assert_err(Game.take("item_toolbox"), "too_heavy", "six kilos will not fit in your arms")
	Game.player.stash.base_capacity = Game.player.stash.total_weight()
	assert_err(Game.store("item_bandage"), "stash_full")
	assert_eq(_rejected, ["not_owned", "not_owned", "bad_quantity", "too_heavy", "stash_full"])


func test_only_at_home() -> void:
	assert_err(Game.store("item_bandage"), "not_at_home")


func test_what_is_kept_at_home_is_saved() -> void:
	_go_home()
	assert_ok(Game.store("item_backpack"))
	assert_ok(Game.save_game("test_home"))
	assert_ok(Game.load_game("test_home"))
	Game.pause_time(true)
	assert_eq(Game.player.stash.count_of("item_backpack"), 1)
	assert_almost(Game.player.stash.capacity(), PlayerState.STASH_CAPACITY, 0.001)


func test_the_cupboard_window() -> void:
	_go_home()
	var window: StashWindow = (load("res://scenes/ui/stash_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	window.open()
	assert_true(window.is_open())
	assert_has(window.stored_texts(), "The cupboard is empty.")
	assert_ok(window.store("item_bandage"))
	assert_has(window.stored_texts(), "Bandage|× 1")
	assert_ok(window.take("item_bandage"))
	assert_err(window.take("item_bandage"), "not_owned")
	assert_eq(window.message(), "It isn't there.")
	window.close()
	window.free()
