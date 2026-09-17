class_name Inventory
extends RefCounted
## What someone is carrying, limited by weight rather than slot count.
##
## Weight-limited because it produces real decisions (do I carry the crowbar
## or the groceries?) without the fiddliness of grid Tetris. Stacking keeps
## the list short.

class Stack extends RefCounted:
	var item_id: String
	var count: int = 1
	## Per-instance state: durability, who it was stolen from, etc.
	var state: Dictionary = {}

	func to_dict() -> Dictionary:
		return {"item": item_id, "count": count, "state": state}

	static func from_dict(d: Dictionary) -> Stack:
		var s := Stack.new()
		s.item_id = str(d.get("item", ""))
		s.count = int(d.get("count", 1))
		s.state = d.get("state", {})
		return s


var stacks: Array[Stack] = []
## Base capacity in weight units, before strength and bags.
var base_capacity: float = 20.0
var bonus_capacity: float = 0.0

var _data: DataRegistry = null


func setup(data: DataRegistry) -> void:
	_data = data


func capacity() -> float:
	return base_capacity + bonus_capacity


func item_weight(item_id: String) -> float:
	if _data == null:
		return 1.0
	return float(_data.get_entry("items", item_id).get("weight", 1.0))


func is_stackable(item_id: String) -> bool:
	if _data == null:
		return true
	return bool(_data.get_entry("items", item_id).get("stackable", true))


func total_weight() -> float:
	var sum := 0.0
	for s in stacks:
		sum += item_weight(s.item_id) * float(s.count)
	return sum


func free_weight() -> float:
	return capacity() - total_weight()


func count_of(item_id: String) -> int:
	var total := 0
	for s in stacks:
		if s.item_id == item_id:
			total += s.count
	return total


func has(item_id: String, amount: int = 1) -> bool:
	return count_of(item_id) >= amount


func item_ids() -> Array[String]:
	var out: Array[String] = []
	for s in stacks:
		if not (s.item_id in out):
			out.append(s.item_id)
	return out


func add(item_id: String, amount: int = 1, state: Dictionary = {}) -> Result:
	if amount <= 0:
		return Result.failure("invalid_amount")
	if _data != null and not _data.has_entry("items", item_id):
		return Result.failure("unknown_item", item_id)
	var added_weight := item_weight(item_id) * float(amount)
	if added_weight > free_weight():
		return Result.failure("too_heavy", item_id)

	if is_stackable(item_id) and state.is_empty():
		for s in stacks:
			if s.item_id == item_id and s.state.is_empty():
				s.count += amount
				Events.inventory_changed.emit()
				return Result.success(amount)
	var stack := Stack.new()
	stack.item_id = item_id
	stack.count = amount
	stack.state = state.duplicate()
	stacks.append(stack)
	Events.inventory_changed.emit()
	return Result.success(amount)


func remove(item_id: String, amount: int = 1) -> Result:
	if count_of(item_id) < amount:
		return Result.failure("not_enough", item_id)
	var remaining := amount
	var i := stacks.size() - 1
	while i >= 0 and remaining > 0:
		var s := stacks[i]
		if s.item_id == item_id:
			var taken := mini(s.count, remaining)
			s.count -= taken
			remaining -= taken
			if s.count <= 0:
				stacks.remove_at(i)
		i -= 1
	Events.inventory_changed.emit()
	return Result.success(amount)


## Moves items to another inventory, respecting the destination's capacity.
func transfer_to(other: Inventory, item_id: String, amount: int = 1) -> Result:
	if not has(item_id, amount):
		return Result.failure("not_enough", item_id)
	var accepted := other.add(item_id, amount)
	if accepted.is_err():
		return accepted
	return remove(item_id, amount)


func clear() -> void:
	stacks.clear()
	Events.inventory_changed.emit()


func to_dict() -> Dictionary:
	var out: Array = []
	for s in stacks:
		out.append(s.to_dict())
	return {"stacks": out, "base_capacity": base_capacity, "bonus_capacity": bonus_capacity}


func from_dict(d: Dictionary) -> void:
	stacks.clear()
	base_capacity = float(d.get("base_capacity", 20.0))
	bonus_capacity = float(d.get("bonus_capacity", 0.0))
	for raw in d.get("stacks", []):
		stacks.append(Stack.from_dict(raw))
