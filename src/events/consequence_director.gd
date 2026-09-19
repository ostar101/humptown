class_name ConsequenceDirector
extends RefCounted
## What the world does about what the player has done (D-055): dynamic events,
## generated once a day from what people *know* and how they feel, never
## scheduled in advance and never random. Three kinds:
##
## - a **dismissal** — an employer who has come to believe something serious of
##   the player lets them go (a delayed consequence);
## - a **grudge** — someone the player beat, or their friends who know it,
##   text a warning and then name a time and place to meet: a new enemy;
## - a **collection** — a debt that was let fail is asked for, then someone
##   stronger is sent: an escalation.
##
## They use only what already exists: the knowledge network to say who knows,
## the relationship graph to say who is a friend, the phone to say it, the
## calendar for a meeting the player may keep or not, and a fight if they do.
## At most one new step a day, so a bad week is not a barrage.

## A creditor warns this many times before sending anyone.
const COLLECTION_WARNINGS := 3

## holder id -> {"kind", "warnings", "confrontations", "last_day", "quiet_until"}
var grudges: Dictionary = {}
## Jobs the player has been let go from for what they did.
var dismissed: Array[String] = []

var _npcs: NpcRegistry = null
var _knowledge: KnowledgeNetwork = null
var _relationships: RelationshipGraph = null
var _crime: CrimeDirector = null
var _quests: QuestLog = null
var _work: Employment = null
var _phone: PhoneDirector = null
var _meetings: MeetingDirector = null
var _data: DataRegistry = null
var _clock: GameClock = null


func setup(npcs: NpcRegistry, knowledge: KnowledgeNetwork, relationships: RelationshipGraph, crime: CrimeDirector,
		quests: QuestLog, work: Employment, phone: PhoneDirector, meetings: MeetingDirector, data: DataRegistry,
		clock: GameClock) -> void:
	_npcs = npcs
	_knowledge = knowledge
	_relationships = relationships
	_crime = crime
	_quests = quests
	_work = work
	_phone = phone
	_meetings = meetings
	_data = data
	_clock = clock


## The day's look at things. Called when a day turns.
func run_daily() -> void:
	_dismissal()
	for source in _sources():
		if _advance(source):
			break


## Someone came to meet the player as they said they would: that grudge has
## had its say, win or lose, and rests for a while.
func on_ambush(npc_id: String) -> void:
	for holder_id: String in grudges:
		var state: Dictionary = grudges[holder_id]
		if holder_id == npc_id or str(state.get("enforcer", "")) == npc_id:
			_rest(state)


# --- a dismissal --------------------------------------------------------------------------------

func _dismissal() -> void:
	if not _work.has_job():
		return
	var job_id := _work.job_id
	var employer := str(_data.get_entry("jobs", job_id).get("employer", ""))
	if employer == "" or dismissed.has(job_id):
		return
	if not ConsequenceRules.dismissal_due(_crime.known_offences(employer)):
		return
	_work.leave()
	dismissed.append(job_id)
	_relationships.adjust(employer, PlayerState.ID, "respect", -0.10, _clock.total_minutes)
	Events.job_changed.emit("")
	Events.job_lost.emit(job_id, "reputation")
	_phone.notice(employer, "dismissal", "phone.msg.dismissed", {})


# --- a grudge, or a debt gone bad ---------------------------------------------------------------------

## Everyone with a reason to come after the player, in a fixed order:
## [{"holder", "kind": "grudge" | "collection", "victim", "owed"}].
func _sources() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Array[String] = []
	var fact_ids: Array = _knowledge.facts.keys()
	fact_ids.sort()
	for fact_id: String in fact_ids:
		var fact := _knowledge.get_fact(fact_id)
		if fact.subject != PlayerState.ID or fact.predicate != "assaulted" or fact.object == "":
			continue
		var holders: Array[String] = [fact.object]
		for knower in _knowledge.knowers_of(fact_id):
			var feeling := _relationships.peek(knower, fact.object)
			if knower != fact.object and feeling != null and feeling.affection >= FightDirector.JOIN_AFFECTION:
				holders.append(knower)
		for holder in holders:
			if not seen.has(holder) and _may_hold(holder):
				seen.append(holder)
				out.append({"holder": holder, "kind": "grudge", "victim": fact.object, "owed": 0})
	var quest_ids: Array = _quests.finished.keys()
	quest_ids.sort()
	for quest_id: String in quest_ids:
		var collection: Dictionary = _quests.definition(quest_id).get("collection", {})
		if _quests.finished[quest_id] == "failed" and not collection.is_empty() and not seen.has(str(collection["holder"])):
			seen.append(str(collection["holder"]))
			out.append({"holder": str(collection["holder"]), "kind": "collection", "victim": "",
				"owed": int(collection.get("owed", 0))})
	return out


## Someone alive, not the law, and not the player's own friend by now.
func _may_hold(npc_id: String) -> bool:
	var npc := _npcs.get_npc(npc_id)
	return npc != null and npc.alive and not _crime.officers().has(npc_id)


## Takes the next step for one of them, if it is time. Returns whether it did.
func _advance(source: Dictionary) -> bool:
	var holder := str(source["holder"])
	var today := _clock.day_index()
	var state: Dictionary = grudges.get(holder, {"kind": str(source["kind"]), "warnings": 0, "confrontations": 0,
		"last_day": today, "quiet_until": 0, "enforcer": ""})
	grudges[holder] = state
	match ConsequenceRules.next_step(state, today, COLLECTION_WARNINGS if source["kind"] == "collection" else 1):
		"warn":
			state["warnings"] = int(state["warnings"]) + 1
			state["last_day"] = today
			_warn(holder, source, int(state["warnings"]))
			return true
		"confront":
			var enforcer := holder if source["kind"] == "grudge" else _enforcer_for(holder)
			if source["kind"] == "grudge" and not ConsequenceRules.fit_to_confront(_health_of(holder)):
				return false   # still mending
			var meeting_id := _meetings.arrange_confrontation(enforcer)
			if meeting_id == 0:
				return false
			var meeting := _meetings.calendar.get_meeting(meeting_id)
			state["confrontations"] = int(state["confrontations"]) + 1
			state["last_day"] = today
			state["enforcer"] = enforcer
			_phone.notice(enforcer, "confrontation", "phone.msg.confrontation.%s" % source["kind"],
				{"place": str(meeting["location"]), "start": int(meeting["start"]), "victim": str(source["victim"])})
			return true
		"rest":
			_rest(state)
	return false


func _warn(holder: String, source: Dictionary, count: int) -> void:
	if source["kind"] == "collection":
		_phone.notice(holder, "collection", "phone.msg.collection.%d" % mini(count, 3), {"owed": int(source["owed"])})
	elif holder == str(source["victim"]):
		_phone.notice(holder, "grudge_warning", "phone.msg.grudge_self", {})
	else:
		_phone.notice(holder, "grudge_warning", "phone.msg.grudge_friend", {"victim": str(source["victim"])})


func _rest(state: Dictionary) -> void:
	state["quiet_until"] = _clock.day_index() + ConsequenceRules.REST_DAYS
	state["warnings"] = 0
	state["confrontations"] = 0


## Who a creditor sends: someone in their crowd who looks the part.
func _enforcer_for(holder: String) -> String:
	var groups: Array = _npcs.get_npc(holder).groups if _npcs.get_npc(holder) != null else []
	var best := holder
	var ids: Array = _npcs.living_ids()
	ids.sort()
	for npc_id: String in ids:
		var npc := _npcs.get_npc(npc_id)
		if npc_id == holder or _crime.officers().has(npc_id):
			continue
		for group in npc.groups:
			if groups.has(group) and npc.has_trait("strong"):
				return npc_id
			if groups.has(group) and best == holder:
				best = npc_id
	return best


func _health_of(npc_id: String) -> float:
	var npc := _npcs.get_npc(npc_id)
	if npc == null:
		return 1.0
	return CombatRules.recovered(float(npc.state.get("health", 1.0)),
		_clock.total_minutes - int(npc.state.get("hurt_at", _clock.total_minutes)))


func to_dict() -> Dictionary:
	return {"grudges": grudges.duplicate(true), "dismissed": dismissed.duplicate()}


func from_dict(d: Dictionary) -> void:
	grudges = {}
	var raw: Dictionary = d.get("grudges", {})
	for holder in raw:
		var entry: Dictionary = raw[holder]
		grudges[str(holder)] = {"kind": str(entry.get("kind", "grudge")), "warnings": int(entry.get("warnings", 0)),
			"confrontations": int(entry.get("confrontations", 0)), "last_day": int(entry.get("last_day", 0)),
			"quiet_until": int(entry.get("quiet_until", 0)), "enforcer": str(entry.get("enforcer", ""))}
	dismissed = []
	for job_id in d.get("dismissed", []):
		dismissed.append(str(job_id))
