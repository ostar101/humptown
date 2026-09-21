class_name Bins
extends RefCounted
## What is in the street's bins (D-069).
##
## A bin is a place in the world (`DistrictMap.furniture`, D-068) with an
## inventory of its own. It is looked into for the first time when the player
## searches it: what it holds is then rolled, once, from the `bins` stream and
## the table in `data/bins.json`, and kept — so is anything the player puts in
## it, and it is saved. An *empty* bin is left alone for `refill_days`, then
## somebody has thrown something new in; a bin holding anything is never
## topped up, so it works as a hiding place too.
##
## This holds state and does the arithmetic. Whether a search or a move may
## happen is `Game`'s call. People have no belongings, so nothing they own is in
## here, and nobody sees you at it yet.

const DEFINITION := "bin_street"

var _data: DataRegistry = null
var _rng: RngStreams = null
## bin id -> {"inv": Inventory, "filled": int (the day it was last filled)}
var _state: Dictionary = {}


func setup(data: DataRegistry, rng: RngStreams) -> void:
	_data = data
	_rng = rng
	_state = {}


func definition() -> Dictionary:
	return _data.get_entry("bins", DEFINITION) if _data != null else {}


## What a bin can hold, in weight.
func capacity() -> float:
	return float(definition().get("capacity", 30.0))


## What is in this bin today; rolled the first time it is asked for, and again
## when it has stood empty long enough.
func contents(bin_id: String, today: int) -> Inventory:
	if not _state.has(bin_id):
		_state[bin_id] = {"inv": _new_inventory(), "filled": today}
		_fill(_state[bin_id]["inv"])
	else:
		var entry: Dictionary = _state[bin_id]
		var inv: Inventory = entry["inv"]
		if inv.stacks.is_empty() and today - int(entry["filled"]) >= int(definition().get("refill_days", 3)):
			entry["filled"] = today
			_fill(inv)
	return _state[bin_id]["inv"]


## Whether anyone has looked in this bin yet.
func was_searched(bin_id: String) -> bool:
	return _state.has(bin_id)


func to_dict() -> Dictionary:
	var out := {}
	for bin_id in _state:
		out[bin_id] = {"filled": int(_state[bin_id]["filled"]), "inv": (_state[bin_id]["inv"] as Inventory).to_dict()}
	return {"bins": out}


func from_dict(d: Dictionary) -> void:
	_state = {}
	var saved: Dictionary = d.get("bins", {})
	for bin_id in saved:
		var inv := _new_inventory()
		inv.from_dict(saved[bin_id].get("inv", {}))
		inv.base_capacity = capacity()
		_state[str(bin_id)] = {"inv": inv, "filled": int(saved[bin_id].get("filled", 0))}


func _new_inventory() -> Inventory:
	var inv := Inventory.new()
	inv.setup(_data)
	inv.base_capacity = capacity()
	return inv


## Rolls what somebody threw away. Weighted picks from the table, a few of them.
func _fill(inv: Inventory) -> void:
	var table: Array = definition().get("loot", [])
	var rolls: Dictionary = definition().get("rolls", {})
	var stream := _rng.stream("bins")
	var total := 0.0
	for entry: Dictionary in table:
		total += float(entry.get("weight", 1))
	if total <= 0.0:
		return
	for i in stream.randi_range(int(rolls.get("min", 0)), int(rolls.get("max", 2))):
		var pick := stream.randf() * total
		for entry: Dictionary in table:
			pick -= float(entry.get("weight", 1))
			if pick <= 0.0:
				inv.add(str(entry["item"]), stream.randi_range(1, int(entry.get("max", 1))))
				break
