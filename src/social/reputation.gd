class_name Reputation
extends RefCounted
## Standing with places and groups, derived from what people actually know.
##
## There is no global "notoriety" bar. Reputation in a scope is a function of
## the facts that members of that scope believe, weighted by how sure they are
## and how much it matters to them. A crime nobody witnessed and nobody heard
## about changes nothing, however serious it was — which is the whole point.
##
## Scopes are ids like "region:old_harbour" or "group:harbour_crew".

## How much a fact shifts standing, per scope-affinity tag. Content data may
## override these per fact via `rep_weights`.
const DEFAULT_WEIGHTS := {
	"helped": 0.30,
	"generous": 0.20,
	"kept_promise": 0.25,
	"competent": 0.20,
	"broke_promise": -0.30,
	"lied": -0.25,
	"stole_from": -0.45,
	"assaulted": -0.60,
	"arrested": -0.35,
	"snitched": -0.50,
	## M8 D-086: dealing in something illicit, seen or heard of.
	"dealt_illicit": -0.35,
	## M8 D-086: someone vouched for the player — knowledge, not a flag
	## (D-085); read by whoever comes to know it, same as anything else.
	"vouched_for": 0.20,
}

## Some groups read the same act differently. A criminal crew does not mind
## that you were arrested; it minds that you talked. Dealing reads the
## opposite way in the two scopes that actually care about it: criminals
## barely mind, the police weigh it more heavily than an ordinary theft
## (M8 D-086). Being vouched for lands hardest exactly where the vouching
## happened — being trusted by one of their own means more among criminals
## than a stranger's good word means anywhere else.
const SCOPE_MODIFIERS := {
	"criminal": {"arrested": 0.05, "snitched": -1.0, "assaulted": -0.1, "stole_from": 0.0,
		"dealt_illicit": 0.10, "vouched_for": 0.35},
	"police": {"arrested": -0.5, "snitched": 0.3, "dealt_illicit": -0.55},
}

## Explicit standings set by scripted events, independent of gossip.
var explicit: Dictionary = {}        # scope -> float in [-1, 1]
## Cached derived values, invalidated whenever knowledge changes.
var _cache: Dictionary = {}
var _cache_dirty: bool = true

var _knowledge: KnowledgeNetwork = null
var _registry: NpcRegistry = null
var _world: WorldState = null


func setup(knowledge: KnowledgeNetwork, registry: NpcRegistry, world: WorldState) -> void:
	_knowledge = knowledge
	_registry = registry
	_world = world
	Events.fact_learned.connect(func(_a: String, _b: String, _c: String) -> void: invalidate())


func invalidate() -> void:
	_cache_dirty = true


## Standing of `subject` (usually "player") within a scope, in [-1, 1].
func standing(scope: String, subject: String = RelationshipGraph.PLAYER_ID) -> float:
	var key := scope + "|" + subject
	if not _cache_dirty and _cache.has(key):
		return _cache[key]
	if _cache_dirty:
		_cache.clear()
		_cache_dirty = false

	var members := members_of(scope)
	if members.is_empty():
		var value: float = float(explicit.get(scope, 0.0))
		_cache[key] = value
		return value

	var scope_kind := _scope_kind(scope)
	var total := 0.0
	var informed := 0

	for member_id in members:
		var member_score := 0.0
		var saw_anything := false
		for fact_id in _knowledge.known_fact_ids(member_id):
			var fact := _knowledge.get_fact(fact_id)
			if fact == null or fact.subject != subject:
				continue
			var belief := _knowledge.belief_of(member_id, fact_id)
			if belief == null:
				continue
			var weight := _weight_for(fact.predicate, scope_kind)
			if is_zero_approx(weight):
				continue
			saw_anything = true
			# Garbled second-hand accounts carry less force than eyewitness.
			var credibility: float = belief.confidence * (1.0 - belief.distortion * 0.5)
			member_score += weight * fact.severity * credibility
		if saw_anything:
			total += clampf(member_score, -1.0, 1.0)
			informed += 1

	var derived := 0.0
	if informed > 0:
		derived = total / float(informed)
		# Standing is diluted by how much of the group has actually heard.
		derived *= clampf(float(informed) / float(members.size()), 0.15, 1.0)

	var result := clampf(derived + float(explicit.get(scope, 0.0)), -1.0, 1.0)
	_cache[key] = result
	return result


## Standing across every scope the "criminal" flavour applies to (a group id
## containing crew/gang/criminal) — the worst of them, not an average, since
## one bad name among criminals is what a dealer weighs (M8 D-085). 0.0 when
## the player has no standing anywhere criminal, same as a stranger.
func criminal_standing(subject: String = RelationshipGraph.PLAYER_ID) -> float:
	if _registry == null:
		return 0.0
	var worst := 0.0
	var seen := {}
	for npc_id in _registry.npcs:
		var npc: Npc = _registry.npcs[npc_id]
		for group in npc.groups:
			var scope := "group:" + str(group)
			if seen.has(scope):
				continue
			seen[scope] = true
			if _scope_kind(scope) == "criminal":
				worst = minf(worst, standing(scope, subject))
	return worst


## Fraction of a scope's members who know a given fact.
func notoriety(scope: String, fact_id: String) -> float:
	var members := members_of(scope)
	if members.is_empty():
		return 0.0
	var count := 0
	for member_id in members:
		if _knowledge.knows(member_id, fact_id):
			count += 1
	return float(count) / float(members.size())


## Sets a standing directly. For authored consequences, not gossip.
func set_explicit(scope: String, value: float) -> void:
	var previous: float = float(explicit.get(scope, 0.0))
	explicit[scope] = clampf(value, -1.0, 1.0)
	invalidate()
	Events.reputation_changed.emit(scope, explicit[scope] - previous)


func adjust_explicit(scope: String, delta: float) -> void:
	set_explicit(scope, float(explicit.get(scope, 0.0)) + delta)


## All scopes the player currently has any standing in.
func active_scopes(subject: String = RelationshipGraph.PLAYER_ID) -> Dictionary:
	var out := {}
	var scopes := {}
	for scope in explicit:
		scopes[scope] = true
	if _world != null:
		for region_id in _world.regions:
			scopes["region:" + str(region_id)] = true
	if _registry != null:
		for npc_id in _registry.npcs:
			for group in _registry.npcs[npc_id].groups:
				scopes["group:" + str(group)] = true
	for scope in scopes:
		var value := standing(str(scope), subject)
		if not is_zero_approx(value):
			out[scope] = value
	return out


## Who counts as a member of a scope.
func members_of(scope: String) -> Array[String]:
	var out: Array[String] = []
	if _registry == null:
		return out
	var parts := scope.split(":", false, 1)
	if parts.size() < 2:
		return out
	var kind := parts[0]
	var value := parts[1]
	match kind:
		"group":
			for npc_id in _registry.npcs:
				var npc: Npc = _registry.npcs[npc_id]
				if npc.alive and npc.in_group(value):
					out.append(str(npc_id))
		"region":
			if _world == null:
				return out
			for npc_id in _registry.npcs:
				var npc: Npc = _registry.npcs[npc_id]
				if npc.alive and _world.region_of(npc.home) == value:
					out.append(str(npc_id))
	return out


func _scope_kind(scope: String) -> String:
	# Group scopes may carry a behavioural flavour used by SCOPE_MODIFIERS.
	if scope.begins_with("group:"):
		var group := scope.substr(6)
		if group.contains("crew") or group.contains("gang") or group.contains("criminal"):
			return "criminal"
		if group.contains("police") or group.contains("law"):
			return "police"
	return "default"


func _weight_for(predicate: String, scope_kind: String) -> float:
	var modifiers: Dictionary = SCOPE_MODIFIERS.get(scope_kind, {})
	if modifiers.has(predicate):
		return float(modifiers[predicate])
	return float(DEFAULT_WEIGHTS.get(predicate, 0.0))


func to_dict() -> Dictionary:
	return {"explicit": explicit}


func from_dict(d: Dictionary) -> void:
	explicit = d.get("explicit", {})
	invalidate()
