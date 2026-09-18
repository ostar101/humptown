class_name WorldView
extends Node2D
## The walkable world: the map the player is on (the region, or the inside of
## a building), its people, the player's body, the camera and the HUD.
##
## Composition only. It reads where the player should be from Game, forwards
## the body's cell changes to Game.move_player() and the interact button to
## Game.interact_at() for the rules to decide, and keeps the map's chunks
## streamed around the camera.

@onready var _region: RegionView = $Actors/RegionView
@onready var _npcs: NpcBodies = $Actors/NpcBodies
@onready var _player: PlayerBody = $Actors/Player
@onready var _camera: PlayerCamera = $Camera
@onready var _hud: Hud = $Hud

const NO_CELL := Vector2i(-99999, -99999)

var _last_accepted := Vector2.ZERO
## The cell the player faced when the prompt was last worked out.
var _front := NO_CELL


func _ready() -> void:
	if not Game.is_running():
		var started := Game.new_game()
		if started.is_err():
			Log.error("world", "Could not start a world", {"reason": started.message})
			return
	_player.cell_changed.connect(_on_player_cell_changed)
	_camera.target = _player
	show_current_area()
	DevCapture.maybe_capture(self)


## (Re)builds the view for wherever the player is: the region, or the inside
## of the building they are in.
func show_current_area() -> void:
	var map := Game.current_map()
	_region.show_map(map)
	_npcs.show_map(map)
	if map == null:
		Log.error("world", "Nowhere to show", {"region": Game.player.region, "interior": Game.player.interior})
		return
	_camera.set_bounds(_region.pixel_rect())
	var start := Game.player_start_position()
	_player.place_at(start)
	var accepted := Game.move_player(start)
	if accepted.is_ok():
		_last_accepted = start
	_camera.snap()
	_region.focus_on(_camera.get_screen_center_position())
	_front = NO_CELL


func _process(_delta: float) -> void:
	_region.focus_on(_camera.get_screen_center_position())
	_refresh_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player.input_enabled:
		get_viewport().set_input_as_handled()
		interact()


## Uses whatever the player is facing. Public so tests and scripted scenes can
## press the button.
func interact() -> Result:
	var cell := _player.current_cell() + _player.facing
	var what := Game.interaction_at(cell)
	var result := Game.interact_at(cell)
	_hud.show_message(InteractionText.outcome_text(what, result))
	if result.is_ok():
		var outcome: Dictionary = result.value
		if outcome.get("kind") in ["entered", "exited"]:
			show_current_area()
	_front = NO_CELL
	return result


func player_body() -> PlayerBody:
	return _player


func region_view() -> RegionView:
	return _region


func npc_bodies() -> NpcBodies:
	return _npcs


func hud() -> Hud:
	return _hud


## Works out the prompt only when the faced cell changes, not every frame.
func _refresh_prompt() -> void:
	var front := _player.current_cell() + _player.facing
	if front == _front:
		return
	_front = front
	_hud.set_prompt(InteractionText.prompt_for(Game.interaction_at(front)))


func _on_player_cell_changed(_cell: Vector2i) -> void:
	var result := Game.move_player(_player.position)
	if result.is_ok():
		_last_accepted = _player.position
	else:
		# The rules refused a place physics allowed. Rules win.
		_player.place_at(_last_accepted)
