extends Node
## Developer view of the front-end screens at any step, for screenshots:
##
##     godot --path . res://scenes/debug/ui_preview.tscn -- --screen=creation \
##         --step=2 --background=bg_dockhand --name=Aino --screenshot=user://c.png
##
## `--screen` is `title`, `creation` or `opening`. For creation, `--step` is
## 1-3 and the screen is driven through its own public methods, exactly as its
## buttons would; for the opening, `--lines=n` reveals that many lines. Scene
## changes are captured, so pressing through never leaves this preview.

const SCREENS := {
	"title": "res://scenes/ui/title_screen.tscn",
	"creation": "res://scenes/ui/character_creation.tscn",
	"opening": "res://scenes/ui/opening.tscn",
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
	DevCapture.maybe_capture(self)


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
