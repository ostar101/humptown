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
## The time-of-day tint over everything drawn in the world (DayNight, D-032).
## The HUD is its own CanvasLayer and is not affected.
@onready var _daylight: CanvasModulate = $Daylight

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
	Events.minute_passed.connect(_on_minute_passed)
	Events.time_skipped.connect(_on_time_skipped)
	Events.game_loaded.connect(refresh_daylight)
	show_current_area()
	DevCapture.maybe_capture(self)


func _exit_tree() -> void:
	if Events.minute_passed.is_connected(_on_minute_passed):
		Events.minute_passed.disconnect(_on_minute_passed)
		Events.time_skipped.disconnect(_on_time_skipped)
		Events.game_loaded.disconnect(refresh_daylight)


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
	refresh_daylight()


## Tints the world for the time of day and sets the street lamps to match.
## Indoors the lights are on whatever the hour, so a room is never darkened.
## Called per game minute — a minute's change in the tint is far below what
## anyone can see, so there is nothing to gain from doing it per frame.
func refresh_daylight() -> void:
	if not Game.is_running():
		return
	var map := Game.current_map()
	if map != null and map.is_interior():
		_daylight.color = Color.WHITE
		_region.set_lamp_energy(0.0)
		return
	var tint := DayNight.tint_at(Game.clock.minute_of_day())
	_daylight.color = tint
	_region.set_lamp_energy(DayNight.lamp_energy_for(tint))


func daylight() -> CanvasModulate:
	return _daylight


func _on_minute_passed(_total_minutes: int) -> void:
	refresh_daylight()


func _on_time_skipped(_from_minutes: int, _to_minutes: int) -> void:
	refresh_daylight()


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
		if result.value is Dictionary and result.value.get("kind") == "travelled":
			show_current_area()
	else:
		# The rules refused a place physics allowed. Rules win.
		_player.place_at(_last_accepted)
