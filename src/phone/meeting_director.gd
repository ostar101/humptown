class_name MeetingDirector
extends RefCounted
## Carries out meetings (D-047). Someone fond of the player may suggest one —
## `suggest()` picks a day, an hour and a public place that is open throughout —
## and the phone offers it. Accepting it schedules the rest as world events:
## a reminder for the player, the person heading over, and the moment it is
## settled. Whether it was kept is read off the simulation — who stands where —
## never off anyone's word. No model is involved.

## The hour a fight is called for.
const CONFRONTATION_HOUR := 21
## The hour someone owed money calls the player in to talk (D-090).
const TALK_HOUR := 18

var calendar: Calendar = Calendar.new()

var _npcs: NpcRegistry = null
var _world: WorldState = null
var _player: PlayerState = null
var _relationships: RelationshipGraph = null
var _memories: MemoryBook = null
var _events: WorldEventQueue = null
var _clock: GameClock = null
var _data: DataRegistry = null


func setup(p_calendar: Calendar, npcs: NpcRegistry, world: WorldState, player: PlayerState,
		relationships: RelationshipGraph, memories: MemoryBook, events: WorldEventQueue,
		clock: GameClock, data: DataRegistry) -> void:
	calendar = p_calendar
	_npcs = npcs
	_world = world
	_player = player
	_relationships = relationships
	_memories = memories
	_events = events
	_clock = clock
	_data = data


## A meeting this person could suggest for tomorrow: {"location", "start"}, or
## {} when they have one going already, or nowhere suitable is open.
func suggest(npc_id: String) -> Dictionary:
	var npc := _npcs.get_npc(npc_id)
	if npc == null or not npc.alive or calendar.has_open_with(npc_id, _clock.total_minutes):
		return {}
	var day := _clock.day_index() + 1
	var hour := MeetingRules.start_hour(npc_id, day)
	var start := day * GameClock.MINUTES_PER_DAY + hour * 60
	var home := _world.get_location(npc.home)
	var places: Array[String] = []
	for location_id: String in _data.ids("locations"):
		if not bool(_data.get_entry("locations", location_id).get("meeting_place", false)):
			continue
		var place := _world.get_location(location_id)
		if place != null and home != null and place.region == home.region and place.is_public() \
				and not place.is_locked() and MeetingRules.open_throughout(place.is_open_at, hour * 60):
			places.append(location_id)
	if places.is_empty():
		return {}
	places.sort()
	var chosen := places[posmod(("meetplace/%s/%d" % [npc_id, day]).hash(), places.size())]
	if not calendar.clashes(start - MeetingRules.GATHER_LEAD, start + MeetingRules.DURATION, MeetingRules.BUFFER).is_empty():
		return {}
	return {"location": chosen, "start": start}


## Puts a suggestion on the calendar, waiting to be answered. Returns its id.
func propose(npc_id: String, spec: Dictionary) -> int:
	return int(calendar.propose(npc_id, str(spec["location"]), int(spec["start"]), MeetingRules.DURATION)["id"])


## Whether the player could accept now, and if not why (`already_answered`,
## `too_late`, `clash`).
func judge_accept(meeting_id: int) -> Result:
	var meeting := calendar.get_meeting(meeting_id)
	var clash := false
	if not meeting.is_empty():
		for other in calendar.clashes(int(meeting["start"]) - MeetingRules.GATHER_LEAD, calendar.end_of(meeting), MeetingRules.BUFFER):
			clash = clash or int(other["id"]) != meeting_id
	return MeetingRules.judge_accept(meeting, {"now": _clock.total_minutes, "clash": clash})


func accept(meeting_id: int) -> Result:
	var judged := judge_accept(meeting_id)
	if judged.is_err():
		return judged
	_schedule(meeting_id)
	Events.meeting_updated.emit(meeting_id, "accepted")
	return Result.success()


## Puts an agreed meeting in the calendar and sets its day going: a reminder,
## the person heading over, the moment it is settled, and the end.
func _schedule(meeting_id: int) -> void:
	var meeting := calendar.get_meeting(meeting_id)
	var start := int(meeting["start"])
	calendar.set_status(meeting_id, "accepted")
	var payload := {"meeting": meeting_id}
	var now := _clock.total_minutes
	_events.schedule(maxi(start - MeetingRules.REMINDER_LEAD, now + 1), "meeting_reminder", payload)
	_events.schedule(maxi(start - MeetingRules.GATHER_LEAD, now + 1), "meeting_gather", payload)
	_events.schedule(start + MeetingRules.GRACE, "meeting_check", payload)
	_events.schedule(calendar.end_of(meeting), "meeting_end", payload)


## Someone names a time and place for a fight (D-055): tomorrow evening, at a
## park. The player is told and not asked — it goes on the calendar, they may go
## or not. Returns the meeting's id, or 0 when there is nowhere to name.
func arrange_confrontation(npc_id: String) -> int:
	var npc := _npcs.get_npc(npc_id)
	if npc == null or not npc.alive:
		return 0
	var day := _clock.day_index() + 1
	var places: Array[String] = []
	for location_id: String in _data.ids("locations"):
		var place := _world.get_location(location_id)
		if place != null and place.kind == "park" and bool(_data.get_entry("locations", location_id).get("meeting_place", false)):
			places.append(location_id)
	if places.is_empty():
		return 0
	places.sort()
	var chosen := places[posmod(("fight/%s/%d" % [npc_id, day]).hash(), places.size())]
	var meeting := calendar.propose(npc_id, chosen, day * GameClock.MINUTES_PER_DAY + CONFRONTATION_HOUR * 60,
		MeetingRules.DURATION, true)
	_schedule(int(meeting["id"]))
	return int(meeting["id"])


## Someone owed money calls the player in to talk about it (D-090): tomorrow
## at six in the evening, at a public place in their own district. Told, not
## asked, like a confrontation — but it is talk, not a fight. Returns the
## meeting's id, or 0 when there is nowhere to name.
func arrange_talk(npc_id: String) -> int:
	var npc := _npcs.get_npc(npc_id)
	var home := _world.get_location(npc.home) if npc != null else null
	if npc == null or not npc.alive or home == null:
		return 0
	var day := _clock.day_index() + 1
	var places: Array[String] = []
	for location_id: String in _data.ids("locations"):
		var place := _world.get_location(location_id)
		if place != null and place.region == home.region and place.is_public() and not place.is_locked() \
				and bool(_data.get_entry("locations", location_id).get("meeting_place", false)) \
				and MeetingRules.open_throughout(place.is_open_at, TALK_HOUR * 60):
			places.append(location_id)
	if places.is_empty():
		return 0
	places.sort()
	var chosen := places[posmod(("talk/%s/%d" % [npc_id, day]).hash(), places.size())]
	var meeting := calendar.propose(npc_id, chosen, day * GameClock.MINUTES_PER_DAY + TALK_HOUR * 60,
		MeetingRules.DURATION, false, "collection")
	_schedule(int(meeting["id"]))
	return int(meeting["id"])


func decline(meeting_id: int) -> void:
	if calendar.get_meeting(meeting_id).get("status", "") == "proposed":
		calendar.set_status(meeting_id, "declined")


## Suggestions nobody answered before their time are no longer on offer.
func lapse() -> void:
	for meeting in calendar.meetings:
		if meeting["status"] == "proposed" and int(meeting["start"]) - MeetingRules.MIN_NOTICE < _clock.total_minutes:
			meeting["status"] = "lapsed"


## A meeting's moment has come. Kinds: `meeting_reminder`, `meeting_gather`,
## `meeting_check`, `meeting_end`.
func on_event(kind: String, payload: Dictionary) -> void:
	var meeting_id := int(payload.get("meeting", 0))
	var meeting := calendar.get_meeting(meeting_id)
	if meeting.is_empty():
		return
	if kind == "meeting_end":
		_release(meeting)   # whatever became of it, they go back to their day
		return
	if meeting["status"] != "accepted":
		return
	match kind:
		"meeting_reminder":
			Events.meeting_updated.emit(meeting_id, "reminder")
		"meeting_gather":
			var npc := _npcs.get_npc(str(meeting["npc"]))
			if npc != null and npc.alive and npc.schedule_override == null:
				npc.set_override(int(meeting["start"]) - MeetingRules.GATHER_LEAD, calendar.end_of(meeting),
					str(meeting["location"]), "socialise", "meeting:%d" % meeting_id)
				_npcs.invalidate_location_cache(npc.id)
		"meeting_check":
			_settle(meeting)


func _settle(meeting: Dictionary) -> void:
	var npc_id := str(meeting["npc"])
	var npc := _npcs.get_npc(npc_id)
	var location := str(meeting["location"])
	var now := _clock.total_minutes
	var verdict := MeetingRules.judge_attendance({
		"player_here": _player.location == location,
		"npc_here": npc != null and npc.alive and _npcs.scheduled_location_of(npc_id, now, _clock.weekday()) == location,
		"late": now - (int(meeting["start"]) + MeetingRules.GRACE) > MeetingRules.GRACE,
	})
	var id := int(meeting["id"])
	if bool(meeting.get("hostile", false)):
		# They came for a fight. If the player is there and so are they, they
		# get one; if not, it is not the player's manners that are in question.
		calendar.set_status(id, verdict)
		if verdict == "kept":
			Events.ambush.emit(npc_id)
		Events.meeting_updated.emit(id, verdict)
		return
	if str(meeting.get("purpose", "")) == "collection":
		# Talk about money that is owed (D-090): turning up is no kindness to
		# anyone, and not turning up is noted.
		if verdict == "kept":
			_memories.add_episode(npc_id, now, location, ["came when you told them to, to talk about the money"] as Array[String], 0.4)
		elif verdict == "missed":
			_relationships.adjust(npc_id, PlayerState.ID, "respect", -0.05, now)
			_memories.add_episode(npc_id, now, location, ["did not come when you told them to, about the money"] as Array[String], 0.6)
		calendar.set_status(id, verdict)
		Events.meeting_updated.emit(id, verdict)
		return
	match verdict:
		"kept":
			_relationships.adjust(npc_id, PlayerState.ID, "affection", 0.05, now)
			_relationships.adjust(npc_id, PlayerState.ID, "trust", 0.03, now)
			_relationships.adjust(npc_id, PlayerState.ID, "familiarity", 0.03, now)
			_relationships.adjust(PlayerState.ID, npc_id, "familiarity", 0.03, now)
			_memories.add_episode(npc_id, now, location, ["met you when you agreed to"] as Array[String], 0.4)
		"missed":
			_relationships.adjust(npc_id, PlayerState.ID, "trust", -0.06, now)
			_relationships.adjust(npc_id, PlayerState.ID, "affection", -0.03, now)
			_memories.add_episode(npc_id, now, location, ["did not turn up when you agreed to meet"] as Array[String], 0.5)
	calendar.set_status(id, verdict)
	if verdict == "kept":
		Events.player_deed.emit("met", {"npc": npc_id, "location": location})
	Events.meeting_updated.emit(id, verdict)


## Lets them go back to their day.
func _release(meeting: Dictionary) -> void:
	var npc := _npcs.get_npc(str(meeting["npc"]))
	if npc != null and npc.schedule_override != null and npc.schedule_override.reason == "meeting:%d" % int(meeting["id"]):
		npc.clear_override()
		_npcs.invalidate_location_cache(npc.id)
