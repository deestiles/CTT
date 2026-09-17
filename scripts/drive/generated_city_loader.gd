class_name GeneratedCityLoader
extends RefCounted
## Reconstructs a runtime `City` node tree from a map-builder v2 map dictionary
## (see scripts/map_builder_v2/city_map_schema.gd).
##
## The returned tree instances REAL Synty Polygon City prefabs at their grid
## transforms and preserves the prefabs' Synty node names. That is the whole
## point of v2: because the approved runtime (scripts/drive/drive_city.gd) reads
## the city purely by name convention, the generated `City` node can be handed to
## the same navigation / lamp / signal / window / knockable passes with no edits
## to the protected runtime files.
##
## This loader ONLY builds geometry. Spawns, sidewalk routes, recovery points and
## the map boundary are returned as parsed metadata for the orchestrator
## (scripts/drive/generated_city.gd) to consume; they are not gameplay nodes.

const Catalog := preload("res://scripts/map_builder_v2/city_module_catalog.gd")
const Schema := preload("res://scripts/map_builder_v2/city_map_schema.gd")


## Build result:
##   {
##     city: Node3D,            # add this under the scene as "City"
##     ground_y: float,         # surface height (0 for generated cities)
##     item_count: int,
##     spawns: Dictionary,      # {police:{world,turns}, thief:{world,turns}}
##     sidewalk_routes: Array,  # [PackedVector3Array, ...] world-space loops
##     recovery_points: Array,  # [Transform3D-ish {world,turns}]
##     boundary: PackedVector3Array,
##     time_of_day: String,
##   }
static func build_city(map_data: Variant) -> Dictionary:
	var data: Dictionary = Schema.normalize(map_data)
	var ground_y := float(data.get("ground_y", 0.0))

	var city := Node3D.new()
	city.name = "City"

	var item_count := 0
	for raw in data.get("items", []):
		if not (raw is Dictionary):
			continue
		var module: Dictionary = Catalog.by_id(String(raw.get("id", "")))
		if module.is_empty() or String(module.get("prefab", "")) == "":
			continue
		var cell := _to_cell(raw.get("cell", [0, 0]))
		var turns := int(raw.get("turns", 0))
		var instance := _instance_module(module, cell, turns, ground_y)
		if instance:
			city.add_child(instance)
			item_count += 1

	return {
		"city": city,
		"ground_y": ground_y,
		"item_count": item_count,
		"spawns": _parse_spawns(data, ground_y),
		"sidewalk_routes": _parse_routes(data, ground_y),
		"recovery_points": _parse_recovery(data, ground_y),
		"boundary": _parse_boundary(data, ground_y),
		"time_of_day": String(data.get("time_of_day", "DAY")),
	}


static func _instance_module(module: Dictionary, cell: Vector2i, turns: int, ground_y: float) -> Node3D:
	var scene: PackedScene = load(String(module["prefab"]))
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	if node == null:
		return null
	var corner_pivot := bool(module.get("corner_pivot", true))
	var offset: Vector3 = module.get("offset", Vector3.ZERO)
	var scale: Vector3 = module.get("scale", Vector3.ONE)
	var origin := Schema.cell_to_world(cell, turns, corner_pivot, ground_y, offset)
	var basis := Schema.basis_for(turns).scaled(scale)
	node.transform = Transform3D(basis, origin)
	# Keep the Synty root name (drive_city keys on it); add a unique suffix so the
	# scene tree stays valid without altering the name pattern the runtime matches.
	node.name = "%s_%d_%d" % [node.name, cell.x, cell.y]
	return node


static func _parse_spawns(data: Dictionary, ground_y: float) -> Dictionary:
	var out := {}
	var spawns: Dictionary = data.get("spawns", {})
	for key in ["police", "thief"]:
		var entry = spawns.get(key, null)
		if entry is Dictionary and entry.has("cell"):
			out[key] = {
				"world": Schema.cell_center(_to_cell(entry["cell"]), ground_y),
				"turns": int(entry.get("turns", 0)),
			}
	return out


static func _parse_routes(data: Dictionary, ground_y: float) -> Array:
	var routes: Array = []
	for raw_route in data.get("sidewalk_routes", []):
		if not (raw_route is Array):
			continue
		var points := PackedVector3Array()
		for raw_cell in raw_route:
			points.append(Schema.cell_center(_to_cell(raw_cell), ground_y))
		if points.size() >= 2:
			routes.append(points)
	return routes


static func _parse_recovery(data: Dictionary, ground_y: float) -> Array:
	var out: Array = []
	for raw in data.get("recovery_points", []):
		if raw is Dictionary and raw.has("cell"):
			out.append({
				"world": Schema.cell_center(_to_cell(raw["cell"]), ground_y),
				"turns": int(raw.get("turns", 0)),
			})
	return out


static func _parse_boundary(data: Dictionary, ground_y: float) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for raw_cell in data.get("boundary", []):
		ring.append(Schema.cell_center(_to_cell(raw_cell), ground_y))
	return ring


static func _to_cell(raw: Variant) -> Vector2i:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	if raw is Vector2i:
		return raw
	return Vector2i.ZERO
