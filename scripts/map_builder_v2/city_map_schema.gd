class_name CityMapSchema
extends RefCounted
## Serialization contract for map-builder v2 city maps.
##
## Deliberately distinct from the old lane-graph builder's map JSON (which stores
## {id,cell,turns} against a fixed lane catalog under user://maps). v2 maps live
## in the repository under maps_v2/ and additionally carry the gameplay-metadata
## layers that the approved runtime currently hardcodes for the Synty Demo:
## spawns, sidewalk routes, recovery points, map boundary, and time-of-day.
##
## A v2 map is a plain Dictionary shaped like new_empty(); JSON round-trips it.

const FORMAT := "ctt_city_v2"
const SCHEMA_VERSION := 1
const GRID_SIZE := 5.0
const REPO_MAP_DIR := "res://maps_v2"

# Corner-pivot offset per quarter turn, so a rotated tile stays inside its
# declared footprint cell (matches the calibrated Synty +X/-Z tile pivot).
const _CORNER_OFFSETS := [Vector2(0, GRID_SIZE), Vector2(GRID_SIZE, GRID_SIZE), Vector2(GRID_SIZE, 0), Vector2(0, 0)]


static func new_empty(map_name := "untitled_city") -> Dictionary:
	return {
		"format": FORMAT,
		"schema_version": SCHEMA_VERSION,
		"grid_size": GRID_SIZE,
		"name": map_name,
		"time_of_day": "DAY",
		"ground_y": 0.0,             # calibrated by live raycast at load time
		"items": [],                 # [{id, cell:[x,y], turns}]
		"spawns": {},                # {police:{cell,turns}, thief:{cell,turns}}
		"sidewalk_routes": [],       # [ [[x,y],...] ordered loop, ... ]
		"recovery_points": [],       # [{cell:[x,y], turns}]
		"boundary": [],              # [[x,y],...] authored ring (optional)
		"camera": {"x": 0.0, "z": 0.0, "size": 120.0},
		"validation": {},
	}


## Deep-normalize an arbitrary parsed dictionary into a valid v2 map, filling
## defaults for any missing key so downstream code never guards every field.
static func normalize(data: Variant) -> Dictionary:
	var base := new_empty()
	if data is Dictionary:
		for key in base.keys():
			if data.has(key):
				base[key] = data[key]
		base["name"] = String(base.get("name", "untitled_city"))
		base["schema_version"] = int(base.get("schema_version", SCHEMA_VERSION))
	return base


static func save(path: String, data: Dictionary) -> int:
	var dir := path.get_base_dir()
	if dir != "":
		var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		if err != OK and err != ERR_ALREADY_EXISTS:
			return err
	var payload := normalize(data)
	payload["schema_version"] = SCHEMA_VERSION
	payload["format"] = FORMAT
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	return OK


static func load_from(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {}
	return normalize(parsed)


static func repo_path(map_name: String) -> String:
	var safe := map_name.strip_edges().validate_filename()
	if safe.is_empty():
		safe = "untitled_city"
	return "%s/%s.json" % [REPO_MAP_DIR, safe]


# --- Grid <-> world -------------------------------------------------------

## World position for a placed item's anchor cell. `ground_y` is the calibrated
## surface height (0 in the editor; set from raycast at runtime load).
static func cell_to_world(cell: Vector2i, turns: int, corner_pivot: bool,
		ground_y := 0.0, offset := Vector3.ZERO) -> Vector3:
	var rotated_offset: Vector3 = Basis(Vector3.UP, posmod(turns, 4) * PI * 0.5) * offset
	if not corner_pivot:
		return Vector3((cell.x + 0.5) * GRID_SIZE, ground_y, (cell.y + 0.5) * GRID_SIZE) + rotated_offset
	var corner: Vector2 = _CORNER_OFFSETS[posmod(turns, 4)]
	return Vector3(cell.x * GRID_SIZE + corner.x, ground_y, cell.y * GRID_SIZE + corner.y) + rotated_offset


## Center of a cell on the ground plane (used for markers, routes, gizmos).
static func cell_center(cell: Vector2i, ground_y := 0.0) -> Vector3:
	return Vector3((cell.x + 0.5) * GRID_SIZE, ground_y, (cell.y + 0.5) * GRID_SIZE)


static func world_to_cell(world: Vector3) -> Vector2i:
	return Vector2i(int(floor(world.x / GRID_SIZE)), int(floor(world.z / GRID_SIZE)))


static func basis_for(turns: int) -> Basis:
	return Basis(Vector3.UP, posmod(turns, 4) * PI * 0.5)


# --- Convenience accessors ------------------------------------------------

static func covered_cells(anchor: Vector2i, footprint: Vector2i, turns: int) -> Array:
	var size := footprint
	if posmod(turns, 4) % 2 == 1:
		size = Vector2i(footprint.y, footprint.x)
	var cells: Array = []
	for dx in range(size.x):
		for dy in range(size.y):
			cells.append(Vector2i(anchor.x + dx, anchor.y + dy))
	return cells
