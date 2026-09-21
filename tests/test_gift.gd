extends TestCase
## Handing an item from the bag to someone (D-062): the rules, the words, and
## the world taking it out of the bag — or refusing, honestly.

var _model: ScriptedDialogueModel
var _rejected: Array[String] = []


func before_each() -> void:
	Game.new_game("", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	_model = ScriptedDialogueModel.new()
	_model.available = false
	Game.dialogue.model = _model
	_rejected = []
	Events.action_rejected.connect(_on_rejected)


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)
	if Game.dialogue.is_talking():
		Game.end_conversation()


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


# --- helpers ---------------------------------------------------------------------

func _state(overrides: Dictionary = {}) -> Dictionary:
	var state := {
		"npc_id": "npc_ida", "player_name": "Aino", "player_cash": 100,
		"relationship": {}, "warmth": 0.0, "channel": "in_person",
		"gift": {"count": 2, "value": 5, "name": "a sandwich", "keep": false},
	}
	state.merge(overrides, true)
	return state


func _judge(state: Dictionary = {}, subject: String = "item_sandwich") -> Result:
	return ConversationRules.judge({"kind": "give_item", "subject": subject, "amount": 0, "name": ""}, _state(state))


func _read(text: String) -> Dictionary:
	var items := OfflineTopics.name_words({"item_sandwich": ["Sandwich", "Voileipä"], "item_coffee": ["Coffee", "Kahvi"]}, false)
	return OfflineTopics.topic_of(text, "npc_ida", {}, {}, items)


func _meet_ida() -> void:
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_dock_street"
	Game.npcs.invalidate_location_cache(ida.id)
	Game.player.interior = ""
	Game.player.location = ""
	assert_ok(Game.start_conversation("npc_ida"))


func _say(text: String) -> Dictionary:
	var said: Result = await Game.say_to_npc(text)
	assert_ok(said, text)
	return said.value if said.is_ok() else {}


# --- the rules -----------------------------------------------------------------------

func test_a_gift_warms_by_its_worth_and_leaves_the_bag() -> void:
	var verdict: Dictionary = _judge().value
	assert_eq(verdict["topic"], "gift_item_accepted")
	assert_eq(verdict["effects"][0], {"do": "give_item", "item": "item_sandwich", "count": 1})
	assert_true(str(verdict["happened"]).contains("a sandwich"))
	var warmed := 0.0
	for effect: Dictionary in verdict["effects"]:
		if effect["do"] == "feel":
			warmed += float(effect["delta"])
	assert_almost(warmed, 5.0 / ConversationRules.GIFT_CASH_PER_POINT)


func test_even_a_worthless_thing_is_a_kindness_but_only_so_far() -> void:
	var cheap: Dictionary = _judge({"gift": {"count": 1, "value": 0, "name": "a thing", "keep": false}}).value
	assert_almost(float(cheap["effects"][1]["delta"]), ConversationRules.GIFT_MIN_ITEM_WARMTH)
	var dear: Dictionary = _judge({"gift": {"count": 1, "value": 9000, "name": "a thing", "keep": false}}).value
	assert_almost(float(dear["effects"][1]["delta"]), ConversationRules.GIFT_WARMTH_MAX)


func test_what_you_do_not_have_or_cannot_spare_is_a_refusal() -> void:
	assert_err(_judge({"gift": {"count": 0, "value": 5, "name": "a sandwich", "keep": false}}), "no_item")
	assert_err(_judge({"gift": {"count": 1, "value": 150, "name": "a phone", "keep": true}}), "keep_it")
	assert_err(_judge({"channel": "text"}), "not_here")
	assert_err(_judge({}, ""), "invalid_item")
	assert_err(_judge({"gift": {}}), "invalid_item")


func test_each_refusal_is_answered_in_her_own_words() -> void:
	assert_eq(ConversationRules.topic_for_refusal("no_item"), "gift_no_item")
	assert_eq(ConversationRules.topic_for_refusal("keep_it"), "gift_keep_it")
	for topic in ["gift_item_accepted", "gift_no_item", "gift_keep_it"]:
		var key := DialogueLines.pick("npc_ida", topic, 1)
		assert_ne(Localization.t(key), key, topic)


func test_the_gift_is_remembered() -> void:
	var judged := _judge()
	var kept := ConversationRules.memory_of({"kind": "give_item", "subject": "item_sandwich"}, judged, "a sandwich")
	assert_eq(kept["text"], "gave you a sandwich")


# --- reading the words -----------------------------------------------------------------

func test_a_giving_phrase_and_a_thing_make_a_gift() -> void:
	for line in ["Here, take this sandwich.", "Have a coffee, it's for you", "Annan sinulle voileivän"]:
		assert_eq(_read(line)["topic"], "give_item", line)
	assert_eq(_read("Here, take this sandwich.")["subject"], "item_sandwich")


func test_money_and_mere_mentions_are_not_gifts() -> void:
	assert_eq(_read("Here's 20 euros for a sandwich")["topic"], "give_money")
	assert_ne(_read("I like a good sandwich")["topic"], "give_item")
	assert_ne(_read("Here you go")["topic"], "give_item", "nothing named")


func test_the_model_is_offered_it() -> void:
	var system := IntentPrompt.build("here", "Ida").system
	assert_true(system.contains("- give_item:"))
	assert_true(system.contains('"item"'))


# --- in the world -----------------------------------------------------------------------

func test_the_sandwich_leaves_the_bag_and_she_thanks_you() -> void:
	_meet_ida()
	Game.player.inventory.add("item_sandwich", 2)
	var before := Game.relationships.get_edge("npc_ida", PlayerState.ID).affection
	var said := await _say("Here, take this sandwich.")
	assert_eq(said["intent"]["kind"], "give_item")
	assert_true(_rejected.is_empty(), str(_rejected))
	assert_eq(Game.player.inventory.count_of("item_sandwich"), 1)
	assert_gt(Game.relationships.get_edge("npc_ida", PlayerState.ID).affection, before)
	assert_eq(said["topic"], "gift_item_accepted")


func test_nothing_leaves_an_empty_hand() -> void:
	_meet_ida()
	var said := await _say("Here, take this sandwich.")
	assert_eq(_rejected, ["no_item"])
	assert_eq(said["topic"], "gift_no_item")


func test_the_phone_stays_in_your_pocket() -> void:
	_meet_ida()
	Game.player.inventory.add("item_phone", 1)
	_model.available = true
	_model.intents.append(ScriptedDialogueModel.meaning("give_item", {"item": "phone"}))
	_model.replies.append(ScriptedDialogueModel.say("Thanks!"))
	await _say("Have my phone")
	assert_eq(_rejected, ["keep_it"])
	assert_eq(Game.player.inventory.count_of("item_phone"), 1)
	var request := _model.requests_for(LlmRequest.Purpose.DIALOGUE)[0]
	assert_true(request.system.contains("You told them to keep it"), request.system)


func test_the_model_reads_it_and_the_rules_do_it() -> void:
	_meet_ida()
	Game.player.inventory.add("item_coffee", 1)
	_model.available = true
	_model.intents.append(ScriptedDialogueModel.meaning("give_item", {"item": "coffee"}))
	_model.replies.append(ScriptedDialogueModel.say("Oh, lovely."))
	await _say("I brought you a little something")
	assert_eq(Game.player.inventory.count_of("item_coffee"), 0)
	var request := _model.requests_for(LlmRequest.Purpose.DIALOGUE)[0]
	assert_true(request.system.contains("They handed you a coffee, and you took it."), request.system)
