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
## Replies come from the model when one is available (D-036), prompted with
## only what this person knows, and from authored lines through
## `OfflineTopics` when it is not or when it fails — the conversation carries
## on either way. What talking *changes* (who you have been introduced to,
## whether that was goodbye, how familiar two people are) is decided here from
## the player's own words, never from the model's reply.

const MAX_LINE_LENGTH := 280
const WEEKDAYS: Array[String] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
## Talking to someone is how you get to know them. Small, because a single
## chat should not make anyone a friend.
const FAMILIARITY_PER_CONVERSATION := 0.05
## Asking someone who they are is how you learn their name.
const FAMILIARITY_ONCE_INTRODUCED := 0.1

var conversation: Conversation = null
## Whatever answers as the person. The game's LLM client in play
## (`LlmDialogueModel`), a scripted stand-in in tests, and the base class —
## which answers nothing — for authored lines only.
var model: DialogueModel = DialogueModel.new()

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
		p_model: DialogueModel = null) -> void:
	_npcs = npcs
	_world = world
	_player = player
	_relationships = relationships
	_knowledge = knowledge
	_clock = clock
	_data = data
	model = p_model if p_model != null else DialogueModel.new()
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
	_build_word_maps(npc_id)
	var key := DialogueLines.pick(npc_id, "greet", now_minute)
	var text := Localization.t(key)
	conversation.add(npc_id, text, "authored")
	return Result.success({"npc": npc_id, "text": text, "key": key})


## The player says something; returns the reply:
## {"text", "topic", "subject", "ends": bool, "source": "model" | "authored",
## "fallback_reason": String}. Await it: with a model, it waits for an answer.
## Refuses `not_talking`, `empty`, `too_long`, `conversation_over`.
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
	var npc_id := talking_to.npc_id
	# What the player's words *do* is read from the player's words, the same
	# way with or without a model, so it can never depend on a reply.
	var found := OfflineTopics.topic_of(line, npc_id, _people_words, _place_words)
	var topic: String = found["topic"]
	var subject: String = found["subject"]

	var reply := ""
	var source := "authored"
	var fallback_reason := ""
	if model.is_available():
		var npc := _npcs.get_npc(npc_id)
		var request := DialoguePrompt.build(prompt_context(npc_id))
		var response: LlmResponse = await model.send(request)
		if talking_to != conversation:
			return Result.failure("not_talking")   # they walked away while it was thinking
		if response.ok:
			reply = DialoguePrompt.clean_reply(response.text, npc.name if npc != null else "")
			source = "model" if reply != "" else "authored"
			fallback_reason = "" if reply != "" else "empty_reply"
		else:
			fallback_reason = response.error_code
	else:
		fallback_reason = "offline"
	if reply == "":
		reply = _authored_reply(npc_id, topic, subject)

	talking_to.add(npc_id, reply, source)
	if topic == "about_self":
		_introduced(npc_id)
	var ends := topic == "farewell"
	talking_to.over = ends
	return Result.success({
		"text": reply, "topic": topic, "subject": subject, "ends": ends,
		"source": source, "fallback_reason": fallback_reason,
	})


## Everything `DialoguePrompt` is allowed to know about this conversation,
## read from the world as it stands. Public so a test can check what a prompt
## would be built from.
func prompt_context(npc_id: String) -> Dictionary:
	var npc := _npcs.get_npc(npc_id)
	var place := _world.get_location(npc.location)
	var minute := _clock.minute_of_day() if _clock != null else 12 * 60
	var feeling := _relationships.peek(npc_id, PlayerState.ID)
	var relationship := {}
	if feeling != null:
		for dimension in Relationship.DIMENSIONS:
			relationship[dimension] = feeling.get_dimension(dimension)
	var history: Array[Dictionary] = []
	if conversation != null:
		for line in conversation.lines:
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
		"relationship": relationship,
		"people": _people_they_know(npc_id),
		"knows": _what_they_believe_about_the_player(npc_id),
		"memories": [],
		"history": history,
		"language": Localization.current_locale(),
	}


## Ends the conversation. Returns {"npc": id, "exchanges": int} so the caller
## can pay the time it took. Talking at all makes two people a little more
## familiar, in both directions.
func end() -> Result:
	if not is_talking():
		return Result.failure("not_talking")
	var ended := conversation
	conversation = null
	if ended.exchanges > 0:
		_relationships.adjust(PlayerState.ID, ended.npc_id, "familiarity", FAMILIARITY_PER_CONVERSATION)
		_relationships.adjust(ended.npc_id, PlayerState.ID, "familiarity", FAMILIARITY_PER_CONVERSATION)
	return Result.success({"npc": ended.npc_id, "exchanges": ended.exchanges})


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


func _authored_reply(npc_id: String, topic: String, subject: String) -> String:
	var turn := conversation.exchanges
	match topic:
		"about_person":
			var other := _npcs.get_npc(subject)
			var first := other.name.split(" ")[0] if other != null else subject
			var known := _relationships.peek(npc_id, subject)
			var variant := "about_person_known" if known != null and known.familiarity > 0.0 else "about_person_unknown"
			return Localization.t(DialogueLines.pick(npc_id, variant, turn), {"person": first})
		"about_place":
			var place := _world.get_location(subject)
			return Localization.t(DialogueLines.pick(npc_id, topic, turn),
				{"place": place.display_name() if place != null else subject})
	return Localization.t(DialogueLines.pick(npc_id, topic, turn))


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
		var what := "%s %s" % [str(belief["predicate"]).replace("_", " "), _name_of(str(belief["object"]))]
		var how := "you saw it yourself" if belief["firsthand"] else ("you heard it and believe it" if belief["confident"] else "you heard a rumour")
		out.append("%s (%s)" % [what.strip_edges(), how])
	return out


## A fact's object as words: a person's or a place's name, else the id made
## readable. The model is never shown an id it could repeat back.
func _name_of(id: String) -> String:
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
	_people_words = OfflineTopics.name_words(people, true)
	_place_words = OfflineTopics.name_words(places, false, first_names)


static func _names_in_every_locale(key: String) -> Array[String]:
	var out: Array[String] = []
	for locale in Localization.available_locales():
		var translation := TranslationServer.get_translation_object(locale)
		var text := String(translation.get_message(key)) if translation != null else ""
		if text != "" and not out.has(text):
			out.append(text)
	return out
