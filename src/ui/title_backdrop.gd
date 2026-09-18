class_name TitleBackdrop
extends Node2D
## Harbourside at dusk behind the title and creation screens (D-034): the
## real district, drawn by the real RegionView, with the lamps coming on and
## the camera drifting slowly down the main street and back.
##
## It builds the map straight from content, the way the tests do, and never
## starts the simulation — nothing is running yet, and nothing here could
## change a world if it were. If the content fails to load, the screens in
## front of it still work over an empty background.

## Where the drift runs between, in cells, and how long one way takes.
const DRIFT_FROM := Vector2i(12, 27)
const DRIFT_TO := Vector2i(84, 27)
const DRIFT_SECONDS := 70.0
const ZOOM := 1.35
## The hour it is always about to be: after the golden light, as the lamps
## come on.
const MINUTE_OF_DAY := 1150

@onready var _view: RegionView = $RegionView
@onready var _camera: Camera2D = $Camera
@onready var _tint: CanvasModulate = $Tint

var _elapsed := 0.0


func _ready() -> void:
	var data := DataRegistry.new()
	if not data.load_all():
		return
	var world := WorldState.new()
	world.build_from(data)
	var map := world.map_for("harbourside")
	if map == null:
		return
	_view.show_map(map)
	_tint.color = DayNight.tint_at(MINUTE_OF_DAY)
	_view.set_lamp_energy(DayNight.lamp_energy_at(MINUTE_OF_DAY))
	_camera.zoom = Vector2(ZOOM, ZOOM)
	_camera.limit_right = int(_view.pixel_rect().end.x)
	_camera.limit_bottom = int(_view.pixel_rect().end.y)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_place_camera()


func _process(delta: float) -> void:
	if _view.map == null:
		return
	_elapsed += delta
	_place_camera()


## Eases out and back along the street, so the turn at each end is a slow
## stop rather than a bounce.
func _place_camera() -> void:
	var phase := fmod(_elapsed / DRIFT_SECONDS, 2.0)
	var t := phase if phase <= 1.0 else 2.0 - phase
	t = smoothstep(0.0, 1.0, t)
	var from := DistrictMap.cell_to_world(DRIFT_FROM)
	var to := DistrictMap.cell_to_world(DRIFT_TO)
	_camera.position = from.lerp(to, t)
	_view.focus_on(_camera.position)
