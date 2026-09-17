class_name WorldEventQueue
extends RefCounted
## Time-ordered queue of scheduled world events (a binary min-heap).
##
## This is how the world stays alive outside the player's region without
## simulating it. Instead of an off-screen manager "thinking" every frame,
## we record what should happen and when, then resolve it at that moment:
##
##     queue.schedule(now + 45, "meeting_response", {"npc": "npc_manager_01"})
##
## Events are ordered by time, then by insertion sequence, so resolution is
## deterministic and therefore save-safe.

class QueuedEvent extends RefCounted:
	var id: String
	var at: int          # absolute world minute
	var kind: String
	var payload: Dictionary
	var seq: int

	func to_dict() -> Dictionary:
		return {"id": id, "at": at, "kind": kind, "payload": payload, "seq": seq}

	static func from_dict(d: Dictionary) -> QueuedEvent:
		var e := QueuedEvent.new()
		e.id = str(d.get("id", ""))
		e.at = int(d.get("at", 0))
		e.kind = str(d.get("kind", ""))
		e.payload = d.get("payload", {})
		e.seq = int(d.get("seq", 0))
		return e


var _heap: Array[QueuedEvent] = []
var _next_seq: int = 0
var _cancelled: Dictionary = {}   # id -> true

signal event_due(event: QueuedEvent)


func size() -> int:
	return _heap.size()


func is_empty() -> bool:
	return _heap.is_empty()


## Schedules an event at an absolute world minute. Returns its id.
func schedule(at: int, kind: String, payload: Dictionary = {}, id: String = "") -> String:
	var e := QueuedEvent.new()
	e.at = at
	e.kind = kind
	e.payload = payload
	e.seq = _next_seq
	_next_seq += 1
	e.id = id if not id.is_empty() else "evt_%d" % e.seq
	_heap.append(e)
	_sift_up(_heap.size() - 1)
	return e.id


## Schedules relative to a "now". Convenience for callers holding the clock.
func schedule_in(now: int, delay: int, kind: String, payload: Dictionary = {}) -> String:
	return schedule(now + maxi(0, delay), kind, payload)


## Marks an event cancelled. It is skipped (and discarded) when it comes due.
func cancel(id: String) -> void:
	_cancelled[id] = true


func is_cancelled(id: String) -> bool:
	return _cancelled.has(id)


## Absolute minute of the next live event, or -1 when the queue is empty.
func peek_time() -> int:
	_discard_cancelled_at_root()
	if _heap.is_empty():
		return -1
	return _heap[0].at


## Pops and emits every event due at or before `now`, in time order.
## Returns the events that actually fired (cancelled ones are dropped).
func drain_due(now: int) -> Array[QueuedEvent]:
	var fired: Array[QueuedEvent] = []
	while true:
		_discard_cancelled_at_root()
		if _heap.is_empty() or _heap[0].at > now:
			break
		var e := _pop()
		fired.append(e)
		event_due.emit(e)
	return fired


## All pending events, time-ordered. For debug overlays and save.
func pending() -> Array[QueuedEvent]:
	var copy := _heap.duplicate()
	copy.sort_custom(func(a: QueuedEvent, b: QueuedEvent) -> bool:
		if a.at != b.at:
			return a.at < b.at
		return a.seq < b.seq)
	return copy


func clear() -> void:
	_heap.clear()
	_cancelled.clear()
	_next_seq = 0


func to_dict() -> Dictionary:
	var out: Array = []
	for e in pending():
		out.append(e.to_dict())
	return {
		"events": out,
		"next_seq": _next_seq,
		"cancelled": _cancelled.keys(),
	}


func from_dict(d: Dictionary) -> void:
	clear()
	_next_seq = int(d.get("next_seq", 0))
	for id in d.get("cancelled", []):
		_cancelled[str(id)] = true
	for raw in d.get("events", []):
		var e := QueuedEvent.from_dict(raw)
		_heap.append(e)
		_sift_up(_heap.size() - 1)


# --- heap internals ---------------------------------------------------------

func _less(a: QueuedEvent, b: QueuedEvent) -> bool:
	if a.at != b.at:
		return a.at < b.at
	return a.seq < b.seq


func _discard_cancelled_at_root() -> void:
	while not _heap.is_empty() and _cancelled.has(_heap[0].id):
		var dead := _pop()
		_cancelled.erase(dead.id)


func _pop() -> QueuedEvent:
	var top := _heap[0]
	var last: QueuedEvent = _heap.pop_back()
	if not _heap.is_empty():
		_heap[0] = last
		_sift_down(0)
	return top


func _sift_up(i: int) -> void:
	while i > 0:
		var parent := (i - 1) >> 1
		if _less(_heap[i], _heap[parent]):
			var tmp := _heap[i]
			_heap[i] = _heap[parent]
			_heap[parent] = tmp
			i = parent
		else:
			break


func _sift_down(i: int) -> void:
	var n := _heap.size()
	while true:
		var left := 2 * i + 1
		var right := left + 1
		var smallest := i
		if left < n and _less(_heap[left], _heap[smallest]):
			smallest = left
		if right < n and _less(_heap[right], _heap[smallest]):
			smallest = right
		if smallest == i:
			return
		var tmp := _heap[i]
		_heap[i] = _heap[smallest]
		_heap[smallest] = tmp
		i = smallest
