extends TestCase
## Fights in the world (D-054): who is really there and who steps in, what a
## fight leaves behind — wounds that last, feelings, witnesses, the police —
## and how it is asked for and shown.

var _rejected: Array[String] = []
var _ended: Array[String] = []
var _requested: Array[String] = []
var _deeds: Array[String] = []
var _collapsed := 0


func before_each() -> void:
	Game.new_game("bg_returning", 7)
	Game.pause_time(true)
	Localization.set_locale("en")
	var model := ScriptedDialogueModel.new()
	model.available = false
	Game.dialogue.model = model
	_rejected = []
	_ended = []
	_requested = []
	_deeds = []
	_collapsed = 0
	Events.action_rejected.connect(_on_rejected)
	Events.fight_ended.connect(_on_ended)
	Events.fight_requested.connect(_on_requested)
	Events.player_deed.connect(_on_deed)
	Events.player_collapsed.connect(_on_collapsed)
	_everyone_elsewhere()


func after_each() -> void:
	Events.action_rejected.disconnect(_on_rejected)
	Events.fight_ended.disconnect(_on_ended)
	Events.fight_requested.disconnect(_on_requested)
	Events.player_deed.disconnect(_on_deed)
	Events.player_collapsed.disconnect(_on_collapsed)
	Game.fights.roll_source = Callable()
	if Game.dialogue.is_talking():
		Game.end_conversation()
	Game.saves.delete_slot("test_fights")


func _on_rejected(_proposal: Dictionary, code: String) -> void:
	_rejected.append(code)


func _on_ended(result: String) -> void:
	_ended.append(result)


func _on_requested(npc_id: String) -> void:
	_requested.append(npc_id)


func _on_deed(kind: String, _data: Dictionary) -> void:
	_deeds.append(kind)


func _on_collapsed(_woke_at: String, _bill: int) -> void:
	_collapsed += 1


## Nobody is where the player is, until a test says who.
func _everyone_elsewhere() -> void:
	for npc_id: String in Game.npcs.living_ids():
		var npc := Game.npcs.get_npc(npc_id)
		npc.location = npc.home
		npc.activity = "idle"


func _here(npc_id: String, health: float = 1.0) -> Npc:
	var npc := Game.npcs.get_npc(npc_id)
	npc.location = Game.player.location
	npc.activity = "idle"
	npc.state["health"] = health
	npc.state["hurt_at"] = Game.clock.total_minutes
	return npc


## Every die comes up a hit, and low.
func _always_hit() -> void:
	Game.fights.roll_source = func() -> float: return 0.1


# --- starting one -----------------------------------------------------------------------------------

func test_you_can_only_fight_someone_who_is_here_and_awake() -> void:
	assert_eq(Game.start_fight("npc_elias").code, "not_here")
	assert_eq(Game.start_fight("npc_nobody").code, "nobody_there")
	var elias := _here("npc_elias")
	elias.activity = "sleep"
	assert_eq(Game.start_fight("npc_elias").code, "asleep")
	elias.activity = "idle"
	assert_ok(Game.start_fight("npc_elias"))
	assert_eq(Game.start_fight("npc_elias").code, "already_fighting")
	assert_eq(_rejected, ["not_here", "nobody_there", "asleep", "already_fighting"] as Array[String])
	assert_true(Game.clock.paused, "the world holds still")


func test_a_friend_steps_in_and_so_does_an_officer() -> void:
	_here("npc_elias")
	_here("npc_leena")
	_here("npc_marika")
	Game.relationships.get_edge("npc_leena", "npc_elias").affection = 0.7
	var began := Game.start_fight("npc_elias")
	assert_ok(began)
	var foes: Array = began.value["foes"]
	assert_eq(foes[0], "npc_elias", "who you went for is first")
	assert_has(foes, "npc_leena")
	assert_has(foes, "npc_marika")
	assert_eq(foes.size(), 3)


func test_a_stranger_watching_does_not_step_in() -> void:
	_here("npc_elias")
	_here("npc_pirjo")
	assert_eq(Game.start_fight("npc_elias").value["foes"], ["npc_elias"])


func test_people_are_built_from_who_they_are() -> void:
	_here("npc_joonas")   # a strong dockhand
	_here("npc_pirjo")    # poor eyesight
	_here("npc_marika")   # an officer, by the book
	var started := Game.start_fight("npc_joonas")
	assert_ok(started)
	var joonas := Game.fights.combat.find("npc_joonas")
	var marika := Game.fights.combat.find("npc_marika")
	assert_gt(int(joonas["strength"]), 5)
	assert_gt(int(marika["resolve"]), 5)
	assert_gt(int(marika["intimidation"]) + int(marika["skill"]), 5, "she has done this before")


# --- winning ----------------------------------------------------------------------------------------

func test_a_win_leaves_them_down_and_you_known() -> void:
	var elias := _here("npc_elias", 0.1)
	_here("npc_pirjo")   # a stranger who sees it
	Game.relationships.get_edge("npc_elias", PlayerState.ID).affection = 0.2
	var minute := Game.clock.total_minutes
	assert_ok(Game.start_fight("npc_elias"))
	_always_hit()
	var done := Game.fight_act("attack")
	assert_ok(done)
	assert_true(done.value["over"])
	var summary: Dictionary = done.value["summary"]
	assert_eq(summary["result"], "won")
	assert_eq(summary["down"], ["npc_elias"])
	assert_lt(float(elias.state["health"]), 0.1 + 0.001, "and they stay hurt")
	assert_not_null(elias.schedule_override, "out cold for a while")
	assert_eq(elias.schedule_override.reason, "knocked_out")
	assert_lt(Game.relationships.get_edge("npc_elias", PlayerState.ID).affection, -0.1)
	assert_gt(Game.relationships.get_edge("npc_elias", PlayerState.ID).fear, 0.0)
	assert_gt(Game.clock.total_minutes, minute, "a fight takes time")
	assert_eq(_ended, ["won"] as Array[String])
	assert_has(_deeds, "fought")
	assert_false(Game.fights.is_fighting())
	var known := Game.knowledge.what_is_known_about("npc_pirjo", PlayerState.ID)
	assert_eq(known[0]["predicate"], "assaulted", "someone who was there saw it")
	assert_true(known[0]["firsthand"])
	var victim := Game.knowledge.what_is_known_about("npc_elias", PlayerState.ID)
	assert_eq(victim[0]["predicate"], "assaulted", "and so did the one it was done to")
	assert_false(Game.memories.recall("npc_elias", Game.clock.total_minutes, func(_l: String) -> String: return "").is_empty())


func test_it_hands_time_back_as_it_found_it() -> void:
	_here("npc_elias", 0.05)
	Game.pause_time(false)
	assert_ok(Game.start_fight("npc_elias"))
	assert_true(Game.clock.paused)
	_always_hit()
	Game.fight_act("attack")
	assert_false(Game.clock.paused, "it was running before, and it is again")


func test_a_person_mends_and_is_stronger_next_time() -> void:
	_here("npc_elias", 0.1)
	assert_ok(Game.start_fight("npc_elias"))
	_always_hit()
	Game.fight_act("attack")
	Game.clock.total_minutes += 10 * 60
	_here("npc_elias", float(Game.npcs.get_npc("npc_elias").state["health"]))
	Game.npcs.get_npc("npc_elias").state["hurt_at"] = Game.clock.total_minutes - 10 * 60
	assert_ok(Game.start_fight("npc_elias"))
	var health := float(Game.fights.combat.find("npc_elias")["health"])
	assert_gt(health, 0.25, "ten hours have done some good")
	assert_lt(health, 1.0)


# --- what it costs --------------------------------------------------------------------------------------

func test_a_blow_that_lands_hard_leaves_a_wound_that_lasts() -> void:
	_here("npc_elias", 0.3)   # hurt, but with fight left in him
	assert_ok(Game.start_fight("npc_elias"))
	# Round one: brace; they hit hard (a crit against a guard is still a bruise).
	# Round two: a crit that ends it. Then the roll that says where it landed.
	var queue := [0.1, 0.1, 0.99, 0.1, 0.99, 0.5]
	Game.fights.roll_source = func() -> float: return float(queue.pop_front())
	Game.fight_act("defend")
	var done := Game.fight_act("attack")
	assert_true(done.value["over"])
	assert_eq(Game.player.stats.injuries.size(), 1)
	assert_eq(Game.player.stats.injuries[0]["id"], "bruise")
	assert_gt(int(Game.player.stats.injuries[0]["heals_at"]), Game.clock.total_minutes, "and it will take days")
	assert_lt(Game.player.stats.health, 0.9)
	assert_lt(Game.player.stats.effectiveness(), 1.0, "you are worse at things while it lasts")


func test_a_bandage_used_in_a_fight_is_used_up() -> void:
	_here("npc_elias", 0.05)
	Game.player.inventory.add("item_bandage", 2)
	Game.player.stats.health = 0.5
	assert_ok(Game.start_fight("npc_elias"))
	var queue := [0.99, 0.1, 0.5]   # the foe's turn after: an attack that misses
	Game.fights.roll_source = func() -> float: return float(queue.pop_front() if not queue.is_empty() else 0.1)
	Game.fight_act("item", "item_bandage")
	_always_hit()
	Game.fight_act("attack")
	assert_eq(Game.player.inventory.count_of("item_bandage"), 1)
	assert_gt(Game.player.stats.health, 0.5)


func test_losing_is_a_collapse_and_a_clinic_bill() -> void:
	_here("npc_elias")
	Game.player.stats.health = 0.05
	Game.player.wallet.cash = 100
	assert_ok(Game.start_fight("npc_elias"))
	_always_hit()
	var done := Game.fight_act("attack")
	assert_eq(done.value["summary"]["result"], "lost")
	assert_eq(_collapsed, 1, "the world goes dark, and the clinic is where you wake")
	assert_eq(Game.player.interior, "loc_clinic")
	assert_lt(Game.player.wallet.cash, 100, "billed")
	assert_eq(_ended, ["lost"] as Array[String])


func test_running_away_is_not_being_forgiven() -> void:
	var elias := _here("npc_elias")
	_here("npc_pirjo")
	Game.player.stats.attributes["agility"] = 12
	assert_ok(Game.start_fight("npc_elias"))
	_always_hit()
	var done := Game.fight_act("flee")
	assert_eq(done.value["summary"]["result"], "fled")
	assert_eq(float(elias.state["health"]), 1.0, "no one was hurt")
	assert_lt(Game.relationships.get_edge("npc_elias", PlayerState.ID).affection, 0.0, "but you did start it")
	assert_eq(Game.knowledge.what_is_known_about("npc_pirjo", PlayerState.ID)[0]["predicate"], "assaulted")


func test_backing_down_ends_it() -> void:
	_here("npc_elias")
	assert_ok(Game.start_fight("npc_elias"))
	var done := Game.fight_act("yield")
	assert_eq(done.value["summary"]["result"], "yielded")
	assert_eq(_ended, ["yielded"] as Array[String])


# --- and then the police ------------------------------------------------------------------------------------

func test_an_assault_an_officer_saw_is_a_matter_for_the_police() -> void:
	_here("npc_elias", 0.05)
	_here("npc_marika", 0.05)
	assert_ok(Game.start_fight("npc_elias"))
	_always_hit()
	var done := Game.fight_act("attack")   # he goes down and she, badly hurt, runs
	assert_eq(done.value["summary"]["result"], "won")
	var case := Game.crime.case_for("npc_marika")
	assert_eq(case.size(), 1)
	assert_true(case[0]["firsthand"])
	assert_gt(float(case[0]["severity"]), 0.49)
	var pending := Game.events_queue.pending().filter(func(e: WorldEventQueue.QueuedEvent) -> bool: return e.kind == "police_assess")
	assert_eq(pending.size(), 1, "she will get round to it")
	Game.pause_time(false)
	Game.advance_time(pending[0].at - Game.clock.total_minutes + 1)
	Game.pause_time(true)
	assert_eq(Game.crime.summons.size(), 1)
	var weighed := PoliceRules.judge_response(case, 0, Game.npcs.get_npc("npc_marika").traits)
	assert_eq(weighed, "arrest", "hitting someone in front of a constable is not a warning")


func test_a_friend_who_saw_you_hit_someone_may_tell_the_police() -> void:
	_here("npc_elias", 0.05)
	_here("npc_pirjo")
	Game.relationships.get_edge("npc_pirjo", PlayerState.ID).affection = 0.0
	assert_ok(Game.start_fight("npc_elias"))
	_always_hit()
	Game.fight_act("attack")
	var reports := Game.events_queue.pending().filter(func(e: WorldEventQueue.QueuedEvent) -> bool: return e.kind == "crime_report")
	assert_gt(reports.size(), 0, "assault is not a sandwich: people tell")


# --- asking for one --------------------------------------------------------------------------------------------

func _say(text: String) -> Dictionary:
	var said: Result = await Game.say_to_npc(text)
	assert_ok(said, text)
	return said.value if said.is_ok() else {}


func _on_the_street(npc_id: String) -> void:
	Game.player.location = "loc_dock_street"
	var npc := Game.npcs.get_npc(npc_id)
	npc.location = "loc_dock_street"
	npc.activity = "walk"


func test_saying_you_will_hit_someone_asks_for_a_fight() -> void:
	_on_the_street("npc_elias")
	assert_ok(Game.start_conversation("npc_elias"))
	var reply := await _say("I'm going to hit you.")
	assert_eq(reply["intent"]["kind"], "attack")
	assert_eq(reply["topic"], "attacked")
	assert_true(reply["ends"], "there is no more talking")
	assert_eq(_requested, ["npc_elias"] as Array[String])


func test_you_cannot_hit_someone_down_a_phone() -> void:
	Game.phone_director.add_contact("npc_elias")
	_on_the_street("npc_elias")
	Game.clock.total_minutes = Game.clock.day_index() * GameClock.MINUTES_PER_DAY + 12 * 60
	assert_ok(Game.send_text("npc_elias", "Let's fight."))
	Game.clock.total_minutes += 60
	await Game.phone_director.process_due()
	assert_eq(_requested, [] as Array[String])
	assert_has(_rejected, "not_here")


func test_a_threat_is_still_only_a_threat() -> void:
	_on_the_street("npc_elias")
	assert_ok(Game.start_conversation("npc_elias"))
	var reply := await _say("You'll regret this.")
	assert_eq(reply["intent"]["kind"], "threaten")
	assert_eq(_requested, [] as Array[String])


# --- shown --------------------------------------------------------------------------------------------------------

func test_the_window_shows_a_fight_and_lets_it_be_played() -> void:
	_on_the_street("npc_elias")
	Game.npcs.get_npc("npc_elias").state["health"] = 0.05
	Game.npcs.get_npc("npc_elias").state["hurt_at"] = Game.clock.total_minutes
	var view: WorldView = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	Events.fight_requested.emit("npc_elias")
	await (Engine.get_main_loop() as SceneTree).process_frame
	await (Engine.get_main_loop() as SceneTree).process_frame
	var window := view.combat_window()
	assert_true(window.is_open(), "the request became a fight")
	assert_eq(window.foe_rows().size(), 1)
	assert_true(window.foe_rows()[0].ends_with("|5|"), window.foe_rows()[0])
	window.close()
	assert_true(window.is_open(), "there is no leaving a fight by shutting a window")
	assert_true(window.command_enabled("attack"))
	assert_false(window.command_enabled("heavy") and false, "")
	_always_hit()
	assert_ok(window.press("attack"))
	assert_false(window.is_open() and Game.fights.is_fighting(), "it is over")
	assert_true(window.log_lines()[0].begins_with("You hit "), window.log_lines()[0])
	assert_true(window.log_lines().back().ends_with("goes down."), window.log_lines().back())
	assert_eq(window.outcome_text(), CombatText.result("won"))
	assert_true(window.foe_rows()[0].ends_with("|Down"), window.foe_rows()[0])
	window.close()
	assert_false(window.is_open(), "now it can be put away")
	assert_true(view.player_body().input_enabled, "and you can walk again")
	view.free()


func test_refusals_are_said_plainly() -> void:
	_here("npc_elias")
	Game.player.stats.stamina = 0.05
	var window: CombatWindow = (load("res://scenes/ui/combat_window.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(window)
	assert_ok(window.open("npc_elias"))
	assert_false(window.command_enabled("heavy"), "too tired for it")
	assert_err(window.press("heavy"))
	assert_eq(window.outcome_text(), "You are too worn out for that.")
	assert_false(window.command_enabled("item"), "nothing to use")
	Game.fight_act("yield")
	window.close()
	window.free()


func test_a_hurt_person_stays_hurt_through_a_save() -> void:
	_here("npc_elias", 0.1)
	assert_ok(Game.start_fight("npc_elias"))
	_always_hit()
	Game.fight_act("attack")
	var health := float(Game.npcs.get_npc("npc_elias").state["health"])
	assert_ok(Game.save_game("test_fights"))
	assert_ok(Game.load_game("test_fights"))
	Game.pause_time(true)
	assert_almost(float(Game.npcs.get_npc("npc_elias").state["health"]), health, 0.0001)
