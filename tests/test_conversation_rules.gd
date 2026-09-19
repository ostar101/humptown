extends TestCase
## What a line is allowed to change (D-037), judged as a pure function: an
## intent and the state of the world in, effects or a refusal out.


func _state(overrides: Dictionary = {}) -> Dictionary:
	var state := {
		"npc_id": "npc_ida", "player_name": "Aino", "player_cash": 100,
		"relationship": {}, "warmth": 0.0,
	}
	state.merge(overrides, true)
	return state


func _judge(kind: String, fields: Dictionary = {}, state: Dictionary = {}) -> Result:
	var intent := {"kind": kind, "subject": "", "amount": 0, "name": ""}
	intent.merge(fields, true)
	return ConversationRules.judge(intent, _state(state))


func _feel(verdict: Dictionary, dimension: String) -> float:
	var total := 0.0
	for effect: Dictionary in verdict["effects"]:
		if effect["do"] == "feel" and effect["dimension"] == dimension:
			total += float(effect["delta"])
	return total


func _does(verdict: Dictionary, what: String) -> bool:
	for effect: Dictionary in verdict["effects"]:
		if effect["do"] == what:
			return true
	return false


# --- talk that changes little ------------------------------------------------------

func test_a_greeting_changes_nothing_and_goodbye_ends_it() -> void:
	var hello: Dictionary = _judge("greet").value
	assert_true(hello["effects"].is_empty())
	assert_false(hello["ends"])
	assert_true(_judge("farewell").value["ends"])


func test_a_kind_without_rules_is_talk() -> void:
	var persuading := _judge("lie")
	assert_ok(persuading, "the player is never restricted to a list")
	assert_true(persuading.value["effects"].is_empty(), "but nothing happens without a rule for it")
	assert_eq(persuading.value["topic"], "unknown")


func test_asking_who_someone_is_is_an_introduction() -> void:
	assert_true(_does(_judge("about_self").value, "introduce_them"))


func test_giving_your_own_name_introduces_you_and_a_false_one_does_not() -> void:
	var honest: Dictionary = _judge("introduce_self", {"name": "aino"}).value
	assert_true(_does(honest, "introduce_player"), "the name matches, whatever the case")
	var unnamed: Dictionary = _judge("introduce_self").value
	assert_true(_does(unnamed, "introduce_player"), "no name heard: they are who they are")
	var false_name: Dictionary = _judge("introduce_self", {"name": "Bob"}).value
	assert_false(_does(false_name, "introduce_player"), "a lie is theirs to tell; it is not learned")
	assert_true(str(false_name["happened"]).contains("Bob"))


# --- feelings -----------------------------------------------------------------------

func test_a_compliment_warms_until_the_conversation_is_warm_enough() -> void:
	assert_gt(_feel(_judge("compliment").value, "affection"), 0.0)
	var enough: Dictionary = _judge("compliment", {}, {"warmth": ConversationRules.WARMTH_CAP}).value
	assert_eq(_feel(enough, "affection"), 0.0, "flattery has diminishing returns")


func test_an_insult_always_lands_and_is_remembered() -> void:
	var insult: Dictionary = _judge("insult", {}, {"warmth": ConversationRules.WARMTH_CAP}).value
	assert_lt(_feel(insult, "affection"), 0.0, "coldness has no cap")
	assert_true(_does(insult, "remember"), "being insulted is something they saw happen")


func test_a_threat_frightens_and_ends_the_conversation() -> void:
	var threat: Dictionary = _judge("threaten").value
	assert_gt(_feel(threat, "fear"), 0.0)
	assert_lt(_feel(threat, "trust"), 0.0)
	assert_true(threat["ends"])
	assert_true(_does(threat, "remember"))


func test_an_apology_mends_a_grievance_and_nothing_more() -> void:
	var sorry: Dictionary = _judge("apologize", {}, {"relationship": {"affection": -0.02}}).value
	assert_almost(_feel(sorry, "affection"), 0.02, 0.0001, "back to even, not beyond")
	var needless: Dictionary = _judge("apologize", {}, {"relationship": {"affection": 0.3}}).value
	assert_true(needless["effects"].is_empty())


func test_flirting_is_welcome_only_from_someone_known_and_liked() -> void:
	var stranger: Dictionary = _judge("flirt").value
	assert_eq(stranger["topic"], "flirt_unwelcome")
	assert_lt(_feel(stranger, "affection"), 0.0)
	var friend: Dictionary = _judge("flirt", {}, {"relationship": {"familiarity": 0.5, "affection": 0.4}}).value
	assert_eq(friend["topic"], "flirt_welcome")
	assert_gt(_feel(friend, "affection"), 0.0)


# --- money ----------------------------------------------------------------------------

func test_a_gift_needs_the_cash_to_be_there() -> void:
	var refused := _judge("give_money", {"amount": 500})
	assert_err(refused, "not_enough_cash")
	assert_true(refused.message.contains("Nothing changed hands"), "the person is told what really happened")
	assert_eq(ConversationRules.topic_for_refusal(refused.code), "gift_no_cash")


func test_a_gift_must_be_an_amount_you_could_hand_over() -> void:
	assert_err(_judge("give_money", {"amount": 0}), "invalid_amount")
	assert_err(_judge("give_money", {"amount": -5}), "invalid_amount")
	assert_err(_judge("give_money", {"amount": ConversationRules.MAX_GIFT + 1},
		{"player_cash": 1_000_000}), "invalid_amount", "past a point it is a transaction, and that is M4")


func test_a_gift_that_can_be_given_is_paid_felt_and_remembered() -> void:
	var gift: Dictionary = _judge("give_money", {"amount": 20}).value
	var paid := 0
	for effect: Dictionary in gift["effects"]:
		if effect["do"] == "pay":
			paid = int(effect["amount"])
	assert_eq(paid, 20)
	assert_gt(_feel(gift, "affection"), 0.0)
	assert_true(_does(gift, "remember"))
	assert_eq(gift["topic"], "gift_accepted")
	assert_true(str(gift["happened"]).contains("20"))


func test_warmth_counts_only_the_warm_effects() -> void:
	var effects: Array[Dictionary] = [
		{"do": "feel", "dimension": "affection", "delta": 0.04},
		{"do": "feel", "dimension": "fear", "delta": 0.2},
		{"do": "feel", "dimension": "trust", "delta": -0.1},
		{"do": "pay", "amount": 5},
	]
	assert_almost(ConversationRules.warmth_of(effects), 0.04, 0.0001)
