extends Node
## First scene. Loads content, then hands off to the debug simulation viewer.
##
## Milestone 2 replaces this with the title screen and character creation
## flow; keeping the entry point separate from those means neither has to
## know about the other.

const SIM_VIEWER := "res://scenes/debug/sim_viewer.tscn"


func _ready() -> void:
	Log.info("boot", "Humptown starting", {
		"version": ProjectSettings.get_setting("application/config/version", "0.1.0"),
		"locale": TranslationServer.get_locale(),
	})
	# Deferred so the autoloads have finished their own _ready first.
	call_deferred("_enter_world")


func _enter_world() -> void:
	get_tree().change_scene_to_file(SIM_VIEWER)
