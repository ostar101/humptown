class_name FightDirector
extends RefCounted
## Fights in the world (D-054). Starts one — who is really there, who would
## step in — and, when it ends, works out what it leaves behind: the wounds that
## last, how people feel, who saw it and what they will tell the police.
## `Combat` is only the arithmetic of the blows; this is the part that touches
## the world, and it does so by the same rules as everything else.
##
## Everyone is a real person. The one you hit has a health of their own that
## stays lowered and mends over hours; a friend of theirs standing there may
## step in; an officer who is there always does.

const JOIN_AFFECTION := 0.5
const MAX_JOINERS := 2
const KNOCKED_OUT_MINUTES := 45
const WEAPON_ITEM := "item_crowbar"
const WEAPON_BONUS := 0.06
const HEAL_ITEM := "item_bandage"
const ASSAULT_SEVERITY_BASE := 0.5
const ASSAULT_SEVERITY_PER_DAMAGE := 0.6

## The fight under way, or null.
var combat: Combat = null
## The last one to finish, for the window to show how it ended.
var last: Combat = null
## Where the dice come from when it is not the game's seeded stream — a test
## scripts a whole fight through this.
var roll_source: Callable = Callable()

var _npcs: NpcRegistry = null
var _player: PlayerState = null
var _relationships: RelationshipGraph = null
var _crime: CrimeDirector = null
var _memories: MemoryBook = null
var _clock: GameClock = null
var _data: DataRegistry = null
var _rng: RngStreams = null
var _location := ""
var _witnesses: Array[String] = []


func setup(npcs: NpcRegistry, player: PlayerState, relationships: RelationshipGraph, crime: CrimeDirector,
		memories: MemoryBook, clock: GameClock, data: DataRegistry, rng: RngStreams) -> void:
	_npcs = npcs
	_player = player
	_relationships = relationships
	_crime = crime
	_memories = memories
	_clock = clock
	_data = data
	_rng = rng


func is_fighting() -> bool:
	return combat != null


## Starts a fight with someone in front of the player. Refused: `already_fighting`,
## `nobody_there`, `asleep`, `not_here`.
func begin(npc_id: String) -> Result:
	if combat != null:
		return Result.failure("already_fighting")
	var npc := _npcs.get_npc(npc_id)
	if npc == null or not npc.alive:
		return Result.failure("nobody_there")
	if npc.activity == "sleep":
		return Result.failure("asleep")
	if npc.location != _player.location:
		return Result.failure("not_here")
	_location = _player.location
	var foes: Array[Dictionary] = [_foe(npc, "primary")]
	var here := _people_here()
	for other_id in here:
		if other_id == npc_id or foes.size() > MAX_JOINERS:
			continue
		if _would_step_in(other_id, npc_id):
			foes.append(_foe(_npcs.get_npc(other_id), "joiner"))
	_witnesses = here
	last = null
	combat = Combat.new(_player_combatant(), foes, Callable(self, "_roll"), _items())
	Events.fight_started.emit(npc_id)
	return Result.success({"foes": foes.map(func(f: Dictionary) -> String: return str(f["id"]))})


func act(action: String, arg: String = "") -> Result:
	if combat == null:
		return Result.failure("not_fighting")
	return combat.player_act(action, arg)


## Ends a fight that is over and works out what it leaves behind. Returns
## {"result", "minutes", "hurt": bool, "down": [ids], "primary": id}.
func finish() -> Dictionary:
	var done := combat
	if done == null or not done.is_over():
		return {}
	combat = null
	last = done
	var now := _clock.total_minutes
	var me := done.player()
	_player.stats.health = maxf(float(me["health"]), 0.0)
	_player.stats.stamina = clampf(float(me["stamina"]), 0.0, 1.0)
	for dealt in done.blows_taken:
		var wound := CombatRules.injury_from(dealt, _roll())
		if not wound.is_empty():
			_player.stats.add_injury(str(wound["id"]), str(wound["part"]), float(wound["severity"]),
				now + int(wound["days"]) * GameClock.MINUTES_PER_DAY)
	for item_id: String in done.items_used:
		_player.inventory.remove(item_id, int(done.items_used[item_id]))
	var down: Array[String] = []
	var primary := ""
	for foe in done.foes():
		var npc := _npcs.get_npc(str(foe["id"]))
		if npc == null:
			continue
		var first := primary == ""
		if first:
			primary = npc.id
		npc.state["health"] = float(foe["health"])
		npc.state["hurt_at"] = now
		if foe["state"] == "down":
			down.append(npc.id)
			npc.set_override(now, now + KNOCKED_OUT_MINUTES, npc.location, "sleep", "knocked_out")
			_npcs.invalidate_location_cache(npc.id)
		_relationships.adjust(npc.id, PlayerState.ID, "affection", -0.40 if first else -0.15, now)
		_relationships.adjust(npc.id, PlayerState.ID, "trust", -0.30 if first else -0.10, now)
		if done.result == "won":
			_relationships.adjust(npc.id, PlayerState.ID, "fear", 0.15, now)
		_memories.add_episode(npc.id, now, _location, ["attacked you"] as Array[String], 0.9)
	var seen: Array[String] = []
	for witness_id in _witnesses:
		seen.append(witness_id)
	_crime.record_crime("assaulted", _location, primary, seen,
		clampf(ASSAULT_SEVERITY_BASE + done.damage_dealt * ASSAULT_SEVERITY_PER_DAMAGE, 0.5, 0.95), true,
		"attacked you in front of everyone")
	Events.player_deed.emit("fought", {"npc": primary, "result": done.result})
	return {"result": done.result, "minutes": maxi(done.rounds, 1), "hurt": not done.blows_taken.is_empty(),
		"down": down, "primary": primary}


# --- who is in it ------------------------------------------------------------------------------------

func _roll() -> float:
	if roll_source.is_valid():
		return float(roll_source.call())
	return _rng.stream("combat").randf()


## Everyone awake at this place, by what the simulation says.
func _people_here() -> Array[String]:
	var out: Array[String] = []
	var ids: Array = _npcs.living_ids()
	ids.sort()
	for npc_id: String in ids:
		var npc := _npcs.get_npc(npc_id)
		if npc.location == _location and npc.activity != "sleep":
			out.append(npc_id)
	return out


func _would_step_in(other_id: String, target_id: String) -> bool:
	if _crime.officers().has(other_id):
		return true
	var feeling := _relationships.peek(other_id, target_id)
	return feeling != null and feeling.affection >= JOIN_AFFECTION


func _player_combatant() -> Dictionary:
	var stats := _player.stats
	return {
		"id": PlayerState.ID, "name": "You", "side": "player",
		"health": stats.health, "stamina": stats.stamina,
		"strength": stats.attribute("strength"), "agility": stats.attribute("agility"),
		"resolve": stats.attribute("resolve"), "skill": _player.skills.level_of("brawling"),
		"intimidation": _player.skills.level_of("intimidation"),
		"weapon": WEAPON_BONUS if _player.inventory.count_of(WEAPON_ITEM) > 0 else 0.0,
		"effectiveness": stats.effectiveness(), "defending": false, "state": "up", "traits": [],
	}


## Someone real, as a fighter: their build from who they are and what they do
## for a living, their health from how they were the last time and how long ago.
func _foe(npc: Npc, _role: String) -> Dictionary:
	var occupation := _data.get_entry("occupations", npc.occupation)
	var skills: Array = occupation.get("skills", [])
	var strength := 5 + (2 if npc.has_trait("strong") else 0) + (1 if skills.has("labour") else 0)
	var resolve := 5 + (2 if skills.has("intimidation") else 0) + (1 if npc.has_trait("steady") or npc.has_trait("by_the_book") else 0)
	var agility := 5 - (1 if npc.has_trait("poor_eyesight") or npc.has_trait("drinks_too_much") else 0) \
		- (1 if npc.has_trait("tired") else 0) + (1 if npc.has_trait("restless") else 0)
	var skill := 3 + (8 if skills.has("brawling") else 0) + (5 if skills.has("intimidation") else 0) \
		+ (3 if npc.has_trait("strong") else 0)
	var health := CombatRules.recovered(float(npc.state.get("health", 1.0)),
		_clock.total_minutes - int(npc.state.get("hurt_at", _clock.total_minutes)))
	return {
		"id": npc.id, "name": npc.name, "side": "foe", "health": health, "stamina": 1.0,
		"strength": strength, "agility": maxi(agility, 1), "resolve": resolve, "skill": skill, "intimidation": 0,
		"weapon": 0.0, "effectiveness": 1.0, "defending": false, "state": "up", "traits": npc.traits,
	}


func _items() -> Dictionary:
	var out := {}
	var owned := _player.inventory.count_of(HEAL_ITEM)
	if owned > 0:
		var heal := float(ItemRules.effects_of(_data.get_entry("items", HEAL_ITEM)).get("health", 0.0))
		if heal > 0.0:
			out[HEAL_ITEM] = {"count": owned, "heal": heal}
	return out
