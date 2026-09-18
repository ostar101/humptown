class_name DistrictMap
extends RefCounted
## The physical layout of one region: what is on the ground in each cell,
## which cells hold a building, and where each Location sits on the grid.
##
## Authored as rectangles in data/maps.json and rasterised here, so a map is
## content like any other — diffable, validated, loadable headless. This is
## simulation-side data: presentation paints it, NPC bodies will path over it,
## and nothing about it depends on how it is drawn. Swapping the art never
## touches this file.
##
## Two layers per cell. `ground` always holds a terrain; `structure` holds a
## building part, a piece of furniture or NONE. A cell is blocked if its ground
## is impassable or anything stands on it.
##
## An interior is the same kind of map, authored in data/interiors.json: walls
## are built around its edge, one door leads out, and its whole floor is the
## building's location. Everything that works outdoors — drawing, routes,
## bodies, the movement rule — works inside unchanged.

enum Terrain {
	NONE = -1, GRASS, PAVEMENT, ROAD, ROAD_LINE, WATER, DOCK, SAND, ROOF, WALL, DOOR,
	FLOOR, COUNTER, SHELF, BED, TABLE, SIGN,
}

const CHUNK_SIZE := 16
## World units per cell. The physical scale of the world, shared by rules
## (which cell is the player on?) and by drawing (how big is a tile?).
const CELL_PIXELS := 32
## Rows of facade at the bottom of every building. The rest of the footprint
## is roof — the angled top-down view shows the south face and the top.
const FACADE_ROWS := 2

const GROUND_NAMES := {
	"grass": Terrain.GRASS,
	"pavement": Terrain.PAVEMENT,
	"road": Terrain.ROAD,
	"road_line": Terrain.ROAD_LINE,
	"water": Terrain.WATER,
	"dock": Terrain.DOCK,
	"sand": Terrain.SAND,
	"floor": Terrain.FLOOR,
}

## Solid things that can be placed with `solids`. Signs are placed by their
## object entry instead.
const SOLID_NAMES := {
	"wall": Terrain.WALL,
	"counter": Terrain.COUNTER,
	"shelf": Terrain.SHELF,
	"bed": Terrain.BED,
	"table": Terrain.TABLE,
}

## What a person can do something with. See Game.interact_at().
const OBJECT_KINDS := ["counter", "bed", "sign"]
## Rows of wall along the top of an interior: the far wall shows its face.
const INTERIOR_TOP_WALL := 2

var id: String = ""
var region: String = ""
var size: Vector2i = Vector2i.ZERO
var spawn: Vector2i = Vector2i.ZERO

## location_id -> {"rect": Rect2i, "door": Vector2i} for buildings,
## {"rects": Array[Rect2i]} for open-air places.
var buildings: Dictionary = {}
var places: Dictionary = {}
## location_id -> Location.kind ("shop", "home", ...), set by whoever builds
## the map alongside its locations (WorldState.build_from()) — DistrictMap
## itself only knows geometry. Used to give a building's facade a matching
## look (RegionTiles); untracked or unset ids read as "" (D-022).
var building_kind: Dictionary = {}
## Each: {"to": region_id, "rect": Rect2i}
var exits: Array[Dictionary] = []
## cell -> {"id", "kind", "text_key"}. Objects stand on solid cells and are
## used from a walkable cell beside them.
var objects: Dictionary = {}

## Interiors only: the building this is the inside of, its way out, and where
## whoever works here stands. Empty / (-1, -1) on region maps.
var interior_of: String = ""
var exit_door := Vector2i(-1, -1)
var staff_cell := Vector2i(-1, -1)

var _ground := PackedByteArray()
var _structure := PackedByteArray()   # stores Terrain + 1 so NONE fits in a byte
## Built on the first path request and kept: maps do not change at runtime.
var _astar: AStarGrid2D = null


## Builds a map from its content entry. Every problem found is reported rather
## than the first, so a content author fixes a layout in one pass.
static func from_data(d: Dictionary) -> Result:
	var m := DistrictMap.new()
	var problems: Array[String] = []
	m.id = str(d.get("id", ""))
	m.region = str(d.get("region", ""))
	m.size = Vector2i(int(d.get("width", 0)), int(d.get("height", 0)))
	if m.size.x <= 0 or m.size.y <= 0:
		return Result.failure("map_invalid", "%s: width and height must be positive" % m.id)

	var fill_name := str(d.get("fill", "grass"))
	if not GROUND_NAMES.has(fill_name):
		problems.append("unknown fill terrain '%s'" % fill_name)
	var cells := m.size.x * m.size.y
	m._ground.resize(cells)
	m._ground.fill(int(GROUND_NAMES.get(fill_name, Terrain.GRASS)))
	m._structure.resize(cells)
	m._structure.fill(0)

	m.interior_of = str(d.get("interior_of", ""))
	if m.is_interior():
		if m.size.x < 4 or m.size.y < INTERIOR_TOP_WALL + 3:
			return Result.failure("map_invalid", "%s: interior is too small" % m.id)
		m._build_interior_shell(_cell_from(d.get("door")), problems)

	for area in d.get("areas", []):
		var terrain_name := str(area.get("terrain", ""))
		var rect := _rect_from(area.get("rect"))
		if not GROUND_NAMES.has(terrain_name):
			problems.append("unknown terrain '%s'" % terrain_name)
			continue
		if not m._contains_rect(rect):
			problems.append("area %s lies outside the map" % [rect])
			continue
		m._fill_ground(rect, int(GROUND_NAMES[terrain_name]))

	for place in d.get("places", []):
		var loc_id := str(place.get("location", ""))
		var rects: Array[Rect2i] = []
		for raw in place.get("rects", []):
			var rect := _rect_from(raw)
			if not m._contains_rect(rect):
				problems.append("place '%s' rect %s lies outside the map" % [loc_id, rect])
				continue
			rects.append(rect)
		if rects.is_empty():
			problems.append("place '%s' has no usable rects" % loc_id)
			continue
		m.places[loc_id] = {"rects": rects}

	for building in d.get("buildings", []):
		var loc_id := str(building.get("location", ""))
		var rect := _rect_from(building.get("rect"))
		var door := _cell_from(building.get("door"))
		if rect.size.y <= FACADE_ROWS or rect.size.x < 2:
			problems.append("building '%s' is too small" % loc_id)
			continue
		if not m._contains_rect(rect):
			problems.append("building '%s' lies outside the map" % loc_id)
			continue
		if door.y != rect.end.y - 1 or door.x < rect.position.x or door.x >= rect.end.x:
			problems.append("building '%s' door %s is not on its front row" % [loc_id, door])
			continue
		if door.y + 1 >= m.size.y:
			problems.append("building '%s' door opens off the map" % loc_id)
			continue
		m.buildings[loc_id] = {"rect": rect, "door": door}
		m._stamp_building(rect, door)

	for solid in d.get("solids", []):
		var kind := str(solid.get("kind", ""))
		var rect := _rect_from(solid.get("rect"))
		if not SOLID_NAMES.has(kind):
			problems.append("unknown solid '%s'" % kind)
			continue
		if not m._contains_rect(rect):
			problems.append("%s %s lies outside the map" % [kind, rect])
			continue
		m._fill_structure(rect, int(SOLID_NAMES[kind]))

	for raw_object in d.get("objects", []):
		m._add_object(raw_object, problems)

	if m.is_interior():
		var staff_raw: Variant = d.get("staff")
		if staff_raw != null:
			m.staff_cell = _cell_from(staff_raw)
			if m.is_blocked(m.staff_cell):
				problems.append("staff spot %s is blocked" % m.staff_cell)
		if m.in_bounds(m.exit_door) and m.is_blocked(m.entry_cell()):
			problems.append("the cell inside the door is blocked")

	for raw_exit in d.get("exits", []):
		var rect := _rect_from(raw_exit.get("rect"))
		if not m._contains_rect(rect):
			problems.append("exit to '%s' lies outside the map" % raw_exit.get("to"))
			continue
		m.exits.append({"to": str(raw_exit.get("to", "")), "rect": rect})

	m.spawn = m.entry_cell() if m.is_interior() else _cell_from(d.get("spawn"))
	if not m.in_bounds(m.spawn):
		problems.append("spawn %s lies outside the map" % m.spawn)
	elif m.is_blocked(m.spawn):
		problems.append("spawn %s is blocked" % m.spawn)

	if not problems.is_empty():
		return Result.failure("map_invalid", "%s: %s" % [m.id, "; ".join(problems)])
	return Result.success(m)


# --- cell queries -----------------------------------------------------------

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func ground_at(cell: Vector2i) -> Terrain:
	if not in_bounds(cell):
		return Terrain.NONE
	return _ground[_index(cell)] as Terrain


func structure_at(cell: Vector2i) -> Terrain:
	if not in_bounds(cell):
		return Terrain.NONE
	return (_structure[_index(cell)] - 1) as Terrain


## Out of bounds counts as blocked, so a walker can never leave the map except
## through an exit handled by rules.
func is_blocked(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return true
	return ground_at(cell) == Terrain.WATER or structure_at(cell) != Terrain.NONE


## Which location a cell belongs to. Buildings win over the open-air place
## they stand in. Empty when the cell is just town.
func location_at(cell: Vector2i) -> String:
	for loc_id in buildings:
		var rect: Rect2i = buildings[loc_id]["rect"]
		if rect.has_point(cell):
			return loc_id
	for loc_id in places:
		for rect: Rect2i in places[loc_id]["rects"]:
			if rect.has_point(cell):
				return loc_id
	return ""


## The location kind at a cell ("shop", "home", ...), or "" off any location
## or where the map was built without kinds (tests, mostly).
func kind_at(cell: Vector2i) -> String:
	return str(building_kind.get(location_at(cell), ""))


## The walkable cell where someone going to or from a location stands: in
## front of a building's door, or the middle of a place. (-1, -1) if the
## location is not on this map.
func anchor_of(location_id: String) -> Vector2i:
	if buildings.has(location_id):
		var door: Vector2i = buildings[location_id]["door"]
		return door + Vector2i.DOWN
	if places.has(location_id):
		var first: Rect2i = places[location_id]["rects"][0]
		return first.get_center()
	return Vector2i(-1, -1)


func is_interior() -> bool:
	return not interior_of.is_empty()


## Interiors: the cell just inside the door, where you arrive and from which
## you leave. (-1, -1) on region maps.
func entry_cell() -> Vector2i:
	if not is_interior():
		return Vector2i(-1, -1)
	return exit_door + Vector2i.UP


func object_at(cell: Vector2i) -> Dictionary:
	return objects.get(cell, {})


## The building whose door is this cell, or empty.
func building_with_door(cell: Vector2i) -> String:
	for loc_id in buildings:
		if buildings[loc_id]["door"] == cell:
			return loc_id
	return ""


func has_location(location_id: String) -> bool:
	return buildings.has(location_id) or places.has(location_id)


func exit_at(cell: Vector2i) -> String:
	for e in exits:
		var rect: Rect2i = e["rect"]
		if rect.has_point(cell):
			return str(e["to"])
	return ""


## Flood fill over walkable cells. Used by content tests to prove every door
## can be reached from the spawn; cheap enough to call on load if ever needed.
func reachable_from(start: Vector2i) -> Dictionary:
	var seen := {}
	if is_blocked(start):
		return seen
	var frontier: Array[Vector2i] = [start]
	seen[start] = true
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := cell + step
			if seen.has(next) or is_blocked(next):
				continue
			seen[next] = true
			frontier.append(next)
	return seen


## Shortest walkable route between two cells, both ends included. Empty when
## either end is blocked or nothing connects them. Diagonal steps are taken
## only where neither side cell is blocked, so a route never clips a corner.
## Meant to be called when someone decides to go somewhere, not per frame.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if is_blocked(from) or is_blocked(to):
		return out
	if _astar == null:
		_build_astar()
	out.assign(_astar.get_id_path(from, to))
	return out


## Where a particular person stands at a location. At a building, in front of
## its door. At an open-air place, a walkable cell chosen from the person's id,
## so a crowd spreads over the place and each person returns to the same spot.
## (-1, -1) if the location is not on this map.
func standing_cell(location_id: String, who: String) -> Vector2i:
	if not places.has(location_id):
		return anchor_of(location_id)
	var open: Array[Vector2i] = []
	for rect: Rect2i in places[location_id]["rects"]:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if not is_blocked(Vector2i(x, y)):
					open.append(Vector2i(x, y))
	if open.is_empty():
		return anchor_of(location_id)
	return open[posmod(who.hash(), open.size())]


func is_building(location_id: String) -> bool:
	return buildings.has(location_id)


## A walkable cell inside the first exit, where someone arriving from or
## leaving for another region appears. The spawn when the map has no exits.
## Inside a building, the cell by the door.
func edge_cell() -> Vector2i:
	if is_interior():
		return entry_cell()
	for e in exits:
		var rect: Rect2i = e["rect"]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if not is_blocked(Vector2i(x, y)):
					return Vector2i(x, y)
	return spawn


static func cell_to_world(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL_PIXELS


static func world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / CELL_PIXELS), floori(world_position.y / CELL_PIXELS))


# --- chunks -----------------------------------------------------------------

func chunk_grid() -> Vector2i:
	return Vector2i(ceili(float(size.x) / CHUNK_SIZE), ceili(float(size.y) / CHUNK_SIZE))


static func chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / CHUNK_SIZE), floori(float(cell.y) / CHUNK_SIZE))


## Cells of a chunk, clipped to the map.
func chunk_rect(chunk: Vector2i) -> Rect2i:
	var rect := Rect2i(chunk * CHUNK_SIZE, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
	return rect.intersection(Rect2i(Vector2i.ZERO, size))


# --- internals --------------------------------------------------------------

func _index(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x


func _build_astar() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(Vector2i.ZERO, size)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for y in size.y:
		for x in size.x:
			if is_blocked(Vector2i(x, y)):
				_astar.set_point_solid(Vector2i(x, y))


func _contains_rect(rect: Rect2i) -> bool:
	return rect.size.x > 0 and rect.size.y > 0 and Rect2i(Vector2i.ZERO, size).encloses(rect)


func _fill_ground(rect: Rect2i, terrain: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_ground[y * size.x + x] = terrain


func _fill_structure(rect: Rect2i, terrain: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_structure[y * size.x + x] = terrain + 1


## Walls on every side, the door in the bottom wall, and the floor inside
## registered as the building's location.
func _build_interior_shell(door: Vector2i, problems: Array[String]) -> void:
	_fill_structure(Rect2i(0, 0, size.x, INTERIOR_TOP_WALL), Terrain.WALL)
	_fill_structure(Rect2i(0, 0, 1, size.y), Terrain.WALL)
	_fill_structure(Rect2i(size.x - 1, 0, 1, size.y), Terrain.WALL)
	_fill_structure(Rect2i(0, size.y - 1, size.x, 1), Terrain.WALL)
	var floor_rect := Rect2i(1, INTERIOR_TOP_WALL, size.x - 2, size.y - INTERIOR_TOP_WALL - 1)
	var rects: Array[Rect2i] = [floor_rect]
	places[interior_of] = {"rects": rects}
	if door.y != size.y - 1 or door.x < 1 or door.x > size.x - 2:
		problems.append("door %s is not in the bottom wall" % door)
		return
	exit_door = door
	_structure[_index(door)] = Terrain.DOOR + 1


func _add_object(raw: Variant, problems: Array[String]) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		problems.append("object entry is not a dictionary")
		return
	var entry: Dictionary = raw
	var object_id := str(entry.get("id", ""))
	var kind := str(entry.get("kind", ""))
	var cell := _cell_from(entry.get("cell"))
	if object_id.is_empty() or not (kind in OBJECT_KINDS):
		problems.append("object '%s' has an unknown kind '%s'" % [object_id, kind])
		return
	if not in_bounds(cell):
		problems.append("object '%s' lies outside the map" % object_id)
		return
	if kind == "sign":
		_structure[_index(cell)] = Terrain.SIGN + 1
	elif not is_blocked(cell):
		problems.append("object '%s' is not on a piece of furniture" % object_id)
		return
	var reachable := false
	for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if not is_blocked(cell + step):
			reachable = true
	if not reachable:
		problems.append("object '%s' cannot be reached from any side" % object_id)
		return
	objects[cell] = {"id": object_id, "kind": kind, "text_key": str(entry.get("text_key", ""))}


func _stamp_building(rect: Rect2i, door: Vector2i) -> void:
	var facade_top := rect.end.y - FACADE_ROWS
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var part := Terrain.ROOF if y < facade_top else Terrain.WALL
			_structure[y * size.x + x] = part + 1
			# Whatever the ground was, a building stands on a floor.
			_ground[y * size.x + x] = Terrain.PAVEMENT
	_structure[_index(door)] = Terrain.DOOR + 1


static func _rect_from(raw: Variant) -> Rect2i:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != 4:
		return Rect2i()
	var a: Array = raw
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))


static func _cell_from(raw: Variant) -> Vector2i:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != 2:
		return Vector2i(-1, -1)
	var a: Array = raw
	return Vector2i(int(a[0]), int(a[1]))
