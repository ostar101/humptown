extends TestCase
## Everything drawn on the ground stops the body where it is drawn (D-066, D-067):
## hydrants and bins, trees, benches, the worksite, each by its own outline.


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)


func _view() -> RegionView:
	var view := RegionView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	view.show_map(Game.world.map_for("harbourside"))
	return view


func test_every_decoration_with_a_foot_has_a_body() -> void:
	if not ResourceLoader.exists(PlaceArt.REAL_DIR + "tree_1.png"):
		return   # art not installed: nothing is drawn, so nothing collides
	var map := Game.world.map_for("harbourside")
	var view := _view()
	var expected := 0
	for location_id in PlaceArt.decorated_places(map):
		for piece: Dictionary in PlaceArt.decorations_for(map, location_id):
			expected += 1 if int(piece["foot"]) > 0 else 0
	var found := 0
	for sprite in view._overlays:
		if str(sprite.name).begins_with("Place_") and sprite.get_node_or_null("Body") != null:
			found += 1
	assert_gt(float(expected), 0.0)
	assert_eq(found, expected, "each tree, bench and cone and the worksite has a body; the court's surface has none")
	view.free()


func test_hydrants_and_bins_have_a_body_but_only_their_own_foot() -> void:
	if not StreetProps.available():
		return
	var map := Game.world.map_for("harbourside")
	var view := _view()
	view.focus_on(DistrictMap.cell_to_world(Vector2i(20, 29)))
	var seen := {"trash": 0, "hydrant": 0}
	for chunk_root: Node in view.get_children():
		for child in chunk_root.get_children():
			if not (child is Sprite2D):
				continue
			var path := str((child as Sprite2D).texture.resource_path)
			for kind in seen:
				if path.ends_with(StreetProps.KINDS[kind]["file"]):
					seen[kind] += 1
					var body := child.get_node_or_null("Body") as StaticBody2D
					assert_not_null(body, "a %s collides" % kind)
					if body != null:
						assert_eq(body.position.y, (child as Sprite2D).offset.y + 32.0, "the body starts at the bottom cell of the art")
						for polygon in body.get_children():
							for point in (polygon as CollisionPolygon2D).polygon:
								assert_true(point.y >= 0.0 and point.y <= 32.0, "and stays within it: %s" % point)
	assert_gt(float(seen["trash"] + seen["hydrant"]), 0.0, "something to bump into on that street")
	view.free()
