class_name AskDirector
extends RefCounted
## What can be asked of whom, and what comes of asking (D-053). An ask is
## authored data (`data/asks.json`): who it is put to, what has to be true for
## there to be anything to ask (an open debt, a summons), the skill it turns
## on, and for each of the four grades what happens — a list of effects from a
## small vocabulary, so a model never writes to the world and the world's
## rules stay the only thing that does.
##
## Effects: `feel` {npc, dimension, delta} · `flag` {flag, value} · `cash`
## {amount} · `extend_deadline` {quest, days} · `raise_requirement` {quest,
## amount} · `leniency` {delta} (how the officer weighs the player's case).

const EFFECTS: Array[String] = ["feel", "flag", "cash", "extend_deadline", "raise_requirement", "leniency"]

## ask id -> the day it was last put to them: nobody is asked twice in a breath.
var asked: Dictionary = {}

var _data: DataRegistry = null
var _relationships: RelationshipGraph = null
var _quests: QuestLog = null
var _crime: CrimeDirector = null
var _player: PlayerState = null
var _clock: GameClock = null
var _rng: RngStreams = null


func setup(data: DataRegistry, relationships: RelationshipGraph, quests: QuestLog, crime: CrimeDirector,
		player: PlayerState, clock: GameClock, rng: RngStreams) -> void:
	_data = data
	_relationships = relationships
	_quests = quests
	_crime = crime
	_player = player
	_clock = clock
	_rng = rng


## What this person could be asked for right now: the ask's entry, or {}.
func offer(npc_id: String) -> Dictionary:
	if _data == null:
		return {}
	for ask_id in _data.ids("asks"):
		var ask := _data.get_entry("asks", ask_id)
		if str(ask.get("npc", "")) == npc_id and _requirements_met(ask.get("requires", {}), npc_id):
			return ask
	return {}


func on_cooldown(ask_id: String) -> bool:
	if not asked.has(ask_id) or _data == null:
		return false
	var days := int(_data.get_entry("asks", ask_id).get("cooldown_days", AskRules.DEFAULT_COOLDOWN_DAYS))
	return _clock.day_index() - int(asked[ask_id]) < days


## Puts the ask. Returns {"grade", "ask", "chance", "happened", "topic"}: what
## happened in words for the person to react to, and the topic they answer on.
func attempt(ask_id: String) -> Dictionary:
	var ask := _data.get_entry("asks", ask_id)
	if ask.is_empty():
		return {}
	var npc_id := str(ask["npc"])
	var skill := str(ask["skill"])
	var difficulty := int(ask.get("difficulty", 30))
	var odds := AskRules.chance(_player.skills.level_of(skill), difficulty,
		_relationships.disposition(npc_id, PlayerState.ID), _player.stats.effectiveness())
	var judged := AskRules.judge({"has_ask": true, "on_cooldown": on_cooldown(ask_id), "chance": odds,
		"roll": _rng.stream("ask").randf()})
	if judged.is_err():
		return {}
	var reached: String = judged.value["grade"]
	_apply_effects(ask["grades"].get(reached, []), npc_id)
	asked[ask_id] = _clock.day_index()
	_player.skills.practise(skill, AskRules.xp(reached), difficulty)
	Events.ask_resolved.emit(ask_id, reached)
	return {"grade": reached, "ask": ask_id, "chance": odds,
		"happened": str((ask.get("happened", {}) as Dictionary).get(reached, "")), "topic": "ask_" + reached}


func to_dict() -> Dictionary:
	return {"asked": asked.duplicate()}


func from_dict(d: Dictionary) -> void:
	asked = {}
	var raw: Dictionary = d.get("asked", {})
	for ask_id in raw:
		asked[str(ask_id)] = int(raw[ask_id])


func _requirements_met(requires: Dictionary, npc_id: String) -> bool:
	if requires.has("quest") and not _quests.active.has(str(requires["quest"])):
		return false
	if bool(requires.get("open_summons", false)) and _crime.open_summons_for(npc_id).is_empty():
		return false
	return true


func _apply_effects(effects: Array, npc_id: String) -> void:
	var now := _clock.total_minutes
	for raw: Dictionary in effects:
		match str(raw.get("do", "")):
			"feel":
				_relationships.adjust(str(raw.get("npc", npc_id)), PlayerState.ID, str(raw["dimension"]), float(raw["delta"]), now)
			"flag":
				_player.quest_flags[str(raw["flag"])] = bool(raw.get("value", true))
			"cash":
				_player.wallet.add_cash(int(raw["amount"]), "ask")
			"extend_deadline":
				_quests.extend_deadline(str(raw["quest"]), int(raw["days"]))
			"raise_requirement":
				_quests.raise_requirement(str(raw["quest"]), int(raw["amount"]))
			"leniency":
				_crime.leniency[npc_id] = float(_crime.leniency.get(npc_id, 0.0)) + float(raw["delta"])
