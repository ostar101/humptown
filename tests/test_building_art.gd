extends TestCase
## BuildingArt: which whole-building overlay a building gets, if any, and the
## geometry that art implies for the map (D-024, D-026, D-028).

const KINDS_WITH_ART := ["home", "shop", "bar", "civic", "work", "police",
	"downtown_2", "downtown_4", "downtown_6"]


func test_wrong_size_never_gets_a_sprite() -> void:
	for kind in KINDS_WITH_ART:
		var right := BuildingArt.footprint(kind)
		assert_eq(BuildingArt.sprite_for(kind, "loc_x", Vector2i(7, 7)), "")
		assert_eq(BuildingArt.sprite_for(kind, "loc_x", right + Vector2i(0, 1)), "")
		assert_eq(BuildingArt.sprite_for(kind, "loc_x", right + Vector2i(1, 0)), "")


func test_a_kind_with_no_art_never_gets_a_sprite() -> void:
	for kind in ["", "unknown_kind", "street"]:
		assert_eq(BuildingArt.sprite_for(kind, "loc_x", Vector2i(8, 11)), "")
		assert_eq(BuildingArt.footprint(kind), Vector2i.ZERO)
		assert_eq(BuildingArt.door_column(kind), -1)


## The porch is drawn by the sprite but is not part of the building: the rect
## a map authors is shorter than the image by exactly those rows, which is
## what leaves them walkable so someone can reach the door (D-028).
func test_the_footprint_is_the_image_minus_its_porch() -> void:
	for kind in KINDS_WITH_ART:
		var porch: int = BuildingArt.BUILDINGS[kind]["porch_rows"]
		assert_eq(BuildingArt.footprint(kind), BuildingArt.draw_cells(kind) - Vector2i(0, porch))
		assert_gt(float(BuildingArt.footprint(kind).y), float(DistrictMap.FACADE_ROWS),
			"%s: a building must be taller than its facade" % kind)


func test_the_villa_has_a_porch_and_the_storefront_does_not() -> void:
	assert_eq(int(BuildingArt.BUILDINGS["home"]["porch_rows"]), 2)
	assert_eq(BuildingArt.footprint("home"), Vector2i(8, 11))
	for kind in ["shop", "bar", "civic", "work"]:
		assert_eq(int(BuildingArt.BUILDINGS[kind]["porch_rows"]), 0)
		assert_eq(BuildingArt.footprint(kind), Vector2i(8, 13))


func test_every_door_column_lies_inside_its_own_footprint() -> void:
	for kind in KINDS_WITH_ART:
		var column := BuildingArt.door_column(kind)
		assert_true(column >= 0 and column < BuildingArt.footprint(kind).x,
			"%s door column %d is outside the building" % [kind, column])


func test_every_kind_at_the_right_size_gets_a_real_file_when_installed() -> void:
	for kind in KINDS_WITH_ART:
		var path := BuildingArt.sprite_for(kind, "loc_test_%s" % kind, BuildingArt.footprint(kind))
		if path == "":
			assert_true(true, "art not installed on this machine; nothing to check")
			continue
		assert_true(path.begins_with(BuildingArt.REAL_DIR), path)
		assert_true(ResourceLoader.exists(path))


func test_the_same_building_always_gets_the_same_variant() -> void:
	var first := BuildingArt.sprite_for("home", "loc_ida_flat", BuildingArt.footprint("home"))
	for i in 5:
		assert_eq(BuildingArt.sprite_for("home", "loc_ida_flat", BuildingArt.footprint("home")), first)


func test_different_homes_are_not_all_forced_onto_one_variant() -> void:
	if not ResourceLoader.exists(BuildingArt.REAL_DIR + "home_1.png"):
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	var seen := {}
	for i in 20:
		var file := BuildingArt.sprite_for("home", "loc_test_home_%d" % i, BuildingArt.footprint("home"))
		seen[file] = true
	assert_gt(float(seen.size()), 1.0, "20 different homes should not all pick the same house")


func test_shop_bar_civic_and_work_each_get_a_distinct_file() -> void:
	if not ResourceLoader.exists(BuildingArt.REAL_DIR + "shop_1.png"):
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	var distinct := {}
	for kind in ["shop", "bar", "civic", "work"]:
		distinct[BuildingArt.sprite_for(kind, "loc_x", BuildingArt.footprint(kind))] = true
	assert_eq(distinct.size(), 4, "each of shop/bar/civic/work is a different sign colour")


## D-060: the post is drawn with the police building, not the shared civic one,
## and the map is authored to that building's size and door.
func test_the_police_post_is_drawn_with_its_own_building() -> void:
	assert_eq(BuildingArt.art_kind("civic", "loc_police_post"), "police")
	assert_eq(BuildingArt.art_kind("civic", "loc_clinic"), "civic", "other civic buildings keep the shared art")
	assert_eq(BuildingArt.footprint("police"), Vector2i(7, 13))
	var data := DataRegistry.new()
	data.load_all()
	var world := WorldState.new()
	world.build_from(data)
	var map := world.map_for("harbourside")
	var rect: Rect2i = map.buildings["loc_police_post"]["rect"]
	assert_eq(rect.size, BuildingArt.footprint("police"), "the post is authored to the art's size")
	var file := BuildingArt.sprite_for("civic", "loc_police_post", rect.size)
	if file == "":
		assert_true(true, "art not installed on this machine; nothing to check")
	else:
		assert_true(file.ends_with("police_1.png"), file)


# --- the map agrees with the art ----------------------------------------

func test_authored_buildings_put_their_door_where_the_art_draws_one() -> void:
	var data := DataRegistry.new()
	data.load_all()
	var world := WorldState.new()
	world.build_from(data)
	var map := world.map_for("harbourside")
	var checked := 0
	for loc_id in map.buildings:
		var rect: Rect2i = map.buildings[loc_id]["rect"]
		var kind := BuildingArt.art_kind(map.kind_of(loc_id), loc_id)
		if rect.size != BuildingArt.footprint(kind):
			continue   # keeps the generic per-cell look; its door is free to sit anywhere
		var door: Vector2i = map.buildings[loc_id]["door"]
		assert_eq(door.x - rect.position.x, BuildingArt.door_column(kind),
			"%s: door is not on the door the art draws" % loc_id)
		checked += 1
	assert_gt(float(checked), 0.0, "no building matched its art; the map and BuildingArt disagree")


## The porch rows the villa draws below its front wall have to be walkable, or
## the drawn door cannot be reached at all — the whole point of D-028.
func test_the_porch_in_front_of_every_home_is_walkable() -> void:
	var data := DataRegistry.new()
	data.load_all()
	var world := WorldState.new()
	world.build_from(data)
	var map := world.map_for("harbourside")
	var checked := 0
	for loc_id in map.buildings:
		var rect: Rect2i = map.buildings[loc_id]["rect"]
		var kind := BuildingArt.art_kind(map.kind_of(loc_id), loc_id)
		if rect.size != BuildingArt.footprint(kind):
			continue
		var porch: int = BuildingArt.BUILDINGS[kind]["porch_rows"]
		var door: Vector2i = map.buildings[loc_id]["door"]
		for row in porch:
			var cell := Vector2i(door.x, rect.end.y + row)
			assert_false(map.is_blocked(cell), "%s: porch cell %s is blocked" % [loc_id, cell])
		checked += 1
	assert_gt(float(checked), 0.0, "no building matched its art")


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
	for sprite in view._overlays:
		by_name[sprite.name] = sprite
	if BuildingArt.sprite_for("home", "loc_player_flat", BuildingArt.footprint("home")) != "":
		assert_true(by_name.has("Building_loc_player_flat"), "a villa-sized home gets a sprite")
		assert_true(by_name.has("Building_loc_tuomas_flat"), "every flat on the row is the same villa")
		assert_true(by_name.has("Building_loc_corner_shop"), "an 8x13 shop gets a sprite")
		assert_true(by_name.has("Building_loc_anchor_bar"), "an 8x13 bar gets a sprite")
		assert_true(by_name.has("Building_loc_clinic"), "an 8x13 civic building gets a sprite")
		assert_true(by_name.has("Building_loc_police_post"), "the police post gets its own building")
		assert_true(by_name.has("Building_loc_warehouse_9"), "an 8x13 work building gets a sprite")
	else:
		assert_true(by_name.is_empty(), "art not installed on this machine; nothing gets a sprite")
	assert_eq(BuildingArt.sprite_for("home", "loc_anywhere", Vector2i(5, 9)), "",
		"a home the wrong size for the art keeps its per-cell tiles")

	view.clear()
	assert_eq(view._overlays.size(), 0, "clear() frees the building sprites too")
	view.free()


## Regression for D-027: a building sprite and a later-streamed chunk are
## siblings under RegionView, so Godot only draws by y-position, not child
## order, if RegionView itself is y-sorted. This must not depend on whatever
## scene happens to embed RegionView remembering to set it.
func test_region_view_y_sorts_itself() -> void:
	var view := RegionView.new()
	assert_true(view.y_sort_enabled, "RegionView must y-sort so building art and streamed chunks layer correctly")
	view.free()


## Regression for D-028: the generic roof/wall/door under a whole-building
## sprite must draw nothing, or it shows through the art's transparent corners
## as leftover brickwork — but it must still block, so the house is solid.
func test_a_covered_building_draws_nothing_but_still_blocks() -> void:
	var data := DataRegistry.new()
	data.load_all()
	var world := WorldState.new()
	world.build_from(data)
	var map := world.map_for("harbourside")
	var rect: Rect2i = map.buildings["loc_player_flat"]["rect"]
	var inside := rect.position + Vector2i(1, 1)
	assert_true(map.is_blocked(inside), "a building is solid whatever draws it")
	var coords := RegionTiles.coords_for(map, inside, true)
	if BuildingArt.covers(map, inside):
		assert_eq(coords, RegionTiles.hidden_coords(), "a covered cell draws the transparent tile")
	else:
		assert_true(true, "art not installed on this machine; the generic tiles are correct")
