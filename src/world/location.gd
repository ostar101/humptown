class_name Location
extends RefCounted
## A place NPCs and the player can be: a home, a shop, a workplace, a street.
##
## Locations are the unit of coarse positioning. Background NPCs have a
## location and nothing finer; only NPCs near the player get real coordinates.
## That is what makes a large population affordable.

enum Access { PUBLIC, SEMI_PUBLIC, PRIVATE, LOCKED }

var id: String
var region: String
var name_key: String
var kind: String = "generic"       # home | shop | work | bar | street | civic
var access: Access = Access.PUBLIC
var owner_id: String = ""
## Minutes from midnight; [0, 1440] means always open.
var open_from: int = 0
var open_until: int = 1440
## Ids of locations reachable directly from here (for travel-time estimates).
var connections: Array[String] = []
## Rough travel minutes from this location to the region hub.
var travel_minutes: int = 5
## Runtime state that saves: e.g. {"locked": true, "lights_on": false}
var state: Dictionary = {}


static func from_data(d: Dictionary) -> Location:
	var l := Location.new()
	l.id = str(d.get("id", ""))
	l.region = str(d.get("region", ""))
	l.name_key = str(d.get("name_key", ""))
	l.kind = str(d.get("kind", "generic"))
	l.owner_id = str(d.get("owner", ""))
	l.open_from = int(d.get("open_from", 0))
	l.open_until = int(d.get("open_until", 1440))
	l.travel_minutes = int(d.get("travel_minutes", 5))
	match str(d.get("access", "public")):
		"semi_public": l.access = Access.SEMI_PUBLIC
		"private": l.access = Access.PRIVATE
		"locked": l.access = Access.LOCKED
		_: l.access = Access.PUBLIC
	var conns: Array[String] = []
	for c in d.get("connections", []):
		conns.append(str(c))
	l.connections = conns
	return l


func display_name() -> String:
	return tr(name_key)


func is_open_at(minute_of_day: int) -> bool:
	if open_from == 0 and open_until >= 1440:
		return true
	if open_from <= open_until:
		return minute_of_day >= open_from and minute_of_day < open_until
	# Wraps past midnight (a bar open 20:00-03:00).
	return minute_of_day >= open_from or minute_of_day < open_until


func is_locked() -> bool:
	return bool(state.get("locked", access == Access.LOCKED))


## Public spaces are where information spreads; private ones are where it does not.
func is_public() -> bool:
	return access == Access.PUBLIC or access == Access.SEMI_PUBLIC


func to_dict() -> Dictionary:
	return {"id": id, "state": state}


func from_dict(d: Dictionary) -> void:
	state = d.get("state", {})
