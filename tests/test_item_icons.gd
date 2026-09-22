extends TestCase
## The pictures of things (D-070): every item has one, the file is well formed,
## layers and recolouring do what they say, and the slot and tile show them.


func before_each() -> void:
	Game.new_game("", 7)
	Localization.set_locale("en")


func _pixels(item_id: String) -> PackedByteArray:
	return ItemIcons.texture(item_id).get_image().get_data()


func test_the_icon_file_is_well_formed() -> void:
	assert_eq(ItemIcons.problems(), [] as Array[String])


func test_every_item_has_its_own_icon() -> void:
	for item_id: String in Game.data.ids("items"):
		assert_true(ItemIcons.has_icon(item_id), "%s has no icon" % item_id)


func test_no_icon_is_for_an_item_that_does_not_exist() -> void:
	for item_id: String in ItemIcons.icon_ids():
		assert_true(Game.data.has_entry("items", item_id), "%s has an icon but is not an item" % item_id)


func test_an_icon_is_sixteen_pixels_square_and_not_blank() -> void:
	for item_id: String in Game.data.ids("items"):
		var image := ItemIcons.texture(item_id).get_image()
		assert_eq(image.get_size(), Vector2i(16, 16))
		var painted := 0
		for y in 16:
			for x in 16:
				if image.get_pixel(x, y).a > 0.0:
					painted += 1
		assert_gt(float(painted), 20.0, "%s is close to empty" % item_id)


func test_an_item_without_an_icon_gets_a_question_mark_not_nothing() -> void:
	assert_false(ItemIcons.has_icon("item_that_is_not_there"))
	var fallback := ItemIcons.texture("item_that_is_not_there")
	assert_true(fallback != null)
	assert_eq(fallback.get_image().get_size(), Vector2i(16, 16))
	assert_ne(_pixels("item_that_is_not_there"), _pixels("item_spoon"), "it is not another item's picture")
	assert_false(_pixels("item_that_is_not_there").is_empty())


func test_a_texture_is_painted_once_and_kept() -> void:
	assert_true(ItemIcons.texture("item_spoon") == ItemIcons.texture("item_spoon"))


func test_layers_change_the_picture() -> void:
	assert_ne(_pixels("item_spoon"), _pixels("item_spoon_powder"), "powder shows on the spoon")
	assert_ne(_pixels("item_spoon_powder"), _pixels("item_spoon_liquid"))
	assert_ne(_pixels("item_spoon_liquid"), _pixels("item_spoon_cooked"))
	assert_ne(_pixels("item_syringe"), _pixels("item_syringe_loaded"))
	assert_ne(_pixels("item_syringe"), _pixels("item_syringe_used"))
	assert_ne(_pixels("item_pipe"), _pixels("item_pipe_loaded"))


func test_one_drawing_in_different_colours() -> void:
	assert_ne(_pixels("item_heroin_bag"), _pixels("item_cocaine_bag"))
	assert_ne(_pixels("item_cocaine_bag"), _pixels("item_amphetamine_bag"))
	assert_ne(_pixels("item_painkillers"), _pixels("item_sleeping_pills"))


func test_a_tile_shows_the_picture_without_taking_focus() -> void:
	var tile := ItemIcons.tile("item_puukko", 40)
	assert_eq(tile.custom_minimum_size, Vector2(40, 40))
	assert_eq(tile.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(tile is Button, "a row's first button is its action, not its picture")
	tile.free()


func test_a_slot_holds_a_thing_and_shows_a_count_from_two() -> void:
	var slot := ItemSlot.new(56.0)
	assert_true(slot.is_empty())
	slot.show_item("item_lighter", 1)
	assert_eq(slot.item_id, "item_lighter")
	assert_true(slot.icon != null)
	assert_eq(slot.tooltip_text, "Lighter")
	assert_eq((slot.get_child(0) as Label).text, "")
	slot.show_item("item_lighter", 3)
	assert_eq((slot.get_child(0) as Label).text, "3")
	slot.show_item("")
	assert_true(slot.is_empty())
	assert_true(slot.icon == null)
	slot.free()


func test_the_bag_and_the_shop_rows_carry_the_picture() -> void:
	var packed: PackedScene = load("res://scenes/world/world.tscn")
	var view: WorldView = packed.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	Game.player.inventory.add("item_puukko", 1)
	view.open_bag()
	var row := view.items_window().get_node("%Rows").get_child(0) as HBoxContainer
	assert_true(row.get_child(0) is PanelContainer, "the first thing in a row is the picture")
	assert_true(view.items_window().row_texts().size() > 0)
	view.items_window().close()
	view.free()
