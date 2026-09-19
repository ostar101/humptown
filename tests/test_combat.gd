extends TestCase
## The arithmetic and the state machine of a fight (D-054): who hits, how
## hard, what a turn looks like, and how a fight ends — with every die
## scripted, so nothing here depends on luck.


func _c(combatant_id: String, side: String, overrides: Dictionary = {}) -> Dictionary:
	var c := {
		"id": combatant_id, "name": combatant_id, "side": side, "health": 1.0, "stamina": 1.0,
		"strength": 5, "agility": 5, "resolve": 5, "skill": 5, "intimidation": 0, "weapon": 0.0,
		"effectiveness": 1.0, "defending": false, "state": "up", "traits": [],
	}
	c.merge(overrides, true)
	return c


## Dice that come out as told, in order, and run out loudly.
func _dice(values: Array) -> Callable:
	var queue := values.duplicate()
	return func() -> float:
		if queue.is_empty():
			assert_true(false, "the fight asked for more dice than were scripted")
			return 0.5
		return float(queue.pop_front())


func _fight(player: Dictionary, foes: Array[Dictionary], dice: Array, items: Dictionary = {}) -> Combat:
	return Combat.new(player, foes, _dice(dice), items)


# --- the arithmetic ---------------------------------------------------------------------------------

func test_the_chance_to_hit_is_skill_and_agility_against_theirs() -> void:
	var me := _c("me", "player")
	var them := _c("them", "foe")
	var even := CombatRules.hit_chance(me, them)
	assert_almost(even, CombatRules.BASE_HIT, 0.0001)
	assert_gt(CombatRules.hit_chance(_c("me", "player", {"skill": 40}), them), even, "practice tells")
	assert_gt(CombatRules.hit_chance(_c("me", "player", {"agility": 9}), them), even, "quickness tells")
	assert_lt(CombatRules.hit_chance(me, _c("them", "foe", {"defending": true})), even, "a guard is hard to get past")
	assert_lt(CombatRules.hit_chance(me, them, true), even, "a heavy blow is easier to see coming")
	assert_lt(CombatRules.hit_chance(_c("me", "player", {"stamina": 0.1}), them), even, "tired arms")
	assert_lt(CombatRules.hit_chance(_c("me", "player", {"effectiveness": 0.6}), them), even, "a hurt or drunk person")
	assert_eq(CombatRules.hit_chance(_c("me", "player", {"skill": 99, "agility": 12}), _c("x", "foe", {"skill": 1, "agility": 1})), 0.95, "never a sure thing")
	assert_eq(CombatRules.hit_chance(_c("me", "player", {"skill": 1, "agility": 1, "stamina": 0.0}), _c("x", "foe", {"skill": 99, "agility": 12, "defending": true})), 0.10, "never hopeless")


func test_a_blow_takes_off_what_strength_and_the_moment_allow() -> void:
	var me := _c("me", "player")
	var them := _c("them", "foe")
	var plain := CombatRules.damage(me, them, false, 0.94)   # the best blow that is not a crit
	assert_almost(plain, CombatRules.BASE_DAMAGE * lerpf(CombatRules.SPREAD_LOW, 1.0, 0.94), 0.0001)
	assert_lt(CombatRules.damage(me, them, false, 0.0), plain, "a glancing blow")
	assert_gt(CombatRules.damage(_c("me", "player", {"strength": 10}), them, false, 0.94), plain)
	assert_gt(CombatRules.damage(_c("me", "player", {"weapon": 0.06}), them, false, 0.94), plain, "a crowbar helps")
	assert_almost(CombatRules.damage(me, them, true, 0.9), CombatRules.damage(me, them, false, 0.9) * CombatRules.HEAVY_FACTOR, 0.0001)
	assert_almost(CombatRules.damage(me, _c("them", "foe", {"defending": true}), false, 0.9), CombatRules.damage(me, them, false, 0.9) * CombatRules.DEFENDING_FACTOR, 0.0001)
	assert_true(CombatRules.is_crit(0.99))
	assert_false(CombatRules.is_crit(0.5))
	assert_gt(CombatRules.damage(me, them, false, 0.99), plain, "a crit is worse than the best ordinary blow")


func test_running_and_scaring_people_off() -> void:
	var me := _c("me", "player")
	assert_gt(CombatRules.flee_chance(me, 3), CombatRules.flee_chance(me, 9), "easier to outrun the slow")
	assert_gt(CombatRules.flee_chance(me, 5), 0.4)
	assert_eq(CombatRules.flee_chance(_c("me", "player", {"agility": 30}), 1), 0.90)
	var steady := _c("t", "foe", {"resolve": 8})
	var shaky := _c("t", "foe", {"resolve": 3})
	assert_gt(CombatRules.intimidate_chance(40, shaky), CombatRules.intimidate_chance(40, steady))
	assert_gt(CombatRules.intimidate_chance(10, _c("t", "foe", {"resolve": 6, "health": 0.2})), CombatRules.intimidate_chance(10, _c("t", "foe", {"resolve": 6, "health": 1.0})), "a hurt person is easier to cow")
	assert_eq(CombatRules.intimidate_chance(0, steady), 0.05, "no skill, no hope, but not none")


func test_what_a_blow_leaves_behind() -> void:
	assert_eq(CombatRules.injury_from(0.10, 0.5), {}, "a knock that will not last")
	assert_eq(CombatRules.injury_from(0.20, 0.1)["id"], "bruise")
	assert_eq(CombatRules.injury_from(0.20, 0.1)["part"], "arm")
	assert_eq(CombatRules.injury_from(0.20, 0.9)["part"], "torso")
	assert_eq(CombatRules.injury_from(0.30, 0.5)["id"], "cracked_rib")
	assert_gt(int(CombatRules.injury_from(0.30, 0.5)["days"]), int(CombatRules.injury_from(0.20, 0.5)["days"]), "it takes longer to mend")


func test_people_choose_what_to_do_from_how_they_are_and_who_they_are() -> void:
	var fresh := _c("t", "foe")
	assert_eq(CombatRules.npc_action(fresh, 0.3), "attack")
	assert_eq(CombatRules.npc_action(fresh, 0.9), "defend")
	assert_eq(CombatRules.npc_action(_c("t", "foe", {"strength": 8}), 0.7), "heavy", "a strong one swings hard")
	assert_eq(CombatRules.npc_action(_c("t", "foe", {"strength": 8, "stamina": 0.1}), 0.7), "defend", "too worn out to")
	var beaten := _c("t", "foe", {"health": 0.2})
	assert_eq(CombatRules.npc_action(beaten, 0.05), "flee", "someone who is losing may run")
	assert_eq(CombatRules.npc_action(beaten, 0.45), "yield", "or give in")
	assert_eq(CombatRules.npc_action(beaten, 0.7), "attack", "or fight on")
	assert_eq(CombatRules.npc_action(_c("t", "foe", {"health": 0.2, "resolve": 10}), 0.45), "attack", "a resolute one does not give in")
	assert_almost(CombatRules.recovered(0.2, 600), 0.5, 0.0001, "ten hours mends a little")
	assert_eq(CombatRules.recovered(0.9, 6000), 1.0)
	assert_eq(CombatRules.recovered(0.4, -5), 0.4)


# --- the fight ---------------------------------------------------------------------------------------

func test_a_round_is_the_players_move_then_everyone_elses() -> void:
	# player: hit roll, spread — foe: action roll, hit roll, spread
	var fight := _fight(_c("player", "player"), [_c("them", "foe")], [0.1, 0.5, 0.3, 0.1, 0.5])
	var acted := fight.player_act("attack")
	assert_ok(acted)
	assert_eq(fight.rounds, 1)
	var kinds: Array[String] = []
	for entry in fight.entries:
		kinds.append("%s:%s" % [entry["kind"], entry["actor"]])
	assert_eq(kinds, ["hit:player", "hit:them"] as Array[String])
	assert_lt(float(fight.find("them")["health"]), 1.0)
	assert_lt(float(fight.player()["health"]), 1.0)
	assert_gt(fight.damage_dealt, 0.0)
	assert_eq(fight.blows_taken.size(), 1)
	assert_false(fight.is_over())


func test_a_miss_is_a_miss() -> void:
	var fight := _fight(_c("player", "player"), [_c("them", "foe")], [0.99, 0.3, 0.99])
	fight.player_act("attack")
	assert_eq(fight.entries[0]["kind"], "miss")
	assert_eq(float(fight.find("them")["health"]), 1.0)
	assert_eq(fight.entries[1]["kind"], "miss")
	assert_eq(float(fight.player()["health"]), 1.0)


func test_bracing_makes_a_blow_hurt_less() -> void:
	var braced := _fight(_c("player", "player"), [_c("them", "foe")], [0.3, 0.1, 0.5])
	braced.player_act("defend")
	# The same blow from the foe against an unbraced player:
	var unguarded := _fight(_c("player", "player"), [_c("them", "foe")], [0.99, 0.3, 0.1, 0.5])
	unguarded.player_act("attack")
	assert_lt(1.0 - float(braced.player()["health"]), 1.0 - float(unguarded.player()["health"]), "a guard takes the edge off")
	assert_eq(braced.entries[0]["kind"], "defend")
	assert_true(bool(braced.player()["defending"]), "and holds until they next move")
	assert_gt(float(braced.player()["stamina"]), 0.99, "and gets a breath")


func test_the_last_foe_down_is_a_win_and_nobody_hits_back() -> void:
	var fight := _fight(_c("player", "player"), [_c("them", "foe", {"health": 0.05})], [0.1, 0.5])
	fight.player_act("attack")
	assert_eq(fight.result, "won")
	assert_eq(fight.find("them")["state"], "down")
	assert_eq(fight.entries.size(), 2, "a hit and the fall — they did not get a turn")
	assert_eq(fight.entries[1]["kind"], "down")
	assert_true(fight.is_over())
	assert_eq(fight.player_act("attack").code, "fight_over")


func test_being_beaten_is_losing() -> void:
	var fight := _fight(_c("player", "player", {"health": 0.05}), [_c("them", "foe")], [0.99, 0.3, 0.1, 0.5])
	fight.player_act("attack")
	assert_eq(fight.result, "lost")
	assert_eq(fight.player()["state"], "down")
	assert_true(float(fight.player()["health"]) <= 0.0)


func test_running_away_works_or_it_does_not() -> void:
	var quick := _fight(_c("player", "player", {"agility": 9}), [_c("them", "foe")], [0.1])
	quick.player_act("flee")
	assert_eq(quick.result, "fled")
	assert_eq(quick.entries.size(), 1, "they do not get a swing at your back")
	var caught := _fight(_c("player", "player"), [_c("them", "foe")], [0.99, 0.3, 0.99])
	caught.player_act("flee")
	assert_false(caught.is_over())
	assert_eq(caught.entries[0]["kind"], "cannot_flee")
	assert_eq(caught.entries[1]["kind"], "miss", "and they get their turn")


func test_backing_down_ends_it() -> void:
	var fight := _fight(_c("player", "player"), [_c("them", "foe")], [])
	assert_ok(fight.player_act("yield"))
	assert_eq(fight.result, "yielded")


func test_a_hard_look_can_end_it_without_a_blow() -> void:
	var fight := _fight(_c("player", "player", {"intimidation": 60}), [_c("them", "foe", {"resolve": 3})], [0.01])
	fight.player_act("intimidate")
	assert_eq(fight.result, "won")
	assert_eq(fight.find("them")["state"], "yielded")
	var unmoved := _fight(_c("player", "player", {"intimidation": 1}), [_c("them", "foe", {"resolve": 9})], [0.99, 0.3, 0.99])
	unmoved.player_act("intimidate")
	assert_eq(unmoved.entries[0]["kind"], "unmoved")
	assert_false(unmoved.is_over())


func test_a_bandage_mends_and_is_used_up() -> void:
	var items := {"item_bandage": {"count": 1, "heal": 0.2}}
	var fight := _fight(_c("player", "player", {"health": 0.5}), [_c("them", "foe")], [0.99, 0.3, 0.99], items)
	assert_ok(fight.player_act("item", "item_bandage"))
	assert_almost(float(fight.player()["health"]), 0.7, 0.0001)
	assert_eq(fight.items_used, {"item_bandage": 1})
	assert_eq(fight.player_act("item", "item_bandage").code, "no_such_item", "that was the only one")
	var well := _fight(_c("player", "player"), [_c("them", "foe")], [], items)
	assert_eq(well.player_act("item", "item_bandage").code, "not_hurt")
	assert_eq(well.player_act("item", "item_nothing").code, "no_such_item")


func test_a_move_that_cannot_be_made_is_refused_and_costs_no_turn() -> void:
	var fight := _fight(_c("player", "player", {"stamina": 0.1}), [_c("them", "foe")], [])
	assert_eq(fight.player_act("heavy").code, "too_tired")
	assert_eq(fight.player_act("dance").code, "unknown_action")
	assert_eq(fight.player_act("attack", "nobody").code, "no_target")
	assert_eq(fight.rounds, 0, "and no one took a turn")
	assert_eq(fight.entries.size(), 0)
	var moves := {}
	for option in fight.available():
		moves[option["action"]] = option["ok"]
	assert_false(moves["heavy"])
	assert_false(moves["item"])
	assert_false(moves["intimidate"], "no skill at it")
	assert_true(moves["attack"] and moves["defend"] and moves["flee"] and moves["yield"])


func test_more_than_one_foe_and_who_you_aim_at() -> void:
	var fight := _fight(_c("player", "player"), [_c("a", "foe"), _c("b", "foe")],
		[0.1, 0.5, 0.3, 0.99, 0.3, 0.99])
	fight.player_act("attack", "b")
	assert_lt(float(fight.find("b")["health"]), 1.0)
	assert_eq(float(fight.find("a")["health"]), 1.0, "aimed at the second")
	var actors: Array[String] = []
	for entry in fight.entries:
		actors.append(str(entry["actor"]))
	assert_eq(actors, ["player", "a", "b"] as Array[String], "and each of them gets a turn")
	assert_eq(fight.foes_up().size(), 2)


func test_a_fight_goes_the_same_way_with_the_same_dice() -> void:
	var dice := [0.1, 0.5, 0.3, 0.6, 0.5, 0.7, 0.2, 0.4, 0.9, 0.1, 0.5, 0.3]
	var first := _fight(_c("player", "player"), [_c("them", "foe")], dice)
	var second := _fight(_c("player", "player"), [_c("them", "foe")], dice)
	for fight in [first, second]:
		fight.player_act("attack")
		fight.player_act("defend")
	assert_eq(first.entries, second.entries)
	assert_eq(first.player()["health"], second.player()["health"])
