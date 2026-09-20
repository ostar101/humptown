extends TestCase
## The event feed (D-059): what happens to the player's money and bag is said on
## screen, in a line, for a while.


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")


func _hud() -> Hud:
	var hud: Hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	return hud


func test_money_lines_say_what_for() -> void:
	assert_eq(FeedText.money(-20, "cash", "gift:npc_ida"), "You gave %s 20 €." % Game.npcs.get_npc("npc_ida").name)
	assert_eq(FeedText.money(110, "bank", "wage:job_dockhand"), "Wage: 110 €.")
	assert_eq(FeedText.money(-4, "cash", "buy:item_sandwich"), "You bought Sandwich for 4 €.")
	assert_eq(FeedText.money(15, "cash", "who_knows"), "You received 15 €.")
	assert_eq(FeedText.money(-7, "mixed", ""), "You paid 7 €.")
	assert_eq(FeedText.money(30, "deposit", ""), "You put 30 € into your account.")
	assert_eq(FeedText.money(0, "cash", ""), "", "nothing moved, nothing said")


func test_item_lines() -> void:
	assert_eq(FeedText.item("item_sandwich", 2), "You got Sandwich ×2.")
	assert_eq(FeedText.item("item_sandwich", -1), "Sandwich ×1 gone from your bag.")


func test_the_feed_shows_money_and_items_as_they_move() -> void:
	var hud := _hud()
	Game.player.wallet.add_cash(20, "errand:e1")
	assert_ok(Game.player.inventory.add("item_sandwich", 1))
	var lines := hud.feed_lines()
	assert_eq(lines.size(), 2, str(lines))
	assert_eq(lines[-2], "Errand reward: 20 €.")
	assert_eq(lines[-1], "You got Sandwich ×1.")
	hud.free()


func test_the_cupboard_is_not_news_and_neither_is_the_start_of_a_life() -> void:
	var hud := _hud()
	Game.player.stash.add("item_sandwich", 1)
	assert_true(hud.feed_lines().is_empty(), "only the player's own bag is announced: %s" % str(hud.feed_lines()))
	hud.free()


func test_the_feed_is_bounded_and_fades() -> void:
	var hud := _hud()
	for i in Hud.FEED_MAX + 3:
		hud.log_event("line %d" % i)
	assert_eq(hud.feed_lines().size(), Hud.FEED_MAX)
	assert_eq(hud.feed_lines()[-1], "line %d" % (Hud.FEED_MAX + 2), "newest last")
	hud._process(Hud.FEED_SECONDS + 1.0)
	assert_true(hud.feed_lines().is_empty(), "and it goes when its time is up")
	hud.free()


func test_important_messages_are_kept_in_the_feed_too() -> void:
	var hud := _hud()
	hud.notify("Something worth keeping")
	assert_eq(hud.message_text(), "Something worth keeping")
	assert_eq(hud.feed_lines(), ["Something worth keeping"] as Array[String])
	hud.show_message("A passing remark")
	assert_eq(hud.feed_lines().size(), 1, "a passing remark is not")
	hud.free()


func test_the_speech_window_leaves_the_status_corner_clear() -> void:
	var box: DialogueBox = (load("res://scenes/ui/dialogue_box.tscn") as PackedScene).instantiate()
	var hud := _hud()
	(Engine.get_main_loop() as SceneTree).root.add_child(box)
	var speech := box.get_node("Root/Speech") as Control
	var status := hud.get_node("Status") as Control
	assert_true(speech.offset_top >= status.offset_bottom + 24.0, "the time and place stay visible while someone talks")
	box.free()
	hud.free()
