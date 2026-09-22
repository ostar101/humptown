class_name Npc
extends RefCounted
## A persistent inhabitant of the world.
##
## An NPC is data, not a scene. A visual body is attached only while they are
## near the player; the person keeps existing either way. Identity is stable
## across saves, so "the woman who runs the corner shop" remains the same
## individual with the same history forty hours later.

enum LifeStage { CHILD, TEEN, YOUNG_ADULT, ADULT, MIDDLE_AGED, ELDER }
## How much the world invests in this person.
enum Importance { BACKGROUND, NAMED, STORY }

# --- identity (authored, stable) -------------------------------------------
var id: String
var name: String
var age: int = 30
var life_stage: LifeStage = LifeStage.ADULT
var occupation: String = ""
var home: String = ""
var workplace: String = ""
var schedule_id: String = ""
var importance: Importance = Importance.BACKGROUND
## Free-form trait tags used for dialogue colour and decision weighting,
## e.g. ["blunt", "generous", "suspicious_of_police"].
var traits: Array[String] = []
## Group memberships (workplace, family, faction) by id.
var groups: Array[String] = []
var portrait: String = ""
## Authored appearance for recognisable people: CharacterFigure palette keys
## to colour strings. Empty for background NPCs, whose look is generated.
var look: Dictionary = {}
## Who they are and how they talk, for the model to speak as them (D-036).
## Prompt material in English, never shown to the player; empty for
## background people, who are described from their occupation and traits.
var bio: String = ""
var voice: String = ""
## What kind of person they are, not how they feel about the player (that is
## Relationship.disposition()). Four axes in [0, 1], authored or defaulted;
## never merges, never changes at runtime (M8 D-082).
var nature: Dictionary = DEFAULT_NATURE.duplicate()
## Shop ids this person deals from, on top of any ordinary workplace shop —
## a list, not a bespoke goods list, so price/stock/till/restock all come
## free from ShopRegistry (M8 D-082).
var deals: Array[String] = []

# --- runtime state (saved) --------------------------------------------------
var location: String = ""
var activity: String = "idle"
var tier: SimLod.Tier = SimLod.Tier.DORMANT
var needs: NpcNeeds = NpcNeeds.new()
var alive: bool = true
var schedule_override: NpcSchedule.Override = null
## World minute this NPC was last simulated, so a coarse tick can catch up
## in one step instead of replaying every intervening minute.
var last_simulated: int = 0
## Persistent per-NPC scratch state (job lost, injured, holding an item...).
var state: Dictionary = {}
## Long-term memory entry ids owned by this NPC (see MemoryStore).
var memory_ids: Array[String] = []

const LIFE_STAGE_NAMES := ["child", "teen", "young_adult", "adult", "middle_aged", "elder"]
const IMPORTANCE_NAMES := ["background", "named", "story"]

## An ordinary person who will not deal: high lawfulness, everything else low
## or middling. Applied per-axis, so an author can set just one and still get
## sane values for the rest.
const NATURE_AXES := ["lawfulness", "greed", "risk", "discretion"]
const DEFAULT_NATURE := {"lawfulness": 0.8, "greed": 0.3, "risk": 0.2, "discretion": 0.5}


static func from_data(d: Dictionary) -> Npc:
	var n := Npc.new()
	n.id = str(d.get("id", ""))
	n.name = str(d.get("name", ""))
	n.age = int(d.get("age", 30))
	n.occupation = str(d.get("occupation", ""))
	n.home = str(d.get("home", ""))
	n.workplace = str(d.get("workplace", ""))
	n.schedule_id = str(d.get("schedule", ""))
	n.portrait = str(d.get("portrait", ""))
	n.bio = str(d.get("bio", ""))
	n.voice = str(d.get("voice", ""))
	var raw_look: Variant = d.get("look", {})
	if raw_look is Dictionary:
		n.look = raw_look
	n.life_stage = n._stage_for_age(n.age)

	var imp := str(d.get("importance", "background"))
	n.importance = Importance.STORY if imp == "story" else (
		Importance.NAMED if imp == "named" else Importance.BACKGROUND)

	var tr_list: Array[String] = []
	for t in d.get("traits", []):
		tr_list.append(str(t))
	n.traits = tr_list

	var gr_list: Array[String] = []
	for g in d.get("groups", []):
		gr_list.append(str(g))
	n.groups = gr_list

	var raw_nature: Variant = d.get("nature", {})
	var nat: Dictionary = DEFAULT_NATURE.duplicate()
	if raw_nature is Dictionary:
		for axis in NATURE_AXES:
			if (raw_nature as Dictionary).has(axis):
				nat[axis] = float((raw_nature as Dictionary)[axis])
	n.nature = nat

	var deal_list: Array[String] = []
	for deal in d.get("deals", []):
		deal_list.append(str(deal))
	n.deals = deal_list

	n.location = n.home
	return n


func _stage_for_age(a: int) -> LifeStage:
	if a < 13: return LifeStage.CHILD
	if a < 18: return LifeStage.TEEN
	if a < 30: return LifeStage.YOUNG_ADULT
	if a < 50: return LifeStage.ADULT
	if a < 68: return LifeStage.MIDDLE_AGED
	return LifeStage.ELDER


func is_adult() -> bool:
	return age >= 18


func has_trait(t: String) -> bool:
	return t in traits


func in_group(g: String) -> bool:
	return g in groups


## Story NPCs are protected from incidental death (see NpcRegistry.kill).
func is_story_critical() -> bool:
	return importance == Importance.STORY


func set_override(from_minutes: int, to_minutes: int, location_id: String, act: String, reason: String) -> void:
	var o := NpcSchedule.Override.new()
	o.from_minutes = from_minutes
	o.to_minutes = to_minutes
	o.location = location_id
	o.activity = act
	o.reason = reason
	schedule_override = o
	Log.debug("npc", "Schedule override set", {"npc": id, "reason": reason})


func clear_override() -> void:
	schedule_override = null


## Compact description handed to the LLM. Deliberately small: identity and
## present circumstance only. History arrives separately via selected memories.
func describe_for_prompt() -> Dictionary:
	return {
		"name": name,
		"age": age,
		"occupation": occupation,
		"traits": traits,
		"doing": activity,
		"feeling": needs.describe(),
	}


func to_dict() -> Dictionary:
	return {
		"id": id,
		"location": location,
		"activity": activity,
		"tier": int(tier),
		"needs": needs.to_dict(),
		"alive": alive,
		"last_simulated": last_simulated,
		"state": state,
		"memory_ids": memory_ids,
		"override": schedule_override.to_dict() if schedule_override != null else null,
	}


func from_dict(d: Dictionary) -> void:
	location = str(d.get("location", home))
	activity = str(d.get("activity", "idle"))
	tier = d.get("tier", SimLod.Tier.DORMANT) as SimLod.Tier
	needs.from_dict(d.get("needs", {}))
	alive = bool(d.get("alive", true))
	last_simulated = int(d.get("last_simulated", 0))
	state = d.get("state", {})
	var mem: Array[String] = []
	for m in d.get("memory_ids", []):
		mem.append(str(m))
	memory_ids = mem
	var ov: Variant = d.get("override")
	schedule_override = NpcSchedule.Override.from_dict(ov) if typeof(ov) == TYPE_DICTIONARY else null
