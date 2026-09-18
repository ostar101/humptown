class_name TitleScreen
extends Node
## Where the game starts (D-034): a new life, the one that was saved, or out.
##
## Continue is offered only when there is a save to continue — sleeping in
## your own bed writes it (D-033). A failed load says why and stays here
## rather than dropping the player into a half-built world.

const CREATION := "res://scenes/ui/character_creation.tscn"
const WORLD := "res://scenes/world/world.tscn"

@onready var _new_game: Button = %NewGame
@onready var _continue: Button = %Continue
@onready var _quit: Button = %Quit
@onready var _message: Label = %Message


func _ready() -> void:
	_new_game.pressed.connect(start_new_game)
	_continue.pressed.connect(continue_saved_game)
	_quit.pressed.connect(func() -> void: get_tree().quit())
	_continue.disabled = not Game.has_saved_game()
	# Whichever is the likelier next step has the keyboard's attention.
	(_new_game if _continue.disabled else _continue).grab_focus()
	DevCapture.maybe_capture(self)


func start_new_game() -> void:
	_go(CREATION)


func continue_saved_game() -> Result:
	var loaded := Game.continue_game()
	if loaded.is_err():
		_message.text = Localization.t("ui.title.load_failed")
		Log.warn("title", "Continue failed", {"reason": loaded.message})
		return loaded
	_go(WORLD)
	return loaded


func continue_button() -> Button:
	return _continue


## Where this screen goes next. Tests set `scene_changer` to see where it would
## go without replacing the test runner's own scene.
var scene_changer: Callable = Callable()


func _go(path: String) -> void:
	if scene_changer.is_valid():
		scene_changer.call(path)
	else:
		get_tree().change_scene_to_file(path)
