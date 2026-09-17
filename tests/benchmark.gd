extends Node
## Performance benchmark for the simulation spine.
##
## Run with:
##     godot --headless --path . res://tests/benchmark.tscn
##
## The brief's hardest constraint is an i3-class CPU with integrated graphics,
## and its clearest process rule is that performance must be measured rather
## than assumed. This measures the real per-minute loop the game runs — NPC
## ticking plus the periodic tier reassignment — at populations well past the
## first slice.
##
## The property under test: cost tracks how many people are *near the player*,
## not how many people exist. Two distributions are measured because they
## stress different halves of that claim:
##
##   spread        residents distributed across regions, as a real world is
##   concentrated  everyone living in the player's district, the worst case

const POPULATIONS := [50, 200, 1000, 3000]
const SIMULATED_MINUTES := 720          # half a game day
const FRAME_BUDGET_MS := 16.7


func _ready() -> void:
	Log.min_level = Log.Level.ERROR
	print("")
	print("=== Humptown simulation benchmark ===")
	print("Godot %s   |   %d game minutes per run   |   frame budget %.1f ms" % [
		Engine.get_version_info()["string"], SIMULATED_MINUTES, FRAME_BUDGET_MS])
	print("")

	for spread in [true, false]:
		print("-- %s --" % ("spread across regions" if spread else "concentrated in one district"))
		print("%8s %8s %9s %12s %13s %12s" % [
			"people", "active", "local", "us/minute", "% of frame", "skip 8h ms"])
		for population in POPULATIONS:
			_run(population, spread)
		print("")

	print("Reading these numbers: game time advances one minute per real second")
	print("by default, so 'us/minute' is the cost of one simulated minute spread")
	print("across ~60 frames. The '%' column is that cost against a single")
	print("60 fps frame, which is the pessimistic reading.")
	print("")
	await get_tree().process_frame
	get_tree().quit(0)


func _run(population: int, spread: bool) -> void:
	Game.new_game("bg_returning", 1234)
	_grow_population_to(population, spread)
	Game.director.assign_tiers()

	var stats := Game.director.stats()
	var local := Game.npcs.ids_in_regions(_nearby_regions()).size()
	var start := Game.clock.total_minutes

	# The real loop: tick every minute, reassign tiers on the game's cadence.
	var began := Time.get_ticks_usec()
	for offset in range(SIMULATED_MINUTES):
		var minute := start + offset
		Game.director.tick(minute)
		if offset % Game.RETIER_INTERVAL == 0:
			Game.director.assign_tiers()
	var loop_us := Time.get_ticks_usec() - began

	# Batched advancement: the cost of sleeping through eight hours.
	Game.clock.set_absolute(start + SIMULATED_MINUTES)
	began = Time.get_ticks_usec()
	Game.director.catch_up(Game.clock.total_minutes + 480)
	Game.director.assign_tiers()
	var skip_us := Time.get_ticks_usec() - began

	var per_minute_us := float(loop_us) / float(SIMULATED_MINUTES)
	print("%8d %8d %9d %12.1f %12.2f%% %12.2f" % [
		stats["total"], stats["active"], local,
		per_minute_us,
		(per_minute_us / 1000.0) / FRAME_BUDGET_MS * 100.0,
		float(skip_us) / 1000.0,
	])


func _nearby_regions() -> Array[String]:
	var out: Array[String] = [Game.world.current_region]
	var region: Region = Game.world.get_region(Game.world.current_region)
	if region != null:
		out.append_array(region.neighbours)
	return out


## Clones the authored population into extra residents so the benchmark runs
## the real code path rather than a stub.
func _grow_population_to(target: int, spread: bool) -> void:
	var templates: Array = Game.npcs.all_ids().duplicate()
	var homes: Array = []
	if spread:
		for region_id in Game.world.regions:
			for location_id in Game.world.locations_in(str(region_id)):
				if Game.world.get_location(location_id).kind == "home":
					homes.append(location_id)
	else:
		homes = Game.world.locations_in("harbourside")
	if homes.is_empty():
		homes = Game.world.locations.keys()

	var index := 0
	while Game.npcs.count() < target:
		var template: Npc = Game.npcs.get_npc(templates[index % templates.size()])
		var clone := Npc.new()
		clone.id = "bench_%d" % index
		clone.name = "Resident %d" % index
		clone.age = 25 + (index % 40)
		clone.home = homes[index % homes.size()]
		clone.workplace = template.workplace
		clone.schedule_id = template.schedule_id
		clone.location = clone.home
		Game.npcs.npcs[clone.id] = clone
		index += 1
	Game.npcs.rebuild_region_index()
