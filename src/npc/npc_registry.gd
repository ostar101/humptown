class_name NpcRegistry
extends RefCounted
## Owns every persistent NPC and their routines.
##
## Population is a controlled hybrid: a base population is authored so the
## town has real, stable inhabitants, and the world may add people later
## through legitimate events (someone moves in, a shop hires). Nobody is
## invented merely because the player turned to look.

var npcs: Dictionary = {}          # id -> Npc
var schedules: Dictionary = {}     # id -> NpcSchedule
var _world: WorldState = null
var _next_generated: int = 1

## region_id -> Array[npc_id] of people who can appear in that region.
## Precomputed once from home, workplace and every explicit location in the
## routine. This is what lets the director consider only local residents
## instead of scanning the whole population every retier pass.
var _by_region: Dictionary = {}
## Named and story NPCs, who stay simulated wherever the player is. There are
## few of them and the set is static, so it is computed once.
var _important: Array[String] = []
## npc_id -> {loc, from, until, had_override}
##
## A dormant NPC's position is a pure function of their routine, and a routine
## block lasts hours. Recomputing it on every tier pass is wasted work, so the
## answer is cached until the block it came from actually ends. This is what
## keeps the cost of a crowded district flat instead of proportional to how
## often the director looks at it.
var _location_cache: Dictionary = {}

signal npc_moved(npc_id: String, from_location: String, to_location: String)


func setup(registry: DataRegistry, world: WorldState) -> void:
	_world = world
	npcs.clear()
	schedules.clear()
	for id in registry.ids("schedules"):
		schedules[id] = NpcSchedule.from_data(registry.get_entry("schedules", id))
	for id in registry.ids("npcs"):
		var npc := Npc.from_data(registry.get_entry("npcs", id))
		npcs[id] = npc
	rebuild_region_index()
	Log.info("npc", "Population loaded", {"npcs": npcs.size(), "schedules": schedules.size()})


## Rebuilds the region index. Call after bulk population changes.
func rebuild_region_index() -> void:
	_by_region.clear()
	_important.clear()
	_location_cache.clear()
	for id in npcs:
		var npc: Npc = npcs[id]
		_index_npc(npc)
		if npc.importance != Npc.Importance.BACKGROUND:
			_important.append(str(id))


## Ids of NPCs who never drop to dormant simply for being far away.
func important_ids() -> Array[String]:
	return _important


## The regions an NPC can turn up in, derived from their fixed places and the
## explicit locations in their routine. Symbolic tokens resolve to home and
## workplace, which are already counted.
func habitual_regions(npc: Npc) -> Array[String]:
	var out: Array[String] = []
	if _world == null:
		return out
	for location_id in [npc.home, npc.workplace]:
		var region := _world.region_of(str(location_id))
		if not region.is_empty() and not (region in out):
			out.append(region)
	var sched: NpcSchedule = schedules.get(npc.schedule_id)
	if sched != null:
		for block in sched.blocks:
			if block.location.is_empty() or NpcSchedule.is_token(block.location):
				continue
			var region := _world.region_of(block.location)
			if not region.is_empty() and not (region in out):
				out.append(region)
	return out


## Ids of everyone who could be in any of these regions. The director uses
## this instead of the full population.
func ids_in_regions(region_ids: Array[String]) -> Array[String]:
	var seen := {}
	for region_id in region_ids:
		for npc_id in _by_region.get(region_id, []):
			seen[npc_id] = true
	var out: Array[String] = []
	for npc_id in seen:
		out.append(str(npc_id))
	return out


func _index_npc(npc: Npc) -> void:
	if npc.importance != Npc.Importance.BACKGROUND and not (npc.id in _important):
		_important.append(npc.id)
	for region in habitual_regions(npc):
		if not _by_region.has(region):
			_by_region[region] = []
		_by_region[region].append(npc.id)


func get_npc(id: String) -> Npc:
	return npcs.get(id)


func has_npc(id: String) -> bool:
	return npcs.has(id)


func all_ids() -> Array:
	return npcs.keys()


func count() -> int:
	return npcs.size()


func schedule_for(npc: Npc) -> NpcSchedule:
	return schedules.get(npc.schedule_id)


# --- location queries -------------------------------------------------------

## Where an NPC is at a given time. For dormant NPCs this *computes* the
## answer from their routine rather than reading simulated state, which is
## why an unobserved population costs nothing.
func location_of(npc_id: String, total_minutes: int, weekday: int) -> String:
	var npc: Npc = npcs.get(npc_id)
	if npc == null or not npc.alive:
		return ""
	if npc.tier != SimLod.Tier.DORMANT:
		return npc.location
	var sched: NpcSchedule = schedules.get(npc.schedule_id)
	if sched == null:
		return npc.home

	var has_override := npc.schedule_override != null
	var cached: Variant = _location_cache.get(npc_id)
	if cached != null \
			and bool(cached["had_override"]) == has_override \
			and total_minutes >= int(cached["from"]) \
			and total_minutes < int(cached["until"]):
		return str(cached["loc"])

	var resolved := sched.resolve_at(total_minutes, weekday, npc.schedule_override)
	var location := resolve_location_token(npc, str(resolved.get("location", "")))
	_location_cache[npc_id] = {
		"loc": location,
		"from": total_minutes,
		"until": _validity_end(sched, npc, total_minutes, weekday),
		"had_override": has_override,
	}
	return location


## Where the routine, and any override, puts an NPC at a given time — read from
## the schedule whatever tier they are in and however far the simulation has
## caught up, so an appointment can be settled at its own minute even in the
## middle of a skip (D-047). Not cached; not for the per-minute path.
func scheduled_location_of(npc_id: String, total_minutes: int, weekday: int) -> String:
	var npc: Npc = npcs.get(npc_id)
	if npc == null or not npc.alive:
		return ""
	var sched: NpcSchedule = schedules.get(npc.schedule_id)
	if sched == null:
		return npc.home
	var resolved := sched.resolve_at(total_minutes, weekday, npc.schedule_override)
	return resolve_location_token(npc, str(resolved.get("location", "")))


## When the cached position stops being trustworthy: the next routine
## boundary, clipped by the start or end of an active override.
func _validity_end(sched: NpcSchedule, npc: Npc, total_minutes: int, weekday: int) -> int:
	var day_start := total_minutes - (total_minutes % NpcSchedule.MINUTES_PER_DAY)
	var next_boundary := sched.next_change_after(weekday, total_minutes % NpcSchedule.MINUTES_PER_DAY)
	var until := day_start + next_boundary if next_boundary >= 0 else total_minutes + NpcSchedule.MINUTES_PER_DAY

	var override := npc.schedule_override
	if override != null:
		if total_minutes < override.from_minutes:
			until = mini(until, override.from_minutes)
		elif total_minutes < override.to_minutes:
			until = mini(until, override.to_minutes)
	return maxi(until, total_minutes + 1)


## Drops cached positions. Called when routines or overrides change outside
## the normal flow, and after loading a save.
func invalidate_location_cache(npc_id: String = "") -> void:
	if npc_id.is_empty():
		_location_cache.clear()
	else:
		_location_cache.erase(npc_id)


## Turns a schedule's symbolic location into a concrete location id for this
## person. An NPC with no workplace falls back to their home rather than
## vanishing from the world.
func resolve_location_token(npc: Npc, location: String) -> String:
	if location.is_empty():
		return npc.home
	if not NpcSchedule.is_token(location):
		return location
	match location:
		NpcSchedule.TOKEN_HOME:
			return npc.home
		NpcSchedule.TOKEN_WORK:
			return npc.workplace if not npc.workplace.is_empty() else npc.home
	Log.warn("npc", "Unknown schedule location token", {"token": location, "npc": npc.id})
	return npc.home


func npcs_at(location_id: String, total_minutes: int, weekday: int) -> Array[String]:
	var out: Array[String] = []
	for id in npcs:
		if location_of(id, total_minutes, weekday) == location_id:
			out.append(id)
	return out


func npcs_in_region(region_id: String, total_minutes: int, weekday: int) -> Array[String]:
	var out: Array[String] = []
	if _world == null:
		return out
	for id in npcs:
		var loc := location_of(id, total_minutes, weekday)
		if not loc.is_empty() and _world.region_of(loc) == region_id:
			out.append(id)
	return out


func move_to(npc_id: String, location_id: String) -> void:
	var npc: Npc = npcs.get(npc_id)
	if npc == null or npc.location == location_id:
		return
	var from := npc.location
	npc.location = location_id
	if not from.is_empty():
		Events.location_exited.emit(npc_id, from)
	Events.location_entered.emit(npc_id, location_id)
	npc_moved.emit(npc_id, from, location_id)


# --- population changes -----------------------------------------------------

## Adds a person through a legitimate world event (hire, move-in, birth).
## `source` is recorded so the world can explain where they came from.
func add_npc(npc: Npc, source: String) -> Result:
	if npc.id.is_empty():
		npc.id = "npc_gen_%03d" % _next_generated
		_next_generated += 1
	if npcs.has(npc.id):
		return Result.failure("duplicate_npc", npc.id)
	npc.state["origin"] = source
	npcs[npc.id] = npc
	_index_npc(npc)
	Events.npc_spawned.emit(npc.id)
	Log.info("npc", "NPC added", {"npc": npc.id, "source": source})
	return Result.success(npc.id)


## Removes someone from active life. Story-critical NPCs refuse to die
## except through an explicitly authored cause, so a stray brawl cannot
## sever the main thread.
func kill(npc_id: String, cause: String, authored: bool = false) -> Result:
	var npc: Npc = npcs.get(npc_id)
	if npc == null:
		return Result.failure("no_such_npc", npc_id)
	if not npc.alive:
		return Result.failure("already_dead", npc_id)
	if npc.is_story_critical() and not authored:
		Log.warn("npc", "Refused incidental death of story NPC", {"npc": npc_id, "cause": cause})
		return Result.failure("story_protected", npc_id)
	npc.alive = false
	npc.tier = SimLod.Tier.DORMANT
	npc.state["death_cause"] = cause
	Events.npc_died.emit(npc_id, cause)
	Log.info("npc", "NPC died", {"npc": npc_id, "cause": cause})
	return Result.success(npc_id)


func living_ids() -> Array[String]:
	var out: Array[String] = []
	for id in npcs:
		if npcs[id].alive:
			out.append(id)
	return out


func to_dict() -> Dictionary:
	var states := {}
	for id in npcs:
		states[id] = npcs[id].to_dict()
	return {"npcs": states, "next_generated": _next_generated}


## Restores runtime state onto NPCs already built from content data.
## NPCs present in the save but absent from content are reported, not
## silently dropped, so renaming a content id is a loud failure.
func from_dict(d: Dictionary) -> Array[String]:
	var orphans: Array[String] = []
	_next_generated = int(d.get("next_generated", 1))
	var states: Dictionary = d.get("npcs", {})
	for id in states:
		if npcs.has(id):
			npcs[id].from_dict(states[id])
		else:
			orphans.append(str(id))
	if not orphans.is_empty():
		Log.warn("npc", "Save contains unknown NPCs", {"count": orphans.size()})
	rebuild_region_index()
	invalidate_location_cache()
	return orphans
