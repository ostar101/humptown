class_name ConsequenceDirector
extends RefCounted
## What the world does about what the player has done (D-055): dynamic events,
## generated once a day from what people *know* and how they feel, never
## scheduled in advance and never random. Three kinds:
##
## - a **dismissal** — an employer who has come to believe something serious of
##   the player lets them go (a delayed consequence);
## - a **grudge** — someone the player beat, or a friend of theirs who knows it,
##   warns once and then names a time and place to meet: a new enemy, until it
##   has been had out (D-090);
## - a **collection** — a debt that was let fail: the one owed calls the player
##   in to talk, threatens, warns a last time, and then sends someone to find
##   them, until it is paid (D-090).
##
## They use only what already exists: the knowledge network to say who knows,
## the relationship graph to say who is a friend, the phone to say it, the
## calendar for a meeting the player may keep or not, and a fight if they do.
## At most one new step a day, so a bad week is not a barrage.

## holder id -> where their grudge or collection stands. A grudge:
## {"kind": "grudge", "warnings", "confrontations", "last_day", "quiet_until",
## "enforcer", "facts": [assault fact ids it is about]}. A collection:
## {"kind": "collection", "quest", "step", "last_day", "quiet_until",
## "enforcer", "owed", "paid", "arriving"}.
var grudges: Dictionary = {}
## Jobs the player has been let go from for what they did.
var dismissed: Array[String] = []
## Assault facts that have been had out, or let go, or made up: they start
## nothing again (D-090). A new blow is a new fact, and may.
var settled_facts: Array[String] = []
## Debts (quest ids) paid off after they went to collection.
var settled_debts: Array[String] = []

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
var _player: PlayerState = null


func setup(npcs: NpcRegistry, knowledge: KnowledgeNetwork, relationships: RelationshipGraph, crime: CrimeDirector,
		quests: QuestLog, work: Employment, phone: PhoneDirector, meetings: MeetingDirector, data: DataRegistry,
		clock: GameClock, player: PlayerState = null) -> void:
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
	_player = player


## The day's look at things. Called when a day turns.
func run_daily() -> void:
	# A settled blow that everyone has since forgotten needs no remembering here.
	var still_known: Array[String] = []
	for fact_id in settled_facts:
		if _knowledge.facts.has(fact_id):
			still_known.append(fact_id)
	settled_facts = still_known
	_dismissal()
	for source in _sources():
		if _advance(source):
			break


## Someone came to fight the player as they said they would (a meeting kept,
## or a collector who found them): that is the fight; what it settles is read
## from how it ended, in `on_fought`.
func on_ambush(npc_id: String) -> void:
	for holder_id: String in grudges:
		var state: Dictionary = grudges[holder_id]
		if str(state.get("enforcer", "")) == npc_id or holder_id == npc_id:
			state["arriving"] = false


## A fight between the player and someone has ended (`result` is the
## player's: "won", "lost", "fled", "yielded"). A grudge that person held is
## had out, whoever won (D-090). A collector who got the better of the player
## takes what cash they have towards the debt; one who was seen off leaves it
## a while.
func on_fought(npc_id: String, result: String) -> void:
	for holder_id: String in grudges.keys():
		var state: Dictionary = grudges[holder_id]
		if state["kind"] == "grudge" and (holder_id == npc_id or str(state.get("enforcer", "")) == npc_id):
			_settle_grudge(holder_id)
		elif state["kind"] == "collection" and str(state.get("enforcer", "")) == npc_id \
				and int(state["step"]) >= ConsequenceRules.HUNT_STEP:
			_after_collector_fight(holder_id, state, result)


## Money handed or sent to whoever is owed, or to the one sent to collect it,
## goes against the debt (D-090); paid in full, it is over.
func on_paid(npc_id: String, amount: int) -> void:
	for holder_id: String in grudges.keys():
		var state: Dictionary = grudges[holder_id]
		if state["kind"] != "collection" or (holder_id != npc_id and str(state.get("enforcer", "")) != npc_id):
			continue
		state["paid"] = int(state["paid"]) + amount
		if owed_to(holder_id) <= 0:
			_square(holder_id, state)
		return


## What is still owed to this person on a debt gone to collection; 0 when none.
func owed_to(npc_id: String) -> int:
	var state: Dictionary = grudges.get(npc_id, {})
	if state.get("kind", "") != "collection":
		return 0
	return maxi(int(state["owed"]) - int(state["paid"]), 0)


## Who a collector has sent to find the player, if it is time and the player
## can be found (`ConsequenceRules.can_be_found`), or "". Marks them on their
## way, so they are sent once, until `on_ambush()` or `not_found()` says how
## it went.
func hunter_for(situation: Dictionary) -> String:
	if not ConsequenceRules.can_be_found(situation):
		return ""
	var today := _clock.day_index()
	var holders: Array = grudges.keys()
	holders.sort()
	for holder_id: String in holders:
		var state: Dictionary = grudges[holder_id]
		if state["kind"] != "collection" or int(state["step"]) < ConsequenceRules.HUNT_STEP \
				or today < int(state["quiet_until"]) or bool(state.get("arriving", false)):
			continue
		var enforcer := _npcs.get_npc(str(state["enforcer"]))
		if enforcer == null or not enforcer.alive or not _may_hold(enforcer.id):
			continue
		state["arriving"] = true
		return enforcer.id
	return ""


## The one who was coming did not find the player after all; they will look
## again later.
func not_found(npc_id: String) -> void:
	on_ambush(npc_id)


## What a person is to the player because of this, in English for a prompt, or
## "" (D-090): a debt they are collecting.
func situation_with(npc_id: String) -> String:
	var owed := owed_to(npc_id)
	if owed > 0:
		var state: Dictionary = grudges[npc_id]
		var threatened := int(state["step"]) >= 2
		return "The person in front of you owes you €%d and is well past the day they should have paid. You want it. %s" % [
			owed, "You have already made clear what happens to people who do not pay: they get hurt." if threatened
			else "Make it plain that not paying will hurt them."]
	return ""


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
## [{"holder", "kind": "grudge" | "collection", "victim", "facts", "quest", "owed"}].
## One holder per blow (D-090): the one who took it, or — only if they cannot
## or will not — one friend of theirs who knows. It used to be the victim and
## every friend, each with their own warnings.
func _sources() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var by_holder := {}
	var fact_ids: Array = _knowledge.facts.keys()
	fact_ids.sort()
	for fact_id: String in fact_ids:
		var fact := _knowledge.get_fact(fact_id)
		if fact.subject != PlayerState.ID or fact.predicate != "assaulted" or fact.object == "" \
				or settled_facts.has(fact_id):
			continue
		var holder := _holder_for(fact_id, fact.object)
		if holder == "":
			continue
		if not by_holder.has(holder):
			by_holder[holder] = {"holder": holder, "kind": "grudge", "victim": fact.object, "facts": [] as Array[String],
				"quest": "", "owed": 0}
			out.append(by_holder[holder])
		(by_holder[holder]["facts"] as Array[String]).append(fact_id)
	var quest_ids: Array = _quests.finished.keys()
	quest_ids.sort()
	for quest_id: String in quest_ids:
		var collection: Dictionary = _quests.definition(quest_id).get("collection", {})
		var holder := str(collection.get("holder", ""))
		if _quests.finished[quest_id] != "failed" or collection.is_empty() or settled_debts.has(quest_id) \
				or by_holder.has(holder):
			continue
		var lapsed: Dictionary = _quests.lapsed.get(quest_id, {})
		var owed := int(collection.get("owed", 0)) + int(lapsed.get("extra_need", 0)) - int(lapsed.get("paid", 0))
		if owed > 0:
			by_holder[holder] = true
			out.append({"holder": holder, "kind": "collection", "victim": "", "facts": [] as Array[String],
				"quest": quest_id, "owed": owed})
	return out


## Who holds this blow against the player: the one it was done to, unless they
## are the law, gone, or have since made it up — and if they made it up, nobody
## does. Otherwise the first friend of theirs who knows and would.
func _holder_for(fact_id: String, victim: String) -> String:
	var npc := _npcs.get_npc(victim)
	if npc != null and npc.alive and not _crime.officers().has(victim):
		return victim if _may_hold(victim) else ""
	var friends: Array[String] = []
	for knower in _knowledge.knowers_of(fact_id):
		var feeling := _relationships.peek(knower, victim)
		if knower != victim and feeling != null and feeling.affection >= FightDirector.JOIN_AFFECTION and _may_hold(knower):
			friends.append(knower)
	friends.sort()
	return friends[0] if not friends.is_empty() else ""


## Someone alive, not the law, and not the player's own friend by now.
func _may_hold(npc_id: String) -> bool:
	var npc := _npcs.get_npc(npc_id)
	if npc == null or not npc.alive or _crime.officers().has(npc_id):
		return false
	var feeling := _relationships.peek(npc_id, PlayerState.ID)
	return feeling == null or not ConsequenceRules.made_up(feeling.affection)


## Takes the next step for one of them, if it is time. Returns whether it did.
func _advance(source: Dictionary) -> bool:
	if source["kind"] == "collection":
		return _advance_collection(source)
	var holder := str(source["holder"])
	var today := _clock.day_index()
	var state: Dictionary = grudges.get(holder, {"kind": "grudge", "warnings": 0, "confrontations": 0,
		"last_day": today, "quiet_until": 0, "enforcer": "", "facts": [] as Array[String]})
	grudges[holder] = state
	var facts: Array[String] = state["facts"]
	for fact_id: String in source["facts"]:
		if not facts.has(fact_id):
			facts.append(fact_id)
	match ConsequenceRules.next_step(state, today, 1):
		"warn":
			state["warnings"] = int(state["warnings"]) + 1
			state["last_day"] = today
			_warn(holder, source)
			return true
		"confront":
			if not ConsequenceRules.fit_to_confront(_health_of(holder)):
				return false   # still mending
			var meeting_id := _meetings.arrange_confrontation(holder)
			if meeting_id == 0:
				return false
			var meeting := _meetings.calendar.get_meeting(meeting_id)
			state["confrontations"] = int(state["confrontations"]) + 1
			state["last_day"] = today
			state["enforcer"] = holder
			_phone.notice(holder, "confrontation", "phone.msg.confrontation.grudge",
				{"place": str(meeting["location"]), "start": int(meeting["start"]), "victim": str(source["victim"])})
			return true
		"rest":
			_settle_grudge(holder)   # asked twice and never answered: they let it go
	return false


func _warn(holder: String, source: Dictionary) -> void:
	if holder == str(source["victim"]):
		_phone.notice(holder, "grudge_warning", "phone.msg.grudge_self", {})
	else:
		_phone.notice(holder, "grudge_warning", "phone.msg.grudge_friend", {"victim": str(source["victim"])})


## Over for good: what it was about starts nothing again.
func _settle_grudge(holder: String) -> void:
	var state: Dictionary = grudges.get(holder, {})
	for fact_id: String in state.get("facts", []):
		if not settled_facts.has(fact_id):
			settled_facts.append(fact_id)
	grudges.erase(holder)


# --- a collection (D-090) -------------------------------------------------------------------------------

func _advance_collection(source: Dictionary) -> bool:
	var holder := str(source["holder"])
	var today := _clock.day_index()
	if not grudges.has(holder):
		grudges[holder] = {"kind": "collection", "quest": str(source["quest"]), "step": 0, "last_day": today,
			"quiet_until": 0, "enforcer": _enforcer_for(holder), "owed": int(source["owed"]), "paid": 0, "arriving": false}
	var state: Dictionary = grudges[holder]
	var owed := owed_to(holder)
	match ConsequenceRules.collection_step(state, today):
		"summon":
			var meeting_id := _meetings.arrange_talk(holder)
			var args := {"owed": owed}
			if meeting_id != 0:
				var meeting := _meetings.calendar.get_meeting(meeting_id)
				args["place"] = str(meeting["location"])
				args["start"] = int(meeting["start"])
			_phone.notice(holder, "collection", "phone.msg.collection.summon" if meeting_id != 0 else "phone.msg.collection.1", args)
		"threaten":
			_phone.notice(holder, "collection", "phone.msg.collection.threat", {"owed": owed})
		"final":
			_phone.notice(holder, "collection", "phone.msg.collection.final", {"owed": owed, "enforcer": str(state["enforcer"])})
		"hunt":
			pass   # nothing more is said: someone is looking for the player now
		_:
			return false
	state["step"] = int(state["step"]) + 1
	state["last_day"] = today
	return true


func _after_collector_fight(holder: String, state: Dictionary, result: String) -> void:
	var today := _clock.day_index()
	state["arriving"] = false
	if result == "lost" or result == "yielded":
		var taken := mini(_player.wallet.cash if _player != null else 0, owed_to(holder))
		if taken > 0:
			_player.wallet.spend(taken, "collected:" + holder, true)
			state["paid"] = int(state["paid"]) + taken
		if owed_to(holder) <= 0:
			_square(holder, state)
			return
		state["quiet_until"] = today + ConsequenceRules.AFTER_TAKING_DAYS
		_phone.notice(holder, "collection_outcome", "phone.msg.collection.taken",
			{"enforcer": str(state["enforcer"]), "taken": taken, "owed": owed_to(holder)})
	elif result == "won":
		state["quiet_until"] = today + ConsequenceRules.AFTER_BEATEN_DAYS
		_phone.notice(holder, "collection_outcome", "phone.msg.collection.beaten", {"owed": owed_to(holder)})
	# Fled: nothing is settled and nobody waits long; they will find you again.


## Paid in full: it is over, and a little better between them for it.
func _square(holder: String, state: Dictionary) -> void:
	settled_debts.append(str(state["quest"]))
	grudges.erase(holder)
	var now := _clock.total_minutes
	_relationships.adjust(holder, PlayerState.ID, "trust", 0.1, now)
	_relationships.adjust(holder, PlayerState.ID, "respect", 0.05, now)
	_phone.notice(holder, "collection_outcome", "phone.msg.collection.square", {})


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


## The quest whose debt this person collects, or "".
func _debt_held_by(holder: String) -> String:
	if _data == null:
		return ""
	for quest_id: String in _data.ids("quests"):
		if str((_data.get_entry("quests", quest_id).get("collection", {}) as Dictionary).get("holder", "")) == holder:
			return quest_id
	return ""


func to_dict() -> Dictionary:
	return {"grudges": grudges.duplicate(true), "dismissed": dismissed.duplicate(),
		"settled_facts": settled_facts.duplicate(), "settled_debts": settled_debts.duplicate()}


func from_dict(d: Dictionary) -> void:
	grudges = {}
	var raw: Dictionary = d.get("grudges", {})
	for holder in raw:
		var entry: Dictionary = raw[holder]
		var kind := str(entry.get("kind", "grudge"))
		if kind == "collection":
			# A save from before D-090 counted warnings, not steps: three
			# warnings and a meeting are as far on as a hunt.
			# A save from before D-090 counted warnings, not steps, and never
			# wrote down the sum: three warnings and a meeting are as far on as
			# a hunt, and the sum is the quest's own.
			var step := int(entry.get("step", mini(int(entry.get("warnings", 0)) + int(entry.get("confrontations", 0)),
				ConsequenceRules.HUNT_STEP)))
			var quest_id := str(entry.get("quest", _debt_held_by(str(holder))))
			var owed := int(entry.get("owed",
				int((_quests.definition(quest_id).get("collection", {}) as Dictionary).get("owed", 0)) if _quests != null else 0))
			grudges[str(holder)] = {"kind": kind, "quest": quest_id, "step": step,
				"last_day": int(entry.get("last_day", 0)), "quiet_until": int(entry.get("quiet_until", 0)),
				"enforcer": str(entry.get("enforcer", "")), "owed": owed,
				"paid": int(entry.get("paid", 0)), "arriving": false}
			continue
		var facts: Array[String] = []
		for fact_id in entry.get("facts", []):
			facts.append(str(fact_id))
		grudges[str(holder)] = {"kind": kind, "warnings": int(entry.get("warnings", 0)),
			"confrontations": int(entry.get("confrontations", 0)), "last_day": int(entry.get("last_day", 0)),
			"quiet_until": int(entry.get("quiet_until", 0)), "enforcer": str(entry.get("enforcer", "")), "facts": facts}
	dismissed = []
	for job_id in d.get("dismissed", []):
		dismissed.append(str(job_id))
	settled_facts = []
	for fact_id in d.get("settled_facts", []):
		settled_facts.append(str(fact_id))
	settled_debts = []
	for quest_id in d.get("settled_debts", []):
		settled_debts.append(str(quest_id))
