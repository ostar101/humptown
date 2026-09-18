extends TestCase
## Talking to people, offline (D-035): what the player's words are taken to be
## about, the authored lines that answer them, the rules for who can be talked
## to, what a conversation changes, and the dialogue box in the world scene.

const WORLD_SCENE := "res://scenes/world/world.tscn"
## The people with a voice of their own; everyone else speaks generically.
const STORY_NPCS := ["npc_ida", "npc_elias", "npc_veikko", "npc_tuomas", "npc_sanna",
	"npc_marika", "npc_rauno", "npc_pirjo", "npc_joonas", "npc_leena"]
const OWN_TOPICS := ["greet", "about_self", "about_work", "unknown", "farewell"]

var _rejections: Array = []


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_rejections = []
	Events.action_rejected.connect(_on_rejected)


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)
	if Game.dialogue.is_talking():
		Game.end_conversation()
	Localization.set_locale("en")


func _on_rejected(proposal: Dictionary, code: String) -> void:
	_rejections.append([proposal, code])


func _people() -> Dictionary:
	return OfflineTopics.name_words({"npc_ida": ["Ida Lahtinen"], "npc_veikko": ["Veikko Nieminen"]}, true)


func _places() -> Dictionary:
	return OfflineTopics.name_words({
		"loc_harbour": ["The Harbour", "Satama"],
		"loc_anchor_bar": ["The Anchor", "Ankkuri"],
	}, false)


func _topic(text: String, speaking_to: String = "npc_joonas") -> String:
	return str(OfflineTopics.topic_of(text, speaking_to, _people(), _places())["topic"])


# --- what the player's words are about ----------------------------------------

func test_greetings_goodbyes_and_thanks_in_both_languages() -> void:
	for text in ["Hello!", "hi there", "Good evening.", "Moi", "Hei!", "huomenta"]:
		assert_eq(_topic(text), "greet", text)
	for text in ["bye", "See you later", "Näkemiin!", "moi moi", "heippa"]:
		assert_eq(_topic(text), "farewell", text)
	for text in ["Thanks!", "thank you", "Kiitos."]:
		assert_eq(_topic(text), "thanks", text)


func test_questions_about_the_person_and_their_work() -> void:
	for text in ["Who are you?", "What's your name?", "Kuka olet?", "kerro itsestäsi"]:
		assert_eq(_topic(text), "about_self", text)
	for text in ["What do you do for work?", "How's the job?", "Mitä teet työksesi?"]:
		assert_eq(_topic(text), "about_work", text)


func test_a_greeting_does_not_hide_the_question_after_it() -> void:
	assert_eq(_topic("hi, who are you?"), "about_self")
	assert_eq(_topic("thanks, bye"), "farewell")


func test_a_short_word_inside_a_longer_one_is_not_that_word() -> void:
	assert_eq(_topic("this is it"), "unknown", "'hi' inside 'this' is not a greeting")


func test_naming_someone_is_asking_about_them_unless_it_is_who_you_are_talking_to() -> void:
	var found := OfflineTopics.topic_of("Do you know Veikko?", "npc_joonas", _people(), _places())
	assert_eq(found["topic"], "about_person")
	assert_eq(found["subject"], "npc_veikko")
	assert_eq(_topic("Ida, who are you?", "npc_ida"), "about_self", "your own name is not gossip")


func test_a_persons_name_inside_a_place_name_is_still_the_person() -> void:
	var places := OfflineTopics.name_words({"loc_veikko_flat": ["Veikko's Flat"]}, false, ["veikko"])
	var found := OfflineTopics.topic_of("Veikko, what do you do?", "npc_veikko", _people(), places)
	assert_eq(found["topic"], "about_work", "Veikko's own name is not a question about his flat")


func test_places_are_recognised_by_name_and_in_inflected_finnish() -> void:
	var found := OfflineTopics.topic_of("Where is the harbour?", "npc_joonas", _people(), _places())
	assert_eq(found["subject"], "loc_harbour")
	assert_eq(OfflineTopics.topic_of("Oletko ollut satamassa?", "npc_joonas", _people(), _places())["subject"],
		"loc_harbour", "satamassa is the harbour too")
	assert_eq(OfflineTopics.topic_of("Mennäänkö Ankkuriin?", "npc_joonas", _people(), _places())["subject"],
		"loc_anchor_bar")


func test_anything_else_is_unknown() -> void:
	assert_eq(_topic("The price of cod has gone up again."), "unknown")


# --- the authored lines --------------------------------------------------------

func test_everyone_with_a_story_has_their_own_voice() -> void:
	for npc_id in STORY_NPCS:
		assert_not_null(Game.npcs.get_npc(npc_id), npc_id)
		for topic in OWN_TOPICS:
			assert_true(DialogueLines.has_own(npc_id, topic), "%s has no %s line of their own" % [npc_id, topic])


func test_background_people_can_answer_every_topic() -> void:
	for topic in ["greet", "about_self", "about_work", "about_place", "about_person_known",
			"about_person_unknown", "thanks", "unknown", "farewell"]:
		assert_false(DialogueLines.keys_for("npc_nobody_in_particular", topic).is_empty(), topic)


func test_every_line_is_translated() -> void:
	var missing := Localization.missing_keys("fi")
	for key in missing:
		assert_false(key.begins_with("dialogue.") or key.begins_with("ui.dialogue."),
			"%s has no Finnish" % key)


# --- who can be talked to ------------------------------------------------------

func _enter_shop_with_ida_working() -> void:
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	var map := Game.current_map()
	assert_ok(Game.move_player(DistrictMap.cell_to_world(map.anchor_of("loc_corner_shop"))))
	assert_ok(Game.interact_at(map.buildings["loc_corner_shop"]["door"]))


func test_someone_in_the_same_room_can_be_talked_to() -> void:
	_enter_shop_with_ida_working()
	var started := Game.start_conversation("npc_ida")
	assert_ok(started)
	assert_true(DialogueLines.keys_for("npc_ida", "greet").has(str((started.value as Dictionary)["key"])),
		"Ida opens with one of her own lines")


func test_a_sleeping_person_is_left_asleep() -> void:
	_enter_shop_with_ida_working()
	Game.npcs.get_npc("npc_ida").activity = "sleep"
	assert_err(Game.start_conversation("npc_ida"), "asleep")
	assert_eq(_rejections[-1][1], "asleep", "a refusal is a rejected proposal like any other")
	assert_false(Game.dialogue.is_talking())


func test_someone_heading_into_a_building_does_not_stop() -> void:
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_corner_shop"
	ida.activity = "work"
	assert_eq(Game.player.interior, "", "the player is out in the street")
	assert_err(Game.start_conversation("npc_ida"), "on_their_way")


func test_someone_elsewhere_or_nobody_at_all_cannot_be_talked_to() -> void:
	_enter_shop_with_ida_working()
	Game.npcs.get_npc("npc_veikko").location = "loc_harbour"
	assert_err(Game.start_conversation("npc_veikko"), "nobody_there", "not in this room")
	assert_err(Game.start_conversation("npc_nobody"), "nobody_there")


func test_one_conversation_at_a_time() -> void:
	_enter_shop_with_ida_working()
	assert_ok(Game.start_conversation("npc_ida"))
	assert_err(Game.start_conversation("npc_ida"), "already_talking")


# --- a conversation ------------------------------------------------------------

func test_asking_who_someone_is_gets_their_own_answer_and_their_name() -> void:
	_enter_shop_with_ida_working()
	assert_false(Game.dialogue.knows_name("npc_ida"), "a stranger to start with")
	assert_ok(Game.start_conversation("npc_ida"))
	var said := Game.say_to_npc("Who are you?")
	assert_ok(said)
	assert_eq((said.value as Dictionary)["text"], Localization.t("dialogue.npc_ida.about_self.1"))
	assert_true(Game.dialogue.knows_name("npc_ida"), "now you know her name")


## Even offline, people only know who they know.
func test_people_only_know_the_people_they_know() -> void:
	_enter_shop_with_ida_working()
	assert_ok(Game.start_conversation("npc_ida"))
	var about_tuomas: Dictionary = Game.say_to_npc("Do you know Tuomas?").value
	assert_eq(about_tuomas["text"], Localization.t("dialogue.generic.about_person_known.1", {"person": "Tuomas"}),
		"Ida and Tuomas are friends")
	var about_joonas: Dictionary = Game.say_to_npc("And Joonas?").value
	assert_eq(about_joonas["text"], Localization.t("dialogue.generic.about_person_unknown.1", {"person": "Joonas"}),
		"Ida has no relationship with Joonas")


func test_time_stands_still_while_talking_and_is_paid_after() -> void:
	_enter_shop_with_ida_working()
	Game.pause_time(false)
	var before := Game.clock.total_minutes
	assert_ok(Game.start_conversation("npc_ida"))
	assert_true(Game.clock.paused, "the world waits while two people talk")
	Game.say_to_npc("Hello.")
	Game.say_to_npc("What do you do?")
	Game.say_to_npc("Bye.")
	assert_ok(Game.end_conversation())
	assert_eq(Game.clock.total_minutes, before + 3, "three things said, three minutes gone")
	assert_false(Game.clock.paused, "and the clock runs again as it did before")


func test_talking_makes_two_people_a_little_more_familiar() -> void:
	_enter_shop_with_ida_working()
	assert_ok(Game.start_conversation("npc_ida"))
	Game.say_to_npc("Hello.")
	assert_ok(Game.end_conversation())
	assert_almost(Game.relationships.peek("npc_ida", PlayerState.ID).familiarity,
		DialogueDirector.FAMILIARITY_PER_CONVERSATION, 0.001)


func test_empty_or_endless_lines_are_refused_and_change_nothing() -> void:
	_enter_shop_with_ida_working()
	assert_ok(Game.start_conversation("npc_ida"))
	assert_err(Game.say_to_npc("   "), "empty")
	assert_err(Game.say_to_npc("a".repeat(DialogueDirector.MAX_LINE_LENGTH + 1)), "too_long")
	assert_eq(Game.dialogue.conversation.exchanges, 0)


func test_after_goodbye_nothing_more_is_said() -> void:
	_enter_shop_with_ida_working()
	assert_ok(Game.start_conversation("npc_ida"))
	var bye: Dictionary = Game.say_to_npc("Goodbye.").value
	assert_true(bye["ends"])
	assert_eq(bye["text"], Localization.t("dialogue.npc_ida.farewell.1"))
	assert_err(Game.say_to_npc("wait, one more thing"), "conversation_over")


func test_finnish_questions_get_finnish_answers() -> void:
	Localization.set_locale("fi")
	_enter_shop_with_ida_working()
	assert_ok(Game.start_conversation("npc_ida"))
	var said: Dictionary = Game.say_to_npc("Kuka olet?").value
	assert_eq(said["topic"], "about_self")
	assert_true(str(said["text"]).begins_with("Ida. Lahtinen"), said["text"])


# --- the world scene -----------------------------------------------------------

func _spawn_world() -> WorldView:
	var view: WorldView = (load(WORLD_SCENE) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	return view


func test_walking_up_to_someone_and_talking_to_them() -> void:
	var joonas := Game.npcs.get_npc("npc_joonas")
	joonas.location = "loc_harbour"
	joonas.activity = "work"
	var view := _spawn_world()
	var tree := Engine.get_main_loop() as SceneTree
	var body := view.npc_bodies().body_for("npc_joonas")
	assert_not_null(body, "Joonas is out on the quay")
	var map := Game.current_map()
	var stand := body.current_cell() + Vector2i.DOWN
	assert_false(map.is_blocked(stand))
	view.player_body().place_at(DistrictMap.cell_to_world(stand))
	view.player_body().facing = Vector2i.UP
	assert_ok(Game.move_player(DistrictMap.cell_to_world(stand)))
	await tree.process_frame
	await tree.process_frame
	assert_eq(view.hud().prompt_text().contains(Localization.t("ui.prompt.talk_stranger")), true,
		"a stranger, until you know their name: " + view.hud().prompt_text())

	var before := Game.clock.total_minutes
	assert_ok(view.interact())
	var box := view.dialogue_box()
	assert_true(box.is_open())
	assert_false(view.player_body().input_enabled, "the player stands still while talking")
	assert_eq(body.facing(), Vector2i.DOWN, "Joonas turns to face the player")

	assert_ok(box.submit("Who are you?"))
	assert_eq(box.line_text(), Localization.t("dialogue.npc_joonas.about_self.1"))
	assert_eq(box.speaker_name(), joonas.name, "introduced, now named")

	box.close()
	assert_false(box.is_open())
	assert_false(Game.dialogue.is_talking())
	assert_true(view.player_body().input_enabled)
	assert_eq(Game.clock.total_minutes, before + 1)
	view.free()


func test_a_refusal_in_the_world_shows_why_and_opens_nothing() -> void:
	var joonas := Game.npcs.get_npc("npc_joonas")
	joonas.location = "loc_harbour"
	joonas.activity = "work"
	var view := _spawn_world()
	var body := view.npc_bodies().body_for("npc_joonas")
	joonas.activity = "sleep"   # dozing on his feet, as far as the rules are concerned
	var result := view.talk_to(body)
	assert_err(result, "asleep")
	assert_false(view.dialogue_box().is_open())
	assert_eq(view.hud().message_text(), Localization.t("ui.msg.refused.asleep"))
	assert_true(view.player_body().input_enabled)
	view.free()
