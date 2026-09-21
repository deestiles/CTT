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
		if module.is_empty() or not is_placeable(module):
			continue
		var cell := _to_cell(raw.get("cell", [0, 0]))
		var turns := int(raw.get("turns", 0))
		var instance := instance_item(module, cell, turns, ground_y)
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


## Instance one placed module at its grid transform (shared by build_city and the
## editor's incremental placement). Public so the builder can add single tiles
## without a full rebuild.
##
## Placement is AABB-based, not pivot-based: the asset's real mesh extent is
## centred on its footprint cells, so it lands exactly where the editor's cursor
## highlights regardless of where the prefab's origin happens to be. (A pivot
## assumption held for the road tiles but not for buildings, which was landing
## them offset from the highlight.)
static func instance_item(module: Dictionary, cell: Vector2i, turns: int, ground_y: float) -> Node3D:
	var node := _build_raw(module)
	if node == null:
		return null
	var basis := Schema.basis_for(turns)
	var aabb := _local_aabb(node)
	var fp := footprint_from_aabb(aabb)
	if posmod(turns, 4) % 2 == 1:
		fp = Vector2i(fp.y, fp.x)   # rotated footprint dims
	var gs := Schema.GRID_SIZE
	var region_center := Vector3((cell.x + fp.x * 0.5) * gs, ground_y, (cell.y + fp.y * 0.5) * gs)
	var local_center := Vector3(aabb.position.x + aabb.size.x * 0.5, 0.0, aabb.position.z + aabb.size.z * 0.5)
	var origin := region_center - basis * local_center
	node.transform = Transform3D(basis, origin)
	# Keep the Synty root name (drive_city keys on it); add a unique suffix so the
	# scene tree stays valid without altering the name pattern the runtime matches.
	node.name = "%s_%d_%d" % [node.name, cell.x, cell.y]
	return node


## Instantiate a module's prefab plus any composite stack, at identity (no
## placement). Composite multi-level buildings stack extra floor/roof modules on
## top of the base prefab -- this is how the Demo builds tall apartments.
static func _build_raw(module: Dictionary) -> Node3D:
	# A group module assembles several sub-prefabs (each with its own relative
	# offset/rotation) under one root -- e.g. a full traffic light from pole +
	# arm + lights + box. Child prefabs keep their Synty names, so the runtime's
	# name-driven passes (signals etc.) still find them.
	var parts: Array = module.get("parts", [])
	if not parts.is_empty():
		var root := Node3D.new()
		root.name = String(module.get("group_root", "Group"))
		# Normalize vertically: rest the group's lowest captured part on the
		# ground plane. Capture stored raw world y (offset by the reference's
		# ground constant), which is unreliable per-building and dropped groups
		# far below the road. Anchoring to the group's own minimum makes it sit
		# on the surface no matter what y was recorded; below-street levels still
		# read correctly because they come from the prefab meshes extending below
		# their origins, not from a negative origin y.
		var min_y := INF
		for part in parts:
			if part is Dictionary:
				min_y = minf(min_y, _to_vec3(part.get("pos", Vector3.ZERO)).y)
		if not is_finite(min_y):
			min_y = 0.0
		for part in parts:
			if not (part is Dictionary):
				continue
			var pscene: PackedScene = load(String(part.get("prefab", "")))
			if pscene == null:
				continue
			var pnode := pscene.instantiate() as Node3D
			if pnode == null:
				continue
			var ppos := _to_vec3(part.get("pos", Vector3.ZERO))
			ppos.y -= min_y
			var yaw := float(part.get("rot_deg", int(part.get("turns", 0)) * 90))
			pnode.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), ppos)
			root.add_child(pnode)
		return root
	var scene: PackedScene = load(String(module["prefab"]))
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	if node == null:
		return null
	var stack: Dictionary = module.get("stack", {})
	if not stack.is_empty():
		_add_stack(node, stack)
	return node


## Cached real footprint (in cells) of a module, from its prefab mesh extent.
## Shared by the runtime and the editor so both agree on size and placement.
static var _fp_cache := {}

## A module can be instanced as geometry if it has a prefab or a parts group.
static func is_placeable(module: Dictionary) -> bool:
	return String(module.get("prefab", "")) != "" or not (module.get("parts", []) as Array).is_empty()


static func asset_footprint(module: Dictionary) -> Vector2i:
	var id := String(module.get("id", ""))
	if _fp_cache.has(id):
		return _fp_cache[id]
	var fp := Vector2i.ONE
	if is_placeable(module):
		var node := _build_raw(module)
		if node != null:
			fp = footprint_from_aabb(_local_aabb(node))
			node.free()
	_fp_cache[id] = fp
	return fp


static func footprint_from_aabb(aabb: AABB) -> Vector2i:
	return Vector2i(
		maxi(1, int(round(aabb.size.x / Schema.GRID_SIZE))),
		maxi(1, int(round(aabb.size.z / Schema.GRID_SIZE))))


## Combined mesh AABB in the node's own local space (no SceneTree required).
static func _local_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var n: Node = entry[0]
		var xf: Transform3D = entry[1]
		if n is VisualInstance3D:
			var a := xf * (n as VisualInstance3D).get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
		for c in n.get_children():
			if c is Node3D:
				stack.append([c, xf * (c as Node3D).transform])
	return out


static func _add_stack(base: Node3D, stack: Dictionary) -> void:
	var y := float(stack.get("base_height", 3.0))
	var mid_scene: PackedScene = load(String(stack.get("mid", "")))
	var mid_height := float(stack.get("mid_height", 9.0))
	var floors := int(stack.get("floors", 1))
	for _i in floors:
		if mid_scene:
			var mid := mid_scene.instantiate() as Node3D
			if mid:
				mid.position = Vector3(0.0, y, 0.0)
				base.add_child(mid)
		y += mid_height
	var roof_scene: PackedScene = load(String(stack.get("roof", "")))
	if roof_scene:
		var roof := roof_scene.instantiate() as Node3D
		if roof:
			roof.position = Vector3(0.0, y, 0.0)
			base.add_child(roof)


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


static func _to_vec3(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO


static func _to_cell(raw: Variant) -> Vector2i:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	if raw is Vector2i:
		return raw
	return Vector2i.ZERO
