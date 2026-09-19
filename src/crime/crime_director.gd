class_name CrimeDirector
extends RefCounted
## What follows a crime (D-051). A crime is a fact in the knowledge network,
## and only what someone saw is one: an unwitnessed theft leaves nothing
## behind (`Reputation` says the same). Witnesses feel differently about the
## player, remember it, and — if it matters enough to them — tell the police,
## later, and not always. What the police then *do* about what they have been
## told is a separate step (D-052); here they only come to know.

var _npcs: NpcRegistry = null
var _knowledge: KnowledgeNetwork = null
var _relationships: RelationshipGraph = null
var _memories: MemoryBook = null
var _events: WorldEventQueue = null
var _clock: GameClock = null


func setup(npcs: NpcRegistry, knowledge: KnowledgeNetwork, relationships: RelationshipGraph,
		memories: MemoryBook, events: WorldEventQueue, clock: GameClock) -> void:
	_npcs = npcs
	_knowledge = knowledge
	_relationships = relationships
	_memories = memories
	_events = events
	_clock = clock


## Everyone in a position to notice something at this place, by what the
## simulation says: awake, and there. `staff` is whoever is on duty. Each is
## {"id", "is_staff", "chance"}, in a fixed order so dice fall the same way.
func watchers(location_id: String, staff: String, stealth_level: int, condition: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array = _npcs.living_ids()
	ids.sort()
	for npc_id: String in ids:
		var npc := _npcs.get_npc(npc_id)
		if npc.location != location_id or npc.activity == "sleep":
			continue
		var on_duty := npc_id == staff
		out.append({"id": npc_id, "is_staff": on_duty,
			"chance": TheftRules.notice_chance(on_duty, npc.traits, stealth_level, condition)})
	return out


## The people whose job it is: anyone in a group whose name starts with "police".
func officers() -> Array[String]:
	var out: Array[String] = []
	for npc_id: String in _npcs.living_ids():
		for group in _npcs.get_npc(npc_id).groups:
			if str(group).begins_with("police"):
				out.append(npc_id)
				break
	return out


## Records a theft that someone saw. Returns the fact's id, or "" when nobody
## did — and then nothing happened, as far as the world can tell.
func record_theft(location_id: String, victim: String, noticed_by: Array[String], severity: float,
		caught: bool) -> String:
	if noticed_by.is_empty():
		return ""
	var now := _clock.total_minutes
	var fact_id := _knowledge.observe_event(PlayerState.ID, "stole_from", now, noticed_by, {
		"object": victim, "location": location_id, "severity": severity, "visibility": "social",
	})
	for witness_id in noticed_by:
		var npc := _npcs.get_npc(witness_id)
		var feeling := _relationships.peek(witness_id, PlayerState.ID)
		var urge := TheftRules.report_urge(severity, caught, feeling.affection if feeling != null else 0.0,
			npc.traits if npc != null else [])
		_relationships.adjust(witness_id, PlayerState.ID, "affection", TheftRules.AFFECTION_HIT, now)
		_relationships.adjust(witness_id, PlayerState.ID, "trust", TheftRules.TRUST_HIT, now)
		_memories.add_episode(witness_id, now, location_id,
			["took something without paying" if not caught else "tried to walk off with something without paying"] as Array[String],
			0.8 if caught else 0.6)
		if TheftRules.will_report(urge) and not officers().has(witness_id):
			_events.schedule(now + TheftRules.report_delay(witness_id, fact_id), "crime_report",
				{"fact": fact_id, "reporter": witness_id})
	Events.crime_committed.emit(fact_id, location_id)
	return fact_id


## A witness gets round to telling the police. The officer comes to know it
## the way anyone learns from someone else: a little less sure of it.
func deliver_report(payload: Dictionary) -> void:
	var fact_id := str(payload.get("fact", ""))
	var reporter := str(payload.get("reporter", ""))
	for officer_id in officers():
		if officer_id == reporter:
			continue
		if _knowledge.tell(reporter, officer_id, fact_id, _clock.total_minutes).is_ok():
			Events.crime_reported.emit(fact_id, reporter, officer_id)
