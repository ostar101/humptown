extends Node
## Developer view of the front-end screens at any step, for screenshots:
##
##     godot --path . res://scenes/debug/ui_preview.tscn -- --screen=creation \
##         --step=2 --background=bg_dockhand --name=Aino --screenshot=user://c.png
##
## `--screen` is `title`, `creation`, `opening`, `settings` or `world`. For
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
