class_name Boot
extends Node
## First scene. Hands off to the title screen — or, in developer mode, to the
## debug simulation viewer instead (M2 step 5: SimViewer is a developer tool,
## not where the game starts).
##
## The title screen leads on to character creation and the opening (D-034);
## keeping the entry point separate from those means none of them has to
## know about the others.

const TITLE := "res://scenes/ui/title_screen.tscn"
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
	return SIM_VIEWER if Settings.get_value("developer_mode") else TITLE
