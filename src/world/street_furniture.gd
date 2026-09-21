class_name StreetFurniture
extends RefCounted
## Where the street's furniture stands: lamps, hydrants and bins (D-022, D-029,
## D-066, D-068). Pure functions of the map, with no art in them, so the
## simulation can know what is on a street — a bin can be searched, a hydrant
## is in the way — whatever is drawn. `StreetProps` draws it.
##
## - **lamp**: the pavement cell next to the road, at a regular interval,
##   turned so the lamp head is on the road's side (the art has the pole in its
##   left column and the head on an arm to the right, so a lamp with the road on
##   its left is mirrored). Beside a road that runs across the screen the arm
##   cannot point at the road, so it is left along the street. Not near a
##   crossing, not on the walk from a door. Computed on demand (`lamp_at`): a
##   lamp blocks only its own foot, by physics, not a cell.
## - **bin**: one for each building, at the front corner *away from* its door
##   (D-068), on the first pavement cell below it. Never in front of a door.
## - **hydrant**: the back edge of a pavement strip, far rarer, on its own
##   offset so it never lands on a lamp — and kept clear of doors and bins.
##
## Bins and hydrants are `DistrictMap.furniture`: they block their cell, routes
## go round them, and a bin can be interacted with. Nothing here is saved.

## Cells between one lamp and the next along a street. Regular rather than
## hashed: a street lit at even intervals reads as a street, and a hashed
## interval clumps.
const LAMP_SPACING := 10
## No lamp this close (in cells) to a corner where two roads meet.
const CORNER_CLEARANCE := 2
const HYDRANT_SPACING := 31
const HYDRANT_OFFSET := 5
## No hydrant within this many cells of a bin or another hydrant.
const HYDRANT_CLEARANCE := 3
## A hydrant keeps this many columns clear either side of a door, and stays out
## of the rows in front of it.
const DOOR_CLEARANCE := 3
## How far below a building's footprint a bin looks for pavement: past the
## porch a home's art draws.
const BIN_SEARCH_ROWS := 4

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


## The bins and hydrants of a map: cell -> {"kind": "trash" | "hydrant",
## "id": String}. Interiors have none.
static func place(map: DistrictMap) -> Dictionary:
	var out := {}
	if map.is_interior():
		return out
	for loc_id in map.buildings:
		var cell := bin_cell(map, loc_id)
		if cell.x >= 0:
			out[cell] = {"kind": "trash", "id": "bin_%s_%d_%d" % [map.id, cell.x, cell.y]}
	for y in map.size.y:
		for x in map.size.x:
			var cell := Vector2i(x, y)
			if _hydrant_fits(map, cell) and not _near(out, cell, HYDRANT_CLEARANCE):
				out[cell] = {"kind": "hydrant", "id": "hydrant_%s_%d_%d" % [map.id, x, y]}
	return out


## Where a building's bin stands: the corner of its front farthest from the
## door, on the first pavement cell below it; (-1, -1) if there is none.
static func bin_cell(map: DistrictMap, loc_id: String) -> Vector2i:
	var rect: Rect2i = map.buildings[loc_id]["rect"]
	var door: Vector2i = map.buildings[loc_id]["door"]
	var right := (door.x - rect.position.x) < rect.size.x / 2
	var x := rect.end.x - 1 if right else rect.position.x
	for y in range(rect.end.y, rect.end.y + BIN_SEARCH_ROWS):
		var cell := Vector2i(x, y)
		if map.ground_at(cell) == DistrictMap.Terrain.PAVEMENT and map.structure_at(cell) == DistrictMap.Terrain.NONE \
				and not touches_road(map, cell):
			return cell
	return Vector2i(-1, -1)


static func _hydrant_fits(map: DistrictMap, cell: Vector2i) -> bool:
	# The cheapest test first: this runs for every cell of the map.
	if posmod(cell.x + cell.y, HYDRANT_SPACING) != HYDRANT_OFFSET:
		return false
	if map.ground_at(cell) != DistrictMap.Terrain.PAVEMENT or map.structure_at(cell) != DistrictMap.Terrain.NONE:
		return false
	if not is_back_of_pavement(map, cell):
		return false
	if not has_headroom(map, cell, 2):
		return false
	return not _door_ahead(map, cell, DOOR_CLEARANCE)


## A door within `columns` either side and up to three rows above: someone
## leaving it would walk into this cell's neighbourhood.
static func _door_ahead(map: DistrictMap, cell: Vector2i, columns: int) -> bool:
	for dx in range(-columns, columns + 1):
		for up in range(1, 5):
			if map.structure_at(cell + Vector2i(dx, -up)) == DistrictMap.Terrain.DOOR:
				return true
	return false


static func _near(placed: Dictionary, cell: Vector2i, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if placed.has(cell + Vector2i(dx, dy)):
				return true
	return false


## Whether a lamp stands on this pavement cell.
static func lamp_at(map: DistrictMap, cell: Vector2i) -> bool:
	if posmod(cell.x + cell.y, LAMP_SPACING) != 0:
		return false
	if map.ground_at(cell) != DistrictMap.Terrain.PAVEMENT or map.structure_at(cell) != DistrictMap.Terrain.NONE:
		return false
	if map.furniture.has(cell) or not touches_road(map, cell):
		return false
	return _lamp_fits(map, cell)


## A lamp is not put where it would be in someone's way or double up: not on a
## corner where two roads meet (each would light it from its own side), and not
## on the walk from a door to the street.
static func _lamp_fits(map: DistrictMap, cell: Vector2i) -> bool:
	for dy in range(-CORNER_CLEARANCE, CORNER_CLEARANCE + 1):
		for dx in range(-CORNER_CLEARANCE, CORNER_CLEARANCE + 1):
			if is_corner(map, cell + Vector2i(dx, dy)):
				return false
	for dx in range(-1, 2):
		for up in range(1, 4):
			if map.structure_at(cell + Vector2i(dx, -up)) == DistrictMap.Terrain.DOOR:
				return false
	return true


## A pavement cell with road beside it on both axes: where two streets meet.
static func is_corner(map: DistrictMap, cell: Vector2i) -> bool:
	if map.ground_at(cell) != DistrictMap.Terrain.PAVEMENT:
		return false
	var across := _is_road(map, cell + Vector2i.LEFT) or _is_road(map, cell + Vector2i.RIGHT)
	var along := _is_road(map, cell + Vector2i.UP) or _is_road(map, cell + Vector2i.DOWN)
	return across and along


## Whether a lamp here is mirrored: the road is on its left and not its right,
## so the head, which the art draws to the right, would point away from it.
static func lamp_faces_left(map: DistrictMap, cell: Vector2i) -> bool:
	return _is_road(map, cell + Vector2i.LEFT) and not _is_road(map, cell + Vector2i.RIGHT)


## Whether a prop this tall (in cells) fits above its own cell without covering
## road. Hydrants are kept off the pavement below a carriageway.
static func has_headroom(map: DistrictMap, cell: Vector2i, cells_tall: int) -> bool:
	for up in range(1, cells_tall):
		if _is_road(map, cell + Vector2i(0, -up)):
			return false
	return true


## The row of a pavement strip furthest from the road: pavement that does not
## itself touch a road but neighbours pavement that does. On the two-cell
## sidewalks this map is built from, that is exactly the far kerb — the grass
## or shopfront side.
static func is_back_of_pavement(map: DistrictMap, cell: Vector2i) -> bool:
	if touches_road(map, cell):
		return false
	for dir in DIRECTIONS:
		var next := cell + dir
		if map.ground_at(next) == DistrictMap.Terrain.PAVEMENT and touches_road(map, next):
			return true
	return false


static func touches_road(map: DistrictMap, cell: Vector2i) -> bool:
	for dir in DIRECTIONS:
		if _is_road(map, cell + dir):
			return true
	return false


static func _is_road(map: DistrictMap, cell: Vector2i) -> bool:
	var ground := map.ground_at(cell)
	return ground == DistrictMap.Terrain.ROAD or ground == DistrictMap.Terrain.ROAD_LINE
