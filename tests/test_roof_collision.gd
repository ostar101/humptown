extends TestCase
## Every building drawn as whole art collides along its drawn outline (D-065).


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)


func _view() -> RegionView:
	var view := RegionView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	view.show_map(Game.world.map_for("harbourside"))
	return view


func test_every_building_with_art_has_a_body_and_none_without_does() -> void:
	var map := Game.world.map_for("harbourside")
	var view := _view()
	var report: Array[String] = []
	for loc_id in map.buildings:
		var rect: Rect2i = map.buildings[loc_id]["rect"]
		var kind := map.kind_of(loc_id)
		var drawn := BuildingArt.sprite_for(kind, loc_id, rect.size) != ""
		var body := view.get_node_or_null("Body_%s" % loc_id)
		report.append("%s art=%s body=%s open=%d" % [loc_id, drawn, body != null,
			BuildingArt.open_cells(kind, loc_id, rect.size).size()])
		if drawn:
			assert_not_null(body, "%s is drawn as art, so it collides as drawn" % loc_id)
			if body != null:
				assert_gt(float(body.get_child_count()), 0.0, "%s has an outline" % loc_id)
		else:
			assert_null(body, "%s has no art and stays a plain rectangle" % loc_id)
	print("\n".join(report))
	view.free()


func test_open_cells_are_cleared_with_the_view() -> void:
	var map := Game.world.map_for("harbourside")
	var view := _view()
	view.clear()
	assert_true(map.open_cells.is_empty())
	view.free()
