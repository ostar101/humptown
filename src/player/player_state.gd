class_name PlayerState
extends RefCounted
## The player character: identity, possessions, progression, position.
##
## The player is deliberately *not* an Npc subclass. NPCs are simulated by the
## director; the player is driven by input and has systems (quests, phone,
## background) that no NPC needs. They meet through the same relationship,
## knowledge and reputation graphs, where the player is just the id "player".

const ID := "player"

# --- identity ---------------------------------------------------------------
var display_name: String = "Player"
var background_id: String = ""
var pronouns: String = "they"
## Modular appearance keys resolved by the character renderer later.
var appearance: Dictionary = {}

# --- position ---------------------------------------------------------------
var region: String = ""
## Empty while the player is out in the region but in no particular place.
var location: String = ""
## The building the player is inside, or empty when out in the region. While
## inside, `position` is on that building's interior map.
var interior: String = ""
## World position on the current map (DistrictMap units): the region's, or the
## interior's while inside. ZERO means "not placed yet";
## Game.player_start_position() then picks a spot.
var position: Vector2 = Vector2.ZERO

# --- systems ----------------------------------------------------------------
var stats := Stats.new()
var skills := Skills.new()
var wallet := Wallet.new()
var inventory := Inventory.new()
## What the player keeps at home (D-043): the cupboard in their flat.
var stash := Inventory.new()
## A cupboard holds far more than a person carries, but not everything.
const STASH_CAPACITY := 150.0

# --- progress ---------------------------------------------------------------
var known_contacts: Array[String] = []
var quest_flags: Dictionary = {}
var home_location: String = ""
## location id -> "visited" | "told": the places the player knows of (D-049).
var known_places: Dictionary = {}
## Crafting recipes the player has found (D-070): made once, or had the makings of.
var known_recipes: Array[String] = []
## Worn or wielded (M8 step 4, D-080): slot -> item id, six slots (head, body,
## legs, feet, hand, back), no more. A pointer, not a move — the thing stays
## in `inventory` and still weighs what it always did.
var equipment: Dictionary = {}

var _data: DataRegistry = null


func setup(data: DataRegistry) -> void:
	_data = data
	skills.setup(data)
	inventory.setup(data)
	inventory.announces = true   # what goes in and out of the bag is told to the feed (D-059)
	stash.setup(data)
	stash.base_capacity = STASH_CAPACITY
	_apply_carry_capacity()


## Applies a character background template: starting kit, ties and problems.
func apply_background(background: Dictionary) -> void:
	background_id = str(background.get("id", ""))

	for attribute in background.get("attributes", {}):
		stats.attributes[attribute] = int(background["attributes"][attribute])
	for skill_id in background.get("skills", {}):
		var level := int(background["skills"][skill_id])
		skills.levels[skill_id] = level
		skills.xp[skill_id] = Skills.xp_for_level(level)

	wallet.cash = int(background.get("cash", 0))
	wallet.bank = int(background.get("bank", 0))
	home_location = str(background.get("home", ""))
	known_places[home_location] = "visited"
	location = home_location
	_apply_carry_capacity()

	for entry in background.get("items", []):
		inventory.add(str(entry.get("id", "")), int(entry.get("count", 1)))
	for contact in background.get("contacts", []):
		add_contact(str(contact))
	for flag in background.get("flags", []):
		quest_flags[str(flag)] = true

	Log.info("player", "Background applied", {"background": background_id})


func add_contact(npc_id: String) -> void:
	if npc_id.is_empty() or npc_id in known_contacts:
		return
	known_contacts.append(npc_id)


## Learns of a place: been there ("visited") or heard of it ("told"). Being
## there outranks hearing of it. Returns whether the place was unknown until
## now — the moment it appears on the map.
func learn_place(location_id: String, how: String) -> bool:
	if location_id == "":
		return false
	var was := str(known_places.get(location_id, ""))
	if was == "visited" or (was == "told" and how == "told"):
		return false
	known_places[location_id] = how
	if was == "":
		Events.place_learned.emit(location_id, how)
		return true
	return false


func knows_place(location_id: String) -> bool:
	return known_places.has(location_id)


func knows_contact(npc_id: String) -> bool:
	return npc_id in known_contacts


## Context dictionary used by region unlock checks and dialogue gating.
func unlock_context(reputation: Reputation, knowledge: KnowledgeNetwork) -> Dictionary:
	return {
		"money": wallet.total(),
		"contacts": known_contacts,
		"items": inventory.item_ids(),
		"skills": skills.level_map(),
		"reputation": reputation.active_scopes() if reputation != null else {},
		"known_facts": knowledge.known_fact_ids(ID) if knowledge != null else [],
	}


## Carry capacity rises with strength and with whatever bag is equipped.
## Applies to `inventory` only, never `stash`: a backpack sitting in the
## cupboard at home does nothing for what the cupboard holds.
func _apply_carry_capacity() -> void:
	inventory.base_capacity = 12.0 + float(stats.attribute("strength")) * 1.6
	inventory.bonus_capacity = _equipped_capacity_bonus()


func on_strength_changed() -> void:
	_apply_carry_capacity()


## Clears any slot whose thing left the bag some other way — sold, given,
## crafted away — then reapplies the capacity a worn backpack gives. The one
## place that closes that leak (D-080); call after any change to `equipment`
## and whenever `inventory` changes.
func reconcile_equipment() -> void:
	for slot: String in equipment.keys().duplicate():
		var item_id: String = str(equipment[slot])
		if not inventory.has(item_id):
			equipment.erase(slot)
			Events.equipment_changed.emit(slot, "")
	_apply_carry_capacity()


func _equipped_capacity_bonus() -> float:
	if _data == null:
		return 0.0
	var bonus := 0.0
	for slot in equipment:
		var item := _data.get_entry("items", str(equipment[slot]))
		bonus += float(item.get("capacity_bonus", 0.0))
	return bonus


func to_dict() -> Dictionary:
	return {
		"display_name": display_name,
		"background_id": background_id,
		"pronouns": pronouns,
		"appearance": appearance,
		"region": region,
		"location": location,
		"interior": interior,
		"position": {"x": position.x, "y": position.y},
		"stats": stats.to_dict(),
		"skills": skills.to_dict(),
		"wallet": wallet.to_dict(),
		"inventory": inventory.to_dict(),
		"stash": stash.to_dict(),
		"known_contacts": known_contacts,
		"quest_flags": quest_flags,
		"home_location": home_location,
		"known_places": known_places,
		"known_recipes": known_recipes,
		"equipment": equipment,
	}


func from_dict(d: Dictionary) -> void:
	display_name = str(d.get("display_name", "Player"))
	background_id = str(d.get("background_id", ""))
	pronouns = str(d.get("pronouns", "they"))
	appearance = d.get("appearance", {})
	region = str(d.get("region", ""))
	location = str(d.get("location", ""))
	# Absent in saves from before interiors, which were all made outdoors.
	interior = str(d.get("interior", ""))
	var pos: Dictionary = d.get("position", {})
	position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	stats.from_dict(d.get("stats", {}))
	skills.from_dict(d.get("skills", {}))
	wallet.from_dict(d.get("wallet", {}))
	inventory.from_dict(d.get("inventory", {}))
	# Absent in saves from before the home had a cupboard: it starts empty.
	stash.from_dict(d.get("stash", {}))
	stash.base_capacity = STASH_CAPACITY
	var contacts: Array[String] = []
	for c in d.get("known_contacts", []):
		contacts.append(str(c))
	known_contacts = contacts
	quest_flags = d.get("quest_flags", {})
	home_location = str(d.get("home_location", ""))
	known_places = {}
	for place_id in d.get("known_places", {}):
		known_places[str(place_id)] = str(d["known_places"][place_id])
	known_recipes = []
	for recipe_id in d.get("known_recipes", []):
		known_recipes.append(str(recipe_id))
	if known_places.is_empty() and home_location != "":
		known_places[home_location] = "visited"   # a save from before the map: you know where you live
	equipment = {}
	for slot in d.get("equipment", {}):
		equipment[str(slot)] = str(d["equipment"][slot])
	_apply_carry_capacity()
