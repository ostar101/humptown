class_name PlayerBody
extends CharacterBody2D
## The player's body in the region: reads input, moves, collides.
##
## Presentation only. It never writes PlayerState itself; when it crosses into
## a new cell it says so through `cell_changed`, and the world view asks Game
## to accept the move. Physics already keeps the body out of walls, so a
## refusal is rare — but the rule decides, not the collider.

signal cell_changed(cell: Vector2i)

const WALK_SPEED := 96.0    # three cells a second
const RUN_SPEED := 168.0

## When non-zero, used instead of input. Tests and cutscenes drive the body
## through this; it is never read from player input.
var scripted_direction := Vector2.ZERO
var scripted_running := false
## False while a menu or conversation owns the input.
var input_enabled := true

var facing := Vector2i.DOWN
var is_running := false

var _cell := Vector2i(-99999, -99999)

@onready var _figure: CharacterFigure = $Figure


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_mask = RegionTiles.COLLISION_LAYER
	_cell = DistrictMap.world_to_cell(position)


## Puts the body somewhere without walking there (spawn, load, travel).
func place_at(world_position: Vector2) -> void:
	position = world_position
	velocity = Vector2.ZERO
	_cell = DistrictMap.world_to_cell(position)


func current_cell() -> Vector2i:
	return _cell


func _physics_process(_delta: float) -> void:
	var direction := _wanted_direction()
	is_running = scripted_running if scripted_direction != Vector2.ZERO \
		else (input_enabled and Input.is_action_pressed("run"))
	velocity = direction * (RUN_SPEED if is_running else WALK_SPEED)
	move_and_slide()

	if direction != Vector2.ZERO:
		facing = facing_for(direction)
	_figure.facing = facing
	_figure.moving = get_real_velocity().length() > 5.0
	_figure.running = is_running

	var cell := DistrictMap.world_to_cell(position)
	if cell != _cell:
		_cell = cell
		cell_changed.emit(cell)


func _wanted_direction() -> Vector2:
	if scripted_direction != Vector2.ZERO:
		return scripted_direction.normalized()
	if not input_enabled:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


## Four-way facing from any direction. Horizontal wins ties so diagonal walking
## shows the profile, which reads better than the back of a head.
static func facing_for(direction: Vector2) -> Vector2i:
	if absf(direction.x) >= absf(direction.y):
		return Vector2i.RIGHT if direction.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if direction.y > 0.0 else Vector2i.UP
