class_name NpcDirector
extends RefCounted
## Assigns simulation tiers and drives NPC ticking within a fixed budget.
##
## The rule this class exists to enforce: no NPC runs expensive logic every
## frame, and the total per-minute cost of the population is bounded no
## matter how many people live in the world. Everyone far away is DORMANT
## and costs literally nothing; proximity and narrative weight buy detail.

var registry: NpcRegistry
var world: WorldState
var clock: GameClock

## NPC currently in conversation/combat with the player.
var focus_ids: Array[String] = []

## Who is walking with the player (D-057): npc id -> true. The truth is in each
## person's `state["following"]`; this is the index that keeps them awake and
## lets the retier find them without a pass over the population.
var followers: Dictionary = {}
## Where those people are while they follow: the player's place, set by Game.
var follow_location: String = ""

var _last_pass_minute: int = -1
var _stats := {"dormant": 0, "background": 0, "active": 0, "focus": 0}
## Ids of every non-dormant NPC. Ticking walks this, never the population, so
## per-minute cost tracks how many people are near the player rather than how
## many people exist.
var _awake: Dictionary = {}


func setup(p_registry: NpcRegistry, p_world: WorldState, p_clock: GameClock) -> void:
	registry = p_registry
	world = p_world
	clock = p_clock


## Recomputes tiers. Called on region change and periodically (not per frame).
func assign_tiers() -> void:
	if registry == null or world == null or clock == null:
		return
	var now := clock.total_minutes
	var weekday := clock.weekday()
	var here := world.current_region
	var neighbours: Array[String] = []
	var region: Region = world.get_region(here)
	if region != null:
		neighbours = region.neighbours

	var active_budget := SimLod.MAX_ACTIVE
	_stats = {"dormant": 0, "background": 0, "active": 0, "focus": 0}

	# Only people who can appear nearby are worth evaluating. Everyone else
	# is dormant by definition, and demoting them costs one dictionary walk
	# over the awake set rather than a pass over the whole town.
	var nearby: Array[String] = [here]
	nearby.append_array(neighbours)

	var considered := {}
	for id in registry.ids_in_regions(nearby):
		considered[id] = true
	for id in registry.important_ids():
		considered[id] = true
	for id in focus_ids:
		considered[id] = true
	for id in followers:
		considered[id] = true

	# Demote anyone awake who is no longer a candidate. Walking the awake set
	# rather than the population is what keeps this bounded.
	for id in _awake.keys():
		if not considered.has(id):
			_set_tier(registry.npcs[id], SimLod.Tier.DORMANT)

	for id in considered:
		var npc: Npc = registry.npcs.get(id)
		if npc == null:
			continue
		if not npc.alive:
			_set_tier(npc, SimLod.Tier.DORMANT)
			continue

		if id in focus_ids:
			_set_tier(npc, SimLod.Tier.FOCUS)
			_stats["focus"] += 1
			continue

		if followers.has(id):
			# Someone walking with the player is always simulated in detail: a
			# retier must not send them back to their routine (D-057).
			_set_tier(npc, SimLod.Tier.ACTIVE)
			active_budget = maxi(active_budget - 1, 0)
			_stats["active"] += 1
			continue

		var loc := registry.location_of(id, now, weekday)
		var npc_region := world.region_of(loc)

		if npc_region == here and active_budget > 0:
			# Entering ACTIVE means the computed schedule position becomes
			# real simulated position; sync it once at promotion.
			if npc.tier == SimLod.Tier.DORMANT:
				npc.location = loc
				npc.last_simulated = now
			_set_tier(npc, SimLod.Tier.ACTIVE)
			active_budget -= 1
			_stats["active"] += 1
		elif npc_region in neighbours or npc.importance != Npc.Importance.BACKGROUND:
			_set_tier(npc, SimLod.Tier.BACKGROUND)
			_stats["background"] += 1
		else:
			_set_tier(npc, SimLod.Tier.DORMANT)

	_stats["dormant"] = registry.count() - _stats["active"] - _stats["background"] - _stats["focus"]


## Ticks NPCs whose tier is due this minute. Cheap by construction: DORMANT
## NPCs are skipped entirely and BACKGROUND ones only every 15 game minutes.
func tick(total_minutes: int) -> void:
	if registry == null or clock == null:
		return
	if total_minutes == _last_pass_minute:
		return
	_last_pass_minute = total_minutes
	var weekday := clock.weekday()

	for id in _awake:
		var npc: Npc = registry.npcs.get(id)
		if npc == null or not npc.alive:
			continue
		if not SimLod.ticks_this_minute(npc.tier, total_minutes):
			continue
		_tick_npc(npc, total_minutes, weekday)


## Brings an NPC's state up to date after a batched time jump, in one step
## rather than by replaying every minute. This is what makes sleeping eight
## hours cost the same as sleeping one.
func catch_up(total_minutes: int) -> void:
	if registry == null or clock == null:
		return
	var weekday := clock.weekday()
	for id in _awake:
		var npc: Npc = registry.npcs.get(id)
		if npc == null or not npc.alive:
			continue
		var elapsed := total_minutes - npc.last_simulated
		if elapsed <= 0:
			continue
		var sched: NpcSchedule = registry.schedule_for(npc)
		var activity := npc.activity
		if sched != null:
			activity = str(sched.resolve_at(total_minutes, weekday, npc.schedule_override).get("activity", activity))
		npc.needs.drift(elapsed, activity)
		npc.last_simulated = total_minutes
		_apply_schedule(npc, total_minutes, weekday)
	_last_pass_minute = total_minutes


func set_focus(npc_ids: Array[String]) -> void:
	focus_ids = npc_ids.slice(0, SimLod.MAX_FOCUS)
	assign_tiers()


func clear_focus() -> void:
	focus_ids.clear()
	assign_tiers()


func stats() -> Dictionary:
	var out := _stats.duplicate()
	out["total"] = registry.count() if registry != null else 0
	return out


func _tick_npc(npc: Npc, total_minutes: int, weekday: int) -> void:
	var elapsed := maxi(1, total_minutes - npc.last_simulated)
	npc.needs.drift(elapsed, npc.activity)
	npc.last_simulated = total_minutes
	_apply_schedule(npc, total_minutes, weekday)


## Moves an NPC to wherever their routine says they should be, and lets an
## urgent need bend that routine. No LLM is involved: deciding to walk to the
## shop is a state machine's job, not a language model's.
func _apply_schedule(npc: Npc, total_minutes: int, weekday: int) -> void:
	if npc.state.has("following") and _follows(npc, total_minutes):
		return
	var sched: NpcSchedule = registry.schedule_for(npc)
	if sched == null:
		return
	var resolved := sched.resolve_at(total_minutes, weekday, npc.schedule_override)
	var want_location := registry.resolve_location_token(npc, str(resolved.get("location", "")))
	var want_activity := str(resolved.get("activity", "idle"))

	# An urgent need can override an ordinary block, but never an explicit
	# override (a police summons outranks being hungry).
	if not bool(resolved.get("overridden", false)):
		var need := npc.needs.dominant_need()
		if need == "food" and want_activity == "work":
			want_activity = "eat"
		elif need == "rest" and want_activity not in ["sleep", "work"]:
			want_location = npc.home
			want_activity = "sleep"

	if not want_location.is_empty() and want_location != npc.location:
		registry.move_to(npc.id, want_location)
		registry.invalidate_location_cache(npc.id)
	if want_activity != npc.activity:
		npc.activity = want_activity
		Events.npc_activity_changed.emit(npc.id, want_activity)


# --- walking with the player (D-057) -------------------------------------------

## Someone begins walking with the player, for at most `minutes` (their own day
## may end it sooner). The rules have already said yes.
func start_follow(npc_id: String, minutes: int) -> bool:
	var npc: Npc = registry.npcs.get(npc_id) if registry != null else null
	if npc == null or not npc.alive or clock == null:
		return false
	npc.state["following"] = {"since": clock.total_minutes, "until": clock.total_minutes + maxi(minutes, 0)}
	followers[npc_id] = true
	assign_tiers()
	if not follow_location.is_empty() and npc.location != follow_location:
		registry.move_to(npc_id, follow_location)
	if npc.activity != "follow":
		npc.activity = "follow"
		Events.npc_activity_changed.emit(npc_id, "follow")
	Events.follow_changed.emit(npc_id, true, "asked")
	return true


## They stop and go back to their routine, wherever that now takes them.
func stop_follow(npc_id: String, why: String) -> void:
	var npc: Npc = registry.npcs.get(npc_id) if registry != null else null
	if npc == null or not npc.state.has("following"):
		followers.erase(npc_id)
		return
	_end_follow(npc, why)
	if clock != null:
		_apply_schedule(npc, clock.total_minutes, clock.weekday())
	assign_tiers()


func stop_all_following(why: String) -> void:
	for id in followers.keys():
		stop_follow(str(id), why)


func is_following(npc_id: String) -> bool:
	return followers.has(npc_id)


## Where the followers are, to the person they follow: called when the player
## changes place. Moving is the registry's; bodies walk to it.
func move_followers() -> void:
	if follow_location.is_empty():
		return
	for id in followers:
		var npc: Npc = registry.npcs.get(id)
		if npc != null and npc.alive and npc.location != follow_location:
			registry.move_to(npc.id, follow_location)
			registry.invalidate_location_cache(npc.id)


## Rebuilds the index from what people carry, after a load.
func rebuild_followers() -> void:
	followers.clear()
	if registry == null:
		return
	for id in registry.npcs:
		var npc: Npc = registry.npcs[id]
		if npc.alive and npc.state.has("following"):
			followers[id] = true


## Whether someone is still walking with the player at this minute; when their
## time is up they are let go and the routine takes over. By absolute minute,
## because a night's sleep can jump over the end.
func _follows(npc: Npc, total_minutes: int) -> bool:
	var follow: Dictionary = npc.state["following"]
	if total_minutes >= int(follow.get("until", 0)):
		_end_follow(npc, "time_up")
		return false
	if not follow_location.is_empty() and npc.location != follow_location:
		registry.move_to(npc.id, follow_location)
		registry.invalidate_location_cache(npc.id)
	if npc.activity != "follow":
		npc.activity = "follow"
		Events.npc_activity_changed.emit(npc.id, "follow")
	return true


func _end_follow(npc: Npc, why: String) -> void:
	npc.state.erase("following")
	followers.erase(npc.id)
	Events.follow_changed.emit(npc.id, false, why)


func _set_tier(npc: Npc, tier: SimLod.Tier) -> void:
	if npc.tier == tier:
		return
	npc.tier = tier
	if tier == SimLod.Tier.DORMANT:
		_awake.erase(npc.id)
	else:
		_awake[npc.id] = true
	Events.npc_tier_changed.emit(npc.id, int(tier))


## Ids currently being simulated. Exposed for the debug overlay and tests.
func awake_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _awake:
		out.append(str(id))
	return out
