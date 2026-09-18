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
## World position on the current region's map (DistrictMap units). ZERO means
## "not placed yet"; Game.player_start_position() then picks a spot.
var position: Vector2 = Vector2.ZERO

# --- systems ----------------------------------------------------------------
var stats := Stats.new()
var skills := Skills.new()
var wallet := Wallet.new()
var inventory := Inventory.new()

# --- progress ---------------------------------------------------------------
var known_contacts: Array[String] = []
var quest_flags: Dictionary = {}
var home_location: String = ""
var job_id: String = ""


func setup(data: DataRegistry) -> void:
	skills.setup(data)
	inventory.setup(data)
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
	job_id = str(background.get("job", ""))
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
func _apply_carry_capacity() -> void:
	inventory.base_capacity = 12.0 + float(stats.attribute("strength")) * 1.6


func on_strength_changed() -> void:
	_apply_carry_capacity()


func to_dict() -> Dictionary:
	return {
		"display_name": display_name,
		"background_id": background_id,
		"pronouns": pronouns,
		"appearance": appearance,
		"region": region,
		"location": location,
		"position": {"x": position.x, "y": position.y},
		"stats": stats.to_dict(),
		"skills": skills.to_dict(),
		"wallet": wallet.to_dict(),
		"inventory": inventory.to_dict(),
		"known_contacts": known_contacts,
		"quest_flags": quest_flags,
		"home_location": home_location,
		"job_id": job_id,
	}


func from_dict(d: Dictionary) -> void:
	display_name = str(d.get("display_name", "Player"))
	background_id = str(d.get("background_id", ""))
	pronouns = str(d.get("pronouns", "they"))
	appearance = d.get("appearance", {})
	region = str(d.get("region", ""))
	location = str(d.get("location", ""))
	var pos: Dictionary = d.get("position", {})
	position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	stats.from_dict(d.get("stats", {}))
	skills.from_dict(d.get("skills", {}))
	wallet.from_dict(d.get("wallet", {}))
	inventory.from_dict(d.get("inventory", {}))
	var contacts: Array[String] = []
	for c in d.get("known_contacts", []):
		contacts.append(str(c))
	known_contacts = contacts
	quest_flags = d.get("quest_flags", {})
	home_location = str(d.get("home_location", ""))
	job_id = str(d.get("job_id", ""))
	_apply_carry_capacity()
