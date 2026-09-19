extends Node
## Developer view of the front-end screens at any step, for screenshots:
##
##     godot --path . res://scenes/debug/ui_preview.tscn -- --screen=creation \
##         --step=2 --background=bg_dockhand --name=Aino --screenshot=user://c.png
##
## `--screen` is `title`, `creation`, `opening`, `settings` or `world`
## (`--overlay=1` shows the developer overlay; `--shop=location_id
## [--selling=1]` stands the player at that shop's counter; `--quests=1`
## opens the quest log; `--phone=threads|thread|contacts` the phone). For
## settings, `--provider=id` chooses a provider — in memory only, since a
## preview never writes the player's settings — and `--locale=fi` the language. For creation, `--step` is
## 1-3 and the screen is driven through its own public methods, exactly as its
## buttons would; for the opening, `--lines=n` reveals that many lines. Scene
## changes are captured, so pressing through never leaves this preview.

const SCREENS := {
	"title": "res://scenes/ui/title_screen.tscn",
	"creation": "res://scenes/ui/character_creation.tscn",
	"opening": "res://scenes/ui/opening.tscn",
	"settings": "res://scenes/ui/settings_screen.tscn",
	# The world as a freshly created character first sees it.
	"world": "res://scenes/world/world.tscn",
}


func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			args[parts[0]] = parts[1]
	var which := str(args.get("screen", "title"))
	if which == "settings":
		Settings.persist = false
		Game.llm.sandboxed = true
		if args.has("locale"):
			Localization.set_locale(str(args["locale"]))
	var background := str(args.get("background", "bg_dockhand"))
	if which == "opening" and not Game.is_running():
		Game.new_game(background, 7)
	if which == "world":
		var draft := CharacterDraft.new()
		draft.background_id = background
		draft.display_name = str(args.get("name", "Aino"))
		draft.appearance = PlayerLook.cycle(PlayerLook.cycle(PlayerLook.default_appearance(), "hair_style", 4), "outfit_style", 7)
		var started := Game.new_game_from(draft, 7)
		if started.is_err():
			Log.error("ui_preview", "Could not start", {"code": started.code})
	var screen: Node = (load(SCREENS.get(which, SCREENS["title"])) as PackedScene).instantiate()
	screen.set("scene_changer", func(path: String) -> void: Log.info("ui_preview", "Would go to", {"path": path}))
	add_child(screen)
	if which == "creation":
		_drive_creation(screen as CharacterCreation, args, background)
	elif which == "opening":
		# Each further line takes two presses — one to finish the fade, one for
		# the next line — and one more press would already be leaving.
		for i in maxi(int(args.get("lines", "1")) * 2 - 1, 0):
			(screen as Opening).advance()
	elif which == "settings" and args.has("provider"):
		(screen as SettingsScreen).choose_provider(str(args["provider"]))
	elif which == "world" and args.has("talk"):
		_drive_talk(screen as WorldView, str(args["talk"]), str(args.get("say", "")))
	if which == "world" and args.has("shop"):
		_drive_shop(screen as WorldView, str(args["shop"]), args.has("selling"))
	if which == "world" and args.has("quests"):
		(screen as WorldView).open_quests()
	if which == "world" and args.has("phone"):
		_drive_phone(screen as WorldView, str(args["phone"]))
	if which == "world" and args.has("overlay"):
		var overlay := screen.get_node_or_null("DevOverlay") as DevOverlay
		if overlay != null:
			overlay.toggle()
	DevCapture.maybe_capture(self)


## `--talk=npc_id [--say=text]`: puts that person on the quay with the
## player in front of them and opens a conversation, so the dialogue box can
## be looked at in place.
func _drive_talk(view: WorldView, npc_id: String, text: String) -> void:
	var npc := Game.npcs.get_npc(npc_id)
	if npc == null:
		return
	npc.activity = "work"
	npc.location = "loc_harbour"
	var map := Game.world.map_for(Game.player.region)
	var stand := map.standing_cell("loc_harbour", npc_id) + Vector2i.DOWN
	# Placing the player before the area is shown lets it snap the camera there.
	Game.player.interior = ""
	Game.player.position = DistrictMap.cell_to_world(stand)
	view.show_current_area()
	var body := view.npc_bodies().body_for(npc_id)
	if body == null:
		Log.warn("ui_preview", "No body to talk to", {"npc": npc_id})
		return
	view.player_body().facing = Vector2i.UP
	view.talk_to(body)
	if text != "":
		view.dialogue_box().submit(text)
	view.dialogue_box().finish_reveal()


## `--shop=location_id`: whoever works there is behind the counter, the
## player walks in with a little money and a few things, and steps up to it.
func _drive_shop(view: WorldView, location_id: String, selling: bool) -> void:
	for npc_id in Game.npcs.living_ids():
		var npc := Game.npcs.get_npc(npc_id)
		if npc.workplace == location_id:
			npc.location = location_id
			npc.activity = "work"
			break
	var map := Game.world.map_for(Game.player.region)
	Game.player.interior = ""
	Game.player.position = DistrictMap.cell_to_world(map.anchor_of(location_id))
	Game.player.wallet.cash = 23
	Game.player.inventory.add("item_beer", 2)
	if Game.interact_at(map.buildings[location_id]["door"]).is_err():
		Log.warn("ui_preview", "Could not go in", {"location": location_id})
		return
	view.show_current_area()
	view.open_shop()
	if selling:
		view.shop_window().show_selling(true)


## `--phone=threads|thread|contacts`: some numbers and a few messages on the
## phone, then the phone open on that page. Written straight into the phone
## state — the rules that would deliver them are tested elsewhere.
func _drive_phone(view: WorldView, page: String) -> void:
	var now := Game.clock.total_minutes
	Game.player.inventory.add(PhoneDirector.ITEM, 1)
	for npc_id in ["npc_pirjo", "npc_ida", "npc_veikko", "npc_rauno"]:
		Game.phone_director.add_contact(npc_id)
	Game.phone.add_message("npc_veikko", true, "missed_shift", "phone.msg.missed_shift", {"place": "loc_harbour"}, now - 1600)
	Game.phone.mark_read("npc_veikko")
	Game.phone.add_message("npc_ida", true, "check_in", "phone.msg.check_in.2", {}, now - 300)
	Game.phone.add_message("npc_pirjo", true, "errand_offer", "phone.msg.errand_offer",
		{"count": 2, "item": "item_sandwich", "reward": 16}, now - 45,
		{"do": "take_errand", "errand": "errand_pirjo_groceries"})
	var phone := view.phone_window()
	phone.open()
	match page:
		"thread":
			phone.open_thread("npc_pirjo")
		"contacts":
			phone.show_page(PhoneWindow.Page.CONTACTS)


func _drive_creation(creation: CharacterCreation, args: Dictionary, background: String) -> void:
	var step := int(args.get("step", "1"))
	if step >= 1 and args.has("background"):
		creation.choose_background(background)
	if step >= 2:
		creation.choose_background(background)
		creation.next()
		creation.draft.display_name = str(args.get("name", "Aino"))
		creation.get_node("%NameEdit").text = creation.draft.display_name
		creation.cycle_look("hair_style", 4)
		creation.cycle_look("outfit_style", 7)
		creation.cycle_look("shirt", 2)
		creation.lower_attribute("strength")
		creation.raise_attribute("wits")
	if step >= 3:
		creation.next()
