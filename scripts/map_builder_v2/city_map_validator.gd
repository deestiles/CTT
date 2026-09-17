class_name CityMapValidator
extends RefCounted
## Validation for map-builder v2 maps.
##
## Two tiers:
##   validate_static(map)        - pure/synchronous grid + data checks; cheap
##                                 enough to run on every editor edit.
##   validate_live(map, host)    - coroutine; builds the city, bakes the road
##                                 NavMesh and raycasts, to confirm the things
##                                 that can only be known from live physics
##                                 (connected navigation, spawns on real road,
##                                 routes on real sidewalk, escape route exists).
##
## Result shape:
##   { valid:bool, errors:[{code,message}], warnings:[{code,message}], stats:{} }
## `valid` is false when any error is present. Warnings never block.

const Catalog := preload("res://scripts/map_builder_v2/city_module_catalog.gd")
const Schema := preload("res://scripts/map_builder_v2/city_map_schema.gd")
const Nav := preload("res://scripts/map_builder_v2/city_navigation.gd")
const Loader := preload("res://scripts/drive/generated_city_loader.gd")

const MIN_SPAWN_SEPARATION_M := 20.0   # police/thief closer than this = warning
const MIN_ESCAPE_ROOM_M := 30.0        # thief needs reachable road this far off


# --- Static (grid + data) -------------------------------------------------

static func validate_static(map_data: Variant) -> Dictionary:
	var data: Dictionary = Schema.normalize(map_data)
	var result := _new_result()

	var classed := _classify(data)
	var road_cells: Dictionary = classed["road_cells"]
	var sidewalk_cells: Dictionary = classed["sidewalk_cells"]
	var building_cells: Dictionary = classed["building_cells"]
	var signals: Array = classed["signals"]

	result["stats"]["road_cells"] = road_cells.size()
	result["stats"]["sidewalk_cells"] = sidewalk_cells.size()
	result["stats"]["building_cells"] = building_cells.size()

	if road_cells.is_empty():
		_error(result, "no_road", "The map has no road tiles.")

	# Building must not overlap road.
	var overlap := 0
	for cell in building_cells:
		if road_cells.has(cell):
			overlap += 1
	if overlap > 0:
		_error(result, "building_on_road", "%d building cell(s) overlap road tiles." % overlap)

	# Connected road islands (4-connected flood fill).
	var islands := _road_islands(road_cells)
	result["stats"]["road_islands"] = islands.size()
	if islands.size() > 1:
		_error(result, "road_islands", "Roads form %d disconnected islands; they must be one connected network." % islands.size())

	# Spawns.
	var spawns: Dictionary = data.get("spawns", {})
	var police_cell = _spawn_cell(spawns, "police")
	var thief_cell = _spawn_cell(spawns, "thief")
	if police_cell == null:
		_error(result, "no_police_spawn", "No police spawn placed.")
	elif not road_cells.has(police_cell):
		_error(result, "police_off_road", "Police spawn is not on a road tile.")
	if thief_cell == null:
		_error(result, "no_thief_spawn", "No thief spawn placed.")
	elif not road_cells.has(thief_cell):
		_error(result, "thief_off_road", "Thief spawn is not on a road tile.")

	if police_cell != null and thief_cell != null:
		var island_of := _island_lookup(islands)
		if island_of.get(police_cell, -1) != island_of.get(thief_cell, -2):
			_error(result, "spawns_unreachable", "Police and thief spawns are not on the same connected road network.")
		else:
			var sep := Schema.cell_center(police_cell).distance_to(Schema.cell_center(thief_cell))
			result["stats"]["spawn_separation_m"] = snappedf(sep, 0.1)
			if sep < MIN_SPAWN_SEPARATION_M:
				_warn(result, "spawns_close", "Police and thief start %.0f m apart (recommended > %d m)." % [sep, int(MIN_SPAWN_SEPARATION_M)])
			# Viable escape room: farthest road cell reachable from the thief.
			var reach := _bfs_reach(thief_cell, road_cells)
			var farthest := 0.0
			for c in reach:
				farthest = maxf(farthest, Schema.cell_center(c).distance_to(Schema.cell_center(police_cell)))
			result["stats"]["escape_room_m"] = snappedf(farthest, 0.1)
			if farthest < MIN_ESCAPE_ROOM_M:
				_warn(result, "cramped_escape", "Thief can only reach road %.0f m from police; the map may be too cramped for a chase." % farthest)

	# Sidewalk route nodes must sit on sidewalk cells (data-level; live pass
	# raycast-confirms the actual surface).
	var routes: Array = data.get("sidewalk_routes", [])
	var off_sidewalk := 0
	var route_nodes := 0
	for route in routes:
		if not (route is Array):
			continue
		for raw_cell in route:
			route_nodes += 1
			var cell := _cell(raw_cell)
			if not sidewalk_cells.has(cell):
				off_sidewalk += 1
	result["stats"]["route_nodes"] = route_nodes
	if off_sidewalk > 0:
		_warn(result, "route_off_sidewalk", "%d sidewalk-route node(s) are not on a sidewalk tile." % off_sidewalk)

	# Signal grouping metadata.
	var sx := 0
	var sz := 0
	for sig in signals:
		if _signal_is_x_axis(int(sig["turns"])):
			sx += 1
		else:
			sz += 1
	result["stats"]["signals_x"] = sx
	result["stats"]["signals_z"] = sz
	if signals.size() > 0 and (sx == 0 or sz == 0):
		_warn(result, "signals_one_axis", "All %d traffic signals face one axis; opposing phases need signals on both axes." % signals.size())

	# Boundary.
	var boundary: Array = data.get("boundary", [])
	if boundary.is_empty():
		_warn(result, "no_boundary", "No map boundary placed; the player car can drive off the road edge into empty space.")
	elif boundary.size() < 4:
		_warn(result, "boundary_thin", "Boundary has only %d posts; it may not enclose the playable area." % boundary.size())

	return result


# --- Live (physics) -------------------------------------------------------

## Coroutine. `host` must be inside the SceneTree; a temporary City + NavRegion
## are parented to it, baked, queried, then freed. Returns the merged result.
static func validate_live(map_data: Variant, host: Node) -> Dictionary:
	var result := validate_static(map_data)
	if host == null or not host.is_inside_tree():
		_warn(result, "no_host", "Live validation skipped (no scene host).")
		return result

	var built: Dictionary = Loader.build_city(map_data)
	var city: Node3D = built["city"]
	var holder := Node3D.new()
	holder.name = "ValidationScratch"
	host.add_child(holder)
	holder.add_child(city)
	var tree := host.get_tree()
	await tree.physics_frame
	await tree.physics_frame

	var region := Nav.bake_region(holder, city)
	# Query the world navigation map (the one the region registers into); the
	# region's own map RID can read back empty right after baking.
	var map: RID = host.get_viewport().world_3d.navigation_map
	var polys := region.navigation_mesh.get_polygon_count()
	result["stats"]["navmesh_polys"] = polys
	if polys == 0:
		_error(result, "no_navmesh", "Road tiles produced no navigation mesh; roads may be too narrow or disconnected.")
	# Poll until the baked region is actually synced into the navigation map
	# (get_closest_point stops returning the origin sentinel), rather than
	# guessing a fixed frame count.
	if polys > 0:
		var synced := false
		for _i in 240:
			Nav.sync_map(map)
			await tree.physics_frame
			var check := Nav.closest_point(map, city.global_position + Vector3(2.5, 0.0, 2.5))
			if check != Vector3.ZERO:
				synced = true
				break
		result["stats"]["nav_synced"] = synced

	# Spawns land on real navigable road, and an escape path exists.
	var spawns: Dictionary = built["spawns"]
	if spawns.has("police") and spawns.has("thief") and polys > 0:
		var p: Vector3 = spawns["police"]["world"]
		var t: Vector3 = spawns["thief"]["world"]
		var p_on := Nav.closest_point(map, p)
		var t_on := Nav.closest_point(map, t)
		# Horizontal error only; the navmesh sits a little above y=0 and that
		# height must not count as being "off road".
		var p_err := Vector2(p.x - p_on.x, p.z - p_on.z).length()
		var t_err := Vector2(t.x - t_on.x, t.z - t_on.z).length()
		result["stats"]["police_navmesh_error_m"] = snappedf(p_err, 0.01)
		result["stats"]["thief_navmesh_error_m"] = snappedf(t_err, 0.01)
		if p_err > 2.5:
			_error(result, "police_navmesh", "Police spawn is not on the navigable road surface.")
		if t_err > 2.5:
			_error(result, "thief_navmesh", "Thief spawn is not on the navigable road surface.")
		var escape := Nav.path_between(map, t_on, p_on)
		# A reachable path proves connectivity; length also gives escape headroom.
		if escape.size() < 2:
			_error(result, "no_escape_path", "No navigable route connects the thief and police spawns.")
		else:
			result["stats"]["escape_path_len_m"] = snappedf(Nav.path_length(escape), 0.1)

	# Sidewalk routes hit real walkable surface (downward raycast, as the runtime
	# verifies pedestrian loops).
	var routes: Array = built["sidewalk_routes"]
	if not routes.is_empty():
		var space := host.get_viewport().world_3d.direct_space_state
		var bad := 0
		var checked := 0
		for route in routes:
			for point in route:
				checked += 1
				var q := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 8.0, point + Vector3.DOWN * 20.0)
				if space.intersect_ray(q).is_empty():
					bad += 1
		result["stats"]["route_points_checked"] = checked
		if bad > 0:
			_warn(result, "route_no_ground", "%d/%d sidewalk-route points have no ground below them." % [bad, checked])

	holder.queue_free()
	return result


# --- Grid helpers ---------------------------------------------------------

static func _classify(data: Dictionary) -> Dictionary:
	var road_cells := {}
	var sidewalk_cells := {}
	var building_cells := {}
	var signals: Array = []
	for raw in data.get("items", []):
		if not (raw is Dictionary):
			continue
		var module: Dictionary = Catalog.by_id(String(raw.get("id", "")))
		if module.is_empty():
			continue
		var anchor := _cell(raw.get("cell", [0, 0]))
		var turns := int(raw.get("turns", 0))
		var footprint: Vector2i = module.get("footprint", Vector2i.ONE)
		var cells := Schema.covered_cells(anchor, footprint, turns)
		var category := String(module.get("category", ""))
		if category == "Roads":
			for c in cells:
				road_cells[c] = true
		elif category == "Sidewalks":
			for c in cells:
				sidewalk_cells[c] = true
		elif category == "Buildings":
			for c in cells:
				building_cells[c] = true
		if bool(module.get("is_signal", false)):
			signals.append({"cell": anchor, "turns": turns})
	return {
		"road_cells": road_cells,
		"sidewalk_cells": sidewalk_cells,
		"building_cells": building_cells,
		"signals": signals,
	}


static func _road_islands(road_cells: Dictionary) -> Array:
	var unvisited := road_cells.duplicate()
	var islands: Array = []
	while not unvisited.is_empty():
		var start: Vector2i = unvisited.keys()[0]
		var island := _bfs_reach(start, unvisited)
		islands.append(island)
		for c in island:
			unvisited.erase(c)
	return islands


static func _bfs_reach(start: Vector2i, cells: Dictionary) -> Array:
	if not cells.has(start):
		return []
	var seen := {start: true}
	var queue: Array = [start]
	var out: Array = [start]
	var neighbors := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_back()
		for step in neighbors:
			var n: Vector2i = current + step
			if cells.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
				out.append(n)
	return out


static func _island_lookup(islands: Array) -> Dictionary:
	var lookup := {}
	for i in islands.size():
		for cell in islands[i]:
			lookup[cell] = i
	return lookup


static func _spawn_cell(spawns: Dictionary, key: String):
	var entry = spawns.get(key, null)
	if entry is Dictionary and entry.has("cell"):
		return _cell(entry["cell"])
	return null


static func _signal_is_x_axis(turns: int) -> bool:
	var facing := Schema.basis_for(turns).z
	return absf(facing.x) >= absf(facing.z)


static func _cell(raw: Variant) -> Vector2i:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	if raw is Vector2i:
		return raw
	return Vector2i.ZERO


# --- Result builders ------------------------------------------------------

static func _new_result() -> Dictionary:
	return {"valid": true, "errors": [], "warnings": [], "stats": {}}


static func _error(result: Dictionary, code: String, message: String) -> void:
	result["errors"].append({"code": code, "message": message})
	result["valid"] = false


static func _warn(result: Dictionary, code: String, message: String) -> void:
	result["warnings"].append({"code": code, "message": message})
