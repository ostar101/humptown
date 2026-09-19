class_name DialogueDirector
extends RefCounted
## Conversations (D-035): who can be talked to, what they say back, and the
## few deterministic things that talking changes.
##
## The layering rule, applied to speech. Presentation proposes "I am talking
## to Ida" — it found her body on the faced cell — and this decides whether
## Ida is really somewhere she could be talked to, from the simulation, never
## from the body (D-017). The body can trail the world by a few seconds of
## walking; if the simulation already has her in the shop, she is on her way
## there and does not stop, which is both true and a reasonable thing for a
## person to do.
##
## Every line goes the same way (D-037): an interpreter says what the player
## meant — the cheap model when there is one, `OfflineTopics` when there is
## not or when it fails; `ConversationRules` judges that against the world
## and either lists the effects or refuses; the effects are applied here; and
## only then does the person answer — from the model (D-036), told what
## actually happened, or from authored lines. A model's reply never changes
## anything, and a model's reading of the player changes only what the rules
## allow.

const MAX_LINE_LENGTH := 280
const WEEKDAYS: Array[String] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
## Talking to someone is how you get to know them. Small, because a single
## chat should not make anyone a friend.
const FAMILIARITY_PER_CONVERSATION := 0.05
## Asking someone who they are is how you learn their name.
const FAMILIARITY_ONCE_INTRODUCED := 0.1
## A text exchange gets you known a little less than a conversation does.
const FAMILIARITY_PER_TEXT := 0.02
## Lines this short and this plain are read from their words even when a
## model is available: a model adds nothing to "hi" but cost and a wait.
const PLAIN_TOPICS: Array[String] = ["greet", "farewell", "thanks"]
const PLAIN_MAX_WORDS := 4

var conversation: Conversation = null
## Whatever answers as the person. The game's LLM client in play
## (`LlmDialogueModel`), a scripted stand-in in tests, and the base class —
## which answers nothing — for authored lines only.
var model: DialogueModel = DialogueModel.new()
## What people remember of the player (D-038). The game's own book in play.
var memories: MemoryBook = MemoryBook.new()
## The player's job (D-042), for hiring and quitting in conversation.
var work: Employment = null
## The player's quests and errands (D-044).
var quests: QuestLog = QuestLog.new()
## What can be asked of people, and what comes of asking (D-053).
var asks: AskDirector = AskDirector.new()
## The last few lines and how each was handled, newest last, for the
## developer overlay: what was meant and by whose reading, what the rules
## did, and where the answer came from.
var turn_log: Array[Dictionary] = []
const TURN_LOG_LIMIT := 8

var _npcs: NpcRegistry = null
var _world: WorldState = null
var _player: PlayerState = null
var _relationships: RelationshipGraph = null
var _knowledge: KnowledgeNetwork = null
var _clock: GameClock = null
var _data: DataRegistry = null
var _people_words: Dictionary = {}
var _place_words: Dictionary = {}


func setup(npcs: NpcRegistry, world: WorldState, player: PlayerState, relationships: RelationshipGraph,
		knowledge: KnowledgeNetwork = null, clock: GameClock = null, data: DataRegistry = null,
		p_model: DialogueModel = null, p_memories: MemoryBook = null, p_work: Employment = null,
		p_quests: QuestLog = null, p_asks: AskDirector = null) -> void:
	_npcs = npcs
	_world = world
	_player = player
	_relationships = relationships
	_knowledge = knowledge
	_clock = clock
	_data = data
	model = p_model if p_model != null else DialogueModel.new()
	memories = p_memories if p_memories != null else MemoryBook.new()
	work = p_work if p_work != null else Employment.new()
	quests = p_quests if p_quests != null else QuestLog.new()
	asks = p_asks if p_asks != null else AskDirector.new()
	if p_quests == null and data != null:
		quests.setup(data)
	conversation = null


func is_talking() -> bool:
	return conversation != null


## Ok if the player could start talking to this person now, else why not:
## `already_talking`, `nobody_there`, `asleep`, `on_their_way`.
func can_talk_to(npc_id: String) -> Result:
	if is_talking():
		return Result.failure("already_talking")
	var npc := _npcs.get_npc(npc_id) if _npcs != null else null
	if npc == null or not npc.alive:
		return Result.failure("nobody_there")
	if npc.activity == "sleep":
		return Result.failure("asleep")
	var where := _where_problem(npc)
	if where != "":
		return Result.failure(where)
	return Result.success()


## Starts a conversation and returns their opening line:
## {"npc": id, "text": String, "key": String}.
func start(npc_id: String, now_minute: int) -> Result:
	var allowed := can_talk_to(npc_id)
	if allowed.is_err():
		return allowed
	conversation = Conversation.new(npc_id, now_minute)
	conversation.place = _npcs.get_npc(npc_id).location
	_build_word_maps(npc_id)
	# Bringing what they asked for is noticed before anything is said (D-044).
	var delivered := _deliver_errand(npc_id)
	var key := DialogueLines.pick(npc_id, "errand_done" if not delivered.is_empty() else "greet", now_minute)
	var text := Localization.t(key, delivered)
	conversation.add(npc_id, text, "authored")
	return Result.success({"npc": npc_id, "text": text, "key": key})


## Starts a phone call (D-050). Whether they would pick up is judged by
## `PhoneRules.judge_call`, before this; here the call is made, and they
## answer. The rest is a conversation like any other, over the phone:
## `say()` and `end()` as usual. Returns what `start()` does.
func start_call(npc_id: String, now_minute: int) -> Result:
	if is_talking():
		return Result.failure("already_talking")
	var npc := _npcs.get_npc(npc_id) if _npcs != null else null
	if npc == null or not npc.alive:
		return Result.failure("nobody_there")
	conversation = Conversation.new(npc_id, now_minute)
	conversation.channel = "call"
	conversation.place = npc.location
	_build_word_maps(npc_id)
	var key := DialogueLines.pick(npc_id, "call_answer", now_minute)
	var text := Localization.t(key)
	conversation.add(npc_id, text, "authored")
	return Result.success({"npc": npc_id, "text": text, "key": key})


## The player says something; returns the reply:
## {"text", "topic", "subject", "ends": bool, "source": "model" | "authored",
## "fallback_reason": String, "intent": Dictionary, "happened": String,
## "rejection": {} or {"proposal": Dictionary, "code": String}}.
## Await it: with a model, it waits for an answer. Refuses `not_talking`,
## `empty`, `too_long`, `conversation_over`. A refused *intent* is not a
## refused line — the line was said; what it tried to do did not happen, and
## `rejection` says why, for the caller to announce.
func say(text: String) -> Result:
	if not is_talking():
		return Result.failure("not_talking")
	if conversation.over:
		return Result.failure("conversation_over")
	var line := text.strip_edges()
	if line.is_empty():
		return Result.failure("empty")
	if line.length() > MAX_LINE_LENGTH:
		return Result.failure("too_long")

	var talking_to := conversation
	talking_to.add(PlayerState.ID, line, "player")
	talking_to.exchanges += 1
	return await _respond(talking_to, line, talking_to.channel)


## A text the person has now read (D-046). The same road as a spoken line:
## read into an intent, judged by the rules, applied, answered — but on the
## phone, with no conversation open and nobody in front of them. Returns what
## `say()` does; the person's memory of it is kept and a little familiarity
## earned, as when a conversation ends. Await it.
func text_exchange(npc_id: String, line: String) -> Result:
	var npc := _npcs.get_npc(npc_id) if _npcs != null else null
	if npc == null or not npc.alive:
		return Result.failure("nobody_there")
	var convo := Conversation.new(npc_id, _clock.total_minutes if _clock != null else 0)
	convo.place = npc.location
	convo.add(PlayerState.ID, line, "player")
	convo.exchanges = 1
	var replied: Result = await _respond(convo, line, "text", _word_maps(npc_id))
	if replied.is_ok():
		_settle(convo, FAMILIARITY_PER_TEXT)
	return replied


## One line, however it was said: what was meant, what that may change, what
## comes back. `channel` is "in_person", "call" or "text"; `words` are the people and
## places that can be mentioned (the conversation's own, when empty).
func _respond(convo: Conversation, line: String, channel: String, words: Dictionary = {}) -> Result:
	var npc_id := convo.npc_id
	var npc := _npcs.get_npc(npc_id)
	# In person or on a call there is a conversation open, and walking away from it
	# ends things; a text is read on its own.
	var live := channel != "text"

	# 1. What the player meant.
	var intent: Dictionary = await _interpret(line, npc_id,
		words.get("people", _people_words), words.get("places", _place_words))
	if live and convo != conversation:
		return Result.failure("not_talking")   # they walked away while it was thinking

	# 2. What that is allowed to change — rules, not the model — and doing it.
	var judged := ConversationRules.judge(intent, _rules_state(npc_id, convo, channel))
	var topic := ConversationRules.topic_for_refusal(judged.code)
	var happened := judged.message
	var ends := false
	var rejection := {}
	if judged.is_ok():
		var verdict: Dictionary = judged.value
		var effects: Array[Dictionary] = verdict["effects"]
		var applied := _apply(npc_id, effects)
		convo.warmth += ConversationRules.warmth_of(effects)
		topic = verdict["topic"]
		happened = verdict["happened"]
		ends = verdict["ends"]
		if applied.has("happened"):   # what an ask came to is only known once it is rolled
			happened = str(applied["happened"])
			topic = str(applied["topic"])
	else:
		rejection = {"code": judged.code, "proposal": {
			"kind": {"in_person": "say", "call": "call", "text": "text"}[channel], "intent": intent["kind"], "npc": npc_id, "amount": intent.get("amount", 0),
		}}
	var kept := ConversationRules.memory_of(intent, judged, _subject_name(intent))
	if not kept.is_empty():
		convo.remember(str(kept["text"]), float(kept["weight"]))
	Events.player_deed.emit({"in_person": "talked", "call": "called", "text": "texted"}[channel],
		{"npc": npc_id, "kind": str(intent["kind"]), "subject": str(intent.get("subject", ""))})
	var reply_args := _errand_args(npc_id) if topic in ["errand_asked", "errand_waiting"] else {}

	# 3. What they say back, knowing what actually happened.
	var reply := ""
	var source := "authored"
	var fallback_reason := ""
	if model.is_available():
		var request := DialoguePrompt.build(prompt_context(npc_id, happened, convo, channel))
		var response: LlmResponse = await model.send(request)
		if live and convo != conversation:
			return Result.failure("not_talking")
		if response.ok:
			reply = DialoguePrompt.clean_reply(response.text, npc.name if npc != null else "", response.hit_length_limit())
			source = "model" if reply != "" else "authored"
			fallback_reason = "" if reply != "" else "empty_reply"
		else:
			fallback_reason = response.error_code
	else:
		fallback_reason = "offline"
	if reply == "":
		reply = _authored_reply(npc_id, topic, intent, reply_args, convo.exchanges)

	convo.add(npc_id, reply, source)
	if live:
		convo.over = ends
	turn_log.append({
		"npc": npc_id, "channel": channel, "line": line.left(60), "intent": intent["kind"], "read_by": intent["source"],
		"read_fallback": intent.get("fallback_reason", ""), "happened": happened,
		"rejected": str(rejection.get("code", "")), "reply_by": source, "reply_fallback": fallback_reason,
	})
	while turn_log.size() > TURN_LOG_LIMIT:
		turn_log.remove_at(0)
	return Result.success({
		"text": reply, "topic": topic, "subject": str(intent.get("subject", "")), "ends": ends,
		"source": source, "fallback_reason": fallback_reason,
		"intent": intent, "happened": happened, "rejection": rejection,
	})


## What the player meant by a line: {"kind", "subject", "amount", "name",
## "person_said", "source": "model" | "offline", "fallback_reason"}. The
## cheap model reads it when one is available, except for lines plain enough
## that words settle them ("hi", "thanks, bye") — never call a model to
## decide what deterministic logic can. Whatever the model says, names are
## resolved to people and places here, or to nothing.
func interpret(line: String, npc_id: String) -> Dictionary:
	return await _interpret(line, npc_id, _people_words, _place_words)


func _interpret(line: String, npc_id: String, people_words: Dictionary, place_words: Dictionary) -> Dictionary:
	var found := OfflineTopics.topic_of(line, npc_id, people_words, place_words)
	var offline := {
		"kind": found["topic"], "subject": found["subject"], "amount": found["amount"],
		"name": found["name"], "person_said": "", "source": "offline", "fallback_reason": "",
	}
	if not model.is_available():
		offline["fallback_reason"] = "offline"
		return offline
	if str(found["topic"]) in PLAIN_TOPICS and OfflineTopics.tokens_of(line).size() <= PLAIN_MAX_WORDS:
		offline["fallback_reason"] = "plain"
		return offline
	var npc := _npcs.get_npc(npc_id)
	var response: LlmResponse = await model.send(IntentPrompt.build(line, npc.name if npc != null else ""))
	var read := IntentPrompt.parse(response)
	if read.is_empty():
		offline["fallback_reason"] = response.error_code if not response.ok else "unreadable"
		return offline
	var subject := ""
	match str(read["kind"]):
		"about_person":
			subject = OfflineTopics.resolve(str(read["person"]), people_words, npc_id)
		"about_place":
			subject = OfflineTopics.resolve(str(read["place"]), place_words, "")
	return {
		"kind": read["kind"], "subject": subject, "amount": read["amount"], "name": read["name"],
		"person_said": read["person"] if str(read["kind"]) == "about_person" else read["place"],
		"source": "model", "fallback_reason": "",
	}


## Everything `DialoguePrompt` is allowed to know about this conversation,
## read from the world as it stands. Public so a test can check what a prompt
## would be built from.
func prompt_context(npc_id: String, happened: String = "", convo: Conversation = null, channel: String = "in_person") -> Dictionary:
	var npc := _npcs.get_npc(npc_id)
	var place := _world.get_location(npc.location)
	var minute := _clock.minute_of_day() if _clock != null else 12 * 60
	var history: Array[Dictionary] = []
	var talk := convo if convo != null else conversation
	if talk != null:
		for line in talk.lines:
			history.append({"speaker": "player" if line["speaker"] == PlayerState.ID else "npc", "text": line["text"]})
	return {
		"npc": {
			"name": npc.name, "age": npc.age, "occupation": _occupation_in_english(npc),
			"bio": npc.bio, "voice": npc.voice, "traits": npc.traits,
		},
		"now": {
			"place": DialoguePrompt.english(place.name_key) if place != null else "",
			"part_of_day": DialoguePrompt.part_of_day(minute),
			"weekday": WEEKDAYS[_clock.weekday()] if _clock != null else "weekday",
			"doing": DialoguePrompt.english("activity." + npc.activity),
		},
		"player": {
			"name": _player.display_name if _knows_players_name(npc_id) else "",
			"pronouns": _player.pronouns,
		},
		"relationship": _feelings(npc_id),
		"people": _people_they_know(npc_id),
		"knows": _what_they_believe_about_the_player(npc_id),
		"memories": memories.recall(npc_id, _clock.total_minutes if _clock != null else 0, _place_name),
		"history": history,
		"happened": happened,
		"channel": channel,
		"language": Localization.current_locale(),
	}


## Ends the conversation. Returns {"npc": id, "exchanges": int, "folded":
## [sentences], "fold": int} so the caller can pay the time it took and, when
## older memories were folded, have a model rewrite the summary. Talking at
## all makes two people a little more familiar, in both directions, and
## leaves the person a memory of it (D-038).
func end() -> Result:
	if not is_talking():
		return Result.failure("not_talking")
	var ended := conversation
	conversation = null
	return Result.success(_settle(ended, FAMILIARITY_PER_CONVERSATION))


## What is left of a conversation once it is over: a little more familiarity,
## both ways, and a memory of it (D-038).
func _settle(ended: Conversation, familiarity: float) -> Dictionary:
	var folded: Array[String] = []
	if ended.exchanges > 0:
		_relationships.adjust(PlayerState.ID, ended.npc_id, "familiarity", familiarity)
		_relationships.adjust(ended.npc_id, PlayerState.ID, "familiarity", familiarity)
		memories.add_episode(ended.npc_id, ended.started_minute, ended.place, ended.things, ended.weight)
		folded = memories.fold_by_rule(ended.npc_id, _place_name)
	return {
		"npc": ended.npc_id, "exchanges": ended.exchanges,
		"folded": folded, "fold": memories.folds(ended.npc_id),
	}


## Has the model rewrite what someone remembers of the player, after older
## memories were folded by rule. Await it; the rule summary stands if this
## fails, and a rewrite that arrives after a newer fold is dropped.
func summarise(npc_id: String, folded: Array[String], for_fold: int) -> Result:
	if not model.is_available():
		return Result.failure("offline")
	var npc := _npcs.get_npc(npc_id)
	if npc == null:
		return Result.failure("nobody_there")
	var request := DialoguePrompt.summary_request(npc.name, memories.summary(npc_id), folded)
	var response: LlmResponse = await model.send(request)
	if not response.ok:
		return Result.failure(response.error_code)
	return memories.set_summary(npc_id, DialoguePrompt.clean_reply(response.text, npc.name), for_fold)


## Whether the player knows this person's name: a contact from their
## background, or someone they have met and been introduced to.
func knows_name(npc_id: String) -> bool:
	if _player != null and _player.knows_contact(npc_id):
		return true
	var edge := _relationships.peek(PlayerState.ID, npc_id) if _relationships != null else null
	return edge != null and edge.familiarity > 0.0


## What to call someone on screen: their name if the player knows it, else
## their occupation, else nothing in particular.
func display_name(npc_id: String, data: DataRegistry) -> String:
	var npc := _npcs.get_npc(npc_id) if _npcs != null else null
	if npc == null:
		return ""
	if knows_name(npc_id):
		return npc.name
	var occupation := data.get_entry("occupations", npc.occupation) if data != null else {}
	if not occupation.is_empty():
		return Localization.t(str(occupation.get("name_key", "")))
	return Localization.t("ui.dialogue.stranger")


# --- internals ----------------------------------------------------------------

func _where_problem(npc: Npc) -> String:
	if not _player.interior.is_empty():
		return "" if npc.location == _player.interior else "nobody_there"
	var location := _world.get_location(npc.location)
	if location == null or location.region != _player.region:
		return "nobody_there"
	var map := _world.map_for(_player.region)
	if map != null and map.is_building(npc.location):
		return "on_their_way"
	return ""


func _authored_reply(npc_id: String, topic: String, intent: Dictionary, extra: Dictionary, turn: int) -> String:
	var subject := str(intent.get("subject", ""))
	var said := str(intent.get("person_said", ""))
	match topic:
		"about_person":
			var other := _npcs.get_npc(subject)
			var first := other.name.split(" ")[0] if other != null else (said if said != "" else subject)
			var known := _relationships.peek(npc_id, subject) if other != null else null
			var variant := "about_person_known" if known != null and known.familiarity > 0.0 else "about_person_unknown"
			return Localization.t(DialogueLines.pick(npc_id, variant, turn), {"person": first})
		"about_place":
			var place := _world.get_location(subject)
			return Localization.t(DialogueLines.pick(npc_id, topic, turn),
				{"place": place.display_name() if place != null else (said if said != "" else subject)})
	var name := str(intent.get("name", ""))
	var args := {
		"name": name if name != "" else _player.display_name,
		"amount": str(intent.get("amount", 0)),
	}
	args.merge(extra, true)
	return Localization.t(DialogueLines.pick(npc_id, topic, turn), args)


## The errand this person could ask for, or is waiting on, as words for a
## line: {"count", "item", "reward"}.
func _errand_args(npc_id: String) -> Dictionary:
	var errand_id := quests.errand_running_for(npc_id)
	if errand_id == "":
		errand_id = quests.errand_offered_by(npc_id, _today())
	var errand := quests.errand(errand_id)
	if errand.is_empty():
		return {}
	var item := _data.get_entry("items", str(errand.get("item", ""))) if _data != null else {}
	return {"count": int(errand.get("count", 1)), "item": Localization.t(str(item.get("name_key", ""))),
		"reward": int(errand.get("reward", 0))}


## If the player brings what this person asked for, it is handed over and
## paid for (D-044). Returns the words for the thanks ({"reward", …}), or {}
## when there is nothing to deliver.
func _deliver_errand(npc_id: String) -> Dictionary:
	var errand_id := quests.errand_running_for(npc_id)
	if errand_id == "":
		return {}
	var errand := quests.errand(errand_id)
	var item_id := str(errand.get("item", ""))
	var count := int(errand.get("count", 1))
	if _player.inventory.count_of(item_id) < count:
		return {}
	var args := _errand_args(npc_id)
	_player.inventory.remove(item_id, count)
	var reward := int(errand.get("reward", 0))
	_player.wallet.add_cash(reward, "errand:" + errand_id)
	var now := _clock.total_minutes if _clock != null else 0
	_relationships.adjust(npc_id, PlayerState.ID, "affection", 0.05, now)
	_relationships.adjust(npc_id, PlayerState.ID, "trust", 0.03, now)
	quests.finish_errand(errand_id, _today())
	conversation.remember("brought you what you asked for", 0.4)
	Events.player_deed.emit("errand_done", {"errand": errand_id, "npc": npc_id})
	Events.quest_updated.emit(errand_id, "errand_done")
	return args


func _today() -> int:
	return _clock.day_index() if _clock != null else 0


## A person or place a line was about, as a name, for memory.
func _subject_name(intent: Dictionary) -> String:
	var subject := str(intent.get("subject", ""))
	if subject.begins_with("npc_") and _npcs.get_npc(subject) != null:
		return _npcs.get_npc(subject).name
	if subject.begins_with("loc_") and _world.get_location(subject) != null:
		return _place_name(subject)
	return str(intent.get("person_said", ""))


func _place_name(location_id: String) -> String:
	var place := _world.get_location(location_id) if _world != null else null
	return DialoguePrompt.english(place.name_key) if place != null else "somewhere in Harbourside"


## How the person feels about the player, dimension by dimension; empty for
## a stranger.
func _feelings(npc_id: String) -> Dictionary:
	var feeling := _relationships.peek(npc_id, PlayerState.ID)
	var out := {}
	if feeling != null:
		for dimension in Relationship.DIMENSIONS:
			out[dimension] = feeling.get_dimension(dimension)
	return out


## What `ConversationRules` needs to know about the world, and nothing more.
func _rules_state(npc_id: String, convo: Conversation, channel: String) -> Dictionary:
	var ask := asks.offer(npc_id)
	return {
		"npc_id": npc_id,
		"channel": channel,
		"player_name": _player.display_name,
		"player_cash": _player.wallet.cash,
		"player_bank": _player.wallet.bank,
		"ask": ask,
		"ask_cooldown": not ask.is_empty() and asks.on_cooldown(str(ask["id"])),
		"relationship": _feelings(npc_id),
		"warmth": convo.warmth,
		"hiring": _hiring(npc_id),
		"errand": _errand_offer(npc_id),
		"errand_running": quests.errand_running_for(npc_id) != "",
		"works_for_them": work.has_job() and _data != null \
			and str(_data.get_entry("jobs", work.job_id).get("employer", "")) == npc_id,
	}


## An errand this person could ask of the player today, in the prompt's
## words: {"id", "what", "reward"}, or {}.
func _errand_offer(npc_id: String) -> Dictionary:
	var errand_id := quests.errand_offered_by(npc_id, _today())
	if errand_id == "":
		return {}
	var errand := quests.errand(errand_id)
	var item := _data.get_entry("items", str(errand.get("item", "")))
	return {"id": errand_id, "reward": int(errand.get("reward", 0)),
		"what": "%d × %s" % [int(errand.get("count", 1)), DialoguePrompt.english(str(item.get("name_key", ""))).to_lower()]}


## The job this person hires for, if any: {"job", "name", "problem"}, where
## `problem` is why the player could not have it ("" when they could).
func _hiring(npc_id: String) -> Dictionary:
	if _data == null:
		return {}
	for job_id in _data.ids("jobs"):
		var job := _data.get_entry("jobs", job_id)
		if str(job.get("employer", "")) != npc_id:
			continue
		var flags: Array = []
		for flag in _player.quest_flags:
			if _player.quest_flags[flag]:
				flags.append(str(flag))
		var feeling := _relationships.peek(npc_id, PlayerState.ID)
		var judged := WorkRules.judge_hire(job, flags, _player.skills.level_map(),
			feeling.familiarity if feeling != null else 0.0)
		var occupation := _data.get_entry("occupations", str(job.get("occupation", "")))
		return {
			"job": str(job_id),
			"name": DialoguePrompt.english(str(occupation.get("name_key", ""))).to_lower(),
			"problem": judged.code if judged.is_err() else "",
		}
	return {}


## Carries out what the rules allowed. Nothing else in a conversation writes
## to the world.
func _apply(npc_id: String, effects: Array[Dictionary]) -> Dictionary:
	var now := _clock.total_minutes if _clock != null else 0
	var came_of_it := {}
	for effect in effects:
		match str(effect["do"]):
			"ask":
				came_of_it = asks.attempt(str(effect["ask"]))
			"fight":
				Events.fight_requested.emit(npc_id)
			"feel":
				_relationships.adjust(npc_id, PlayerState.ID, str(effect["dimension"]), float(effect["delta"]), now)
			"pay":
				var paid := _player.wallet.spend(int(effect["amount"]), "gift:" + npc_id, true)
				if paid.is_err():
					Log.warn("dialogue", "A judged payment failed", {"code": paid.code})
				else:
					Events.player_deed.emit("gave_money", {"npc": npc_id, "amount": int(effect["amount"])})
			"transfer":
				var sent := _player.wallet.transfer_out(int(effect["amount"]), "transfer:" + npc_id)
				if sent.is_err():
					Log.warn("dialogue", "A judged transfer failed", {"code": sent.code})
				else:
					Events.player_deed.emit("gave_money", {"npc": npc_id, "amount": int(effect["amount"])})
			"remember":
				if _knowledge != null:
					var npc := _npcs.get_npc(npc_id)
					var witnesses: Array[String] = [npc_id]
					_knowledge.observe_event(PlayerState.ID, str(effect["predicate"]), now, witnesses, {
						"object": npc_id, "visibility": str(effect["visibility"]),
						"severity": float(effect["severity"]), "location": npc.location if npc != null else "",
					})
			"introduce_them":
				_introduced(npc_id)
			"tell_place":
				_player.learn_place(str(effect["place"]), "told")
			"hire":
				work.hire(str(effect["job"]), _today())
				if _data != null:
					_player.learn_place(str(_data.get_entry("jobs", str(effect["job"])).get("workplace", "")), "told")
				Events.job_changed.emit(str(effect["job"]))
				Events.player_deed.emit("hired", {"job": str(effect["job"])})
			"take_errand":
				quests.take_errand(str(effect["errand"]), _today())
				Events.quest_updated.emit(str(effect["errand"]), "errand_taken")
			"quit":
				work.leave()
				Events.job_changed.emit("")
			"introduce_player":
				var edge := _relationships.get_edge(npc_id, PlayerState.ID)
				if edge.familiarity < FAMILIARITY_ONCE_INTRODUCED:
					_relationships.adjust(npc_id, PlayerState.ID, "familiarity", FAMILIARITY_ONCE_INTRODUCED - edge.familiarity, now)
	return came_of_it


## Someone knows the player's name if the player is a contact of theirs from
## the start — the background says they know each other — or they have
## talked before.
func _knows_players_name(npc_id: String) -> bool:
	if _player.knows_contact(npc_id):
		return true
	var edge := _relationships.peek(npc_id, PlayerState.ID)
	return edge != null and edge.familiarity >= FAMILIARITY_PER_CONVERSATION


func _people_they_know(npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for other_id in _relationships.contacts_of(npc_id):
		if other_id == PlayerState.ID:
			continue
		var other := _npcs.get_npc(other_id)
		var edge := _relationships.peek(npc_id, other_id)
		if other != null and edge != null:
			out.append("%s (%s)" % [other.name, Relationship.KIND_NAMES[edge.kind]])
	return out


func _what_they_believe_about_the_player(npc_id: String) -> Array[String]:
	var out: Array[String] = []
	if _knowledge == null:
		return out
	for belief in _knowledge.what_is_known_about(npc_id, PlayerState.ID):
		var what := "%s %s" % [str(belief["predicate"]).replace("_", " "), _name_of(str(belief["object"]), npc_id)]
		var how := "you saw it yourself" if belief["firsthand"] else ("you heard it and believe it" if belief["confident"] else "you heard a rumour")
		out.append("%s (%s)" % [what.strip_edges(), how])
	return out


## A fact's object as words: "you" to the person it is about, else a
## person's or a place's name, else the id made readable. The model is never
## shown an id it could repeat back.
func _name_of(id: String, knower_id: String = "") -> String:
	if id != "" and id == knower_id:
		return "you"
	if id.begins_with("npc_") and _npcs.get_npc(id) != null:
		return _npcs.get_npc(id).name
	if id.begins_with("loc_") and _world.get_location(id) != null:
		return DialoguePrompt.english(_world.get_location(id).name_key)
	if id.begins_with("item_") and _data != null and _data.has_entry("items", id):
		return DialoguePrompt.english(str(_data.get_entry("items", id).get("name_key", id)))
	return id.replace("_", " ")


func _occupation_in_english(npc: Npc) -> String:
	var occupation := _data.get_entry("occupations", npc.occupation) if _data != null else {}
	return DialoguePrompt.english(str(occupation.get("name_key", ""))).to_lower() if not occupation.is_empty() else "a local"


func _introduced(npc_id: String) -> void:
	var edge := _relationships.get_edge(PlayerState.ID, npc_id)
	if edge.familiarity < FAMILIARITY_ONCE_INTRODUCED:
		edge.familiarity = FAMILIARITY_ONCE_INTRODUCED


## Who and where can be mentioned, in every language the game has, built once
## per conversation rather than per line.
func _build_word_maps(npc_id: String) -> void:
	var words := _word_maps(npc_id)
	_people_words = words["people"]
	_place_words = words["places"]


func _word_maps(npc_id: String) -> Dictionary:
	var people := {}
	var first_names: Array[String] = []
	for other_id in _npcs.all_ids():
		var other := _npcs.get_npc(str(other_id))
		if other == null:
			continue
		first_names.append_array(OfflineTopics.tokens_of(other.name).slice(0, 1))
		if other.id != npc_id:
			people[other.id] = [other.name]
	var places := {}
	for location_id in _world.locations_in(_player.region):
		var loc := _world.get_location(str(location_id))
		if loc != null:
			places[loc.id] = _names_in_every_locale(loc.name_key)
	return {"people": OfflineTopics.name_words(people, true), "places": OfflineTopics.name_words(places, false, first_names)}


static func _names_in_every_locale(key: String) -> Array[String]:
	var out: Array[String] = []
	for locale in Localization.available_locales():
		var translation := TranslationServer.get_translation_object(locale)
		var text := String(translation.get_message(key)) if translation != null else ""
		if text != "" and not out.has(text):
			out.append(text)
	return out
