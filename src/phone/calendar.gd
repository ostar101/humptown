class_name Calendar
extends RefCounted
## The player's meetings (D-047): who, where, when, and how each one stands.
## Plain data, saved as the `calendar` section — `MeetingRules` says what may
## happen to a meeting and `MeetingDirector` carries it out.
##
## A meeting: {"id", "npc", "location", "start" (absolute minute), "duration",
## "status": "proposed" | "accepted" | "declined" | "kept" | "missed" |
## "stood_up" | "lapsed", "hostile": bool}. A hostile meeting is one someone has
## named for a fight (D-055); the player is told, not asked.

const KEEP_FINISHED := 12

var meetings: Array[Dictionary] = []
var _next_id := 1


## `purpose` says what a meeting is for when it is neither company nor a fight:
## "collection", a debt to be talked over (D-090); "" otherwise.
func propose(npc_id: String, location_id: String, start: int, duration: int, hostile: bool = false,
		purpose: String = "") -> Dictionary:
	var meeting := {"id": _next_id, "npc": npc_id, "location": location_id, "start": start,
		"duration": duration, "status": "proposed", "hostile": hostile, "purpose": purpose}
	_next_id += 1
	meetings.append(meeting)
	return meeting


func get_meeting(meeting_id: int) -> Dictionary:
	for meeting in meetings:
		if int(meeting["id"]) == meeting_id:
			return meeting
	return {}


func set_status(meeting_id: int, status: String) -> void:
	var meeting := get_meeting(meeting_id)
	if not meeting.is_empty():
		meeting["status"] = status
		_trim()


func end_of(meeting: Dictionary) -> int:
	return int(meeting["start"]) + int(meeting["duration"])


## Agreed and not yet over, soonest first.
func upcoming(now: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for meeting in meetings:
		if meeting["status"] == "accepted" and end_of(meeting) > now:
			out.append(meeting)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["start"]) < int(b["start"]))
	return out


## Meetings that have been and gone, most recent first.
func finished() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(meetings.size() - 1, -1, -1):
		if meetings[i]["status"] in ["kept", "missed", "stood_up"]:
			out.append(meetings[i])
	return out


## Whether this person already has something asked or agreed with the player
## that has not happened yet.
func has_open_with(npc_id: String, now: int) -> bool:
	for meeting in meetings:
		if meeting["npc"] == npc_id and meeting["status"] in ["proposed", "accepted"] \
				and end_of(meeting) > now:
			return true
	return false


## Agreed meetings that overlap `start` to `end`, each padded by `buffer` minutes.
func clashes(start: int, end: int, buffer: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for meeting in meetings:
		if meeting["status"] == "accepted" and start < end_of(meeting) + buffer \
				and end > int(meeting["start"]) - buffer:
			out.append(meeting)
	return out


func to_dict() -> Dictionary:
	return {"meetings": meetings.duplicate(true), "next_id": _next_id}


func from_dict(d: Dictionary) -> void:
	meetings = []
	for raw: Dictionary in d.get("meetings", []):
		meetings.append({"id": int(raw.get("id", 0)), "npc": str(raw.get("npc", "")),
			"location": str(raw.get("location", "")), "start": int(raw.get("start", 0)),
			"duration": int(raw.get("duration", 0)), "status": str(raw.get("status", "lapsed")),
			"hostile": bool(raw.get("hostile", false)), "purpose": str(raw.get("purpose", ""))})
	_next_id = int(d.get("next_id", 1))
	for meeting in meetings:
		_next_id = maxi(_next_id, int(meeting["id"]) + 1)


## The long tail of finished meetings is not worth keeping.
func _trim() -> void:
	var done := 0
	for i in range(meetings.size() - 1, -1, -1):
		if meetings[i]["status"] in ["kept", "missed", "stood_up", "declined", "lapsed"]:
			done += 1
			if done > KEEP_FINISHED:
				meetings.remove_at(i)
