class_name NpcBodies
extends Node2D
## The visible people of the shown region, pooled.
##
## Reacts to the simulation and never polls it: a body is given out when the
## director makes someone ACTIVE (or FOCUS), a walk is planned when their
## location changes, and the body is taken back when they leave the shown map
## or drop out of detail. On a region map people are seen in open-air places
## and on the way between them; someone in a building is inside it. Inside a
## building (an interior map) the people there are seen, and whoever works
## there stands at the staff spot.
##
## The simulation moves a person the moment their routine says so; the body
## then walks there along a route computed once, from DistrictMap.find_path.
## What you see trails the world by a few seconds of walking. It never leads.

var _map: DistrictMap = null
## npc_id -> NpcBody, for everyone currently visible.
var _bodies: Dictionary = {}
var _pool: Array[NpcBody] = []
## npc_id -> the location this view last placed them at. The simulation's
## location has already changed by the time we hear of a move, so where the
## walk starts has to be remembered here.
var _known: Dictionary = {}


func _ready() -> void:
	y_sort_enabled = true
	Events.npc_tier_changed.connect(_on_tier_changed)
	Events.location_entered.connect(_on_location_entered)
	Events.time_skipped.connect(_on_time_skipped)
	Events.game_loaded.connect(resync)
	Game.world_unloaded.connect(_release_all)


## Shows the people of this map. Call when the region is (re)built.
func show_map(map: DistrictMap) -> void:
	_map = map
	resync()


## Rebuilds every body from the simulation as it stands, without walking:
## after loading, after a time skip, after a region change.
func resync() -> void:
	_release_all()
	if _map == null or not Game.is_running():
		return
	for npc_id in Game.director.awake_ids():
		_place(npc_id)


func body_for(npc_id: String) -> NpcBody:
	return _bodies.get(npc_id)


## Whoever's body stands on this cell, or null. Presentation's half of
## talking to someone: it names who the player is facing; whether that person
## can actually be talked to is the simulation's call (DialogueDirector).
func body_at(cell: Vector2i) -> NpcBody:
	for npc_id in _bodies:
		var body: NpcBody = _bodies[npc_id]
		if body.current_cell() == cell:
			return body
	return null


func visible_count() -> int:
	return _bodies.size()


func pooled_count() -> int:
	return _pool.size()


# --- reacting to the simulation ---------------------------------------------

func _on_tier_changed(npc_id: String, tier: int) -> void:
	if _map == null:
		return
	if _is_detailed(tier):
		if not _bodies.has(npc_id):
			_place(npc_id)
	else:
		_release(npc_id)
		_known.erase(npc_id)


func _on_location_entered(actor_id: String, location_id: String) -> void:
	if _map == null or not Game.is_running():
		return
	var npc := Game.npcs.get_npc(actor_id)
	if npc == null or not npc.alive or not _is_detailed(npc.tier):
		return
	var from := str(_known.get(actor_id, ""))
	_known[actor_id] = location_id
	_walk(npc, from, location_id)


func _on_time_skipped(_from_minutes: int, _to_minutes: int) -> void:
	# Hours passed in one step; nobody walks through them.
	resync()


# --- placing and walking ----------------------------------------------------

## Puts someone where the simulation says they are, standing still.
func _place(npc_id: String) -> void:
	var npc := Game.npcs.get_npc(npc_id)
	if npc == null or not npc.alive or not _is_detailed(npc.tier):
		_release(npc_id)
		return
	_known[npc_id] = npc.location
	if not _is_shown_at(npc.location):
		_release(npc_id)
		return
	_acquire(npc).stand_at(DistrictMap.cell_to_world(_spot(npc, npc.location)))


func _walk(npc: Npc, from: String, to: String) -> void:
	var body: NpcBody = _bodies.get(npc.id)
	var start := body.current_cell() if body != null else _endpoint(from, npc)
	var goal := _endpoint(to, npc)
	var route := _map.find_path(start, goal)
	if route.size() <= 1:
		# Nowhere to walk, or no way there: show them where they now are.
		if route.is_empty():
			Log.debug("npc", "No route for body; placing directly", {"npc": npc.id, "from": from, "to": to})
		_place(npc.id)
		return
	if body == null:
		body = _acquire(npc)
		body.stand_at(DistrictMap.cell_to_world(start))
	var points := PackedVector2Array()
	for cell: Vector2i in route.slice(1):
		points.append(DistrictMap.cell_to_world(cell))
	body.walk(points)


## Where a walk to or from a location begins or ends on this map: the
## person's spot at a place, the door of a building, or the map's way out
## (region edge, or the door of an interior) for anywhere off the map.
func _endpoint(location_id: String, npc: Npc) -> Vector2i:
	if _map.has_location(location_id):
		return _spot(npc, location_id)
	return _map.edge_cell()


## Where this person stands at a location on the shown map: behind the
## counter if they work there, otherwise their own spot.
func _spot(npc: Npc, location_id: String) -> Vector2i:
	if _map.is_interior() and location_id == _map.interior_of \
			and npc.workplace == location_id and _map.staff_cell.x >= 0:
		return _map.staff_cell
	return _map.standing_cell(location_id, npc.id)


func _on_body_arrived(body: NpcBody) -> void:
	# Arrived at a door or the edge of the map: they go in, or on.
	if not _is_shown_at(str(_known.get(body.npc_id, ""))):
		_release(body.npc_id)


## Whether someone at this location has a body on the shown map: an open-air
## place outdoors, or the building itself when showing its inside.
func _is_shown_at(location_id: String) -> bool:
	return _map != null and _map.has_location(location_id) and not _map.is_building(location_id)


static func _is_detailed(tier: int) -> bool:
	return tier == SimLod.Tier.ACTIVE or tier == SimLod.Tier.FOCUS


# --- the pool ---------------------------------------------------------------

func _acquire(npc: Npc) -> NpcBody:
	var body: NpcBody = _bodies.get(npc.id)
	if body != null:
		return body
	if _pool.is_empty():
		body = NpcBody.new()
		body.arrived.connect(_on_body_arrived)
		add_child(body)
	else:
		body = _pool.pop_back()
	body.assume(npc.id, NpcLook.palette_for(npc), body.position)
	body.name = "Body_" + npc.id
	_bodies[npc.id] = body
	return body


func _release(npc_id: String) -> void:
	var body: NpcBody = _bodies.get(npc_id)
	if body == null:
		return
	_bodies.erase(npc_id)
	body.release()
	_pool.append(body)


func _release_all() -> void:
	for npc_id in _bodies.keys():
		_release(str(npc_id))
	_known.clear()
