class_name Boot
extends Node
## First scene. Loads content, then hands off to the world — or, in
## developer mode, to the debug simulation viewer instead (M2 step 5:
## SimViewer is a developer tool now, not where the game starts).
##
## Milestone 2 later replaces the world hand-off with a title screen and
## character creation flow; keeping the entry point separate from those
## means neither has to know about the other.

const WORLD := "res://scenes/world/world.tscn"
const SIM_VIEWER := "res://scenes/debug/sim_viewer.tscn"


func _ready() -> void:
	Log.info("boot", "Humptown starting", {
		"version": ProjectSettings.get_setting("application/config/version", "0.1.0"),
		"locale": TranslationServer.get_locale(),
	})
	# Deferred so the autoloads have finished their own _ready first.
	call_deferred("_enter_world")


func _enter_world() -> void:
	get_tree().change_scene_to_file(destination_scene())


## Which scene to hand off to. A static, side-effect-free decision so it can
## be tested without instantiating either scene.
static func destination_scene() -> String:
	return SIM_VIEWER if Settings.get_value("developer_mode") else WORLD
