extends TestCase
## CharacterSprites: choosing LimeZu layers for a person and finding frames on
## a sheet (D-019). Runs on a small fake manifest, so it passes on machines
## without the art; the last tests check the real art only where it exists.

const FAKE := {
	"frame": [32, 64],
	"bodies": [
		{"file": "bodies/light.png", "colour": "#ffcbb0"},
		{"file": "bodies/dark.png", "colour": "#7a4a30"},
	],
	"eyes": [
		{"file": "eyes/a.png", "colour": "#000000"},
		{"file": "eyes/b.png", "colour": "#000000"},
	],
	"outfits": [
		{"file": "outfits/01_red.png", "style": "01", "colour": "#c03030"},
		{"file": "outfits/01_blue.png", "style": "01", "colour": "#3050c0"},
		{"file": "outfits/02_green.png", "style": "02", "colour": "#30a040"},
	],
	"hairstyles": [
		{"file": "hair/01_black.png", "style": "01", "colour": "#1a1a1a"},
		{"file": "hair/01_blond.png", "style": "01", "colour": "#d0b070"},
		{"file": "hair/02_grey.png", "style": "02", "colour": "#9a9a9a"},
	],
}


func after_each() -> void:
	CharacterSprites.reset()


func test_without_art_there_is_no_look() -> void:
	CharacterSprites.use_manifest({})
	assert_false(CharacterSprites.available())
	assert_eq(CharacterSprites.look_for("npc_anyone", {}), {}, "the figure stays code-painted")


func test_a_look_has_every_layer_and_is_stable() -> void:
	CharacterSprites.use_manifest(FAKE)
	var palette := NpcLook.generated("npc_someone")
	var look := CharacterSprites.look_for("npc_someone", palette)
	for layer in CharacterSprites.LAYERS:
		assert_has(look, layer)
	assert_eq(CharacterSprites.look_for("npc_someone", palette), look, "same person, same look")


func test_palette_colours_pick_the_closest_variant() -> void:
	CharacterSprites.use_manifest(FAKE)
	var dark := {"skin": Color("6f4630"), "hair": Color("202020"), "shirt": Color("2040d0")}
	var light := {"skin": Color("f8d0b8"), "hair": Color("d8b878"), "shirt": Color("d02020")}
	for i in 20:
		var id := "npc_%02d" % i
		var look := CharacterSprites.look_for(id, dark)
		assert_eq(look["bodies"], "bodies/dark.png", "skin picks the body")
		assert_eq(CharacterSprites.look_for(id, light)["bodies"], "bodies/light.png")
		if str(look["hairstyles"]).begins_with("hair/01"):
			assert_eq(look["hairstyles"], "hair/01_black.png", "hair colour picks the variant")
		if str(look["outfits"]).begins_with("outfits/01"):
			assert_eq(look["outfits"], "outfits/01_blue.png", "shirt colour picks the variant")


func test_ids_spread_across_styles() -> void:
	CharacterSprites.use_manifest(FAKE)
	var styles := {}
	for i in 40:
		var look := CharacterSprites.look_for("npc_gen_%03d" % i, {})
		styles[str(look["outfits"]).substr(0, 10)] = true
	assert_eq(styles.size(), 2, "both outfit styles are worn by someone")


func test_frame_rects_follow_the_sheet_layout() -> void:
	# Standing: one frame per facing on the top row, ordered right, up, left, down.
	assert_eq(CharacterSprites.frame_rect(Vector2i.DOWN, false, 0), Rect2i(96, 0, 32, 64))
	assert_eq(CharacterSprites.frame_rect(Vector2i.RIGHT, false, 4), Rect2i(0, 0, 32, 64))
	# Walking: six frames per facing on the third row.
	assert_eq(CharacterSprites.frame_rect(Vector2i.RIGHT, true, 2), Rect2i(64, 128, 32, 64))
	assert_eq(CharacterSprites.frame_rect(Vector2i.UP, true, 0), Rect2i(192, 128, 32, 64))
	assert_eq(CharacterSprites.frame_rect(Vector2i.DOWN, true, 7), Rect2i(608, 128, 32, 64), "frames wrap")


func test_missing_files_fall_back_to_the_painted_figure() -> void:
	CharacterSprites.use_manifest(FAKE)
	var figure := CharacterFigure.new()
	figure.look = CharacterSprites.look_for("npc_someone", {})
	assert_eq(CharacterSprites.textures_for(figure.look).size(), 0, "the fake files do not exist")
	figure.free()


func test_real_art_is_adult_and_loads_when_present() -> void:
	CharacterSprites.reset()
	if not CharacterSprites.available():
		assert_true(true, "art not installed on this machine; nothing to check")
		return
	var data := CharacterSprites.manifest()
	for layer in CharacterSprites.LAYERS:
		var entries: Array = data.get(layer, [])
		assert_gt(float(entries.size()), 0.0, "%s imported" % layer)
		for entry: Dictionary in entries:
			assert_false(str(entry["file"]).to_lower().contains("kid"), "adults only: %s" % entry["file"])
	var look := CharacterSprites.look_for("npc_joonas", NpcLook.generated("npc_joonas"))
	assert_eq(CharacterSprites.textures_for(look).size(), CharacterSprites.LAYERS.size(), "every layer loads")


# --- other animations (D-058) -----------------------------------------------------

func test_actions_come_from_the_manifest_and_default_to_the_old_rows() -> void:
	CharacterSprites.use_manifest(FAKE)
	assert_true(CharacterSprites.has_action("walk"), "an import without the table still has the three rows")
	assert_false(CharacterSprites.has_action("gift"))
	var richer := FAKE.duplicate()
	richer["actions"] = {
		"stand": {"y": 0, "frames": 1, "directional": true},
		"phone": {"y": 192, "frames": 12, "directional": false},
		"gift": {"y": 256, "frames": 10, "directional": true},
	}
	CharacterSprites.use_manifest(richer)
	assert_true(CharacterSprites.has_action("gift"))
	assert_eq(CharacterSprites.action_frames("gift"), 10)
	# Directional: a block of frames per facing, right, up, left, down.
	assert_eq(CharacterSprites.frame_rect_for("gift", Vector2i.DOWN, 2), Rect2i(32 * 32, 256, 32, 64))
	assert_eq(CharacterSprites.frame_rect_for("gift", Vector2i.RIGHT, 12), Rect2i(64, 256, 32, 64), "frames wrap")
	# Not directional: one run, whichever way they face.
	assert_eq(CharacterSprites.frame_rect_for("phone", Vector2i.LEFT, 5), Rect2i(160, 192, 32, 64))
	assert_eq(CharacterSprites.frame_rect_for("phone", Vector2i.UP, 5), Rect2i(160, 192, 32, 64))


func test_an_action_the_art_lacks_is_shown_as_standing() -> void:
	CharacterSprites.use_manifest(FAKE)
	assert_eq(CharacterSprites.frame_rect_for("juggle", Vector2i.DOWN, 3), CharacterSprites.frame_rect(Vector2i.DOWN, false, 0))
	assert_eq(CharacterSprites.action_frames("juggle"), 0)


func test_the_painted_figure_has_nothing_to_play() -> void:
	CharacterSprites.use_manifest({})
	var figure := CharacterFigure.new()
	assert_false(figure.play("gift"), "no art, no animation; nothing waits on it")
	assert_false(figure.is_posing())
	figure.free()


func test_a_played_action_runs_out_and_a_held_one_waits_to_be_put_away() -> void:
	CharacterSprites.reset()
	if not CharacterSprites.has_action("gift") or not CharacterSprites.available():
		assert_true(true, "art not installed (or imported before D-058); nothing to play")
		return
	var figure := CharacterFigure.new()
	figure.look = CharacterSprites.look_for("npc_joonas", NpcLook.generated("npc_joonas"))
	var finished: Array[String] = []
	figure.pose_finished.connect(func(action: String) -> void: finished.append(action))

	assert_true(figure.play("gift"))
	assert_true(figure.is_posing())
	figure._process(0.1)
	assert_true(figure.is_posing(), "a moment in")
	figure._process(5.0)
	assert_false(figure.is_posing())
	assert_eq(finished, ["gift"])

	assert_true(figure.play("phone", true))
	figure._process(30.0)
	assert_true(figure.is_posing(), "held: the loop repeats until it is put away")
	figure.end_pose()
	figure._process(5.0)
	assert_false(figure.is_posing())
	assert_eq(finished, ["gift", "phone"])

	assert_true(figure.play("gift"))
	figure.moving = true
	assert_false(figure.is_posing(), "setting off ends it")
	assert_false(figure.play("gift"), "and nobody strikes a pose mid-stride")
	figure.free()
