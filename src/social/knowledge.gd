class_name KnowledgeNetwork
extends RefCounted
## Who knows what, how they found out, and how wrong they are about it.
##
## NPCs do not read world state. They know only what reached them, through a
## traceable path: they saw it, someone told them, they read it, it was on the
## news. That single constraint is what makes secrecy, rumour and reputation
## work without any of them being special-cased.
##
## A fact spreads by scheduling future "telling" events along the relationship
## graph rather than by polling, so a rumour crossing town costs a handful of
## queue entries, not a simulation loop.

## How far a fact can travel on its own.
enum Visibility {
	PRIVATE,      ## Only direct witnesses. Never spreads unless someone tells.
	SOCIAL,       ## Spreads through personal ties.
	PUBLIC,       ## Happened in the open; spreads fast and widely.
	BROADCAST,    ## Reported by news/online. Effectively everyone eventually.
}

const VISIBILITY_NAMES := ["private", "social", "public", "broadcast"]

## Facts weaker than this are not worth passing on.
const MIN_SPREAD_CONFIDENCE := 0.25
## Distortion added per retelling.
const DISTORTION_PER_HOP := 0.12
## Confidence lost per retelling.
const CONFIDENCE_PER_HOP := 0.15


class Fact extends RefCounted:
	var id: String
	var subject: String          ## whom it is about (npc id or "player")
	var predicate: String        ## e.g. "stole_from", "works_at", "was_seen_with"
	var object: String = ""      ## optional target
	var at_minute: int = 0
	var location: String = ""
	var visibility: Visibility = Visibility.SOCIAL
	## How much this matters; drives spread speed and memory retention.
	var severity: float = 0.5
	## False facts are rumours that were wrong from the start.
	var truth: bool = true
	var tags: Array[String] = []

	func to_dict() -> Dictionary:
		return {
			"id": id, "subject": subject, "predicate": predicate, "object": object,
			"at": at_minute, "location": location, "visibility": int(visibility),
			"severity": severity, "truth": truth, "tags": tags,
		}

	static func from_dict(d: Dictionary) -> Fact:
		var f := Fact.new()
		f.id = str(d.get("id", ""))
		f.subject = str(d.get("subject", ""))
		f.predicate = str(d.get("predicate", ""))
		f.object = str(d.get("object", ""))
		f.at_minute = int(d.get("at", 0))
		f.location = str(d.get("location", ""))
		f.visibility = d.get("visibility", Visibility.SOCIAL) as Visibility
		f.severity = float(d.get("severity", 0.5))
		f.truth = bool(d.get("truth", true))
		var t: Array[String] = []
		for tag in d.get("tags", []):
			t.append(str(tag))
		f.tags = t
		return f


## One person's grasp of one fact.
class Belief extends RefCounted:
	var fact_id: String
	var confidence: float = 1.0     ## how sure they are
	var distortion: float = 0.0     ## how garbled the retelling has become
	var learned_at: int = 0
	var source_id: String = ""      ## who told them, or "" for direct witness
	var hops: int = 0               ## retellings away from the event
	var faded_at: int = 0           ## the minute `fade()` last wore it down

	func is_firsthand() -> bool:
		return hops == 0

	## Whether they would state this as fact rather than hedge.
	func is_confident() -> bool:
		return confidence >= 0.6 and distortion < 0.4

	func to_dict() -> Dictionary:
		return {
			"fact": fact_id, "conf": confidence, "dist": distortion,
			"at": learned_at, "src": source_id, "hops": hops, "faded": faded_at,
		}

	static func from_dict(d: Dictionary) -> Belief:
		var b := Belief.new()
		b.fact_id = str(d.get("fact", ""))
		b.confidence = float(d.get("conf", 1.0))
		b.distortion = float(d.get("dist", 0.0))
		b.learned_at = int(d.get("at", 0))
		b.source_id = str(d.get("src", ""))
		b.hops = int(d.get("hops", 0))
		b.faded_at = int(d.get("faded", b.learned_at))
		return b


var facts: Dictionary = {}          # fact_id -> Fact
var beliefs: Dictionary = {}        # knower_id -> { fact_id -> Belief }
var _next_fact := 1

var _graph: RelationshipGraph = null
var _queue: WorldEventQueue = null


func setup(graph: RelationshipGraph, queue: WorldEventQueue) -> void:
	_graph = graph
	_queue = queue


# --- creating and observing -------------------------------------------------

## Records that something happened. Returns the fact id.
func record(subject: String, predicate: String, at_minute: int, opts: Dictionary = {}) -> String:
	var f := Fact.new()
	f.id = str(opts.get("id", "fact_%04d" % _next_fact))
	_next_fact += 1
	f.subject = subject
	f.predicate = predicate
	f.object = str(opts.get("object", ""))
	f.at_minute = at_minute
	f.location = str(opts.get("location", ""))
	f.severity = float(opts.get("severity", 0.5))
	f.truth = bool(opts.get("truth", true))
	var vis := str(opts.get("visibility", "social"))
	var vis_idx := VISIBILITY_NAMES.find(vis)
	f.visibility = (vis_idx if vis_idx >= 0 else Visibility.SOCIAL) as Visibility
	for tag in opts.get("tags", []):
		f.tags.append(str(tag))
	facts[f.id] = f
	return f.id


func get_fact(fact_id: String) -> Fact:
	return facts.get(fact_id)


## Someone directly perceives a fact. Firsthand knowledge: full confidence.
func witness(knower_id: String, fact_id: String, at_minute: int) -> void:
	_learn(knower_id, fact_id, at_minute, "", 0, 1.0, 0.0)


## Records the event and immediately gives it to its witnesses, then lets it
## start spreading according to its visibility.
func observe_event(subject: String, predicate: String, at_minute: int,
		witnesses: Array[String], opts: Dictionary = {}) -> String:
	var fact_id := record(subject, predicate, at_minute, opts)
	for w in witnesses:
		witness(w, fact_id, at_minute)
	begin_spread(fact_id, at_minute, witnesses)
	return fact_id


func knows(knower_id: String, fact_id: String) -> bool:
	return beliefs.has(knower_id) and beliefs[knower_id].has(fact_id)


func belief_of(knower_id: String, fact_id: String) -> Belief:
	if not beliefs.has(knower_id):
		return null
	return beliefs[knower_id].get(fact_id)


func known_fact_ids(knower_id: String) -> Array[String]:
	var out: Array[String] = []
	for fact_id in beliefs.get(knower_id, {}):
		out.append(str(fact_id))
	return out


## Everyone who knows a fact. Used for "has this got out?" checks.
func knowers_of(fact_id: String) -> Array[String]:
	var out: Array[String] = []
	for knower_id in beliefs:
		if beliefs[knower_id].has(fact_id):
			out.append(str(knower_id))
	return out


## What `knower_id` knows about `subject`, strongest belief first. This is
## the selection step that keeps LLM prompts small.
func what_is_known_about(knower_id: String, subject: String, limit: int = 6) -> Array[Dictionary]:
	var scored: Array = []
	for fact_id in beliefs.get(knower_id, {}):
		var fact: Fact = facts.get(fact_id)
		if fact == null or fact.subject != subject:
			continue
		var belief: Belief = beliefs[knower_id][fact_id]
		scored.append({
			"fact": fact, "belief": belief,
			"score": fact.severity * belief.confidence,
		})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	var out: Array[Dictionary] = []
	for entry in scored.slice(0, limit):
		var fact: Fact = entry["fact"]
		var belief: Belief = entry["belief"]
		out.append({
			"predicate": fact.predicate,
			"object": fact.object,
			"confident": belief.is_confident(),
			"firsthand": belief.is_firsthand(),
			"distortion": belief.distortion,
		})
	return out


# --- propagation ------------------------------------------------------------

## Starts a fact travelling. Private facts go nowhere on their own.
func begin_spread(fact_id: String, now: int, from_ids: Array[String]) -> void:
	var fact: Fact = facts.get(fact_id)
	if fact == null or _queue == null or _graph == null:
		return
	if fact.visibility == Visibility.PRIVATE:
		return
	if fact.visibility == Visibility.BROADCAST:
		# Reported publicly: everyone learns it within a day, no social path.
		_queue.schedule(now + 120, "knowledge_broadcast", {"fact": fact_id})
		return
	for teller in from_ids:
		_schedule_tellings(teller, fact_id, now)


## Deliberate telling: the player or an NPC chooses to pass something on.
func tell(teller_id: String, listener_id: String, fact_id: String, now: int) -> Result:
	var belief := belief_of(teller_id, fact_id)
	if belief == null:
		return Result.failure("teller_does_not_know", fact_id)
	var new_conf := belief.confidence - CONFIDENCE_PER_HOP
	var new_dist := belief.distortion + DISTORTION_PER_HOP
	_learn(listener_id, fact_id, now, teller_id, belief.hops + 1, new_conf, new_dist)
	return Result.success(fact_id)


## Resolves a queued spreading event. Called by the world event handler.
func resolve_spread_event(event_kind: String, payload: Dictionary, now: int) -> void:
	match event_kind:
		"knowledge_tell":
			var teller := str(payload.get("from", ""))
			var listener := str(payload.get("to", ""))
			var fact_id := str(payload.get("fact", ""))
			if knows(listener, fact_id):
				return
			if tell(teller, listener, fact_id, now).is_ok():
				_schedule_tellings(listener, fact_id, now)
		"knowledge_broadcast":
			var fact_id := str(payload.get("fact", ""))
			for knower_id in _graph.contacts_of(RelationshipGraph.PLAYER_ID):
				if not knows(knower_id, fact_id):
					_learn(knower_id, fact_id, now, "news", 1, 0.8, 0.05)


## Queues future tellings from one person to their close contacts. Spread
## speed scales with how interesting the fact is.
func _schedule_tellings(teller_id: String, fact_id: String, now: int) -> void:
	var belief := belief_of(teller_id, fact_id)
	var fact: Fact = facts.get(fact_id)
	if belief == null or fact == null or _queue == null or _graph == null:
		return
	if belief.confidence < MIN_SPREAD_CONFIDENCE:
		return

	var reach := 3 if fact.visibility == Visibility.PUBLIC else 2
	var contacts := _graph.close_contacts(teller_id, 0.25, reach)
	# Juicier news travels faster: severity 1.0 -> ~30 min, 0.1 -> ~8 h.
	var base_delay := int(lerpf(480.0, 30.0, clampf(fact.severity, 0.0, 1.0)))
	var i := 0
	for listener_id in contacts:
		if listener_id == fact.subject:
			i += 1
			continue  # people rarely gossip to the person it is about
		if knows(listener_id, fact_id):
			i += 1
			continue
		var jitter := int(RngStreams.stable_unit(teller_id + listener_id + fact_id, "gossip") * 180.0)
		_queue.schedule(now + base_delay + jitter + i * 20, "knowledge_tell", {
			"from": teller_id, "to": listener_id, "fact": fact_id,
		})
		i += 1


func _learn(knower_id: String, fact_id: String, at_minute: int, source_id: String,
		hops: int, confidence: float, distortion: float) -> void:
	if not facts.has(fact_id):
		return
	if not beliefs.has(knower_id):
		beliefs[knower_id] = {}
	var existing: Belief = beliefs[knower_id].get(fact_id)
	# A better-sourced account replaces a worse one.
	if existing != null and existing.confidence >= confidence:
		return
	var b := Belief.new()
	b.fact_id = fact_id
	b.confidence = clampf(confidence, 0.0, 1.0)
	b.distortion = clampf(distortion, 0.0, 1.0)
	b.learned_at = at_minute
	b.faded_at = at_minute
	b.source_id = source_id
	b.hops = hops
	beliefs[knower_id][fact_id] = b
	Events.fact_learned.emit(knower_id, fact_id, source_id)


## Memory wears (D-090): every belief grows less sure with time, halving over
## a span that grows with how much it mattered — days for trivia, months for a
## beating — and three times as long for what someone saw with their own eyes.
## Because everything that reads knowledge reads `confidence` (reputation,
## the police, a dealer, a grudge, gossip itself), all of it cools the same
## way, with nothing special-cased: an old story weighs less, stops being
## passed on, and in the end is gone. It used to be kept for ever unless it was
## trivial, and the network only grew.
const FADE_BASE_DAYS := 4.0
const FADE_SEVERITY_DAYS := 56.0
const FIRSTHAND_MEMORY := 3.0
## Below this, a belief is forgotten.
const FORGET_BELOW := 0.1


## How many days it takes this belief to lose half its certainty.
static func half_life_days(severity: float, firsthand: bool) -> float:
	var days := FADE_BASE_DAYS + FADE_SEVERITY_DAYS * severity * severity
	return days * (FIRSTHAND_MEMORY if firsthand else 1.0)


## Wears every belief down to `now`, forgets the ones worn through, and drops
## facts nobody holds any more. Called once a day. Returns how many beliefs
## were forgotten.
func fade(now: int) -> int:
	var removed := 0
	for knower_id in beliefs:
		var to_drop: Array[String] = []
		for fact_id in beliefs[knower_id]:
			var belief: Belief = beliefs[knower_id][fact_id]
			var fact: Fact = facts.get(fact_id)
			if fact == null:
				to_drop.append(str(fact_id))
				continue
			var days := float(now - belief.faded_at) / 1440.0
			if days > 0.0:
				belief.confidence *= pow(0.5, days / half_life_days(fact.severity, belief.is_firsthand()))
				belief.faded_at = now
			if belief.confidence < FORGET_BELOW:
				to_drop.append(str(fact_id))
		for fact_id in to_drop:
			beliefs[knower_id].erase(fact_id)
			removed += 1
	var held := {}
	for knower_id in beliefs:
		for fact_id in beliefs[knower_id]:
			held[fact_id] = true
	for fact_id in facts.keys():
		if not held.has(fact_id) and now - (facts[fact_id] as Fact).at_minute > 1440:
			facts.erase(fact_id)
	return removed


func to_dict() -> Dictionary:
	var fact_out := {}
	for id in facts:
		fact_out[id] = facts[id].to_dict()
	var belief_out := {}
	for knower_id in beliefs:
		var row := {}
		for fact_id in beliefs[knower_id]:
			row[fact_id] = beliefs[knower_id][fact_id].to_dict()
		belief_out[knower_id] = row
	return {"facts": fact_out, "beliefs": belief_out, "next_fact": _next_fact}


func from_dict(d: Dictionary) -> void:
	facts.clear()
	beliefs.clear()
	_next_fact = int(d.get("next_fact", 1))
	var fact_in: Dictionary = d.get("facts", {})
	for id in fact_in:
		facts[id] = Fact.from_dict(fact_in[id])
	var belief_in: Dictionary = d.get("beliefs", {})
	for knower_id in belief_in:
		beliefs[knower_id] = {}
		for fact_id in belief_in[knower_id]:
			beliefs[knower_id][fact_id] = Belief.from_dict(belief_in[knower_id][fact_id])
