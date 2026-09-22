extends TestCase
## ask_deal (M8 step 9, D-085): DealRules gets its first caller. Asking a
## real dealer for something in conversation opens the kept shop it was for;
## everyone else's "no" is an honest refusal, except a lawful person's,
## which costs something rather than simply not happening.

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
	if Game.is_shopping():
		Game.close_shop()
	if Game.dialogue.is_talking():
		Game.end_conversation()


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


# --- ConversationRules, pure --------------------------------------------------

func _deal_facts(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"has_deal": true, "shop_id": "shop_warehouse_stash", "legality": "illicit",
		"lawfulness": 0.1, "greed": 0.3, "risk": 0.6, "discretion": 0.5,
		"requires_met": true, "familiarity": 0.9, "trust": 0.9, "vouched": false,
		"standing": 0.0, "heat": 0.0, "watched": false,
	}
	base.merge(overrides, true)
	return base


func _judge(deal: Dictionary = {}) -> Result:
	return ConversationRules.judge({"kind": "ask_deal", "subject": "", "amount": 0, "name": ""}, {
		"npc_id": "npc_rauno", "player_name": "Aino", "player_cash": 0, "relationship": {},
		"warmth": 0.0, "channel": "in_person", "deal": _deal_facts(deal),
	})


func test_a_good_deal_is_offered() -> void:
	var verdict: Dictionary = _judge().value
	assert_eq(verdict["topic"], "deal_offered")
	assert_true(verdict["ends"])
	var effect: Dictionary = verdict["effects"][0]
	assert_eq(effect["do"], "deal")
	assert_eq(effect["shop"], "shop_warehouse_stash")
	assert_gt(float(effect["factor"]), 0.0)


func test_every_ordinary_refusal_is_a_refused_proposal() -> void:
	assert_err(_judge({"has_deal": false}), "not_a_dealer")
	assert_err(_judge({"requires_met": false}), "requires_unmet")
	assert_err(_judge({"familiarity": 0.0}), "dont_know_you")
	assert_err(_judge({"trust": -1.0}), "dont_trust_you")
	assert_err(_judge({"standing": -0.5}), "bad_standing")
	assert_err(_judge({"risk": 0.2, "heat": 0.5}), "too_hot")
	assert_err(_judge({"watched": true, "risk": 0.1}), "not_now")


func test_a_lawful_persons_no_costs_trust_instead_of_refusing() -> void:
	var judged := _judge({"legality": "illicit", "lawfulness": 0.9})
	assert_ok(judged)
	var verdict: Dictionary = judged.value
	assert_eq(verdict["topic"], "wont_deal")
	assert_false(verdict["ends"])
	assert_eq(verdict["effects"][0], {"do": "feel", "dimension": "trust", "delta": -0.05 * 0.9})


func test_every_deal_refusal_has_a_topic_and_a_line() -> void:
	for code in ["not_a_dealer", "requires_unmet", "dont_know_you", "dont_trust_you", "bad_standing", "too_hot", "not_now"]:
		assert_eq(ConversationRules.topic_for_refusal(code), code)
		assert_false(DialogueLines.pick("npc_rauno", code, 1).is_empty(), code)
	assert_false(DialogueLines.pick("npc_rauno", "wont_deal", 1).is_empty())
	assert_false(DialogueLines.pick("npc_rauno", "deal_offered", 1).is_empty())


func test_the_model_is_offered_it() -> void:
	assert_true(IntentPrompt.build("got anything?", "Rauno").system.contains("- ask_deal:"))


func test_reading_the_words() -> void:
	assert_eq(str(OfflineTopics.topic_of("Got anything?", "npc_rauno", {}, {}).get("topic")), "ask_deal")
	assert_eq(str(OfflineTopics.topic_of("Onko sulla mitään?", "npc_rauno", {}, {}).get("topic")), "ask_deal")


# --- through the game ----------------------------------------------------------

## Rauno on the street, alone, and no schedule override in the way.
func _meet_rauno() -> Npc:
	var rauno := Game.npcs.get_npc("npc_rauno")
	rauno.location = "loc_dock_street"
	rauno.activity = "idle"
	Game.npcs.invalidate_location_cache("npc_rauno")
	Game.player.interior = ""
	Game.player.location = ""
	assert_ok(Game.start_conversation("npc_rauno"))
	return rauno


func test_asking_a_dealer_who_knows_you_opens_their_shop() -> void:
	_meet_rauno()
	Game.relationships.adjust("npc_rauno", PlayerState.ID, "familiarity", 0.9)
	Game.relationships.adjust("npc_rauno", PlayerState.ID, "trust", 0.9)
	var said: Result = await Game.say_to_npc("Got anything?")
	assert_ok(said)
	assert_eq(said.value["intent"]["kind"], "ask_deal")
	assert_true(_rejected.is_empty(), str(_rejected))
	assert_true(bool(said.value["ends"]))
	var opened := Game.open_deal_shop("npc_rauno", "shop_warehouse_stash")
	assert_ok(opened)
	assert_true(Game.is_shopping())
	var view := Game.shop_view()
	assert_eq(view["shop"], "shop_warehouse_stash")
	assert_eq(view["staff"], "npc_rauno")
	assert_eq(view["location"], "loc_dock_street")


func test_the_struck_price_carries_into_the_shop() -> void:
	_meet_rauno()
	Game.relationships.adjust("npc_rauno", PlayerState.ID, "familiarity", 0.9)
	Game.relationships.adjust("npc_rauno", PlayerState.ID, "trust", 0.9)
	await Game.say_to_npc("Got anything?")
	assert_ok(Game.open_deal_shop("npc_rauno", "shop_warehouse_stash"))
	var item_id: String = Game.shops.items_for_sale("shop_warehouse_stash")[0]
	var plain := Game.shops.buy_price("shop_warehouse_stash", item_id)
	var view := Game.shop_view()
	var shown := 0
	for row: Dictionary in view["for_sale"]:
		if row["item"] == item_id:
			shown = int(row["price"])
	assert_ne(shown, 0)
	# The struck factor came from real nature (greed 0.75) and real
	# closeness (0.9 familiarity, 0.9 trust) — a price, not just a pass.
	assert_ne(shown, plain, "a struck deal prices differently from the shop's plain price")


func test_a_stranger_is_turned_away() -> void:
	_meet_rauno()
	await Game.say_to_npc("Got anything?")
	assert_eq(_rejected, ["dont_know_you"])
	assert_false(Game.is_shopping())


func test_asking_someone_who_deals_nothing_gets_a_flat_no() -> void:
	var ida := Game.npcs.get_npc("npc_ida")
	ida.location = "loc_dock_street"
	ida.activity = "idle"
	Game.npcs.invalidate_location_cache("npc_ida")
	Game.player.interior = ""
	Game.player.location = ""
	assert_ok(Game.start_conversation("npc_ida"))
	await Game.say_to_npc("Got anything?")
	assert_eq(_rejected, ["not_a_dealer"])


func test_asking_a_lawful_dealer_costs_trust_and_the_shop_stays_shut() -> void:
	# Marika (an officer) deals from nothing, but a lawful person turned down
	# for an illicit ask specifically loses trust (M8 D-085) — proven here
	# against Rauno's own shop with his lawfulness overridden, since the
	# nature axis, not the person, is what the rule reads.
	_meet_rauno()
	Game.relationships.adjust("npc_rauno", PlayerState.ID, "familiarity", 0.9)
	Game.relationships.adjust("npc_rauno", PlayerState.ID, "trust", 0.9)
	Game.npcs.get_npc("npc_rauno").nature["lawfulness"] = 0.9
	var before: float = Game.relationships.peek("npc_rauno", PlayerState.ID).trust
	await Game.say_to_npc("Got anything?")
	assert_true(_rejected.is_empty(), str(_rejected))
	var after: float = Game.relationships.peek("npc_rauno", PlayerState.ID).trust
	assert_lt(after, before)
	assert_false(Game.is_shopping())
