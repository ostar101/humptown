extends TestCase
## Directed relationships and the social graph gossip travels along.

var graph: RelationshipGraph


func before_each() -> void:
	graph = RelationshipGraph.new()


func test_relationships_are_directed() -> void:
	graph.adjust("a", "b", "trust", 0.8)
	assert_almost(graph.disposition("a", "b"), 0.32)
	assert_almost(graph.disposition("b", "a"), 0.0,
		0.0001, "trusting someone does not make them trust you")


func test_peek_does_not_create() -> void:
	assert_null(graph.peek("a", "b"))
	assert_eq(graph.edge_count(), 0)
	assert_not_null(graph.get_edge("a", "b"))
	assert_eq(graph.edge_count(), 1)


func test_dimensions_clamp() -> void:
	graph.adjust("a", "b", "trust", 5.0)
	assert_almost(graph.get_edge("a", "b").trust, 1.0)
	graph.adjust("a", "b", "trust", -50.0)
	assert_almost(graph.get_edge("a", "b").trust, -1.0)


func test_familiarity_never_goes_negative() -> void:
	graph.adjust("a", "b", "familiarity", -1.0)
	assert_almost(graph.get_edge("a", "b").familiarity, 0.0)


func test_apply_batches_deltas() -> void:
	graph.apply("a", "b", {"trust": 0.2, "affection": 0.4, "familiarity": 0.1}, 500)
	var edge := graph.get_edge("a", "b")
	assert_almost(edge.trust, 0.2)
	assert_almost(edge.affection, 0.4)
	assert_eq(edge.last_interaction, 500)


func test_setting_kind_is_symmetric_by_default() -> void:
	graph.set_kind("a", "b", Relationship.Kind.FAMILY)
	assert_eq(graph.get_edge("b", "a").kind, Relationship.Kind.FAMILY)


func test_asymmetric_kind() -> void:
	graph.set_kind("a", "b", Relationship.Kind.RIVAL, false)
	assert_eq(graph.get_edge("b", "a").kind, Relationship.Kind.STRANGER)


func test_emits_change_events() -> void:
	var seen := []
	var handler := func(f: String, t: String, d: String, delta: float) -> void:
		seen.append([f, t, d, delta])
	Events.relationship_changed.connect(handler)
	graph.adjust("a", "b", "trust", 0.3)
	Events.relationship_changed.disconnect(handler)
	assert_eq(seen.size(), 1)
	assert_eq(seen[0][2], "trust")


func test_zero_delta_is_a_no_op() -> void:
	var count := [0]
	var handler := func(_a: String, _b: String, _c: String, _d: float) -> void: count[0] += 1
	Events.relationship_changed.connect(handler)
	graph.adjust("a", "b", "trust", 0.0)
	Events.relationship_changed.disconnect(handler)
	assert_eq(count[0], 0)


func test_close_contacts_are_ranked_and_thresholded() -> void:
	graph.adjust("a", "friend", "familiarity", 0.9)
	graph.adjust("a", "mate", "familiarity", 0.5)
	graph.adjust("a", "stranger", "familiarity", 0.05)
	var close := graph.close_contacts("a", 0.25)
	assert_eq(close.size(), 2, "the near-stranger is below the threshold")
	assert_eq(close[0], "friend", "strongest tie first")


func test_close_contacts_respect_the_limit() -> void:
	for i in range(20):
		graph.adjust("a", "p%d" % i, "familiarity", 0.5)
	assert_eq(graph.close_contacts("a", 0.25, 5).size(), 5)


func test_who_knows_finds_incoming_edges() -> void:
	graph.adjust("a", "target", "trust", 0.1)
	graph.adjust("b", "target", "trust", 0.1)
	var incoming := graph.who_knows("target")
	assert_eq(incoming.size(), 2)
	assert_has(incoming, "a")


func test_disposition_weighs_goodwill_over_fear() -> void:
	graph.adjust("a", "liked", "trust", 1.0)
	graph.adjust("a", "liked", "affection", 1.0)
	graph.adjust("a", "feared", "fear", 1.0)
	assert_gt(graph.disposition("a", "liked"), graph.disposition("a", "feared"))


func test_describe_reflects_familiarity_and_feeling() -> void:
	assert_eq(graph.get_edge("a", "b").describe(), "a stranger")
	graph.apply("a", "b", {"familiarity": 0.8, "trust": 0.9, "affection": 0.9})
	graph.set_kind("a", "b", Relationship.Kind.FRIEND)
	assert_eq(graph.get_edge("a", "b").describe(), "a trusted friend")


func test_seed_from_data() -> void:
	graph.seed_from_data([
		{"from": "a", "to": "b", "kind": "family", "trust": 0.8, "familiarity": 1.0},
	])
	var edge := graph.get_edge("a", "b")
	assert_eq(edge.kind, Relationship.Kind.FAMILY)
	assert_almost(edge.trust, 0.8)


func test_purge_removes_both_directions() -> void:
	graph.adjust("a", "b", "trust", 0.5)
	graph.adjust("b", "a", "trust", 0.5)
	graph.adjust("c", "b", "trust", 0.5)
	graph.purge("b")
	assert_null(graph.peek("a", "b"))
	assert_null(graph.peek("c", "b"))
	assert_eq(graph.contacts_of("b").size(), 0)


func test_survives_a_save_round_trip() -> void:
	graph.apply("a", "b", {"trust": 0.4, "familiarity": 0.7}, 300)
	graph.set_kind("a", "b", Relationship.Kind.COLLEAGUE)
	var restored := RelationshipGraph.new()
	restored.from_dict(graph.to_dict())
	var edge := restored.peek("a", "b")
	assert_not_null(edge)
	assert_almost(edge.trust, 0.4)
	assert_eq(edge.kind, Relationship.Kind.COLLEAGUE)
	assert_eq(restored.who_knows("b").size(), 1, "reverse index is rebuilt")
