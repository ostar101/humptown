class_name NpcBody
extends Node2D
## One person's visible body. Pooled: NpcBodies hands it to whoever needs one
## and takes it back when they go indoors or out of detail.
##
## Presentation only. It never decides where anyone goes; it is handed a
## finished route and follows it. Following a route is a few vector steps a
## frame, and an idle body does not process at all.

signal arrived(body: NpcBody)

## Slower than the player's walk, so the player can overtake a stroller.
const WALK_SPEED := 72.0
## Someone keeping up with the player: quicker than a stroller, or they would
## fall behind for good.
const FOLLOW_SPEED := 130.0

var npc_id := ""
var speed := WALK_SPEED

var _figure := CharacterFigure.new()
var _route := PackedVector2Array()
var _next := 0


func _init() -> void:
	_figure.name = "Figure"
	add_child(_figure)
	set_process(false)


## Takes on a person's appearance and stands still at a spot.
func assume(p_npc_id: String, palette: Dictionary, world_position: Vector2) -> void:
	npc_id = p_npc_id
	speed = WALK_SPEED
	_figure.palette = palette
	_figure.look = CharacterSprites.look_for(p_npc_id, palette)
	_figure.facing = Vector2i.DOWN
	stand_at(world_position)
	visible = true


func stand_at(world_position: Vector2) -> void:
	position = world_position
	_route.clear()
	_next = 0
	_figure.moving = false
	set_process(false)


## Walks through these points in order, starting from wherever the body is.
func walk(route: PackedVector2Array) -> void:
	_route = route
	_next = 0
	_figure.moving = not route.is_empty()
	set_process(not route.is_empty())
	if route.is_empty():
		arrived.emit(self)


## Stops, hides and forgets who it was. The body can then serve anyone.
func release() -> void:
	stand_at(position)
	npc_id = ""
	visible = false


## Plays an action from the character art (a small idle, mostly) if the body is
## standing and the art has it. Never changes where anyone is.
func play(action: String, hold: bool = false) -> bool:
	return not is_walking() and _figure.play(action, hold)


func end_pose() -> void:
	_figure.end_pose()


func is_posing() -> bool:
	return _figure.is_posing()


func is_walking() -> bool:
	return _next < _route.size()


## Stops mid-route and turns to face someone — a person being talked to
## (D-035). The route is kept; `resume()` carries on along it.
func hold(facing: Vector2i) -> void:
	set_process(false)
	_figure.moving = false
	_figure.facing = facing


func resume() -> void:
	if is_walking():
		_figure.moving = true
		set_process(true)


func facing() -> Vector2i:
	return _figure.facing


func current_cell() -> Vector2i:
	return DistrictMap.world_to_cell(position)


func palette() -> Dictionary:
	return _figure.palette


func _process(delta: float) -> void:
	advance(delta)


## Moves along the route by `delta` seconds of walking. Public so tests can
## finish a walk without waiting for it.
func advance(delta: float) -> void:
	var budget := speed * delta
	while budget > 0.0 and _next < _route.size():
		var offset := _route[_next] - position
		var distance := offset.length()
		if distance > 0.0:
			_figure.facing = CharacterFigure.facing_for(offset)
		if distance <= budget:
			position = _route[_next]
			budget -= distance
			_next += 1
		else:
			position += offset / distance * budget
			budget = 0.0
	if _next >= _route.size() and _figure.moving:
		_figure.moving = false
		set_process(false)
		arrived.emit(self)
