class_name CrimeDirector
extends RefCounted
## What follows a crime (D-051). A crime is a fact in the knowledge network,
## and only what someone saw is one: an unwitnessed theft leaves nothing
## behind (`Reputation` says the same). Witnesses feel differently about the
## player, remember it, and — if it matters enough to them — tell the police,
## later, and not always. What the police then *do* about what they have been
## told is a separate step (D-052); here they only come to know — and, in
## the second half of this class, decide what to do about what they know.

## The predicates the police act on. One predicate for dealing, not one per
## commodity — severity (the item's own `heat`, M8 D-086) carries the
## difference between a joint and a bag of heroin, the way it already does
## between a sandwich and a wallet for theft.
const CRIME_PREDICATES: Array[String] = ["stole_from", "assaulted", "dealt_illicit"]

## What the player has been dealt with for: [{"fact", "outcome", "day"}], one
## per case. An earlier offence weighs on the next (`PoliceRules`).
var record: Array[Dictionary] = []
## fact id -> what was decided about it, so nothing is dealt with twice.
var handled: Dictionary = {}
## Told to come in: {"id", "officer", "due", "status": "open" | "attended" |
## "ignored", "facts"}.
var summons: Array[Dictionary] = []
## officer id -> how far she has been talked round (negative) or put out
## (positive), added to the weight of a case she is about to decide (D-053).
var leniency: Dictionary = {}
var _next_summons := 1

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
	return record_crime("stole_from", location_id, victim, noticed_by, severity, caught,
		"took something without paying" if not caught else "tried to walk off with something without paying")


## Records a crime that someone saw (theft, assault — D-051, D-054). `caught`
## is whether a witness was the one it was done to or stopped it, which weighs
## on whether they tell the police. `phrase` is how they remember it.
func record_crime(predicate: String, location_id: String, victim: String, noticed_by: Array[String],
		severity: float, caught: bool, phrase: String) -> String:
	if noticed_by.is_empty():
		return ""
	var now := _clock.total_minutes
	var fact_id := _knowledge.observe_event(PlayerState.ID, predicate, now, noticed_by, {
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
			[phrase] as Array[String], 0.8 if caught else 0.6)
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


# --- what the police make of it (D-052) -----------------------------------------------------

## What this officer believes the player has done and not yet been dealt with
## for: [{"fact", "severity", "strength", "firsthand"}]. Only what reached
## her counts, as she came to know it — never what actually happened.
func case_for(officer_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for fact_id in _knowledge.known_fact_ids(officer_id):
		var fact := _knowledge.get_fact(fact_id)
		if fact == null or fact.subject != PlayerState.ID or not CRIME_PREDICATES.has(fact.predicate) 				or handled.has(fact_id):
			continue
		var belief := _knowledge.belief_of(officer_id, fact_id)
		out.append({"fact": fact_id, "severity": fact.severity,
			"strength": PoliceRules.strength(belief.confidence, belief.distortion), "firsthand": belief.is_firsthand()})
	return out


## Everything this person believes the player has done that people are
## punished or shunned for — dealt with by the police or not (D-055):
## [{"fact", "predicate", "severity", "strength"}]. An employer asks this; the
## police ask `case_for`, which leaves out what is already settled.
func known_offences(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for fact_id in _knowledge.known_fact_ids(npc_id):
		var fact := _knowledge.get_fact(fact_id)
		if fact == null or fact.subject != PlayerState.ID or not (CRIME_PREDICATES.has(fact.predicate) or fact.predicate == "arrested"):
			continue
		var belief := _knowledge.belief_of(npc_id, fact_id)
		out.append({"fact": fact_id, "predicate": fact.predicate, "severity": fact.severity,
			"strength": PoliceRules.strength(belief.confidence, belief.distortion)})
	return out


## An officer has come to know something: she gets round to deciding what to
## do about it, in her own time.
func on_fact_learned(knower_id: String, fact_id: String) -> void:
	if not officers().has(knower_id):
		return
	var fact := _knowledge.get_fact(fact_id)
	if fact == null or fact.subject != PlayerState.ID or not CRIME_PREDICATES.has(fact.predicate) 			or handled.has(fact_id):
		return
	if not open_summons_for(knower_id).is_empty() or _assess_scheduled(knower_id):
		return
	var npc := _npcs.get_npc(knower_id)
	_events.schedule(_clock.total_minutes + PoliceRules.assess_delay(npc.traits if npc != null else []),
		"police_assess", {"officer": knower_id})


## She decides. Returns the summons she issues, or {} when what she knows does
## not warrant one (a rumour, or too petty) — and she may look again if more
## reaches her.
func assess(officer_id: String) -> Dictionary:
	if not open_summons_for(officer_id).is_empty():
		return {}
	var entries := case_for(officer_id)
	var npc := _npcs.get_npc(officer_id)
	if PoliceRules.judge_response(entries, record.size(), npc.traits if npc != null else [], false,
			float(leniency.get(officer_id, 0.0))) == "none":
		return {}
	var due := _clock.total_minutes + PoliceRules.SUMMONS_WINDOW
	var facts: Array[String] = []
	for entry in entries:
		facts.append(str(entry["fact"]))
	var issued := {"id": _next_summons, "officer": officer_id, "due": due, "status": "open", "facts": facts}
	_next_summons += 1
	summons.append(issued)
	_events.schedule(due, "police_summons_due", {"summons": int(issued["id"])})
	Events.summons_issued.emit(int(issued["id"]))
	return issued


func get_summons(summons_id: int) -> Dictionary:
	for entry in summons:
		if int(entry["id"]) == summons_id:
			return entry
	return {}


func open_summons_for(officer_id: String) -> Dictionary:
	for entry in summons:
		if entry["officer"] == officer_id and entry["status"] == "open":
			return entry
	return {}


## The case is weighed — the player came in, or did not. Returns {"outcome":
## "none" | "warning" | "fine" | "arrest", "fine": int, "officer", "facts",
## "severity", "attended"}, or {} when there is nothing open. `money` is what
## the player could pay a fine with: a fine they cannot pay is a night in the
## cells. The record and what has been dealt with are kept here; what the
## outcome does to the player is the game's.
func resolve(summons_id: int, attended: bool, money: int) -> Dictionary:
	var open := get_summons(summons_id)
	if open.is_empty() or open["status"] != "open":
		return {}
	var officer_id := str(open["officer"])
	var npc := _npcs.get_npc(officer_id)
	var entries := case_for(officer_id)
	var outcome := PoliceRules.judge_response(entries, record.size(), npc.traits if npc != null else [], not attended,
		float(leniency.get(officer_id, 0.0)))
	leniency.erase(officer_id)   # what was said is spent once she has decided
	var worst := 0.0
	var facts: Array[String] = []
	for entry in entries:
		worst = maxf(worst, float(entry["severity"]))
		facts.append(str(entry["fact"]))
	var fine := PoliceRules.fine_for(worst) if outcome == "fine" else 0
	outcome = PoliceRules.settle(outcome, fine, money)
	open["status"] = "attended" if attended else "ignored"
	for fact_id in facts:
		handled[fact_id] = outcome
	if outcome != "none":
		record.append({"fact": facts[0], "outcome": outcome, "day": _clock.day_index()})
	return {"outcome": outcome, "fine": fine if outcome == "fine" else 0, "officer": officer_id,
		"facts": facts, "severity": worst, "attended": attended}


func to_dict() -> Dictionary:
	return {"record": record.duplicate(true), "handled": handled.duplicate(), "summons": summons.duplicate(true),
		"leniency": leniency.duplicate(), "next_summons": _next_summons}


func from_dict(d: Dictionary) -> void:
	record = []
	for raw: Dictionary in d.get("record", []):
		record.append({"fact": str(raw.get("fact", "")), "outcome": str(raw.get("outcome", "")), "day": int(raw.get("day", 0))})
	handled = {}
	var raw_handled: Dictionary = d.get("handled", {})
	for fact_id in raw_handled:
		handled[str(fact_id)] = str(raw_handled[fact_id])
	summons = []
	for raw: Dictionary in d.get("summons", []):
		var facts: Array[String] = []
		for fact_id in raw.get("facts", []):
			facts.append(str(fact_id))
		summons.append({"id": int(raw.get("id", 0)), "officer": str(raw.get("officer", "")), "due": int(raw.get("due", 0)),
			"status": str(raw.get("status", "open")), "facts": facts})
	leniency = {}
	var raw_leniency: Dictionary = d.get("leniency", {})
	for officer_id in raw_leniency:
		leniency[str(officer_id)] = float(raw_leniency[officer_id])
	_next_summons = int(d.get("next_summons", 1))
	for entry in summons:
		_next_summons = maxi(_next_summons, int(entry["id"]) + 1)


func _assess_scheduled(officer_id: String) -> bool:
	for event in _events.pending():
		if event.kind == "police_assess" and str(event.payload.get("officer", "")) == officer_id:
			return true
	return false
