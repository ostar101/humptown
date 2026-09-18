extends Node2D
## Developer view of a region's map, from before there is a player to walk it.
## Arrow keys or WASD pan, mouse wheel zooms, and the streamed chunks follow
## the camera exactly as they will follow the player.
##
##     godot --path . res://scenes/debug/region_preview.tscn
##     godot --path . res://scenes/debug/region_preview.tscn -- --screenshot=user://region.png
##
## With --screenshot the scene saves one frame and quits, which is how the
## map's look is checked without anyone sitting at the window.

const PAN_SPEED := 600.0

@onready var _view: RegionView = $RegionView
@onready var _camera: Camera2D = $Camera

func _ready() -> void:
	if not Game.is_running():
		var started := Game.new_game()
		if started.is_err():
			Log.error("preview", "Could not start a world", {"reason": started.message})
			return
	Game.pause_time(true)
	var map := Game.world.map_for(Game.world.current_region)
	if map == null:
		Log.error("preview", "Region has no map", {"region": Game.world.current_region})
		return
	_view.show_map(map)
	var limits := _view.pixel_rect()
	_camera.limit_left = int(limits.position.x)
	_camera.limit_top = int(limits.position.y)
	_camera.limit_right = int(limits.end.x)
	_camera.limit_bottom = int(limits.end.y)
	_camera.position = RegionView.cell_to_world(map.spawn)
	_view.focus_on(_camera.position)
	DevCapture.maybe_capture(self)


func _process(delta: float) -> void:
	var direction := Vector2(
		Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if direction != Vector2.ZERO:
		_camera.position += direction.normalized() * PAN_SPEED * delta / _camera.zoom.x
		_view.focus_on(_camera.get_screen_center_position())


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_camera.zoom = (_camera.zoom * 1.1).clampf(0.25, 3.0)
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_camera.zoom = (_camera.zoom / 1.1).clampf(0.25, 3.0)
