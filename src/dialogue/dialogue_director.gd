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
## Replies come from authored lines through `OfflineTopics` in this step.
## The model path arrives in M3 step 2 and slots in behind the same `say()`,
## with these lines as what it falls back to.

const MAX_LINE_LENGTH := 280
## Talking to someone is how you get to know them. Small, because a single
## chat should not make anyone a friend.
const FAMILIARITY_PER_CONVERSATION := 0.05
## Asking someone who they are is how you learn their name.
const FAMILIARITY_ONCE_INTRODUCED := 0.1

var conversation: Conversation = null

var _npcs: NpcRegistry = null
var _world: WorldState = null
var _player: PlayerState = null
var _relationships: RelationshipGraph = null
var _people_words: Dictionary = {}
var _place_words: Dictionary = {}


func setup(npcs: NpcRegistry, world: WorldState, player: PlayerState, relationships: RelationshipGraph) -> void:
	_npcs = npcs
	_world = world
	_player = player
	_relationships = relationships
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
## {"text": String, "topic": String, "subject": String, "ends": bool}.
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

	conversation.add(PlayerState.ID, line, "player")
	conversation.exchanges += 1
	var npc_id := conversation.npc_id
	var found := OfflineTopics.topic_of(line, npc_id, _people_words, _place_words)
	var topic: String = found["topic"]
	var subject: String = found["subject"]
	var reply := _authored_reply(npc_id, topic, subject)
	conversation.add(npc_id, reply, "authored")
	if topic == "about_self":
		_introduced(npc_id)
	var ends := topic == "farewell"
	conversation.over = ends
	return Result.success({"text": reply, "topic": topic, "subject": subject, "ends": ends})


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
