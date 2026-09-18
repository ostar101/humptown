extends TestCase
## BuildingArt: which whole-building overlay a building gets, if any
## (D-024, D-026).

const KINDS_WITH_ART := ["home", "shop", "bar", "civic", "work"]


func test_wrong_size_never_gets_a_sprite() -> void:
	for kind in KINDS_WITH_ART:
		assert_eq(BuildingArt.sprite_for(kind, "loc_x", Vector2i(7, 7)), "")
		assert_eq(BuildingArt.sprite_for(kind, "loc_x", Vector2i(9, 11)), "")
		assert_eq(BuildingArt.sprite_for(kind, "loc_x", BuildingArt.SPRITE_SIZE + Vector2i(0, 1)), "")


func test_a_kind_with_no_art_never_gets_a_sprite() -> void:
	for kind in ["", "unknown_kind", "street"]:
		assert_eq(BuildingArt.sprite_for(kind, "loc_x", BuildingArt.SPRITE_SIZE), "")


func test_every_kind_at_the_right_size_gets_a_real_file_when_installed() -> void:
	for kind in KINDS_WITH_ART:
		var path := BuildingArt.sprite_for(kind, "loc_test_%s" % kind, BuildingArt.SPRITE_SIZE)
		if path == "":
			assert_true(true, "art not installed on this machine; nothing to check")
			continue
		assert_true(path.begins_with(BuildingArt.REAL_DIR), path)
		assert_true(ResourceLoader.exists(path))


func test_the_same_building_always_gets_the_same_variant() -> void:
	var first := BuildingArt.sprite_for("home", "loc_ida_flat", BuildingArt.SPRITE_SIZE)
	for i in 5:
		assert_eq(BuildingArt.sprite_for("home", "loc_ida_flat", BuildingArt.SPRITE_SIZE), first)


func test_different_homes_are_not_all_forced_onto_one_variant() -> void:
	if not ResourceLoader.exists(BuildingArt.REAL_DIR + "home_1.png"):
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	var seen := {}
	for i in 20:
		var file := BuildingArt.sprite_for("home", "loc_test_home_%d" % i, BuildingArt.SPRITE_SIZE)
		seen[file] = true
	assert_gt(float(seen.size()), 1.0, "20 different homes should not all pick the same house")


func test_shop_bar_civic_and_work_each_get_a_distinct_file() -> void:
	if not ResourceLoader.exists(BuildingArt.REAL_DIR + "shop_1.png"):
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	var files := {}
	for kind in ["shop", "bar", "civic", "work"]:
		files[kind] = BuildingArt.sprite_for(kind, "loc_x", BuildingArt.SPRITE_SIZE)
	var distinct := {}
	for file in files.values():
		distinct[file] = true
	assert_eq(distinct.size(), 4, "each of shop/bar/civic/work is a different sign colour")


# --- RegionView integration --------------------------------------------

func test_region_view_gives_correctly_sized_buildings_a_sprite_and_others_none() -> void:
	var data := DataRegistry.new()
	data.load_all()
	var world := WorldState.new()
	world.build_from(data)
	var map := world.map_for("harbourside")
	var view := RegionView.new()
	view.show_map(map)

	var by_name := {}
	for sprite in view._buildings:
		by_name[sprite.name] = sprite
	if BuildingArt.sprite_for("home", "loc_player_flat", BuildingArt.SPRITE_SIZE) != "":
		assert_true(by_name.has("Building_loc_player_flat"), "an 8x13 home gets a sprite")
		assert_true(by_name.has("Building_loc_corner_shop"), "an 8x13 shop gets a sprite")
		assert_true(by_name.has("Building_loc_anchor_bar"), "an 8x13 bar gets a sprite")
		assert_true(by_name.has("Building_loc_clinic"), "an 8x13 civic building gets a sprite")
		assert_true(by_name.has("Building_loc_warehouse_9"), "an 8x13 work building gets a sprite")
	else:
		assert_true(by_name.is_empty(), "art not installed on this machine; nothing gets a sprite")
	assert_false(by_name.has("Building_loc_tuomas_flat"),
		"a home the wrong size for the art keeps its per-cell tiles")

	view.clear()
	assert_eq(view._buildings.size(), 0, "clear() frees the building sprites too")
	view.free()


## Regression for D-027: a building sprite and a later-streamed chunk are
## siblings under RegionView, so Godot only draws by y-position, not child
## order, if RegionView itself is y-sorted. This must not depend on whatever
## scene happens to embed RegionView remembering to set it.
func test_region_view_y_sorts_itself() -> void:
	var view := RegionView.new()
	assert_true(view.y_sort_enabled, "RegionView must y-sort so building art and streamed chunks layer correctly")
	view.free()
