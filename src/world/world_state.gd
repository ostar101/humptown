class_name WorldState
extends RefCounted
## Authoritative world facts: regions, locations, story flags, unlocks.
##
## This object is the single source of truth about *where things are and what
## is true*. Nothing else — least of all an LLM response — writes to it
## directly; mutations go through methods here so they can be validated and
## so every change can be broadcast.

var regions: Dictionary = {}       # id -> Region
var locations: Dictionary = {}     # id -> Location
var flags: Dictionary = {}         # story/world flags: name -> Variant
var current_region: String = ""
## region_id -> DistrictMap. Derived from content, so never saved.
var maps: Dictionary = {}
## location_id -> DistrictMap of the inside of that building. Also derived.
var interiors: Dictionary = {}

var _locations_by_region: Dictionary = {}   # region_id -> Array[String]


func build_from(registry: DataRegistry) -> void:
	regions.clear()
	locations.clear()
	_locations_by_region.clear()

	for id in registry.ids("regions"):
		regions[id] = Region.from_data(registry.get_entry("regions", id))
	for id in registry.ids("locations"):
		var loc := Location.from_data(registry.get_entry("locations", id))
		locations[id] = loc
		if not _locations_by_region.has(loc.region):
			_locations_by_region[loc.region] = []
		_locations_by_region[loc.region].append(loc.id)

	maps.clear()
	for id in registry.ids("maps"):
		var built := DistrictMap.from_data(registry.get_entry("maps", id))
		if built.is_err():
			Log.error("world", "Map rejected", {"map": id, "reason": built.message})
			continue
		var map: DistrictMap = built.value
		for loc_id in map.buildings:
			var location: Location = locations.get(loc_id)
			if location != null:
				map.building_kind[loc_id] = location.kind
		maps[map.region] = map

	interiors.clear()
	for id in registry.ids("interiors"):
		var entry := registry.get_entry("interiors", id)
		var built := DistrictMap.from_data(entry)
		if built.is_err():
			Log.error("world", "Interior rejected", {"interior": id, "reason": built.message})
			continue
		var inside: DistrictMap = built.value
		var location: Location = locations.get(inside.interior_of)
		inside.region = location.region if location != null else ""
		interiors[inside.interior_of] = inside


# --- queries ----------------------------------------------------------------

func get_region(id: String) -> Region:
	return regions.get(id)


## The physical layout of a region, or null for regions not yet mapped.
func map_for(region_id: String) -> DistrictMap:
	return maps.get(region_id)


## The inside of a building, or null for buildings nobody can enter.
func interior_for(location_id: String) -> DistrictMap:
	return interiors.get(location_id)


func get_location(id: String) -> Location:
	return locations.get(id)


func locations_in(region_id: String) -> Array:
	return _locations_by_region.get(region_id, [])


func region_of(location_id: String) -> String:
	var loc: Location = locations.get(location_id)
	return loc.region if loc != null else ""


func get_flag(name: String, fallback: Variant = null) -> Variant:
	return flags.get(name, fallback)


func has_flag(name: String) -> bool:
	return flags.has(name) and flags[name] != false


func set_flag(name: String, value: Variant = true) -> void:
	var previous: Variant = flags.get(name)
	if previous == value:
		return
	flags[name] = value
	Log.debug("world", "Flag set", {"flag": name, "value": value})


# --- movement / unlocking ---------------------------------------------------

func enter_region(region_id: String) -> Result:
	var region: Region = regions.get(region_id)
	if region == null:
		return Result.failure("no_such_region", region_id)
	if current_region == region_id:
		return Result.success(region_id)
	var previous := current_region
	current_region = region_id
	region.discovered = true
	if not previous.is_empty():
		Events.region_exited.emit(previous)
	Events.region_entered.emit(region_id)
	return Result.success(region_id)


## Evaluates a region's unlock requirements against the world and player.
## Returns success, or failure whose code names the first unmet requirement.
func evaluate_unlock(region_id: String, ctx: Dictionary) -> Result:
	var region: Region = regions.get(region_id)
	if region == null:
		return Result.failure("no_such_region", region_id)
	if region.unlocked:
		return Result.success(true)
	for req in region.unlock:
		var kind := str(req.get("type", ""))
		match kind:
			"story_flag":
				if not has_flag(str(req.get("flag", ""))):
					return Result.failure("needs_story", str(req.get("flag", "")))
			"money":
				if int(ctx.get("money", 0)) < int(req.get("amount", 0)):
					return Result.failure("needs_money", str(req.get("amount", 0)))
			"reputation":
				var scope := str(req.get("scope", ""))
				var reps: Dictionary = ctx.get("reputation", {})
				if float(reps.get(scope, 0.0)) < float(req.get("min", 0.0)):
					return Result.failure("needs_reputation", scope)
			"contact":
				if not (str(req.get("npc", "")) in ctx.get("contacts", [])):
					return Result.failure("needs_contact", str(req.get("npc", "")))
			"item":
				if not (str(req.get("item", "")) in ctx.get("items", [])):
					return Result.failure("needs_item", str(req.get("item", "")))
			"knowledge":
				if not (str(req.get("fact", "")) in ctx.get("known_facts", [])):
					return Result.failure("needs_knowledge", str(req.get("fact", "")))
			"skill":
				var skills: Dictionary = ctx.get("skills", {})
				if int(skills.get(str(req.get("skill", "")), 0)) < int(req.get("level", 0)):
					return Result.failure("needs_skill", str(req.get("skill", "")))
			_:
				Log.warn("world", "Unknown unlock requirement", {"type": kind})
	return Result.success(true)


## Unlocks a region if its requirements are met. Idempotent.
func try_unlock(region_id: String, ctx: Dictionary) -> Result:
	var check := evaluate_unlock(region_id, ctx)
	if check.is_err():
		return check
	var region: Region = regions[region_id]
	if not region.unlocked:
		region.unlocked = true
		Log.info("world", "Region unlocked", {"region": region_id})
	return Result.success(true)


func discover_region(region_id: String) -> void:
	var region: Region = regions.get(region_id)
	if region != null and not region.discovered:
		region.discovered = true


func to_dict() -> Dictionary:
	var region_states := {}
	for id in regions:
		region_states[id] = regions[id].to_dict()
	var location_states := {}
	for id in locations:
		var loc: Location = locations[id]
		if not loc.state.is_empty():
			location_states[id] = loc.to_dict()
	return {
		"current_region": current_region,
		"flags": flags,
		"regions": region_states,
		"locations": location_states,
	}


func from_dict(d: Dictionary) -> void:
	current_region = str(d.get("current_region", ""))
	flags = d.get("flags", {})
	var region_states: Dictionary = d.get("regions", {})
	for id in region_states:
		if regions.has(id):
			regions[id].from_dict(region_states[id])
	var location_states: Dictionary = d.get("locations", {})
	for id in location_states:
		if locations.has(id):
			locations[id].from_dict(location_states[id])
