class_name PhoneDirector
extends RefCounted
## Carries out the phone (D-045). Godot decides who has a reason to write and
## `PhoneRules` decides whether they may; no model is asked, and every line is
## authored. It looks only at the player's contacts — never a loop over the
## whole population — and only once an hour (and once after time was skipped).
##
## The causes, in the order they are looked at:
## - a deadline coming up on a quest, from whoever gave it (`quest_nudge`)
## - a shift missed, from the employer (`missed_shift`, told by `Game`)
## - an errand someone needs done and you could do (`errand_offer`)
## - a friend thinking of you (`check_in`), or wanting to meet (`meeting_request`,
##   D-047)
## - a meeting you did not come to (`meeting_missed`, told by `MeetingDirector`)
##
## Without a phone in the bag nothing arrives and nothing is queued: the
## messages you would have had are simply not there.
##
## The player may write back, or write first, to anyone whose number they have
## (D-046). A text waits in the outbox until the person gets to it — soon, or
## after a shift, or in the morning — and is then read exactly as a spoken line
## is (`DialogueDirector.text_exchange`): the same intent, the same rules, the
## same effects; the answer comes back as a text.

const ITEM := "item_phone"
const MINUTES_PER_DAY := 1440

var state: PhoneState = PhoneState.new()

var _npcs: NpcRegistry = null
var _relationships: RelationshipGraph = null
var _quests: QuestLog = null
var _player: PlayerState = null
var _clock: GameClock = null
var _dialogue: DialogueDirector = null
var _meetings: MeetingDirector = null
## Message ids being read right now (a model may take a while).
var _busy: Array[int] = []


func setup(p_state: PhoneState, npcs: NpcRegistry, relationships: RelationshipGraph, quests: QuestLog,
		player: PlayerState, clock: GameClock, dialogue: DialogueDirector = null,
		meetings: MeetingDirector = null) -> void:
	_dialogue = dialogue
	_meetings = meetings
	state = p_state
	_npcs = npcs
	_relationships = relationships
	_quests = quests
	_player = player
	_clock = clock


func has_phone() -> bool:
	return _player != null and _player.inventory.count_of(ITEM) > 0


## Adds the number of everyone who knows the player well enough (introduced,
## or talked twice). Returns the people newly added.
func sync_contacts() -> Array[String]:
	var added: Array[String] = []
	for npc_id in _relationships.who_knows(PlayerState.ID):
		var edge := _relationships.peek(npc_id, PlayerState.ID)
		if edge != null and edge.familiarity >= PhoneRules.CONTACT_FAMILIARITY and add_contact(npc_id):
			added.append(npc_id)
	return added


## Their number, given or taken. False when it was already there or the person
## is not someone who exists.
func add_contact(npc_id: String) -> bool:
	var npc := _npcs.get_npc(npc_id)
	if npc == null or not npc.alive or not state.add_contact(npc_id, _clock.day_index()):
		return false
	Events.phone_contact_added.emit(npc_id)
	return true


## One look at who has a reason to write. Returns how many messages arrived.
func run_outreach() -> int:
	if not has_phone():
		return 0
	var arrived := _deliver_pending()
	for cause in _causes():
		if deliver(cause).is_ok():
			arrived += 1
	return arrived


## A message the simulation has a reason for: {"npc", "kind", "key", "args",
## "action"?}. Judged by the rules; delivered if allowed.
func deliver(cause: Dictionary) -> Result:
	var npc_id := str(cause.get("npc", ""))
	var npc := _npcs.get_npc(npc_id)
	var now := _clock.total_minutes
	var judged := PhoneRules.judge_outreach(cause, {
		"has_phone": has_phone(),
		"is_contact": state.is_contact(npc_id),
		"npc_awake": npc != null and npc.alive and npc.activity != "sleep",
		"hour": _clock.hour(),
		"minutes_since": state.minutes_since_started(npc_id, now),
		"started_today": state.started_since(_clock.day_index() * MINUTES_PER_DAY),
	})
	if judged.is_err():
		Log.debug("phone", "Message held back", {"npc": npc_id, "kind": cause.get("kind"), "why": judged.code})
		return judged
	var action: Dictionary = cause.get("action", {})
	if cause.has("meeting") and _meetings != null:
		action = {"do": "meeting", "meeting": _meetings.propose(npc_id, cause["meeting"])}
		_player.learn_place(str(cause["meeting"]["location"]), "told")   # they said where
	var message := state.add_message(npc_id, true, str(cause["kind"]), str(cause["key"]),
		cause.get("args", {}), now, action)
	Events.phone_message.emit(npc_id, int(message["id"]))
	return Result.success(message)


## The employer noticing a missed shift. Told by `Game` when it counts one —
## at midnight, which is no time to write, so it waits for morning.
func missed_shift(employer_id: String, workplace_id: String) -> void:
	if not has_phone():
		return
	state.pending.append({"queued": _clock.total_minutes, "cause": {
		"npc": employer_id, "kind": "missed_shift", "key": "phone.msg.missed_shift", "args": {"place": workplace_id}}})


## The police tell the player to come in (D-052). They have your number: it is
## added if it was not there. Waits for a civil hour like any message, and is
## never seen at all without a phone.
func summons(officer_id: String, due_minute: int) -> void:
	if not has_phone():
		return
	add_contact(officer_id)
	_player.learn_place("loc_police_post", "told")
	state.pending.append({"queued": _clock.total_minutes, "cause": {
		"npc": officer_id, "kind": "summons", "key": "phone.msg.summons",
		"args": {"place": "loc_police_post", "start": due_minute}}})


## Someone who has something to say to the player and does not need to be asked
## (D-055): a grudge, a debt, a dismissal. As with the police they have your
## number; it waits for a civil hour like any message.
func notice(npc_id: String, kind: String, key: String, args: Dictionary) -> void:
	if not has_phone():
		return
	add_contact(npc_id)
	if args.has("place"):
		_player.learn_place(str(args["place"]), "told")
	state.pending.append({"queued": _clock.total_minutes, "cause": {"npc": npc_id, "kind": kind, "key": key, "args": args}})


## Someone waited at a meeting the player never came to; they say so, at a
## civil hour (D-047).
func meeting_missed(npc_id: String, place_id: String) -> void:
	if not has_phone():
		return
	state.pending.append({"queued": _clock.total_minutes, "cause": {
		"npc": npc_id, "kind": "meeting_missed", "key": "phone.msg.meeting_missed", "args": {"place": place_id}}})


## Whether they would pick up if the player rang now (D-050).
func can_call(npc_id: String) -> Result:
	var npc := _npcs.get_npc(npc_id)
	return PhoneRules.judge_call({
		"has_phone": has_phone(), "is_contact": state.is_contact(npc_id) and npc != null and npc.alive,
		"npc_awake": npc != null and npc.alive and npc.activity != "sleep",
		"npc_busy": npc != null and npc.activity == "work", "hour": _clock.hour(),
	})


## The player sends a text. Judged by `PhoneRules.judge_send`; it goes into the
## outbox to be read when the person gets to it. Returns the message.
func send_text(npc_id: String, line: String) -> Result:
	var npc := _npcs.get_npc(npc_id)
	var judged := PhoneRules.judge_send(line, {
		"has_phone": has_phone(), "is_contact": state.is_contact(npc_id) and npc != null and npc.alive,
		"waiting": state.waiting_for(npc_id),
	})
	if judged.is_err():
		return judged
	var now := _clock.total_minutes
	var message := state.add_message(npc_id, false, "text", "", {}, now, {}, str(judged.value))
	state.outbox.append({"npc": npc_id, "message": int(message["id"]), "line": str(judged.value),
		"due": now + PhoneRules.reading_delay(npc.activity)})
	return Result.success(message)


## Reads the texts whose time has come. A coroutine — a model may answer — so
## the caller does not wait for it; it is safe to start again while one is
## still being read.
func process_due() -> void:
	for entry in state.outbox.duplicate():
		var message_id := int(entry["message"])
		if int(entry["due"]) > _clock.total_minutes or _busy.has(message_id):
			continue
		var npc_id := str(entry["npc"])
		var npc := _npcs.get_npc(npc_id)
		if npc == null or not npc.alive:
			state.outbox.erase(entry)
			continue
		if PhoneRules.judge_reading({"npc_awake": npc.activity != "sleep", "hour": _clock.hour()}).is_err():
			entry["due"] = _clock.total_minutes + PhoneRules.READ_RETRY
			continue
		_busy.append(message_id)
		var replied: Result = await _dialogue.text_exchange(npc_id, str(entry["line"]))
		_busy.erase(message_id)
		state.outbox.erase(entry)
		if replied.is_err():
			continue
		var reply: Dictionary = replied.value
		var rejection: Dictionary = reply.get("rejection", {})
		if not rejection.is_empty():
			Events.action_rejected.emit(rejection["proposal"], str(rejection["code"]))
		if has_phone():
			var answer := state.add_message(npc_id, true, "reply", "", {}, _clock.total_minutes, {}, str(reply["text"]))
			Events.phone_message.emit(npc_id, int(answer["id"]))


## The player answers a message's question: "accept" or "decline". Judged, then
## applied through the same state the conversation route uses.
func answer(message_id: int, choice: String) -> Result:
	var message := state.get_message(message_id)
	var action: Dictionary = message.get("action", {})
	var possible := false
	var why := "no_longer_possible"
	var meeting_id := int(action.get("meeting", 0))
	match str(action.get("do", "")):
		"take_errand":
			possible = _quests.errand_offered_by(str(message.get("npc", "")), _clock.day_index()) == str(action.get("errand", "-"))
		"meeting":
			var can := _meetings.judge_accept(meeting_id) if _meetings != null else Result.failure("no_longer_possible")
			possible = can.is_ok()
			why = can.code if can.is_err() else why
	var judged := PhoneRules.judge_answer(message, choice, {
		"has_phone": has_phone(), "open": state.is_open(message), "still_possible": possible, "why": why,
	})
	if judged.is_err():
		return judged
	var npc_id := str(message["npc"])
	var now := _clock.total_minutes
	if choice == "accept":
		state.answer(message_id, "accepted")
		if str(action["do"]) == "meeting":
			_meetings.accept(meeting_id)
			state.add_message(npc_id, false, "reply", "phone.reply.meet_accept", {}, now)
		else:
			_quests.take_errand(str(action["errand"]), _clock.day_index())
			state.add_message(npc_id, false, "reply", "phone.reply.accept", {}, now)
			Events.quest_updated.emit(str(action["errand"]), "errand_taken")
	else:
		state.answer(message_id, "declined")
		if str(action["do"]) == "meeting":
			_meetings.decline(meeting_id)
		state.add_message(npc_id, false, "reply", "phone.reply.decline", {}, now)
	return Result.success(choice)


## Tries what is waiting. Something held back only for the hour, sleep, a full
## day or someone having just written keeps waiting, up to a day; anything else
## is dropped.
func _deliver_pending() -> int:
	var arrived := 0
	var waiting: Array[Dictionary] = []
	for entry in state.pending:
		var judged := deliver(entry["cause"])
		if judged.is_ok():
			arrived += 1
		elif judged.code in ["quiet_hours", "asleep", "daily_cap", "too_soon"] and _clock.total_minutes - int(entry["queued"]) < MINUTES_PER_DAY:
			waiting.append(entry)
	state.pending = waiting
	return arrived


# --- causes ----------------------------------------------------------------------------

func _causes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var today := _clock.day_index()
	var hour := _clock.hour()
	for quest_id in _quests.active:
		var quest := _quests.definition(quest_id)
		var giver := str(quest.get("giver", ""))
		var deadline := int(_quests.active[quest_id].get("deadline_day", -1))
		if giver == "" or deadline < 0 or deadline - today > PhoneRules.NUDGE_DAYS:
			continue
		var days := deadline - today
		out.append({"npc": giver, "kind": "quest_nudge",
			"key": "phone.msg.quest_nudge" if days > 0 else "phone.msg.quest_nudge_last",
			"args": {"quest_key": str(quest.get("name_key", "")), "days": days}})
	var contacts: Array = state.contacts.keys()
	contacts.sort()
	for npc_id: String in contacts:
		if hour < _preferred_hour(npc_id, today):
			continue
		var errand_id := _quests.errand_offered_by(npc_id, today)
		if errand_id != "":
			var errand := _quests.errand(errand_id)
			out.append({"npc": npc_id, "kind": "errand_offer", "key": "phone.msg.errand_offer",
				"args": {"count": int(errand.get("count", 1)), "item": str(errand.get("item", "")),
					"reward": int(errand.get("reward", 0))},
				"action": {"do": "take_errand", "errand": errand_id}})
		var edge := _relationships.peek(npc_id, PlayerState.ID)
		if edge != null and edge.familiarity >= PhoneRules.CHECK_IN_FAMILIARITY \
				and edge.affection >= PhoneRules.CHECK_IN_AFFECTION:
			# A fond friend either suggests meeting up or just checks in.
			var meeting := {}
			if _meetings != null and posmod(("%s/%d" % [npc_id, today]).hash(), 2) == 0:
				meeting = _meetings.suggest(npc_id)
			if not meeting.is_empty():
				out.append({"npc": npc_id, "kind": "meeting_request", "key": "phone.msg.meeting_request",
					"args": {"place": str(meeting["location"]), "start": int(meeting["start"])}, "meeting": meeting})
			else:
				out.append({"npc": npc_id, "kind": "check_in", "args": {},
					"key": "phone.msg.check_in.%d" % (1 + posmod(("%s/%d" % [npc_id, today]).hash(), 3))})
	return out


## The hour of the day from which someone gets round to it, so a day's
## messages arrive spread out and not all as the clock strikes seven.
func _preferred_hour(npc_id: String, day: int) -> int:
	return PhoneRules.FIRST_HOUR + 1 + posmod(("%s/%d" % [npc_id, day]).hash(), 12)
