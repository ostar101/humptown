class_name RelationshipGraph
extends RefCounted
## Every directed relationship in the world, including the player's.
##
## Stored as a sparse map so an empty relationship costs nothing: two people
## who have never met simply have no entry. Nothing here is ticked — feelings
## change when something happens, not on a timer.

const PLAYER_ID := "player"

var _edges: Dictionary = {}          # from_id -> { to_id -> Relationship }
var _incoming: Dictionary = {}       # to_id -> { from_id -> true }


func has(from_id: String, to_id: String) -> bool:
	return _edges.has(from_id) and _edges[from_id].has(to_id)


## Returns the relationship, creating a blank one if absent.
func get_edge(from_id: String, to_id: String) -> Relationship:
	if not _edges.has(from_id):
		_edges[from_id] = {}
	if not _edges[from_id].has(to_id):
		_edges[from_id][to_id] = Relationship.new()
		if not _incoming.has(to_id):
			_incoming[to_id] = {}
		_incoming[to_id][from_id] = true
	return _edges[from_id][to_id]


## Reads without creating. Returns null when they have no relationship.
func peek(from_id: String, to_id: String) -> Relationship:
	if not _edges.has(from_id):
		return null
	return _edges[from_id].get(to_id)


func set_kind(from_id: String, to_id: String, kind: Relationship.Kind, symmetric: bool = true) -> void:
	get_edge(from_id, to_id).kind = kind
	if symmetric:
		get_edge(to_id, from_id).kind = kind


func adjust(from_id: String, to_id: String, dimension: String, delta: float, at_minute: int = -1) -> void:
	if is_zero_approx(delta):
		return
	var edge := get_edge(from_id, to_id)
	edge.adjust(dimension, delta)
	if at_minute >= 0:
		edge.last_interaction = at_minute
	Events.relationship_changed.emit(from_id, to_id, dimension, delta)


## Applies several dimension deltas at once, e.g. after a conversation:
## {"trust": 0.1, "affection": 0.05}
func apply(from_id: String, to_id: String, deltas: Dictionary, at_minute: int = -1) -> void:
	for dimension in deltas:
		adjust(from_id, to_id, str(dimension), float(deltas[dimension]), at_minute)


func disposition(from_id: String, to_id: String) -> float:
	var edge := peek(from_id, to_id)
	return edge.disposition() if edge != null else 0.0


## Everyone `from_id` has a relationship with.
func contacts_of(from_id: String) -> Array[String]:
	var out: Array[String] = []
	for to_id in _edges.get(from_id, {}):
		out.append(str(to_id))
	return out


## Everyone who has a relationship pointing at `to_id`. Used by information
## propagation: who would plausibly hear about something that happened to them.
func who_knows(to_id: String) -> Array[String]:
	var out: Array[String] = []
	for from_id in _incoming.get(to_id, {}):
		out.append(str(from_id))
	return out


## Social neighbours of `from_id` above a closeness threshold, strongest
## first. This is the channel along which gossip travels.
func close_contacts(from_id: String, min_familiarity: float = 0.25, limit: int = 12) -> Array[String]:
	var scored: Array = []
	for to_id in _edges.get(from_id, {}):
		var edge: Relationship = _edges[from_id][to_id]
		if edge.familiarity >= min_familiarity:
			scored.append({"id": str(to_id), "score": edge.familiarity})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	var out: Array[String] = []
	for entry in scored.slice(0, limit):
		out.append(entry["id"])
	return out


func player_edge(npc_id: String) -> Relationship:
	return get_edge(npc_id, PLAYER_ID)


func edge_count() -> int:
	var total := 0
	for from_id in _edges:
		total += _edges[from_id].size()
	return total


## Removes all relationships involving an id (used when someone dies and the
## world has finished reacting to it).
func purge(entity_id: String) -> void:
	_edges.erase(entity_id)
	for from_id in _edges:
		_edges[from_id].erase(entity_id)
	_incoming.erase(entity_id)
	for to_id in _incoming:
		_incoming[to_id].erase(entity_id)


func seed_from_data(entries: Array) -> void:
	for raw in entries:
		var from_id := str(raw.get("from", ""))
		var to_id := str(raw.get("to", ""))
		if from_id.is_empty() or to_id.is_empty():
			continue
		var edge := get_edge(from_id, to_id)
		for dimension in Relationship.DIMENSIONS:
			if raw.has(dimension):
				edge.adjust(dimension, float(raw[dimension]))
		var kind_name := str(raw.get("kind", ""))
		if not kind_name.is_empty():
			var idx := Relationship.KIND_NAMES.find(kind_name)
			if idx >= 0:
				edge.kind = idx as Relationship.Kind


func to_dict() -> Dictionary:
	var out := {}
	for from_id in _edges:
		var row := {}
		for to_id in _edges[from_id]:
			row[to_id] = _edges[from_id][to_id].to_dict()
		out[from_id] = row
	return {"edges": out}


func from_dict(d: Dictionary) -> void:
	_edges.clear()
	_incoming.clear()
	var edges: Dictionary = d.get("edges", {})
	for from_id in edges:
		for to_id in edges[from_id]:
			if not _edges.has(from_id):
				_edges[from_id] = {}
			_edges[from_id][to_id] = Relationship.from_dict(edges[from_id][to_id])
			if not _incoming.has(to_id):
				_incoming[to_id] = {}
			_incoming[to_id][from_id] = true
