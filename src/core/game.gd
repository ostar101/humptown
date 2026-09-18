extends Node
## Composition root. Autoload singleton: Game
##
## Owns every simulation system and wires them together. Systems do not
## reach for each other through this node during play — they were handed
## what they need at setup and talk through Events afterwards — but having a
## single place where the world is assembled, saved and torn down is what
## keeps the dependency graph honest.
##
## This node also enforces the central architectural rule: the execution
## layer (here and the systems below) is the only thing that mutates world
## state. Presentation reads. The LLM proposes.

signal world_ready()
signal world_unloaded()

# --- systems ----------------------------------------------------------------
var data := DataRegistry.new()
var world := WorldState.new()
var npcs := NpcRegistry.new()
var director := NpcDirector.new()
var events_queue := WorldEventQueue.new()
var clock: GameClock = null
var relationships := RelationshipGraph.new()
var knowledge := KnowledgeNetwork.new()
var reputation := Reputation.new()
var player := PlayerState.new()
var saves := SaveManager.new()
var rng := RngStreams.new()
var llm: LlmClient = null

var running: bool = false
## Directory tier reassignment cadence, in game minutes. Cheap, but not free.
const RETIER_INTERVAL := 5

var _last_retier: int = -999


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	llm = LlmClient.new()
	llm.name = "LlmClient"
	add_child(llm)
	Localization.setup()
	Log.min_level = int(Settings.get_value("log_level", Log.Level.INFO)) as Log.Level
	Log.info("game", "Game root ready")


func _process(delta: float) -> void:
	if not running or clock == null:
		return
	clock.tick(delta)


# --- lifecycle --------------------------------------------------------------

## Loads content and builds a fresh world. `background_id` selects the
## player's starting circumstances.
func new_game(background_id: String = "", world_seed: int = 0) -> Result:
	unload()

	if not data.load_all():
		return Result.failure("content_invalid", "; ".join(data.load_errors))
	var reference_problems := data.validate_references()
	if not reference_problems.is_empty():
		for problem in reference_problems:
			Log.error("data", problem)
		return Result.failure("content_invalid", "; ".join(reference_problems))

	rng.reseed(world_seed if world_seed != 0 else int(Time.get_unix_time_from_system()))

	clock = GameClock.new()
	clock.event_queue = events_queue
	clock.minutes_per_real_second = float(Settings.get_value("minutes_per_real_second", 1.0))

	world.build_from(data)
	npcs.setup(data, world)
	director.setup(npcs, world, clock)
	knowledge.setup(relationships, events_queue)
	reputation.setup(knowledge, npcs, world)
	player.setup(data)

	_seed_relationships()
	_apply_background(background_id)
	_connect_simulation()

	# Open the starting region and place the player.
	var start_region := _starting_region()
	var start := world.get_region(start_region)
	if start != null:
		start.unlocked = true
		start.discovered = true
	world.enter_region(start_region)
	player.region = start_region
	if player.location.is_empty():
		player.location = player.home_location

	director.assign_tiers()
	running = true
	Log.info("game", "New game started", {
		"background": background_id,
		"npcs": npcs.count(),
		"region": start_region,
	})
	world_ready.emit()
	return Result.success()


## Tears the world down without touching settings or secrets.
func unload() -> void:
	running = false
	if clock != null:
		_disconnect_simulation()
	clock = null
	events_queue.clear()
	relationships = RelationshipGraph.new()
	knowledge = KnowledgeNetwork.new()
	reputation = Reputation.new()
	player = PlayerState.new()
	world = WorldState.new()
	npcs = NpcRegistry.new()
	director = NpcDirector.new()
	world_unloaded.emit()


func is_running() -> bool:
	return running and clock != null


# --- time -------------------------------------------------------------------

## Batched advancement for sleep, travel and scene transitions. Resolves every
## world event that should have happened, then brings NPCs up to date in one
## step rather than replaying the interval minute by minute.
func advance_time(minutes: int) -> void:
	if clock == null or minutes <= 0:
		return
	clock.advance(minutes)


func pause_time(paused: bool) -> void:
	if clock != null:
		clock.paused = paused


# --- player movement --------------------------------------------------------

## Presentation reports where the player's body now stands; rules decide
## whether that is somewhere a person can be and which location it counts as.
## Called when the body crosses into a new cell, not every frame.
func move_player(world_position: Vector2) -> Result:
	var proposal := {"kind": "move_player", "x": world_position.x, "y": world_position.y}
	if not is_running():
		return _reject(proposal, "no_world")
	var map := world.map_for(player.region)
	if map == null:
		return _reject(proposal, "region_unmapped")
	var cell := DistrictMap.world_to_cell(world_position)
	if map.is_blocked(cell):
		return _reject(proposal, "cell_blocked")

	player.position = world_position
	var now_at := map.location_at(cell)
	if now_at != player.location:
		var was_at := player.location
		player.location = now_at
		if not was_at.is_empty():
			Events.location_exited.emit(PlayerState.ID, was_at)
		if not now_at.is_empty():
			Events.location_entered.emit(PlayerState.ID, now_at)
	return Result.success(now_at)


## Where the player's body should appear when the region is shown: the saved
## position if it is still valid ground, otherwise in front of their current
## location, otherwise the map's spawn.
func player_start_position() -> Vector2:
	var map := world.map_for(player.region)
	if map == null:
		return Vector2.ZERO
	if player.position != Vector2.ZERO and not map.is_blocked(DistrictMap.world_to_cell(player.position)):
		return player.position
	var anchor := map.anchor_of(player.location)
	if anchor.x >= 0 and not map.is_blocked(anchor):
		return DistrictMap.cell_to_world(anchor)
	return DistrictMap.cell_to_world(map.spawn)


func _reject(proposal: Dictionary, code: String) -> Result:
	Events.action_rejected.emit(proposal, code)
	return Result.failure(code)


# --- saving -----------------------------------------------------------------

func save_game(slot: String) -> Result:
	if not is_running():
		return Result.failure("no_world", "Nothing to save")
	var sections := {
		"clock": clock.to_dict(),
		"rng": rng.to_dict(),
		"world": world.to_dict(),
		"npcs": npcs.to_dict(),
		"relationships": relationships.to_dict(),
		"knowledge": knowledge.to_dict(),
		"reputation": reputation.to_dict(),
		"events": events_queue.to_dict(),
		"player": player.to_dict(),
	}
	var meta := {
		"player_name": player.display_name,
		"region": world.current_region,
		"day": clock.day_index(),
		"time": clock.format_time(),
		"date": clock.format_date(),
		"character_level": player.stats.character_level,
	}
	return saves.save(slot, sections, meta)


func load_game(slot: String) -> Result:
	var read := saves.load_slot(slot)
	if read.is_err():
		return read
	var sections: Dictionary = read.value

	# Rebuild from content first so ids resolve, then overlay saved state.
	var fresh := new_game("", 1)
	if fresh.is_err():
		return fresh
	running = false

	clock.from_dict(sections.get("clock", {}))
	rng.from_dict(sections.get("rng", {}))
	world.from_dict(sections.get("world", {}))
	npcs.from_dict(sections.get("npcs", {}))
	relationships.from_dict(sections.get("relationships", {}))
	knowledge.from_dict(sections.get("knowledge", {}))
	reputation.from_dict(sections.get("reputation", {}))
	events_queue.from_dict(sections.get("events", {}))
	player.from_dict(sections.get("player", {}))

	director.assign_tiers()
	running = true
	Events.game_loaded.emit()
	Log.info("game", "Save restored", {"slot": slot})
	return Result.success(slot)


# --- world event dispatch ---------------------------------------------------

## Central handler for everything the event queue resolves. Systems register
## their own kinds here rather than each polling the queue.
func _on_world_event(event: WorldEventQueue.QueuedEvent) -> void:
	Events.world_event_fired.emit(event.to_dict())
	if event.kind.begins_with("knowledge_"):
		knowledge.resolve_spread_event(event.kind, event.payload, clock.total_minutes)
		return
	match event.kind:
		"npc_override_expired":
			var npc := npcs.get_npc(str(event.payload.get("npc", "")))
			if npc != null:
				npc.clear_override()
		"injury_healed":
			player.stats.heal_expired_injuries(clock.total_minutes)
		_:
			Log.debug("events", "Unhandled world event", {"kind": event.kind})


func _on_minute(total_minutes: int) -> void:
	Events.minute_passed.emit(total_minutes)
	director.tick(total_minutes)
	if total_minutes - _last_retier >= RETIER_INTERVAL:
		_last_retier = total_minutes
		director.assign_tiers()


func _on_hour(hour_of_day: int) -> void:
	Events.hour_passed.emit(hour_of_day)
	player.stats.drift(60, "idle")


func _on_day(day: int) -> void:
	Events.day_passed.emit(day)
	llm.budget.on_new_day(day)
	knowledge.forget_stale(clock.total_minutes)
	player.stats.heal_expired_injuries(clock.total_minutes)


func _on_time_skipped(from_minutes: int, to_minutes: int) -> void:
	director.catch_up(to_minutes)
	director.assign_tiers()
	Events.time_skipped.emit(from_minutes, to_minutes)


func _connect_simulation() -> void:
	clock.minute_passed.connect(_on_minute)
	clock.hour_passed.connect(_on_hour)
	clock.day_passed.connect(_on_day)
	clock.time_skipped.connect(_on_time_skipped)
	events_queue.event_due.connect(_on_world_event)


func _disconnect_simulation() -> void:
	if clock.minute_passed.is_connected(_on_minute):
		clock.minute_passed.disconnect(_on_minute)
		clock.hour_passed.disconnect(_on_hour)
		clock.day_passed.disconnect(_on_day)
		clock.time_skipped.disconnect(_on_time_skipped)
	if events_queue.event_due.is_connected(_on_world_event):
		events_queue.event_due.disconnect(_on_world_event)


func _seed_relationships() -> void:
	var seeds: Array = []
	for npc_id in npcs.all_ids():
		var entry := data.get_entry("npcs", npc_id)
		for tie in entry.get("relationships", []):
			var row: Dictionary = tie.duplicate()
			row["from"] = npc_id
			seeds.append(row)
	relationships.seed_from_data(seeds)


func _apply_background(background_id: String) -> void:
	var backgrounds := data.table("backgrounds")
	if backgrounds.has(background_id):
		player.apply_background(backgrounds[background_id])
		return
	# No background chosen yet (or an unknown id): minimal viable start.
	player.apply_background({
		"id": "drifter",
		"cash": 40,
		"home": _default_home(),
	})


func _default_home() -> String:
	for location_id in world.locations:
		var location: Location = world.locations[location_id]
		if location.kind == "home" and location.owner_id.is_empty():
			return location_id
	return world.locations.keys()[0] if not world.locations.is_empty() else ""


func _starting_region() -> String:
	for region_id in world.regions:
		var region: Region = world.regions[region_id]
		if region.unlock.is_empty():
			return region_id
	return world.regions.keys()[0] if not world.regions.is_empty() else ""


## Snapshot for the developer overlay.
func debug_snapshot() -> Dictionary:
	if not is_running():
		return {"running": false}
	return {
		"running": true,
		"time": clock.format_time(),
		"date": clock.format_date(),
		"day": clock.day_index(),
		"total_minutes": clock.total_minutes,
		"region": world.current_region,
		"npc_tiers": director.stats(),
		"queued_events": events_queue.size(),
		"relationship_edges": relationships.edge_count(),
		"facts": knowledge.facts.size(),
		"llm": llm.stats(),
	}
