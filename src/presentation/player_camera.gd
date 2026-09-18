class_name PlayerCamera
extends Camera2D
## Follows the player with a little restraint.
##
## Two contextual touches and no more (the brief: "do not turn the camera
## system into a gimmick"): it leads slightly in the direction of travel, and
## pulls back a touch when running so there is more road ahead. Interiors and
## cinematic framing will set `base_zoom` and `lead_distance` rather than add
## new behaviour here.

@export var base_zoom := 2.0
@export var run_zoom := 1.8
@export var lead_distance := 20.0
@export var zoom_speed := 2.5

var target: PlayerBody = null

var _lead := Vector2.ZERO


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 6.0
	zoom = Vector2(base_zoom, base_zoom)


## Keeps the view inside the map. A map smaller than the view (a small room)
## is centred rather than pinned to the top-left corner.
func set_bounds(rect: Rect2) -> void:
	var widest_view := get_viewport_rect().size / minf(base_zoom, run_zoom)
	var margin := (widest_view - rect.size).max(Vector2.ZERO) / 2.0
	rect = rect.grow_individual(margin.x, margin.y, margin.x, margin.y)
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)


## Jumps straight to the target, skipping smoothing (spawn, load, travel).
func snap() -> void:
	if target == null:
		return
	_lead = Vector2.ZERO
	position = target.position
	reset_smoothing()


func _process(delta: float) -> void:
	if target == null:
		return
	var moving := target.velocity.length() > 5.0
	var wanted_lead := Vector2(target.facing) * lead_distance if moving else Vector2.ZERO
	_lead = _lead.lerp(wanted_lead, clampf(delta * 2.0, 0.0, 1.0))
	# Aim at the upper body rather than the feet.
	position = target.position + _lead + Vector2(0, -12)

	var wanted_zoom := run_zoom if target.is_running and moving else base_zoom
	var z := lerpf(zoom.x, wanted_zoom, clampf(delta * zoom_speed, 0.0, 1.0))
	zoom = Vector2(z, z)
