extends Node
## Composition root. Autoload singleton: Game
##
## Owns every simulation system and wires them together. Systems do not
## reach for each other through this node during play — they were handed
## what they need at setup and talk through Events afterwards — but having a
## single place where the world is assembled, saved and torn down is what
## keeps the dependency graph honest.
##
## This node also enforces the central architectural rule: the execution
## layer (here and the systems below) is the only thing that mutates world
## state. Presentation reads. The LLM proposes.

signal world_ready()
signal world_unloaded()

# --- systems ----------------------------------------------------------------
var data := DataRegistry.new()
var world := WorldState.new()
var npcs := NpcRegistry.new()
var director := NpcDirector.new()
var events_queue := WorldEventQueue.new()
var clock: GameClock = null
var relationships := RelationshipGraph.new()
var knowledge := KnowledgeNetwork.new()
var memories := MemoryBook.new()
var shops := ShopRegistry.new()
var work := Employment.new()
var quests := QuestLog.new()
var phone := PhoneState.new()
var phone_director := PhoneDirector.new()
var calendar := Calendar.new()
var meetings := MeetingDirector.new()
var crime := CrimeDirector.new()
var asks := AskDirector.new()
var fights := FightDirector.new()
var consequences := ConsequenceDirector.new()
var reputation := Reputation.new()
var player := PlayerState.new()
var saves := SaveManager.new()
var rng := RngStreams.new()
var llm: LlmClient = null
var dialogue := DialogueDirector.new()

var running: bool = false
## Directory tier reassignment cadence, in game minutes. Cheap, but not free.
const RETIER_INTERVAL := 5
## Minute of the day the player wakes after sleeping.
const WAKE_MINUTE := 7 * 60
## Above this much rest the player is not tired enough to sleep.
const SLEEP_THRESHOLD := 0.75

## The one save a life has in M2 (D-033). Sleeping in your own bed writes it —
## the save point is a place, as D-010 asks — and the title screen's Continue
## reads it. A variable, not a constant, only so the test runner can point it
## somewhere that is not the player's real save.
var save_slot: String = "main"

var _last_retier: int = -999
## Whether the clock was already paused when a conversation began, so ending
## it restores what was there rather than always unpausing.
var _time_paused_before_talk := false
## What the player's body is doing as hours pass; "sleep" during a night.
var _player_activity := "idle"
## The shop the player is at the counter of, or "" (D-039), and how many
## purchases and sales it has seen — each is a minute, paid on leaving.
var _shopping := ""
## A collapse noticed in the middle of a clock step, carried out once the
## step is over (D-041); and a guard against collapsing inside a collapse.
var _collapse_due := false
var _collapsing := false
## A forced arrest waiting for the clock to stop moving (D-052), as a collapse waits.
var _arrest_pending: Dictionary = {}
var _time_paused_before_fight := false
var _arresting := false
## Where someone who collapses wakes, when, and what the clinic charges.
const COLLAPSE_WAKE_MINUTE := 8 * 60
const CLINIC := "loc_clinic"
const POLICE_POST := "loc_police_post"
## The morning they let you go.
const RELEASE_MINUTE := 8 * 60
const CLINIC_BILL := 60
var _shop_deals := 0
var _time_paused_before_shopping := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	llm = LlmClient.new()
	llm.name = "LlmClient"
	add_child(llm)
	Localization.setup()
	Events.player_deed.connect(_on_player_deed)
	Events.relationship_changed.connect(_on_relationship_changed)
	Events.dialogue_ended.connect(_on_dialogue_ended)
	Events.meeting_updated.connect(_on_meeting_updated)
	Events.fact_learned.connect(_on_fact_learned)
	Events.ambush.connect(_on_ambush)
	Log.min_level = int(Settings.get_value("log_level", Log.Level.INFO)) as Log.Level
	Log.info("game", "Game root ready")


func _process(delta: float) -> void:
	if not running or clock == null:
		return
	clock.tick(delta)
	_resolve_collapse()
	_resolve_arrest()


# --- lifecycle --------------------------------------------------------------

## Loads content and builds a fresh world. `background_id` selects the
## player's starting circumstances.
func new_game(background_id: String = "", world_seed: int = 0) -> Result:
	unload()

	if not data.load_all():
		return Result.failure("content_invalid", "; ".join(data.load_errors))
	var reference_problems := data.validate_references()
	if not reference_problems.is_empty():
		for problem in reference_problems:
			Log.error("data", problem)
		return Result.failure("content_invalid", "; ".join(reference_problems))

	rng.reseed(world_seed if world_seed != 0 else int(Time.get_unix_time_from_system()))

	clock = GameClock.new()
	clock.event_queue = events_queue
	clock.minutes_per_real_second = float(Settings.get_value("minutes_per_real_second", 1.0))

	world.build_from(data)
	npcs.setup(data, world)
	director.setup(npcs, world, clock)
	knowledge.setup(relationships, events_queue)
	reputation.setup(knowledge, npcs, world)
	player.setup(data)
	player.wallet.stamp = func() -> int: return clock.total_minutes if clock != null else -1
	shops.setup(data)
	quests.setup(data)

	_seed_relationships()
	_apply_background(background_id)
	_start_background_job(background_id)
	_know_where_you_work()
	_start_background_quests(background_id)
	meetings.setup(calendar, npcs, world, player, relationships, memories, events_queue, clock, data)
	crime.setup(npcs, knowledge, relationships, memories, events_queue, clock)
	asks.setup(data, relationships, quests, crime, player, clock, rng)
	fights.setup(npcs, player, relationships, crime, memories, clock, data, rng)
	consequences.setup(npcs, knowledge, relationships, crime, quests, work, phone_director, meetings, data, clock)
	phone_director.setup(phone, npcs, relationships, quests, player, clock, dialogue, meetings)
	phone_director.sync_contacts()
	dialogue.setup(npcs, world, player, relationships, knowledge, clock, data, LlmDialogueModel.new(llm), memories, work, quests, asks)
	_connect_simulation()

	# Open the starting region and place the player.
	var start_region := _starting_region()
	var start := world.get_region(start_region)
	if start != null:
		start.unlocked = true
		start.discovered = true
	world.enter_region(start_region)
	player.region = start_region
	if player.location.is_empty():
		player.location = player.home_location

	director.assign_tiers()
	running = true
	Log.info("game", "New game started", {
		"background": background_id,
		"npcs": npcs.count(),
		"region": start_region,
	})
	world_ready.emit()
	return Result.success()


## Starts a life from what the player chose on the creation screens (D-033).
## The draft is validated against the content before anything is built; a
## refused draft leaves no world behind. A new life starts at home, indoors,
## at the start of the day — the opening hands over to a person waking up in
## their own flat, not standing in the street.
func new_game_from(draft: CharacterDraft, world_seed: int = 0) -> Result:
	if not data.load_all():
		return Result.failure("content_invalid", "; ".join(data.load_errors))
	var checked := draft.validate(data)
	if checked.is_err():
		return checked
	var started := new_game(draft.background_id, world_seed)
	if started.is_err():
		return started

	player.display_name = draft.display_name.strip_edges()
	player.pronouns = draft.pronouns
	player.appearance = draft.appearance.duplicate()
	for attribute in draft.attribute_shifts:
		player.stats.attributes[attribute] = player.stats.attribute(attribute) + int(draft.attribute_shifts[attribute])
	player.on_strength_changed()

	if world.interior_for(player.home_location) != null:
		player.interior = player.home_location
		player.location = player.home_location
		player.position = Vector2.ZERO
	Log.info("game", "Character created", {"background": draft.background_id})
	return Result.success()


## Whether there is a life to continue.
func has_saved_game() -> bool:
	return saves.has_slot(save_slot)


func continue_game() -> Result:
	return load_game(save_slot)


## Tears the world down without touching settings or secrets.
func unload() -> void:
	running = false
	if clock != null:
		_disconnect_simulation()
	clock = null
	events_queue.clear()
	relationships = RelationshipGraph.new()
	knowledge = KnowledgeNetwork.new()
	memories = MemoryBook.new()
	shops = ShopRegistry.new()
	work = Employment.new()
	quests = QuestLog.new()
	phone = PhoneState.new()
	phone_director = PhoneDirector.new()
	calendar = Calendar.new()
	meetings = MeetingDirector.new()
	crime = CrimeDirector.new()
	asks = AskDirector.new()
	fights = FightDirector.new()
	consequences = ConsequenceDirector.new()
	_shopping = ""
	_shop_deals = 0
	reputation = Reputation.new()
	player = PlayerState.new()
	world = WorldState.new()
	npcs = NpcRegistry.new()
	director = NpcDirector.new()
	dialogue = DialogueDirector.new()
	_time_paused_before_talk = false
	world_unloaded.emit()


func is_running() -> bool:
	return running and clock != null


# --- time -------------------------------------------------------------------

## Batched advancement for sleep, travel and scene transitions. Resolves every
## world event that should have happened, then brings NPCs up to date in one
## step rather than replaying the interval minute by minute.
func advance_time(minutes: int) -> void:
	if clock == null or minutes <= 0:
		return
	clock.advance(minutes)
	_resolve_collapse()
	_resolve_arrest()


func pause_time(paused: bool) -> void:
	if clock != null:
		clock.paused = paused


# --- player movement --------------------------------------------------------

## Presentation reports where the player's body now stands; rules decide
## whether that is somewhere a person can be and which location it counts as.
## Called when the body crosses into a new cell, not every frame.
func move_player(world_position: Vector2) -> Result:
	var proposal := {"kind": "move_player", "x": world_position.x, "y": world_position.y}
	if not is_running():
		return _reject(proposal, "no_world")
	var map := current_map()
	if map == null:
		return _reject(proposal, "region_unmapped")
	var cell := DistrictMap.world_to_cell(world_position)
	if map.is_blocked(cell):
		return _reject(proposal, "cell_blocked")

	var destination := map.exit_at(cell)
	if not destination.is_empty():
		return _travel_to_region(proposal, destination)

	player.position = world_position
	_set_player_location(map.location_at(cell))
	return Result.success(player.location)


## Walking onto a region's exit rect steps straight into the neighbouring
## region — no button press, the way leaving a building needs one: an exit is
## the size of a border, not a single door. Refused the same way a blocked
## cell is: WorldView snaps the player back to where they stood.
func _travel_to_region(proposal: Dictionary, destination: String) -> Result:
	var region: Region = world.regions.get(destination)
	if region == null:
		return _reject(proposal, "region_unknown")
	if not region.unlocked:
		return _reject(proposal, "region_locked")
	var dest_map := world.map_for(destination)
	if dest_map == null:
		return _reject(proposal, "region_unmapped")
	player.region = destination
	player.position = DistrictMap.cell_to_world(dest_map.spawn)
	_set_player_location(dest_map.location_at(dest_map.spawn))
	return Result.success({"kind": "travelled", "region": destination})


## The map the player stands on: the inside of a building, or the region.
func current_map() -> DistrictMap:
	if player.interior.is_empty():
		return world.map_for(player.region)
	return world.interior_for(player.interior)


## Where the player's body should appear when the region is shown: the saved
## position if it is still valid ground, otherwise in front of their current
## location, otherwise the map's spawn.
func player_start_position() -> Vector2:
	var map := current_map()
	if map == null:
		return Vector2.ZERO
	if player.position != Vector2.ZERO and not map.is_blocked(DistrictMap.world_to_cell(player.position)):
		return player.position
	var anchor := map.anchor_of(player.location)
	if anchor.x >= 0 and not map.is_blocked(anchor):
		return DistrictMap.cell_to_world(anchor)
	return DistrictMap.cell_to_world(map.spawn)


func _set_player_location(now_at: String) -> void:
	if now_at == player.location:
		return
	var was_at := player.location
	player.location = now_at
	player.learn_place(now_at, "visited")
	if not was_at.is_empty():
		Events.location_exited.emit(PlayerState.ID, was_at)
	if not now_at.is_empty():
		Events.location_entered.emit(PlayerState.ID, now_at)


# --- interaction ------------------------------------------------------------

## What the player could do with whatever is on this cell of the current map,
## without doing it: {"kind", "target", ...}, or empty. Presentation asks this
## to show a prompt. Kinds: door, exit, counter, bed, sign.
func interaction_at(cell: Vector2i) -> Dictionary:
	if not is_running():
		return {}
	var map := current_map()
	if map == null:
		return {}
	if map.is_interior() and cell == map.exit_door:
		return {"kind": "exit", "target": map.interior_of}
	var building := map.building_with_door(cell)
	if not building.is_empty():
		return {"kind": "door", "target": building}
	var thing := map.object_at(cell)
	if not thing.is_empty():
		return {"kind": str(thing["kind"]), "target": str(thing["id"]), "text_key": str(thing["text_key"])}
	# Nothing on the cell, but a shift that could start right here (D-042).
	var job := job_here()
	if not job.is_empty() and judge_shift_here().is_ok():
		return {"kind": "work", "target": str(job["id"])}
	return {}


## The player uses whatever is on this cell. The cell must touch the player's
## own; what happens is decided here, from the world as it is. On success the
## value is a dictionary whose "kind" says what happened: entered, exited,
## served, slept or read.
func interact_at(cell: Vector2i) -> Result:
	var proposal := {"kind": "interact", "x": cell.x, "y": cell.y}
	if not is_running():
		return _reject(proposal, "no_world")
	var map := current_map()
	if map == null:
		return _reject(proposal, "region_unmapped")
	var offset := cell - DistrictMap.world_to_cell(player.position)
	if absi(offset.x) + absi(offset.y) != 1:
		return _reject(proposal, "out_of_reach")
	var what := interaction_at(cell)
	match str(what.get("kind", "")):
		"door":
			return _enter_building(proposal, str(what["target"]))
		"exit":
			return _leave_building(proposal)
		"counter":
			return _use_counter(proposal, map.interior_of)
		"bed":
			return _sleep_in_bed(proposal, map.interior_of)
		"sign":
			return Result.success({"kind": "read", "text_key": what["text_key"]})
		"work":
			return work_shift()
		"stash":
			if map.interior_of != player.home_location:
				return _reject(proposal, "not_your_stash")
			return Result.success({"kind": "stash", "location": map.interior_of})
		"atm":
			return Result.success({"kind": "atm", "location": map.interior_of})
	return _reject(proposal, "nothing_there")


## Who is working behind the counter of this place right now, according to
## the simulation. Empty when nobody is.
func staff_serving(location_id: String) -> String:
	for npc_id in npcs.living_ids():
		var npc := npcs.get_npc(npc_id)
		if npc.workplace == location_id and npc.location == location_id and npc.activity == "work":
			return npc_id
	return ""


func _enter_building(proposal: Dictionary, location_id: String) -> Result:
	var location := world.get_location(location_id)
	if location == null:
		return _reject(proposal, "no_such_location")
	if location_id != player.home_location:
		if location.is_locked():
			return _reject(proposal, "locked")
		if location.access == Location.Access.PRIVATE:
			return _reject(proposal, "private")
		if not location.is_open_at(clock.minute_of_day()):
			return _reject(proposal, "closed")
	var inside := world.interior_for(location_id)
	if inside == null:
		return _reject(proposal, "no_interior")
	player.interior = location_id
	player.position = DistrictMap.cell_to_world(inside.entry_cell())
	_set_player_location(location_id)
	Events.player_deed.emit("entered", {"location": location_id})
	return Result.success({"kind": "entered", "location": location_id})


func _leave_building(proposal: Dictionary) -> Result:
	var outside := world.map_for(player.region)
	if outside == null:
		return _reject(proposal, "region_unmapped")
	var left := player.interior
	var anchor := outside.anchor_of(left)
	player.interior = ""
	player.position = DistrictMap.cell_to_world(anchor)
	_set_player_location(outside.location_at(anchor))
	return Result.success({"kind": "exited", "location": left})


func _use_counter(proposal: Dictionary, location_id: String) -> Result:
	var staff := staff_serving(location_id)
	if staff.is_empty():
		return _reject(proposal, "nobody_serving")
	if crime.officers().has(staff):
		return _at_the_desk(staff)
	if location_id == CLINIC:
		return _treat_injuries(proposal, staff)
	return Result.success({"kind": "served", "npc": staff})


## Sleeps until the next WAKE_MINUTE, in one batched jump.
func _sleep_in_bed(proposal: Dictionary, location_id: String) -> Result:
	if location_id != player.home_location:
		return _reject(proposal, "not_your_bed")
	if player.stats.sleep > SLEEP_THRESHOLD:
		return _reject(proposal, "not_tired")
	var minutes := posmod(WAKE_MINUTE - clock.minute_of_day(), GameClock.MINUTES_PER_DAY)
	if minutes == 0:
		minutes = GameClock.MINUTES_PER_DAY
	_player_activity = "sleep"
	advance_time(minutes)
	_player_activity = "idle"
	# Your own bed is the save point (D-033): the one place a life is kept.
	var saved := save_game(save_slot)
	if saved.is_err():
		Log.warn("game", "Could not save after sleeping", {"reason": saved.message})
	return Result.success({"kind": "slept", "minutes": minutes, "saved": saved.is_ok()})


# --- shopping ---------------------------------------------------------------------

## Steps up to the counter of the shop the player is in (D-039). Refuses
## `not_a_shop` and `nobody_serving`. Time stands still while shopping, as it
## does while talking; each purchase or sale is a minute, paid on leaving.
func open_shop() -> Result:
	var proposal := {"kind": "shop", "location": player.interior}
	if not is_running():
		return _reject(proposal, "no_world")
	if not _shopping.is_empty():
		return _reject(proposal, "already_shopping")
	if shops.shop_at(player.interior).is_empty():
		return _reject(proposal, "not_a_shop")
	if staff_serving(player.interior).is_empty():
		return _reject(proposal, "nobody_serving")
	_shopping = player.interior
	_shop_deals = 0
	_time_paused_before_shopping = clock.paused
	clock.paused = true
	return Result.success(shop_view())


func is_shopping() -> bool:
	return not _shopping.is_empty()


## The counter as the player sees it: {"shop", "location", "staff", "cash",
## "bank", "for_sale": [{item, name_key, price, stock}], "will_buy": [{item,
## name_key, price, owned}]}. Empty when not shopping.
func shop_view() -> Dictionary:
	if _shopping.is_empty():
		return {}
	var shop_id := shops.shop_at(_shopping)
	var for_sale: Array[Dictionary] = []
	for item_id in shops.items_for_sale(shop_id):
		var deal: Dictionary = shops.haggled(shop_id).get(item_id, {})
		for_sale.append({
			"item": item_id, "name_key": str(data.get_entry("items", item_id).get("name_key", item_id)),
			"price": shops.buy_price(shop_id, item_id), "stock": shops.stock_of(shop_id, item_id),
			"haggled": not deal.is_empty(), "discount": shops.discount(shop_id, item_id),
		})
	var will_buy: Array[Dictionary] = []
	for item_id in player.inventory.item_ids():
		if shops.buys(shop_id, item_id):
			will_buy.append({
				"item": item_id, "name_key": str(data.get_entry("items", item_id).get("name_key", item_id)),
				"price": shops.sell_price(shop_id, item_id), "owned": player.inventory.count_of(item_id),
			})
	return {
		"shop": shop_id, "location": _shopping, "staff": staff_serving(_shopping),
		"cash": player.wallet.cash, "bank": player.wallet.bank,
		"for_sale": for_sale, "will_buy": will_buy,
	}


## Buys from the shop the player is at. Pays cash first, then by card.
func buy(item_id: String, quantity: int = 1) -> Result:
	var proposal := {"kind": "buy", "item": item_id, "quantity": quantity, "location": _shopping}
	if _shopping.is_empty():
		return _reject(proposal, "not_shopping")
	var shop_id := shops.shop_at(_shopping)
	var judged := ShopRules.judge_buy({
		"serving": not staff_serving(_shopping).is_empty(),
		"sells": shops.sells(shop_id, item_id),
		"stock": shops.stock_of(shop_id, item_id),
		"quantity": quantity,
		"price": shops.buy_price(shop_id, item_id),
		"money": player.wallet.total(),
		"free_weight": player.inventory.free_weight(),
		"weight": player.inventory.item_weight(item_id),
	})
	if judged.is_err():
		return _reject(proposal, judged.code)
	var total := int(judged.value["total"])
	player.wallet.spend(total, "buy:" + item_id)
	player.inventory.add(item_id, quantity)
	shops.sold(shop_id, item_id, quantity, total)
	_shop_deals += 1
	Events.player_deed.emit("bought", {"item": item_id, "shop": shop_id, "quantity": quantity})
	return Result.success({"kind": "bought", "item": item_id, "quantity": quantity, "total": total})


## Tries to talk the price of an item down (D-040): the player's haggling
## skill against the shopkeeper's, moved by how they feel about the player,
## rolled on the game's seeded stream. Won: that item is cheaper here for
## the rest of the day. Lost: they are a little put out, and will not haggle
## over it again until tomorrow. Either way the skill learns. Refuses
## `not_shopping`, `nobody_serving`, `not_sold_here`, `already_haggled`.
func haggle(item_id: String) -> Result:
	var proposal := {"kind": "haggle", "item": item_id, "location": _shopping}
	if _shopping.is_empty():
		return _reject(proposal, "not_shopping")
	var shop_id := shops.shop_at(_shopping)
	var staff := staff_serving(_shopping)
	var keeper := npcs.get_npc(staff)
	var against := HaggleRules.difficulty(
		data.get_entry("occupations", keeper.occupation).get("skills", []) if keeper != null else [],
		keeper.traits if keeper != null else [])
	var odds := HaggleRules.chance(player.skills.level_of("haggling"), against,
		relationships.disposition(staff, PlayerState.ID) if keeper != null else 0.0,
		player.stats.effectiveness())
	var judged := HaggleRules.judge({
		"serving": keeper != null,
		"sells": shops.sells(shop_id, item_id),
		"tried": shops.haggled(shop_id).has(item_id),
		"chance": odds,
		"roll": rng.stream("haggle").randf(),
	})
	if judged.is_err():
		return _reject(proposal, judged.code)
	var outcome: Dictionary = judged.value
	var won := bool(outcome["won"])
	shops.record_haggle(shop_id, item_id, won, float(outcome["discount"]))
	if not won:
		relationships.adjust(staff, PlayerState.ID, "affection", HaggleRules.SOURED_AFFECTION, clock.total_minutes)
	player.skills.practise("haggling", HaggleRules.XP_WON if won else HaggleRules.XP_LOST, against)
	_shop_deals += 1
	return Result.success({
		"kind": "haggled", "item": item_id, "won": won, "discount": float(outcome["discount"]),
		"price": shops.buy_price(shop_id, item_id), "chance": odds, "staff": staff,
	})


## Tries to walk off with something without paying (D-051). Everyone present
## might notice — someone on duty who does stops it and the item stays; anyone
## else who does lets it happen and remembers. Nobody noticing leaves no trace.
## The dice are the game's seeded ones. Refuses `not_shopping`,
## `nobody_serving`, `not_sold_here`, `out_of_stock`, `too_heavy`.
func steal(item_id: String) -> Result:
	var proposal := {"kind": "steal", "item": item_id, "location": _shopping}
	if _shopping.is_empty():
		return _reject(proposal, "not_shopping")
	var shop_id := shops.shop_at(_shopping)
	var staff := staff_serving(_shopping)
	var watchers := crime.watchers(_shopping, staff, player.skills.level_of("stealth"), player.stats.effectiveness())
	for watcher in watchers:
		watcher["roll"] = rng.stream("theft").randf()
	var judged := TheftRules.judge({
		"serving": not staff.is_empty(), "sells": shops.sells(shop_id, item_id),
		"stock": shops.stock_of(shop_id, item_id), "weight": player.inventory.item_weight(item_id),
		"free_weight": player.inventory.free_weight(), "watchers": watchers,
	})
	if judged.is_err():
		return _reject(proposal, judged.code)
	var outcome: Dictionary = judged.value
	var noticed: Array[String] = []
	noticed.assign(outcome["noticed_by"])
	if bool(outcome["taken"]):
		player.inventory.add(item_id, 1)
		shops.sold(shop_id, item_id, 1, 0)
	player.skills.practise("stealth", TheftRules.xp(bool(outcome["caught"]), not noticed.is_empty()), TheftRules.SKILL_DIFFICULTY)
	crime.record_theft(_shopping, staff, noticed, TheftRules.severity(int(data.get_entry("items", item_id).get("value", 0))),
		bool(outcome["caught"]))
	_shop_deals += 1
	Events.player_deed.emit("stole", {"item": item_id, "shop": shop_id, "caught": bool(outcome["caught"])})
	return Result.success({"kind": "stole", "item": item_id, "taken": bool(outcome["taken"]),
		"caught": bool(outcome["caught"]), "staff": staff})


## Sells to the shop the player is at, for cash from its till.
func sell(item_id: String, quantity: int = 1) -> Result:
	var proposal := {"kind": "sell", "item": item_id, "quantity": quantity, "location": _shopping}
	if _shopping.is_empty():
		return _reject(proposal, "not_shopping")
	var shop_id := shops.shop_at(_shopping)
	var judged := ShopRules.judge_sell({
		"serving": not staff_serving(_shopping).is_empty(),
		"buys": shops.buys(shop_id, item_id),
		"owned": player.inventory.count_of(item_id),
		"quantity": quantity,
		"price": shops.sell_price(shop_id, item_id),
		"till": shops.till(shop_id),
	})
	if judged.is_err():
		return _reject(proposal, judged.code)
	var total := int(judged.value["total"])
	player.inventory.remove(item_id, quantity)
	player.wallet.add_cash(total, "sell:" + item_id)
	shops.bought(shop_id, item_id, quantity, total)
	_shop_deals += 1
	return Result.success({"kind": "sold", "item": item_id, "quantity": quantity, "total": total})


## Steps away from the counter and pays the minutes it took.
func close_shop() -> Result:
	if _shopping.is_empty():
		return Result.failure("not_shopping")
	var deals := _shop_deals
	_shopping = ""
	_shop_deals = 0
	clock.paused = _time_paused_before_shopping
	advance_time(maxi(deals, 1))
	return Result.success({"deals": deals})


# --- quests ----------------------------------------------------------------------

func _start_background_quests(background_id: String) -> void:
	for quest_id in data.ids("quests"):
		var starts: Dictionary = data.get_entry("quests", quest_id).get("starts", {})
		if str(starts.get("background", "")) == background_id and background_id != "":
			if quests.start(str(quest_id), clock.day_index()):
				Events.quest_updated.emit(str(quest_id), "started")


## A deed, counted towards every active quest (D-044).
func _on_player_deed(kind: String, deed: Dictionary) -> void:
	if not is_running():
		return
	for moved in quests.on_deed(kind, deed, _feeling):
		_quest_moved(moved)


## Stages that wait on how someone feels are looked at again when a feeling
## toward the player changes.
func _on_relationship_changed(_from_id: String, to_id: String, _dimension: String, _delta: float) -> void:
	if not is_running() or to_id != PlayerState.ID or quests.active.is_empty():
		return
	for moved in quests.recheck(_feeling):
		_quest_moved(moved)


func _quest_moved(moved: Dictionary) -> void:
	var quest_id := str(moved["quest"])
	if moved["status"] == "done":
		_quest_ended(quest_id, "done")
	else:
		Events.quest_updated.emit(quest_id, str(moved["status"]))


func _quest_ended(quest_id: String, status: String) -> void:
	var quest := data.get_entry("quests", quest_id)
	_apply_quest_effects(quest.get("on_done" if status == "done" else "on_fail", []))
	Log.info("quests", "Quest ended", {"quest": quest_id, "status": status})
	Events.quest_updated.emit(quest_id, status)


## What finishing or failing a quest does, from its data: feelings, flags,
## cash, items, and facts people witness.
func _apply_quest_effects(effects: Array) -> void:
	for raw in effects:
		var effect: Dictionary = raw
		match str(effect.get("do", "")):
			"feel":
				relationships.adjust(str(effect["npc"]), PlayerState.ID, str(effect["dimension"]),
					float(effect["delta"]), clock.total_minutes)
			"flag":
				player.quest_flags[str(effect["flag"])] = bool(effect.get("value", true))
			"cash":
				player.wallet.add_cash(int(effect["amount"]), "quest")
			"item":
				player.inventory.add(str(effect["item"]), int(effect.get("count", 1)))
			"fact":
				var witnesses: Array[String] = []
				if str(effect.get("witness", "")) != "":
					witnesses.append(str(effect["witness"]))
				knowledge.observe_event(PlayerState.ID, str(effect["predicate"]), clock.total_minutes, witnesses, {
					"object": str(effect.get("object", "")), "visibility": str(effect.get("visibility", "social")),
					"severity": float(effect.get("severity", 0.5)),
				})


func _feeling(npc_id: String, dimension: String) -> float:
	var edge := relationships.peek(npc_id, PlayerState.ID)
	return edge.get_dimension(dimension) if edge != null else 0.0


# --- the phone -------------------------------------------------------------------

## Once an hour, and once after time was skipped: numbers exchanged, and
## whoever has a reason to write (D-045).
func _phone_tick() -> void:
	if not is_running():
		return
	phone_director.sync_contacts()
	phone_director.run_outreach()
	if not phone.outbox.is_empty():
		phone_director.process_due()


## Someone who waited for the player says so, later, by text (D-047).
func _on_meeting_updated(meeting_id: int, status: String) -> void:
	if status != "missed" or not is_running():
		return
	var meeting := calendar.get_meeting(meeting_id)
	if bool(meeting.get("hostile", false)):
		return   # they wanted a fight, not company
	phone_director.meeting_missed(str(meeting.get("npc", "")), str(meeting.get("location", "")))


func _on_dialogue_ended(_npc_id: String) -> void:
	if is_running():
		phone_director.sync_contacts()


func has_phone() -> bool:
	return is_running() and phone_director.has_phone()


## The player texts someone (D-046). It is read when they get to it, and
## answered as a text; a refusal here is a text that was never sent.
func send_text(npc_id: String, line: String) -> Result:
	if not is_running():
		return Result.failure("no_world")
	var sent := phone_director.send_text(npc_id, line)
	if sent.is_err():
		return _reject({"kind": "send_text", "npc": npc_id}, sent.code)
	return sent


## Opens a thread: everything in it is read.
func read_thread(npc_id: String) -> void:
	if is_running() and phone.mark_read(npc_id) > 0:
		Events.phone_read.emit(npc_id)


## The player answers a text that asks something: "accept" or "decline".
func answer_message(message_id: int, choice: String) -> Result:
	if not is_running():
		return Result.failure("no_world")
	var answered := phone_director.answer(message_id, choice)
	if answered.is_err():
		return _reject({"kind": "phone_answer", "message": message_id, "answer": choice}, answered.code)
	return answered


# --- the clinic (D-055) -----------------------------------------------------------------

## The nurse at the clinic desk sees to the player's injuries: what is left to
## heal takes a third of the time, and they are a little better for it today.
## It costs per wound, up to a limit. Refused: `nothing_to_treat`,
## `not_enough_money`.
func _treat_injuries(proposal: Dictionary, nurse: String) -> Result:
	var judged := ClinicRules.judge_treatment({
		"injuries": player.stats.injuries.size(), "health": player.stats.health, "money": player.wallet.total()})
	if judged.is_err():
		return _reject(proposal, judged.code)
	var fee := int(judged.value["fee"])
	var now := clock.total_minutes
	if fee > 0:
		player.wallet.spend(fee, "clinic")
	for injury in player.stats.injuries:
		injury["heals_at"] = now + int(float(int(injury["heals_at"]) - now) * ClinicRules.REMAINING_FRACTION)
	player.stats.modify("health", ClinicRules.HEALTH_GAINED)
	advance_time(ClinicRules.MINUTES_TAKEN)
	return Result.success({"kind": "treated", "npc": nurse, "fee": fee})


# --- fights (D-054) -----------------------------------------------------------------

## The player starts a fight with someone in front of them. A conversation
## with them is over; the world stands still until the fight is. Refused:
## `already_fighting`, `nobody_there`, `asleep`, `not_here`.
func start_fight(npc_id: String, aggressor: String = "player") -> Result:
	if not is_running():
		return Result.failure("no_world")
	var proposal := {"kind": "fight", "npc": npc_id}
	if fights.is_fighting():
		return _reject(proposal, "already_fighting")
	if dialogue.is_talking():
		end_conversation()
	if is_shopping():
		close_shop()
	var began := fights.begin(npc_id, aggressor)
	if began.is_err():
		return _reject(proposal, began.code)
	_time_paused_before_fight = clock.paused
	clock.paused = true
	return began


## The player's move. When it ends the fight, this settles it: the world moves
## on by the minutes it took, and a player who lost collapses. Returns
## {"over": bool, "summary": {…}}.
func fight_act(action: String, arg: String = "") -> Result:
	var acted := fights.act(action, arg)
	if acted.is_err():
		return _reject({"kind": "fight_act", "action": action}, acted.code)
	if not fights.combat.is_over():
		return Result.success({"over": false})
	var summary := fights.finish()
	clock.paused = _time_paused_before_fight
	if player.stats.health <= 0.0 and not _collapsing:
		_collapse_due = true
	advance_time(int(summary["minutes"]))
	Events.fight_ended.emit(str(summary["result"]))
	return Result.success({"over": true, "summary": summary})


# --- the police (D-052) -----------------------------------------------------------

## The officer has looked at what she knows and decided the player should come
## in: she sends for them.
func _police_assess(payload: Dictionary) -> void:
	var issued := crime.assess(str(payload.get("officer", "")))
	if not issued.is_empty():
		phone_director.summons(str(issued["officer"]), int(issued["due"]))


## The time to come in has passed. If the player did not, the case is weighed
## without them — and worse for it.
func _summons_due(payload: Dictionary) -> void:
	var result := crime.resolve(int(payload.get("summons", 0)), false, player.wallet.total())
	if not result.is_empty():
		_apply_police_outcome(result, true)


## The player at the police desk. If they were sent for, the case is weighed
## now, on what she knows; if not, she has nothing to say to them.
func _at_the_desk(officer_id: String) -> Result:
	var open := crime.open_summons_for(officer_id)
	if open.is_empty():
		return Result.success({"kind": "desk", "officer": officer_id, "outcome": "nothing", "fine": 0})
	var result := crime.resolve(int(open["id"]), true, player.wallet.total())
	if result.is_empty():
		return Result.success({"kind": "desk", "officer": officer_id, "outcome": "nothing", "fine": 0})
	_apply_police_outcome(result, false)
	result["kind"] = "desk"
	return Result.success(result)


## What an outcome does to the player. A warning and a fine are done at once;
## an arrest that happens while time is moving waits until it has stopped.
func _apply_police_outcome(result: Dictionary, forced: bool) -> void:
	var officer_id := str(result["officer"])
	var outcome := str(result["outcome"])
	match outcome:
		"warning":
			relationships.adjust(officer_id, PlayerState.ID, "respect", -0.03, clock.total_minutes)
		"fine":
			player.wallet.spend(int(result["fine"]), "fine")
			relationships.adjust(officer_id, PlayerState.ID, "respect", -0.05, clock.total_minutes)
		"arrest":
			if forced:
				_arrest_pending = result
			else:
				_arrest(result)
	Log.info("police", "Case weighed", {"officer": officer_id, "outcome": outcome, "forced": forced})
	Events.police_action.emit(outcome, officer_id, int(result["fine"]), forced)


func _resolve_arrest() -> void:
	if not _arrest_pending.is_empty() and not _arresting:
		var result := _arrest_pending
		_arrest_pending = {}
		_arrest(result)


## A night in the cells: the player is taken to the police post and let go in
## the morning. It is known — that is what an arrest is — and it travels.
func _arrest(result: Dictionary) -> void:
	_arresting = true
	if dialogue.is_talking():
		end_conversation()
	if is_shopping():
		close_shop()
	var officer_id := str(result["officer"])
	var post := world.interior_for(POLICE_POST)
	if post != null:
		player.interior = POLICE_POST
		player.position = DistrictMap.cell_to_world(post.entry_cell())
		_set_player_location(POLICE_POST)
	var minutes := posmod(RELEASE_MINUTE - clock.minute_of_day(), GameClock.MINUTES_PER_DAY)
	if minutes < 6 * 60:
		minutes += GameClock.MINUTES_PER_DAY
	# They feed you and let you sleep; a night in the cells is not a starvation.
	player.stats.hunger = minf(player.stats.hunger, 0.3)
	player.stats.sleep = maxf(player.stats.sleep, 0.6)
	_player_activity = "sleep"
	advance_time(minutes)
	_player_activity = "idle"
	player.stats.modify("stress", 0.25)
	var witnesses: Array[String] = [officer_id]
	knowledge.observe_event(PlayerState.ID, "arrested", clock.total_minutes, witnesses, {
		"object": officer_id, "location": POLICE_POST, "severity": 0.6, "visibility": "social"})
	relationships.adjust(officer_id, PlayerState.ID, "respect", -0.08, clock.total_minutes)
	_arresting = false
	Log.info("police", "Player arrested", {"officer": officer_id})
	Events.player_arrested.emit(officer_id, clock.total_minutes)


## Someone came for a fight they had named (D-055): that grudge has had its say.
func _on_ambush(npc_id: String) -> void:
	if is_running():
		consequences.on_ambush(npc_id)


func _on_fact_learned(knower_id: String, fact_id: String, _source_id: String) -> void:
	if is_running():
		crime.on_fact_learned(knower_id, fact_id)


# --- the cash machine -------------------------------------------------------------

## Whether the player is standing where there is a cash machine: inside a
## place that has one.
func atm_here() -> bool:
	var map := current_map()
	if not is_running() or map == null or not map.is_interior():
		return false
	for thing: Dictionary in map.objects.values():
		if thing["kind"] == "atm":
			return true
	return false


## Puts cash into the account (D-048). Refused: `not_at_atm`, `bad_amount`,
## `insufficient_cash`.
func atm_deposit(amount: int) -> Result:
	var proposal := {"kind": "deposit", "amount": amount}
	if not atm_here():
		return _reject(proposal, "not_at_atm")
	var done := player.wallet.deposit(amount)
	return done if done.is_ok() else _reject(proposal, done.code)


## Takes cash out of the account. Refused: `not_at_atm`, `bad_amount`,
## `insufficient_bank`.
func atm_withdraw(amount: int) -> Result:
	var proposal := {"kind": "withdraw", "amount": amount}
	if not atm_here():
		return _reject(proposal, "not_at_atm")
	var done := player.wallet.withdraw(amount)
	return done if done.is_ok() else _reject(proposal, done.code)


# --- home ------------------------------------------------------------------------

## Puts something away in the cupboard at home (D-043). Only at home, and only
## what the player carries and the cupboard has room for. Refuses
## `not_at_home`, `bad_quantity`, `not_owned`, `stash_full`.
func store(item_id: String, quantity: int = 1) -> Result:
	return _move_between(player.inventory, player.stash, item_id, quantity,
		{"kind": "store", "item": item_id, "quantity": quantity}, "stash_full")


## Takes something from the cupboard at home. Refuses `not_at_home`,
## `bad_quantity`, `not_owned`, `too_heavy`.
func take(item_id: String, quantity: int = 1) -> Result:
	return _move_between(player.stash, player.inventory, item_id, quantity,
		{"kind": "take", "item": item_id, "quantity": quantity}, "too_heavy")


func _move_between(from: Inventory, to: Inventory, item_id: String, quantity: int,
		proposal: Dictionary, no_room: String) -> Result:
	if not is_running() or player.interior != player.home_location or player.home_location.is_empty():
		return _reject(proposal, "not_at_home")
	if quantity < 1:
		return _reject(proposal, "bad_quantity")
	if from.count_of(item_id) < quantity:
		return _reject(proposal, "not_owned")
	if to.item_weight(item_id) * quantity > to.free_weight() + 0.0001:
		return _reject(proposal, no_room)
	var moved := from.transfer_to(to, item_id, quantity)
	if moved.is_err():
		return _reject(proposal, moved.code)
	return Result.success({"kind": str(proposal["kind"]), "item": item_id, "quantity": quantity})


# --- work ------------------------------------------------------------------------

## The job the player could work where they stand: their own, if this is its
## workplace; else casual work here, which takes anyone for the day. Empty
## when neither (D-042).
func job_here() -> Dictionary:
	if not is_running():
		return {}
	if work.has_job():
		var own := data.get_entry("jobs", work.job_id)
		if str(own.get("workplace", "")) == player.location:
			return own
	for job_id in data.ids("jobs"):
		var job := data.get_entry("jobs", job_id)
		if bool(job.get("casual", false)) and str(job.get("workplace", "")) == player.location:
			return job
	return {}


## Whether a shift could start here now, and if not why not.
func judge_shift_here() -> Result:
	var job := job_here()
	return WorkRules.judge_shift({
		"job": job,
		"employed_here": not job.is_empty() and (bool(job.get("casual", false)) or str(job["id"]) == work.job_id),
		"at_workplace": not job.is_empty(),
		"weekday": clock.weekday(),
		"minute": clock.minute_of_day(),
		"day": clock.day_index(),
		"last_worked_day": work.last_worked_day,
		"intoxication": player.stats.intoxication,
		"sleep": player.stats.sleep,
	})


## Works a shift at the job here (D-042): the rest of the shift passes in one
## step, the body pays its strain, the wage — for the part worked, scaled a
## little by how fit the player was — goes to cash or the bank, the job's
## skills learn, and the employer notes whether the player was on time.
## Refuses what `WorkRules.judge_shift` refuses.
func work_shift() -> Result:
	var proposal := {"kind": "work", "location": player.location if is_running() else ""}
	if not is_running():
		return _reject(proposal, "no_world")
	if dialogue.is_talking() or is_shopping():
		return _reject(proposal, "busy")
	var job := job_here()
	var judged := judge_shift_here()
	if judged.is_err():
		return _reject(proposal, judged.code)
	var shift: Dictionary = judged.value
	var fraction := float(shift["fraction"])
	var fitness := player.stats.effectiveness()
	var day := clock.day_index()
	_player_activity = "work"
	advance_time(int(shift["minutes"]))
	_player_activity = "idle"
	var strain: Dictionary = job.get("strain", {})
	for meter in strain:
		player.stats.modify(str(meter), float(strain[meter]) * fraction)
	var wage := WorkRules.pay(int(job.get("wage", 0)), fraction, fitness)
	var reason := "wage:" + str(job["id"])
	if str(job.get("pay_to", "cash")) == "bank":
		player.wallet.add_to_bank(wage, reason)
	else:
		player.wallet.add_cash(wage, reason)
	for skill_id in job.get("skills", []):
		player.skills.practise(str(skill_id), 25.0 * fraction, int(job.get("difficulty", 5)))
	var casual := bool(job.get("casual", false))
	work.record_shift(day, fraction >= 0.95, bool(shift["late"]), casual)
	var employer := str(job.get("employer", ""))
	if employer != "" and npcs.get_npc(employer) != null:
		relationships.adjust(employer, PlayerState.ID, "familiarity", 0.02, clock.total_minutes)
		relationships.adjust(PlayerState.ID, employer, "familiarity", 0.02, clock.total_minutes)
	Events.player_deed.emit("worked_shift", {"job": str(job["id"])})
	return Result.success({
		"kind": "worked", "job": str(job["id"]), "pay": wage, "pay_to": str(job.get("pay_to", "cash")),
		"late": shift["late"], "until": clock.format_time(),
	})


## Takes the job on (D-042), from the first shift after today.
func hire_player(job_id: String) -> Result:
	if not data.has_entry("jobs", job_id):
		return _reject({"kind": "hire", "job": job_id}, "no_such_job")
	work.hire(job_id, clock.day_index())
	player.learn_place(str(data.get_entry("jobs", job_id).get("workplace", "")), "told")
	phone_director.add_contact(str(data.get_entry("jobs", job_id).get("employer", "")))
	Events.job_changed.emit(job_id)
	Events.player_deed.emit("hired", {"job": job_id})
	return Result.success(job_id)


func quit_job() -> Result:
	if not work.has_job():
		return _reject({"kind": "quit"}, "no_job")
	work.leave()
	Events.job_changed.emit("")
	return Result.success()


## You know where you work, from the first day (D-049).
func _know_where_you_work() -> void:
	if work.has_job():
		var workplace := str(data.get_entry("jobs", work.job_id).get("workplace", ""))
		if not player.knows_place(workplace):
			player.known_places[workplace] = "told"


func _start_background_job(background_id: String) -> void:
	var occupation := str(data.get_entry("backgrounds", background_id).get("job", ""))
	if occupation.is_empty():
		return
	for job_id in data.ids("jobs"):
		if str(data.get_entry("jobs", job_id).get("occupation", "")) == occupation:
			# From today, but today is not counted: a life starts at 07:00,
			# and nobody is fired on their first morning (D-042).
			work.hire(str(job_id), clock.day_index())
			return


## At midnight, every working day since the last check that the player did
## not work counts as missed; standing at zero loses the job (D-042).
func _count_missed_shifts(day: int) -> void:
	if not work.has_job():
		work.checked_through_day = day - 1
		return
	var job := data.get_entry("jobs", work.job_id)
	var today_weekday := clock.weekday()
	var missed_before := work.shifts_missed
	for d in range(maxi(work.checked_through_day + 1, work.hired_day + 1), day):
		var weekday := posmod(today_weekday - (day - d), 7)
		if WorkRules.works_on(job.get("days", "all"), weekday) and work.last_worked_day != d:
			work.record_missed()
	work.checked_through_day = day - 1
	if work.shifts_missed > missed_before and work.standing > 0.0 and str(job.get("employer", "")) != "":
		phone_director.missed_shift(str(job["employer"]), str(job.get("workplace", "")))
	if work.standing <= 0.0:
		var lost := work.job_id
		var employer := str(job.get("employer", ""))
		if employer != "" and npcs.get_npc(employer) != null:
			relationships.adjust(employer, PlayerState.ID, "respect", -0.1, clock.total_minutes)
		work.leave()
		Log.info("game", "Job lost", {"job": lost})
		Events.job_lost.emit(lost, "missed_shifts")


# --- using things and the body --------------------------------------------------

## Eats, drinks or uses something the player carries (D-041). `ItemRules`
## judges; the item is used up, its effects applied, and the minutes it
## took pass. Refuses `busy` while talking or shopping, and `not_owned`,
## `not_usable`, `not_hungry`, `not_hurt`.
func use_item(item_id: String) -> Result:
	var proposal := {"kind": "use", "item": item_id}
	if not is_running():
		return _reject(proposal, "no_world")
	if dialogue.is_talking() or is_shopping():
		return _reject(proposal, "busy")
	var meters := {}
	for meter in ItemRules.METERS:
		meters[meter] = player.stats.get_meter(meter)
	var judged := ItemRules.judge_use(data.get_entry("items", item_id), player.inventory.count_of(item_id), meters)
	if judged.is_err():
		return _reject(proposal, judged.code)
	var use: Dictionary = judged.value
	player.inventory.remove(item_id, 1)
	var effects: Dictionary = use["effects"]
	for meter in effects:
		player.stats.modify(str(meter), float(effects[meter]))
	advance_time(int(use["minutes"]))
	return Result.success({"kind": "used", "item": item_id, "effects": effects, "minutes": use["minutes"]})


func _resolve_collapse() -> void:
	if _collapse_due and not _collapsing:
		_collapse()


## Health gone — from hunger or exhaustion today, from harm later — the
## player collapses and wakes in the clinic the next morning, patched up,
## fed and billed for what they can pay (D-041). A floor under the condition
## loop that costs a night and money, not the game.
func _collapse() -> void:
	_collapsing = true
	_collapse_due = false
	if dialogue.is_talking():
		end_conversation()
	if is_shopping():
		close_shop()
	var clinic := world.interior_for(CLINIC)
	var wake_at := CLINIC if clinic != null else player.home_location
	var inside := world.interior_for(wake_at)
	if inside != null:
		player.interior = wake_at
		player.position = DistrictMap.cell_to_world(inside.entry_cell())
		_set_player_location(wake_at)
	var minutes := posmod(COLLAPSE_WAKE_MINUTE - clock.minute_of_day(), GameClock.MINUTES_PER_DAY)
	if minutes < 60:
		minutes += GameClock.MINUTES_PER_DAY
	_player_activity = "sleep"
	advance_time(minutes)
	_player_activity = "idle"
	player.stats.health = 0.35
	player.stats.hunger = 0.2
	player.stats.sleep = maxf(player.stats.sleep, 0.7)
	player.stats.modify("stress", 0.2)
	var bill := mini(CLINIC_BILL, player.wallet.total())
	if bill > 0:
		player.wallet.spend(bill, "clinic")
	_collapsing = false
	Log.info("game", "Player collapsed", {"woke_at": wake_at, "bill": bill})
	Events.player_collapsed.emit(wake_at, bill)


# --- conversation -------------------------------------------------------------

## Starts talking to someone the player is facing (D-035). Refusals are
## rejected proposals like any other: `already_talking`, `nobody_there`,
## `asleep`, `on_their_way`. Time stands still while two people talk; the
## minutes it took are paid in one step when it ends.
func start_conversation(npc_id: String) -> Result:
	if not is_running():
		return Result.failure("no_world")
	var started := dialogue.start(npc_id, clock.total_minutes)
	if started.is_err():
		return _reject({"kind": "talk", "npc": npc_id}, started.code)
	_time_paused_before_talk = clock.paused
	clock.paused = true
	var opening: Dictionary = started.value
	Events.dialogue_started.emit(npc_id)
	Events.dialogue_line.emit(npc_id, str(opening["text"]))
	return started


## Whether the player could ring this person now, and if not why:
## `no_phone`, `not_a_contact`, `asleep`, `quiet_hours`, `busy`,
## `already_talking` (D-050).
func can_call(npc_id: String) -> Result:
	if not is_running():
		return Result.failure("no_world")
	if dialogue.is_talking():
		return Result.failure("already_talking")
	return phone_director.can_call(npc_id)


## Rings someone. If they pick up, a conversation begins, as in person — the
## same box, the same rules, minutes paid when it ends — but down the phone.
func start_call(npc_id: String) -> Result:
	var may := can_call(npc_id)
	if may.is_err():
		return _reject({"kind": "call", "npc": npc_id}, may.code)
	var started := dialogue.start_call(npc_id, clock.total_minutes)
	if started.is_err():
		return _reject({"kind": "call", "npc": npc_id}, started.code)
	_time_paused_before_talk = clock.paused
	clock.paused = true
	var opening: Dictionary = started.value
	Events.dialogue_started.emit(npc_id)
	Events.dialogue_line.emit(npc_id, str(opening["text"]))
	return started


## The player says something to whoever they are talking to; returns the
## reply as `DialogueDirector.say()` describes it. Await it: with a model
## answering, the reply takes as long as the model does.
func say_to_npc(text: String) -> Result:
	var talking_to := dialogue.conversation.npc_id if dialogue.is_talking() else ""
	var said: Result = await dialogue.say(text)
	if said.is_ok():
		var reply: Dictionary = said.value
		Events.dialogue_line.emit(PlayerState.ID, text.strip_edges())
		# The line was said; what it tried to do was refused (D-037).
		var rejection: Dictionary = reply.get("rejection", {})
		if not rejection.is_empty():
			Events.action_rejected.emit(rejection["proposal"], str(rejection["code"]))
		Events.dialogue_line.emit(talking_to, str(reply["text"]))
	return said


func end_conversation() -> Result:
	var ended := dialogue.end()
	if ended.is_err():
		return ended
	var outcome: Dictionary = ended.value
	clock.paused = _time_paused_before_talk
	advance_time(maxi(int(outcome["exchanges"]), 1))
	Events.dialogue_ended.emit(str(outcome["npc"]))
	var folded: Array[String] = outcome["folded"]
	if not folded.is_empty() and dialogue.model.is_available():
		_rewrite_memory(str(outcome["npc"]), folded, int(outcome["fold"]))
	return ended


## Lets the model rewrite a folded memory in the background; the game does
## not wait for it, and the rule-written summary stands if it fails (D-038).
func _rewrite_memory(npc_id: String, folded: Array[String], fold: int) -> void:
	var talking_to := dialogue
	var rewritten: Result = await talking_to.summarise(npc_id, folded, fold)
	if rewritten.is_err():
		Log.info("dialogue", "Memory kept as written by rule", {"npc": npc_id, "reason": rewritten.code})


func _reject(proposal: Dictionary, code: String) -> Result:
	Events.action_rejected.emit(proposal, code)
	return Result.failure(code)


# --- saving -----------------------------------------------------------------

func save_game(slot: String) -> Result:
	if not is_running():
		return Result.failure("no_world", "Nothing to save")
	var sections := {
		"clock": clock.to_dict(),
		"rng": rng.to_dict(),
		"world": world.to_dict(),
		"npcs": npcs.to_dict(),
		"relationships": relationships.to_dict(),
		"knowledge": knowledge.to_dict(),
		"memories": memories.to_dict(),
		"shops": shops.to_dict(),
		"work": work.to_dict(),
		"quests": quests.to_dict(),
		"phone": phone.to_dict(),
		"calendar": calendar.to_dict(),
		"crime": crime.to_dict(),
		"asks": asks.to_dict(),
		"consequences": consequences.to_dict(),
		"reputation": reputation.to_dict(),
		"events": events_queue.to_dict(),
		"player": player.to_dict(),
	}
	var meta := {
		"player_name": player.display_name,
		"region": world.current_region,
		"day": clock.day_index(),
		"time": clock.format_time(),
		"date": clock.format_date(),
		"character_level": player.stats.character_level,
	}
	return saves.save(slot, sections, meta)


func load_game(slot: String) -> Result:
	var read := saves.load_slot(slot)
	if read.is_err():
		return read
	var sections: Dictionary = read.value

	# Rebuild from content first so ids resolve, then overlay saved state.
	var fresh := new_game("", 1)
	if fresh.is_err():
		return fresh
	running = false

	clock.from_dict(sections.get("clock", {}))
	rng.from_dict(sections.get("rng", {}))
	world.from_dict(sections.get("world", {}))
	npcs.from_dict(sections.get("npcs", {}))
	relationships.from_dict(sections.get("relationships", {}))
	knowledge.from_dict(sections.get("knowledge", {}))
	memories.from_dict(sections.get("memories", {}))
	shops.from_dict(sections.get("shops", {}))
	work.from_dict(sections.get("work", {}))
	quests.from_dict(sections.get("quests", {}))
	phone.from_dict(sections.get("phone", {}))
	calendar.from_dict(sections.get("calendar", {}))
	crime.from_dict(sections.get("crime", {}))
	asks.from_dict(sections.get("asks", {}))
	consequences.from_dict(sections.get("consequences", {}))
	reputation.from_dict(sections.get("reputation", {}))
	events_queue.from_dict(sections.get("events", {}))
	player.from_dict(sections.get("player", {}))

	director.assign_tiers()
	running = true
	Events.game_loaded.emit()
	Log.info("game", "Save restored", {"slot": slot})
	return Result.success(slot)


# --- world event dispatch ---------------------------------------------------

## Central handler for everything the event queue resolves. Systems register
## their own kinds here rather than each polling the queue.
func _on_world_event(event: WorldEventQueue.QueuedEvent) -> void:
	Events.world_event_fired.emit(event.to_dict())
	if event.kind.begins_with("knowledge_"):
		knowledge.resolve_spread_event(event.kind, event.payload, clock.total_minutes)
		return
	match event.kind:
		"npc_override_expired":
			var npc := npcs.get_npc(str(event.payload.get("npc", "")))
			if npc != null:
				npc.clear_override()
		"injury_healed":
			player.stats.heal_expired_injuries(clock.total_minutes)
		"meeting_reminder", "meeting_gather", "meeting_check", "meeting_end":
			meetings.on_event(event.kind, event.payload)
		"crime_report":
			crime.deliver_report(event.payload)
		"police_assess":
			_police_assess(event.payload)
		"police_summons_due":
			_summons_due(event.payload)
		_:
			Log.debug("events", "Unhandled world event", {"kind": event.kind})


func _on_minute(total_minutes: int) -> void:
	Events.minute_passed.emit(total_minutes)
	director.tick(total_minutes)
	if not phone.outbox.is_empty():
		phone_director.process_due()
	if total_minutes - _last_retier >= RETIER_INTERVAL:
		_last_retier = total_minutes
		director.assign_tiers()


func _on_hour(hour_of_day: int) -> void:
	Events.hour_passed.emit(hour_of_day)
	player.stats.drift(60, _player_activity)
	_phone_tick()
	if player.stats.health <= 0.0 and not _collapsing:
		_collapse_due = true


func _on_day(day: int) -> void:
	Events.day_passed.emit(day)
	llm.budget.on_new_day(day)
	knowledge.forget_stale(clock.total_minutes)
	player.stats.heal_expired_injuries(clock.total_minutes)
	shops.restock()
	meetings.lapse()
	consequences.run_daily()
	_count_missed_shifts(day)
	for failed in quests.expire(day):
		_quest_ended(failed, "failed")


func _on_time_skipped(from_minutes: int, to_minutes: int) -> void:
	director.catch_up(to_minutes)
	director.assign_tiers()
	_phone_tick()
	Events.time_skipped.emit(from_minutes, to_minutes)


func _connect_simulation() -> void:
	clock.minute_passed.connect(_on_minute)
	clock.hour_passed.connect(_on_hour)
	clock.day_passed.connect(_on_day)
	clock.time_skipped.connect(_on_time_skipped)
	events_queue.event_due.connect(_on_world_event)


func _disconnect_simulation() -> void:
	if clock.minute_passed.is_connected(_on_minute):
		clock.minute_passed.disconnect(_on_minute)
		clock.hour_passed.disconnect(_on_hour)
		clock.day_passed.disconnect(_on_day)
		clock.time_skipped.disconnect(_on_time_skipped)
	if events_queue.event_due.is_connected(_on_world_event):
		events_queue.event_due.disconnect(_on_world_event)


func _seed_relationships() -> void:
	var seeds: Array = []
	for npc_id in npcs.all_ids():
		var entry := data.get_entry("npcs", npc_id)
		for tie in entry.get("relationships", []):
			var row: Dictionary = tie.duplicate()
			row["from"] = npc_id
			seeds.append(row)
	relationships.seed_from_data(seeds)


func _apply_background(background_id: String) -> void:
	var backgrounds := data.table("backgrounds")
	if backgrounds.has(background_id):
		player.apply_background(backgrounds[background_id])
		return
	# No background chosen yet (or an unknown id): minimal viable start.
	player.apply_background({
		"id": "drifter",
		"cash": 40,
		"home": _default_home(),
	})


func _default_home() -> String:
	for location_id in world.locations:
		var location: Location = world.locations[location_id]
		if location.kind == "home" and location.owner_id.is_empty():
			return location_id
	return world.locations.keys()[0] if not world.locations.is_empty() else ""


func _starting_region() -> String:
	for region_id in world.regions:
		var region: Region = world.regions[region_id]
		if region.unlock.is_empty():
			return region_id
	return world.regions.keys()[0] if not world.regions.is_empty() else ""


## Snapshot for the developer overlay.
func debug_snapshot() -> Dictionary:
	if not is_running():
		return {"running": false}
	return {
		"running": true,
		"time": clock.format_time(),
		"date": clock.format_date(),
		"day": clock.day_index(),
		"total_minutes": clock.total_minutes,
		"region": world.current_region,
		"npc_tiers": director.stats(),
		"queued_events": events_queue.size(),
		"relationship_edges": relationships.edge_count(),
		"facts": knowledge.facts.size(),
		"llm": llm.stats(),
	}
