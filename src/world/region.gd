class_name Region
extends RefCounted
## A district, town or rural area. The unit of world streaming and of
## unlocking: only the player's current region (plus neighbours) is fully
## simulated, and regions open up through varied requirements rather than a
## single "story flag" gate.

var id: String
var name_key: String
var description_key: String = ""
## Ids of adjacent regions.
var neighbours: Array[String] = []
## Travel minutes to each neighbour: { region_id -> minutes }
var travel_times: Dictionary = {}
## Unlock requirements. Each entry is {type, ...}. ALL must be satisfied.
## Types: story_flag, money, reputation, contact, item, knowledge, skill.
var unlock: Array[Dictionary] = []
var discovered: bool = false
var unlocked: bool = false


static func from_data(d: Dictionary) -> Region:
	var r := Region.new()
	r.id = str(d.get("id", ""))
	r.name_key = str(d.get("name_key", ""))
	r.description_key = str(d.get("description_key", ""))
	var ns: Array[String] = []
	for n in d.get("neighbours", []):
		ns.append(str(n))
	r.neighbours = ns
	r.travel_times = d.get("travel_times", {})
	var reqs: Array[Dictionary] = []
	for u in d.get("unlock", []):
		reqs.append(u)
	r.unlock = reqs
	r.discovered = bool(d.get("discovered", false))
	r.unlocked = bool(d.get("unlocked", r.unlock.is_empty()))
	return r


func display_name() -> String:
	return tr(name_key)


func travel_minutes_to(region_id: String) -> int:
	return int(travel_times.get(region_id, 30))


func to_dict() -> Dictionary:
	return {"id": id, "discovered": discovered, "unlocked": unlocked}


func from_dict(d: Dictionary) -> void:
	discovered = bool(d.get("discovered", false))
	unlocked = bool(d.get("unlocked", false))
