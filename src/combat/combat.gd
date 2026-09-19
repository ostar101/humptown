class_name Combat
extends RefCounted
## One fight, from the first blow to the last (D-054). A state machine over
## `CombatRules`: the player chooses, then everyone else takes their turn, a
## round at a time, until one side is finished or the player gets away or
## gives in. It holds numbers and a log and touches nothing else — what a fight
## costs and leaves behind is worked out from its result by `FightDirector`.
##
## The dice come from a callable (`() -> float`, 0..1) so the game feeds it the
## seeded stream and a test feeds it a script; each is used in a fixed order.
##
## Log entries are structured, for `CombatText` to say in the player's language:
## {"kind": "hit" | "heavy_hit" | "miss" | "defend" | "intimidate" | "unmoved" |
## "item" | "flee" | "cannot_flee" | "yield" | "down" | "foe_flee" | "foe_yield",
## "actor", "target", "damage"}.

## "" while it goes on; then "won" | "lost" | "fled" | "yielded".
var result := ""
var rounds := 0
var entries: Array[Dictionary] = []
var combatants: Array[Dictionary] = []
## Health the player took from each blow, in order, for wounds that last.
var blows_taken: Array[float] = []
## How much damage the player did, and to whom.
var damage_dealt := 0.0
## item id -> {"count", "heal"}: what the player may use mid-fight.
var items: Dictionary = {}
var items_used: Dictionary = {}

var _roll: Callable


func _init(p_player: Dictionary, p_foes: Array[Dictionary], roll: Callable, p_items: Dictionary = {}) -> void:
	combatants.append(p_player)
	combatants.append_array(p_foes)
	_roll = roll
	items = p_items.duplicate(true)


func is_over() -> bool:
	return result != ""


func player() -> Dictionary:
	return combatants[0]


func foes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(1, combatants.size()):
		out.append(combatants[i])
	return out


## Foes still on their feet and in the fight.
func foes_up() -> Array[Dictionary]:
	return foes().filter(func(c: Dictionary) -> bool: return c["state"] == "up")


func find(combatant_id: String) -> Dictionary:
	for c in combatants:
		if c["id"] == combatant_id:
			return c
	return {}


## What the player may do right now and why not, for the window: each is
## {"action", "ok": bool, "why": String}.
func available() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me := player()
	for action in CombatRules.ACTIONS:
		var why := ""
		match action:
			"heavy":
				if float(me["stamina"]) < CombatRules.STAMINA_HEAVY:
					why = "too_tired"
			"intimidate":
				if int(me["intimidation"]) < 1:
					why = "no_skill"
			"item":
				why = "no_such_item" if _usable_items().is_empty() else ""
		out.append({"action": action, "ok": why == "", "why": why})
	return out


## The player's turn. `arg` is a target id (for attack, heavy, intimidate) or an
## item id (for item); empty for the first foe standing. Refused: `fight_over`,
## `unknown_action`, `no_target`, `too_tired`, `no_such_item`, `not_hurt`. Then
## everyone else takes their turn.
func player_act(action: String, arg: String = "") -> Result:
	if is_over():
		return Result.failure("fight_over")
	if not CombatRules.ACTIONS.has(action):
		return Result.failure("unknown_action")
	var me := player()
	var target := _target(arg)
	match action:
		"attack", "heavy", "intimidate":
			if target.is_empty():
				return Result.failure("no_target")
			if action == "heavy" and float(me["stamina"]) < CombatRules.STAMINA_HEAVY:
				return Result.failure("too_tired")
		"item":
			if not items.has(arg) or int(items[arg]["count"]) < 1:
				return Result.failure("no_such_item")
			if float(me["health"]) >= 1.0:
				return Result.failure("not_hurt")
	me["defending"] = false
	match action:
		"attack":
			_strike(me, target, false)
		"heavy":
			_strike(me, target, true)
		"defend":
			me["defending"] = true
			me["stamina"] = minf(float(me["stamina"]) - CombatRules.stamina_cost("defend"), 1.0)
			entries.append({"kind": "defend", "actor": me["id"]})
		"intimidate":
			_intimidate(me, target)
		"item":
			var heal := float(items[arg]["heal"])
			items[arg]["count"] = int(items[arg]["count"]) - 1
			items_used[arg] = int(items_used.get(arg, 0)) + 1
			me["health"] = minf(float(me["health"]) + heal, 1.0)
			entries.append({"kind": "item", "actor": me["id"], "damage": heal})
		"flee":
			var quickest := 0
			for foe in foes_up():
				quickest = maxi(quickest, int(foe["agility"]))
			if float(_roll.call()) < CombatRules.flee_chance(me, quickest):
				entries.append({"kind": "flee", "actor": me["id"]})
				result = "fled"
			else:
				entries.append({"kind": "cannot_flee", "actor": me["id"]})
		"yield":
			entries.append({"kind": "yield", "actor": me["id"]})
			result = "yielded"
	_check_end()
	if not is_over():
		_foes_act()
		_check_end()
	rounds += 1
	return Result.success({"round": rounds})


# --- internals ---------------------------------------------------------------------------------------

func _target(arg: String) -> Dictionary:
	if arg != "":
		var chosen := find(arg)
		return chosen if not chosen.is_empty() and chosen["state"] == "up" and chosen["side"] == "foe" else {}
	var standing := foes_up()
	return standing[0] if not standing.is_empty() else {}


func _usable_items() -> Array[String]:
	var out: Array[String] = []
	for item_id: String in items:
		if int(items[item_id]["count"]) > 0 and float(player()["health"]) < 1.0:
			out.append(item_id)
	return out


func _strike(attacker: Dictionary, defender: Dictionary, heavy: bool) -> void:
	attacker["stamina"] = clampf(float(attacker["stamina"]) - CombatRules.stamina_cost("heavy" if heavy else "attack"), 0.0, 1.0)
	if float(_roll.call()) >= CombatRules.hit_chance(attacker, defender, heavy):
		entries.append({"kind": "miss", "actor": attacker["id"], "target": defender["id"]})
		return
	var spread := float(_roll.call())
	var dealt := CombatRules.damage(attacker, defender, heavy, spread)
	defender["health"] = maxf(float(defender["health"]) - dealt, 0.0)
	entries.append({"kind": "heavy_hit" if heavy else "hit", "actor": attacker["id"], "target": defender["id"], "damage": dealt})
	if attacker["side"] == "player":
		damage_dealt += dealt
	else:
		blows_taken.append(dealt)
	if float(defender["health"]) <= 0.0:
		defender["state"] = "down"
		entries.append({"kind": "down", "target": defender["id"]})


func _intimidate(me: Dictionary, target: Dictionary) -> void:
	me["stamina"] = clampf(float(me["stamina"]) - CombatRules.stamina_cost("intimidate"), 0.0, 1.0)
	if float(_roll.call()) < CombatRules.intimidate_chance(int(me["intimidation"]), target):
		target["state"] = "yielded"
		entries.append({"kind": "intimidate", "actor": me["id"], "target": target["id"]})
	else:
		entries.append({"kind": "unmoved", "actor": me["id"], "target": target["id"]})


func _foes_act() -> void:
	for foe in foes_up():
		foe["defending"] = false
		var action := CombatRules.npc_action(foe, float(_roll.call()))
		match action:
			"flee":
				foe["state"] = "fled"
				entries.append({"kind": "foe_flee", "actor": foe["id"]})
			"yield":
				foe["state"] = "yielded"
				entries.append({"kind": "foe_yield", "actor": foe["id"]})
			"defend":
				foe["defending"] = true
				foe["stamina"] = minf(float(foe["stamina"]) - CombatRules.stamina_cost("defend"), 1.0)
				entries.append({"kind": "defend", "actor": foe["id"]})
			_:
				_strike(foe, player(), action == "heavy")
		if float(player()["health"]) <= 0.0:
			break


func _check_end() -> void:
	if is_over():
		return
	if float(player()["health"]) <= 0.0:
		player()["state"] = "down"
		result = "lost"
	elif foes_up().is_empty():
		result = "won"
