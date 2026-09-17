extends TestCase
## Reputation derived from knowledge, not from a hidden global counter.

var graph: RelationshipGraph
var queue: WorldEventQueue
var net: KnowledgeNetwork
var registry: NpcRegistry
var world: WorldState
var reputation: Reputation


func before_each() -> void:
	graph = RelationshipGraph.new()
	queue = WorldEventQueue.new()
	net = KnowledgeNetwork.new()
	net.setup(graph, queue)

	world = WorldState.new()
	registry = NpcRegistry.new()
	for i in range(4):
		var npc := Npc.from_data({
			"id": "crew_%d" % i, "name": "Crew %d" % i,
			"home": "loc_x", "schedule": "s", "groups": ["harbour_crew"],
		})
		registry.npcs[npc.id] = npc
	for i in range(4):
		var npc := Npc.from_data({
			"id": "cop_%d" % i, "name": "Cop %d" % i,
			"home": "loc_x", "schedule": "s", "groups": ["police_harbour"],
		})
		registry.npcs[npc.id] = npc

	reputation = Reputation.new()
	reputation.setup(net, registry, world)


func test_unknown_deeds_change_nothing() -> void:
	net.record("player", "stole_from", 100, {"severity": 1.0})
	assert_almost(reputation.standing("group:harbour_crew"), 0.0,
		0.0001, "a crime nobody knows about is not a reputation")


func test_witnessed_harm_lowers_standing() -> void:
	var fact_id := net.record("player", "assaulted", 100, {"severity": 0.9})
	for i in range(4):
		net.witness("crew_%d" % i, fact_id, 100)
	reputation.invalidate()
	assert_lt(reputation.standing("group:harbour_crew"), 0.0)


func test_witnessed_help_raises_standing() -> void:
	var fact_id := net.record("player", "helped", 100, {"severity": 0.8})
	for i in range(4):
		net.witness("crew_%d" % i, fact_id, 100)
	reputation.invalidate()
	assert_gt(reputation.standing("group:harbour_crew"), 0.0)


func test_standing_is_scoped_not_global() -> void:
	var fact_id := net.record("player", "helped", 100, {"severity": 0.9})
	for i in range(4):
		net.witness("crew_%d" % i, fact_id, 100)
	reputation.invalidate()
	assert_gt(reputation.standing("group:harbour_crew"), 0.0)
	assert_almost(reputation.standing("group:police_harbour"), 0.0,
		0.0001, "the police have not heard a thing")


func test_groups_read_the_same_act_differently() -> void:
	# Being arrested costs you nothing with the crew; informing costs you
	# everything. The police see it the other way round.
	var arrest := net.record("player", "arrested", 100, {"severity": 0.8})
	for i in range(4):
		net.witness("crew_%d" % i, arrest, 100)
		net.witness("cop_%d" % i, arrest, 100)
	reputation.invalidate()
	assert_gt(reputation.standing("group:harbour_crew"),
		reputation.standing("group:police_harbour"))


func test_snitching_is_what_the_crew_punishes() -> void:
	var snitch := net.record("player", "snitched", 100, {"severity": 0.9})
	for i in range(4):
		net.witness("crew_%d" % i, snitch, 100)
	reputation.invalidate()
	assert_lt(reputation.standing("group:harbour_crew"), -0.3)


func test_partial_knowledge_dilutes_standing() -> void:
	var fact_id := net.record("player", "helped", 100, {"severity": 1.0})
	net.witness("crew_0", fact_id, 100)
	reputation.invalidate()
	var one_knows := reputation.standing("group:harbour_crew")

	for i in range(1, 4):
		net.witness("crew_%d" % i, fact_id, 100)
	reputation.invalidate()
	assert_gt(reputation.standing("group:harbour_crew"), one_knows)


func test_garbled_secondhand_accounts_carry_less_weight() -> void:
	var fact_id := net.record("player", "assaulted", 100, {"severity": 1.0})
	for i in range(4):
		net._learn("crew_%d" % i, fact_id, 100, "gossip", 3, 0.3, 0.6)
	reputation.invalidate()
	var rumoured := reputation.standing("group:harbour_crew")

	for i in range(4):
		net.witness("crew_%d" % i, fact_id, 100)
	reputation.invalidate()
	assert_lt(reputation.standing("group:harbour_crew"), rumoured,
		"eyewitness accounts hit harder than rumour")


func test_notoriety_measures_spread() -> void:
	var fact_id := net.record("player", "stole_from", 100)
	assert_almost(reputation.notoriety("group:harbour_crew", fact_id), 0.0)
	net.witness("crew_0", fact_id, 100)
	net.witness("crew_1", fact_id, 100)
	assert_almost(reputation.notoriety("group:harbour_crew", fact_id), 0.5)


func test_explicit_standing_applies_on_top() -> void:
	reputation.set_explicit("group:police_harbour", -0.5)
	assert_almost(reputation.standing("group:police_harbour"), -0.5)
	reputation.adjust_explicit("group:police_harbour", 0.2)
	assert_almost(reputation.standing("group:police_harbour"), -0.3)


func test_standing_clamps() -> void:
	reputation.set_explicit("group:harbour_crew", 5.0)
	assert_almost(reputation.standing("group:harbour_crew"), 1.0)


func test_members_of_unknown_scope_is_empty() -> void:
	assert_eq(reputation.members_of("group:nobody").size(), 0)
	assert_eq(reputation.members_of("malformed").size(), 0)


func test_survives_a_save_round_trip() -> void:
	reputation.set_explicit("group:harbour_crew", 0.4)
	var restored := Reputation.new()
	restored.setup(net, registry, world)
	restored.from_dict(reputation.to_dict())
	assert_almost(restored.standing("group:harbour_crew"), 0.4)
