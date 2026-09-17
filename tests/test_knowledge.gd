extends TestCase
## Information propagation: who knows what, how they learned it, and how
## garbled it got on the way.

var graph: RelationshipGraph
var queue: WorldEventQueue
var net: KnowledgeNetwork


func before_each() -> void:
	graph = RelationshipGraph.new()
	queue = WorldEventQueue.new()
	net = KnowledgeNetwork.new()
	net.setup(graph, queue)


func _make_social_circle() -> void:
	graph.adjust("witness", "friend_a", "familiarity", 0.8)
	graph.adjust("witness", "friend_b", "familiarity", 0.6)
	graph.adjust("friend_a", "friend_c", "familiarity", 0.7)


func test_recording_a_fact_tells_nobody() -> void:
	var fact_id := net.record("player", "stole_from", 100)
	assert_not_null(net.get_fact(fact_id))
	assert_eq(net.knowers_of(fact_id).size(), 0,
		"an event nobody saw is known to nobody")


func test_witnesses_know_it_firsthand() -> void:
	var fact_id := net.observe_event("player", "stole_from", 100, ["witness"])
	assert_true(net.knows("witness", fact_id))
	var belief := net.belief_of("witness", fact_id)
	assert_true(belief.is_firsthand())
	assert_almost(belief.confidence, 1.0)
	assert_almost(belief.distortion, 0.0)


func test_private_facts_do_not_spread() -> void:
	_make_social_circle()
	net.observe_event("player", "stole_from", 100, ["witness"], {"visibility": "private"})
	assert_eq(queue.size(), 0, "a private act queues no tellings")


func test_social_facts_queue_tellings() -> void:
	_make_social_circle()
	net.observe_event("player", "stole_from", 100, ["witness"],
		{"visibility": "social", "severity": 0.9})
	assert_gt(queue.size(), 0)


func test_gossip_reaches_a_second_hop() -> void:
	_make_social_circle()
	var fact_id := net.observe_event("player", "stole_from", 100, ["witness"],
		{"visibility": "social", "severity": 0.9})

	# Resolve a day of scheduled tellings.
	for event in queue.drain_due(100 + 1440):
		net.resolve_spread_event(event.kind, event.payload, event.at)
	for event in queue.drain_due(100 + 2880):
		net.resolve_spread_event(event.kind, event.payload, event.at)

	assert_true(net.knows("friend_a", fact_id), "the direct contact heard")
	assert_true(net.knows("friend_c", fact_id), "and it carried one hop further")


func test_retelling_degrades_the_account() -> void:
	_make_social_circle()
	var fact_id := net.observe_event("player", "stole_from", 100, ["witness"],
		{"visibility": "social", "severity": 0.9})
	for event in queue.drain_due(100 + 2880):
		net.resolve_spread_event(event.kind, event.payload, event.at)

	var direct := net.belief_of("friend_a", fact_id)
	assert_eq(direct.hops, 1)
	assert_lt(direct.confidence, 1.0)
	assert_gt(direct.distortion, 0.0)

	var distant := net.belief_of("friend_c", fact_id)
	if distant != null:
		assert_gt(distant.hops, direct.hops)
		assert_lt(distant.confidence, direct.confidence)
		assert_gt(distant.distortion, direct.distortion)


func test_the_subject_is_not_told_about_themselves() -> void:
	graph.adjust("witness", "player", "familiarity", 0.9)
	graph.adjust("witness", "friend_a", "familiarity", 0.8)
	var fact_id := net.observe_event("player", "stole_from", 100, ["witness"],
		{"visibility": "social", "severity": 0.9})
	for event in queue.drain_due(100 + 2880):
		net.resolve_spread_event(event.kind, event.payload, event.at)
	assert_false(net.knows("player", fact_id),
		"people do not gossip to the person the story is about")


func test_juicy_news_travels_faster_than_dull_news() -> void:
	_make_social_circle()
	net.observe_event("player", "assaulted", 100, ["witness"], {"severity": 1.0})
	var fast := queue.peek_time()

	var slow_queue := WorldEventQueue.new()
	var slow_net := KnowledgeNetwork.new()
	slow_net.setup(graph, slow_queue)
	slow_net.observe_event("player", "helped", 100, ["witness"], {"severity": 0.1})
	var slow := slow_queue.peek_time()

	assert_lt(float(fast), float(slow))


func test_telling_requires_knowing() -> void:
	var fact_id := net.record("player", "lied", 100)
	assert_err(net.tell("ignorant", "listener", fact_id, 200), "teller_does_not_know")


func test_deliberate_telling_works() -> void:
	var fact_id := net.observe_event("player", "lied", 100, ["witness"], {"visibility": "private"})
	assert_ok(net.tell("witness", "listener", fact_id, 200))
	assert_true(net.knows("listener", fact_id))
	assert_eq(net.belief_of("listener", fact_id).source_id, "witness")


func test_a_better_source_overwrites_a_worse_one() -> void:
	var fact_id := net.record("player", "lied", 100)
	net._learn("person", fact_id, 100, "rumour", 3, 0.3, 0.5)
	net.witness("person", fact_id, 200)
	var belief := net.belief_of("person", fact_id)
	assert_almost(belief.confidence, 1.0, 0.0001, "seeing it beats hearing it")
	assert_eq(belief.hops, 0)


func test_a_worse_source_does_not_overwrite_a_better_one() -> void:
	var fact_id := net.record("player", "lied", 100)
	net.witness("person", fact_id, 100)
	net._learn("person", fact_id, 200, "rumour", 3, 0.3, 0.5)
	assert_almost(net.belief_of("person", fact_id).confidence, 1.0)


func test_what_is_known_ranks_by_importance_and_certainty() -> void:
	var minor := net.record("player", "helped", 100, {"severity": 0.1})
	var major := net.record("player", "assaulted", 100, {"severity": 1.0})
	net.witness("person", minor, 100)
	net.witness("person", major, 100)
	var known := net.what_is_known_about("person", "player")
	assert_eq(known[0]["predicate"], "assaulted")


func test_what_is_known_filters_by_subject() -> void:
	net.witness("person", net.record("player", "helped", 100), 100)
	net.witness("person", net.record("npc_other", "lied", 100), 100)
	assert_eq(net.what_is_known_about("person", "player").size(), 1)


func test_stale_trivia_is_forgotten_but_serious_events_are_not() -> void:
	var trivial := net.record("player", "helped", 0, {"severity": 0.1})
	var serious := net.record("player", "assaulted", 0, {"severity": 0.9})
	net._learn("person", trivial, 0, "x", 2, 0.4, 0.2)
	net._learn("person", serious, 0, "x", 2, 0.4, 0.2)
	net.forget_stale(30000)
	assert_false(net.knows("person", trivial))
	assert_true(net.knows("person", serious))


func test_survives_a_save_round_trip() -> void:
	var fact_id := net.observe_event("player", "stole_from", 100, ["witness"],
		{"object": "loc_corner_shop", "severity": 0.8})
	var restored := KnowledgeNetwork.new()
	restored.setup(graph, queue)
	restored.from_dict(net.to_dict())
	assert_true(restored.knows("witness", fact_id))
	assert_eq(restored.get_fact(fact_id).object, "loc_corner_shop")
	assert_almost(restored.belief_of("witness", fact_id).confidence, 1.0)
