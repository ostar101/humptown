class_name WorldView
extends Node2D
## The walkable world: the current region, the player's body and the camera.
##
## Composition only. It reads where the player should be from Game, forwards
## the body's cell changes to Game.move_player() for the rules to accept, and
## keeps the region's chunks streamed around the camera.

@onready var _region: RegionView = $Actors/RegionView
@onready var _player: PlayerBody = $Actors/Player
@onready var _camera: PlayerCamera = $Camera

var _last_accepted := Vector2.ZERO


func _ready() -> void:
	if not Game.is_running():
		var started := Game.new_game()
		if started.is_err():
			Log.error("world", "Could not start a world", {"reason": started.message})
			return
	_player.cell_changed.connect(_on_player_cell_changed)
	_camera.target = _player
	show_current_region()
	DevCapture.maybe_capture(self)


## (Re)builds the view for the region the player is in.
func show_current_region() -> void:
	var map := Game.world.map_for(Game.player.region)
	_region.show_map(map)
	if map == null:
		Log.error("world", "Region has no map", {"region": Game.player.region})
		return
	_camera.set_bounds(_region.pixel_rect())
	var start := Game.player_start_position()
	_player.place_at(start)
	var accepted := Game.move_player(start)
	if accepted.is_ok():
		_last_accepted = start
	_camera.snap()
	_region.focus_on(_camera.get_screen_center_position())


func _process(_delta: float) -> void:
	_region.focus_on(_camera.get_screen_center_position())


func player_body() -> PlayerBody:
	return _player


func region_view() -> RegionView:
	return _region


func _on_player_cell_changed(_cell: Vector2i) -> void:
	var result := Game.move_player(_player.position)
	if result.is_ok():
		_last_accepted = _player.position
	else:
		# The rules refused a place physics allowed. Rules win.
		_player.place_at(_last_accepted)
