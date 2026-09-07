extends Node3D

const RoadManagerScript = preload("res://addons/road-generator/nodes/road_manager.gd")
const RoadContainerScript = preload("res://addons/road-generator/nodes/road_container.gd")
const RoadPointScript = preload("res://addons/road-generator/nodes/road_point.gd")
const RoadMaterial = preload("res://addons/road-generator/resources/road_texture.material")
const RoadActor = preload("res://road_demos/demo_resources/actors/RoadActor.tscn")
const BuilderCatalog = preload("res://scripts/map_builder/map_builder_catalog.gd")
const BuilderLaneNetwork = preload("res://scripts/chase/builder_lane_network.gd")

const DEFAULT_CIRCUIT := [
	Vector3(-90, 0, -90), Vector3(-30, 0, -90), Vector3(30, 0, -90), Vector3(90, 0, -90),
	Vector3(90, 0, -30), Vector3(90, 0, 30), Vector3(90, 0, 90), Vector3(30, 0, 90),
	Vector3(30, 0, 30), Vector3(30, 0, -30), Vector3(-30, 0, -30), Vector3(-30, 0, 30),
	Vector3(-30, 0, 90), Vector3(-90, 0, 90), Vector3(-90, 0, 30), Vector3(-90, 0, -30)
]

var circuit: Array = DEFAULT_CIRCUIT.duplicate()
var saved_map: Dictionary = {}
var saved_map_offset := Vector3.ZERO


func _enter_tree() -> void:
	set_meta("grid_city", true)
	set_meta("streets_only", true)
	_load_saved_builder_map()
	build_world()
	var manager := RoadManagerScript.new() as Node3D
	manager.name = "RoadManager"
	add_child(manager)
	build_vehicles(manager)
	build_pursuit_grid(manager)


func _load_saved_builder_map() -> void:
	var requested_map := String(GameState.get("builder_map_name")) if GameState.get("builder_map_name") != null else "city_map"
	var safe_name := requested_map.strip_edges().validate_filename()
	var path := "user://maps/%s.json" % (safe_name if not safe_name.is_empty() else "city_map")
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.has("items"):
		return
	saved_map = parsed
	set_meta("builder_map", true)
	_repair_single_missing_circuit_corner()
	var horizontal_centers: Array[float] = []
	var vertical_centers: Array[float] = []
	for item in saved_map["items"]:
		if not item is Dictionary or not String(item.get("id", "")).begins_with("two_way_street"):
			continue
		var cell: Array = item.get("cell", [])
		if cell.size() < 2:
			continue
		var turns := posmod(int(item.get("turns", 0)), 4)
		if turns % 2 == 1:
			horizontal_centers.append((float(cell[1]) + 2.0) * 5.0)
		else:
			vertical_centers.append((float(cell[0]) + 2.0) * 5.0)
	if horizontal_centers.size() < 2 or vertical_centers.size() < 2:
		saved_map.clear()
		return
	horizontal_centers.sort()
	vertical_centers.sort()
	var top: float = horizontal_centers.front()
	var bottom: float = horizontal_centers.back()
	var left: float = vertical_centers.front()
	var right: float = vertical_centers.back()
	saved_map_offset = Vector3(-(left + right) * 0.5, 0.0, -(top + bottom) * 0.5)
	left += saved_map_offset.x
	right += saved_map_offset.x
	top += saved_map_offset.z
	bottom += saved_map_offset.z
	var radius := minf(10.0, minf(right - left, bottom - top) * 0.22)
	circuit = [
		Vector3(left + radius, 0, top), Vector3(right - radius, 0, top),
		Vector3(right, 0, top + radius), Vector3(right, 0, bottom - radius),
		Vector3(right - radius, 0, bottom), Vector3(left + radius, 0, bottom),
		Vector3(left, 0, bottom - radius), Vector3(left, 0, top + radius),
	]


func _repair_single_missing_circuit_corner() -> void:
	# A rectangular test circuit is unambiguous when three matching corners and
	# both pairs of perimeter streets exist. Complete its fourth corner in memory
	# so an older/incomplete builder save remains driveable.
	var vertical_x: Array[int] = []
	var horizontal_y: Array[int] = []
	var curve_keys := {}
	var curve_id := ""
	for item in saved_map["items"]:
		if not item is Dictionary:
			continue
		var id := String(item.get("id", ""))
		var cell: Array = item.get("cell", [])
		if cell.size() < 2:
			continue
		var turns := posmod(int(item.get("turns", 0)), 4)
		if id == "two_way_street_2x2":
			if turns % 2 == 0:
				vertical_x.append(int(cell[0]))
			else:
				horizontal_y.append(int(cell[1]))
		elif id == "curve_two_way_2x2":
			curve_id = id
			curve_keys[Vector2i(int(cell[0]), int(cell[1]))] = true
	if curve_keys.size() != 3 or vertical_x.is_empty() or horizontal_y.is_empty():
		return
	vertical_x.sort()
	horizontal_y.sort()
	var expected := {
		Vector2i(vertical_x.front(), horizontal_y.front()): 0,
		Vector2i(vertical_x.front(), horizontal_y.back()): 1,
		Vector2i(vertical_x.back(), horizontal_y.back()): 2,
		Vector2i(vertical_x.back(), horizontal_y.front()): 3,
	}
	for corner: Vector2i in expected:
		if curve_keys.has(corner):
			continue
		saved_map["items"].append({"id": curve_id, "cell": [corner.x, corner.y], "turns": expected[corner]})
		set_meta("repaired_missing_corner", true)
		break


func build_saved_map_visuals() -> void:
	var definitions := {}
	for definition in BuilderCatalog.create_default():
		definitions[definition.id] = definition
	var visuals := Node3D.new()
	visuals.name = "SavedBuilderMap"
	add_child(visuals)
	for item in saved_map["items"]:
		if not item is Dictionary:
			continue
		var definition = definitions.get(String(item.get("id", "")))
		var coordinates: Array = item.get("cell", [])
		if definition == null or coordinates.size() < 2:
			continue
		var cell := Vector2i(int(coordinates[0]), int(coordinates[1]))
		var turns := posmod(int(item.get("turns", 0)), 4)
		var owner := Node3D.new()
		owner.name = definition.id
		visuals.add_child(owner)
		if definition.id.begins_with("curve_"):
			_add_saved_curve(owner, cell, definition, turns)
			continue
		var packed := load(definition.scene_path) as PackedScene
		if packed == null:
			continue
		if definition.fill_footprint_with_tiles:
			var footprint: Vector2i = definition.footprint
			if turns % 2 == 1:
				footprint = Vector2i(footprint.y, footprint.x)
			for x in footprint.x:
				for y in footprint.y:
					var tile_cell := cell + Vector2i(x, y)
					var tile_turns := turns
					var lateral_index := x if turns % 2 == 0 else y
					var lateral_width := footprint.x if turns % 2 == 0 else footprint.y
					if definition.id.begins_with("two_way_street") and lateral_index >= lateral_width / 2:
						tile_turns += 2
					var tile := packed.instantiate() as Node3D
					owner.add_child(tile)
					tile.position = _saved_item_position(definition, tile_cell, tile_turns)
					tile.rotation.y = tile_turns * PI * 0.5
			if definition.id.begins_with("two_way_street"):
				_add_saved_straight_markings(owner, cell, definition, turns)
		else:
			var instance := packed.instantiate() as Node3D
			owner.add_child(instance)
			instance.position = _saved_item_position(definition, cell, turns)
			instance.rotation.y = turns * PI * 0.5
			instance.scale = definition.visual_scale
			if definition.id == "pedestrian":
				_add_pedestrian_collision(instance)
			elif definition.id == "street_lamp":
				_configure_saved_street_lamp(instance)
			elif definition.id == "traffic_light":
				_add_traffic_light_support(instance)
				instance.add_to_group("builder_traffic_lights")
				instance.set_meta("signal_axis", "NS" if turns % 2 == 0 else "EW")


func _configure_saved_street_lamp(lamp: Node3D) -> void:
	# The Polygon mesh supplies the fixture. This light originates at its real
	# lamp head and aims outward/downward in the same direction as the arm.
	var light := SpotLight3D.new()
	light.name = "SidewalkStreetLight"
	light.position = Vector3(0.0, 6.28, 2.08)
	light.rotation_degrees.x = -62.0
	light.light_color = Color("#ffd39c")
	light.light_energy = 0.0
	light.spot_range = 17.0
	light.spot_angle = 47.0
	light.shadow_enabled = true
	lamp.add_child(light)


func _add_traffic_light_support(signal_head: Node3D) -> void:
	var pole := MeshInstance3D.new()
	pole.name = "TrafficSignalSupport"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.105
	mesh.bottom_radius = 0.145
	mesh.height = 2.46
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#26343b")
	material.metallic = 0.28
	material.roughness = 0.52
	mesh.material = material
	pole.mesh = mesh
	pole.position.y = -2.13
	signal_head.add_child(pole)


func _add_pedestrian_collision(person: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "PedestrianSafetyBody"
	var shape_node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.8
	shape_node.shape = shape
	shape_node.position.y = 0.9
	body.add_child(shape_node)
	person.add_child(body)


func _saved_item_position(definition: Resource, cell: Vector2i, turns: int) -> Vector3:
	turns = posmod(turns, 4)
	var rotated_offset: Vector3 = Basis(Vector3.UP, turns * PI * 0.5) * definition.placement_offset
	if not definition.corner_pivot:
		return Vector3((cell.x + 0.5) * 5.0, 0.12, (cell.y + 0.5) * 5.0) + rotated_offset + saved_map_offset
	var offsets := [Vector2(0, 5), Vector2(5, 5), Vector2(5, 0), Vector2(0, 0)]
	var offset: Vector2 = offsets[turns]
	return Vector3(cell.x * 5.0 + offset.x, 0.08, cell.y * 5.0 + offset.y) + rotated_offset + saved_map_offset


func _add_saved_curve(owner: Node3D, cell: Vector2i, definition: Resource, turns: int) -> void:
	var width := float(definition.footprint.x) * 5.0
	var center := Vector3((cell.x + definition.footprint.x) * 5.0, 0.1, (cell.y + definition.footprint.y) * 5.0) + saved_map_offset
	var material := StandardMaterial3D.new()
	# Procedural geometry receives roughly half the direct light of the imported
	# road mesh in this camera setup. Compensate at the source so both surfaces
	# resolve to the same warm asphalt under day/dusk/night lighting.
	material.albedo_color = Color("#b8a6a3")
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var curve := MeshInstance3D.new()
	curve.mesh = _saved_arc_mesh(center, 0.0, width, material)
	owner.add_child(curve)
	var pivot := Vector3((cell.x + definition.footprint.x * 0.5) * 5.0, 0.0, (cell.y + definition.footprint.y * 0.5) * 5.0) + saved_map_offset
	var angle := turns * PI * 0.5
	curve.position = pivot + Basis(Vector3.UP, angle) * (curve.position - pivot)
	curve.rotation.y = angle
	if definition.id.begins_with("curve_two_way"):
		_add_saved_arc_marking(owner, center, pivot, width * 0.5, turns, true)
		if int(definition.module_rules.get("lanes_forward", 1)) > 1:
			_add_saved_arc_marking(owner, center, pivot, width * 0.5 - 5.0, turns, false)
			_add_saved_arc_marking(owner, center, pivot, width * 0.5 + 5.0, turns, false)


func _add_saved_straight_markings(owner: Node3D, cell: Vector2i, definition: Resource, turns: int) -> void:
	var width := float(definition.module_rules.get("road_width", 5.0))
	var center := Vector3((cell.x + 0.5) * 5.0, 0.145, (cell.y + 0.5) * 5.0) + saved_map_offset
	if turns % 2 == 0:
		center.x = cell.x * 5.0 + width * 0.5 + saved_map_offset.x
	else:
		center.z = cell.y * 5.0 + width * 0.5 + saved_map_offset.z
	_add_saved_line(owner, center, turns, true)
	if int(definition.module_rules.get("lanes_forward", 1)) > 1:
		for side in [-1.0, 1.0]:
			var divider := center
			if turns % 2 == 0:
				divider.x += side * 5.0
			else:
				divider.z += side * 5.0
			_add_saved_line(owner, divider, turns, false)


func _add_saved_line(owner: Node3D, position: Vector3, turns: int, solid: bool) -> void:
	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var length := 5.0 if solid else 2.6
	mesh.size = Vector3(0.12, 0.025, length) if turns % 2 == 0 else Vector3(length, 0.025, 0.12)
	mesh.material = _saved_marking_material(solid)
	line.mesh = mesh
	line.position = position
	owner.add_child(line)


func _add_saved_arc_marking(owner: Node3D, center: Vector3, pivot: Vector3, radius: float, turns: int, solid: bool) -> void:
	var count := 1 if solid else 6
	for dash in count:
		var start := PI
		var finish := PI * 1.5
		if not solid:
			var slice := (PI * 0.5) / count
			start += dash * slice + slice * 0.18
			finish = PI + (dash + 1) * slice - slice * 0.28
		var line := MeshInstance3D.new()
		line.mesh = _saved_arc_mesh_range(center, radius - 0.065, radius + 0.065, start, finish, _saved_marking_material(solid))
		owner.add_child(line)
		var angle := turns * PI * 0.5
		line.position = pivot + Basis(Vector3.UP, angle) * (line.position - pivot)
		line.rotation.y = angle


func _saved_marking_material(solid: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#e6b83f") if solid else Color("#e8edf0")
	material.roughness = 0.72
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _saved_arc_mesh(center: Vector3, inner_radius: float, outer_radius: float, material: Material) -> ArrayMesh:
	return _saved_arc_mesh_range(center, inner_radius, outer_radius, PI, PI * 1.5, material)


func _saved_arc_mesh_range(center: Vector3, inner_radius: float, outer_radius: float, start_angle: float, end_angle: float, material: Material) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var segments := 32
	for index in range(segments + 1):
		var angle := lerpf(start_angle, end_angle, float(index) / segments)
		for radius in [inner_radius, outer_radius]:
			var vertex := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			vertices.append(vertex)
			normals.append(Vector3.UP)
			uvs.append(Vector2(vertex.x, vertex.z) / 5.0)
	for index in range(segments):
		var base := index * 2
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func build_world() -> void:
	var environment_node := WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	environment_node.environment = Environment.new()
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	add_child(sun)
	var ground := MeshInstance3D.new()
	ground.name = "ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(500, 500)
	ground.mesh = plane
	ground.position.y = -0.32
	add_child(ground)
	if saved_map.is_empty():
		var asphalt := MeshInstance3D.new()
		asphalt.name = "CityAsphalt"
		var asphalt_mesh := PlaneMesh.new()
		asphalt_mesh.size = Vector2(204, 204)
		var asphalt_material := StandardMaterial3D.new()
		asphalt_material.albedo_color = Color("#263440")
		asphalt_material.roughness = 0.93
		asphalt_mesh.material = asphalt_material
		asphalt.mesh = asphalt_mesh
		asphalt.position.y = -0.20
		add_child(asphalt)
	# Interior avenues complete the visual 4x4 grid. The pursuit circuit uses
	# the connected outer/alternating streets while these reserve future turn lanes.
	for x in ([] if not saved_map.is_empty() else [-30.0, 30.0]):
		var avenue := MeshInstance3D.new()
		avenue.name = "ReservedAvenue_%d" % int(x)
		var avenue_mesh := BoxMesh.new()
		avenue_mesh.size = Vector3(24.0, 0.06, 180.0)
		avenue_mesh.material = RoadMaterial
		avenue.mesh = avenue_mesh
		# Keep the reserved surface just below generated streets so crossings
		# never fight for the same depth value.
		avenue.position = Vector3(x, -0.04, 0)
		add_child(avenue)
	if not saved_map.is_empty():
		build_saved_map_visuals()
	if saved_map.is_empty():
		build_lane_markings()


func build_lane_markings() -> void:
	var markings := Node3D.new()
	markings.name = "LaneMarkings"
	add_child(markings)
	for index in circuit.size():
		var start: Vector3 = circuit[index]
		var finish: Vector3 = circuit[(index + 1) % circuit.size()]
		var direction := finish - start
		direction.y = 0.0
		var length := direction.length()
		if length < 20.0:
			continue
		direction = direction.normalized()
		var right := direction.cross(Vector3.UP).normalized()
		var center := (start + finish) * 0.5 + Vector3.UP * 0.025
		var painted_length := length - 18.0
		add_marking(markings, center + right * 0.28, direction, Color("#e6b83f"), 0.18, painted_length)
		add_marking(markings, center - right * 0.28, direction, Color("#e6b83f"), 0.18, painted_length)
		add_dashed_lane(markings, start, finish, right * 4.0)
		add_dashed_lane(markings, start, finish, right * -4.0)


func add_dashed_lane(parent: Node3D, start: Vector3, finish: Vector3, offset: Vector3) -> void:
	var direction := finish - start
	direction.y = 0.0
	var length := direction.length()
	direction = direction.normalized()
	var usable := length - 20.0
	var dash_count := maxi(2, floori(usable / 9.0))
	for dash_index in dash_count:
		var distance := 10.0 + (float(dash_index) + 0.5) * usable / float(dash_count)
		var center := start + direction * distance + offset + Vector3.UP * 0.026
		add_marking(parent, center, direction, Color("#e8edf0"), 0.14, 3.6)


func add_marking(parent: Node3D, center: Vector3, forward: Vector3, color: Color, width: float, length: float) -> void:
	var marking := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.025, length)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	mesh.material = material
	marking.mesh = mesh
	parent.add_child(marking)
	marking.global_position = center
	marking.look_at(center + forward, Vector3.UP)


func build_vehicles(manager: Node3D) -> void:
	var vehicles := Node3D.new()
	vehicles.name = "vehicles"
	manager.add_child(vehicles)
	for index in 20:
		var actor := RoadActor.instantiate() as Node3D
		actor.name = "Player" if index == 0 else "NOC%d" % index
		vehicles.add_child(actor)
		var spawn: Dictionary = _builder_vehicle_spawn(index)
		if spawn.is_empty():
			spawn = circuit_spawn((float(index) + 0.35) / 20.0)
		var spawn_forward: Vector3 = spawn.forward
		var lane_right := spawn_forward.cross(Vector3.UP).normalized()
		var lane_offset := float(spawn.get("lane_offset", 5.5 if index % 2 == 0 else -5.5))
		actor.position = spawn.position + lane_right * lane_offset + Vector3.UP * 0.05
		actor.look_at(actor.position + spawn_forward, Vector3.UP)
		actor.set("acceleration", 3)
		actor.set("target_speed", 25)
		if index == 0:
			actor.set("drive_state", 2)
			var camera := Camera3D.new()
			camera.name = "Camera3D"
			camera.position = Vector3(0, 7.0, 13.5)
			camera.rotation_degrees = Vector3(-12.0, 0, 0)
			camera.far = 500.0
			actor.add_child(camera)


func _builder_vehicle_spawn(index: int) -> Dictionary:
	var candidates = saved_map.get("spawn_candidates", {}).get("vehicles", [])
	if not candidates is Array or candidates.is_empty():
		return {}
	var candidate = candidates[index % candidates.size()]
	if not candidate is Dictionary:
		return {}
	var coordinates: Array = candidate.get("cell", [])
	if coordinates.size() < 2:
		return {}
	var definition
	for entry in BuilderCatalog.create_default():
		if entry.id == String(candidate.get("road_id", "")):
			definition = entry
			break
	if definition == null or definition.module_rules.is_empty():
		return {}
	var turns := posmod(int(candidate.get("turns", 0)), 4)
	var footprint: Vector2i = definition.footprint
	if turns % 2 == 1:
		footprint = Vector2i(footprint.y, footprint.x)
	var center := Vector3(
		(float(coordinates[0]) + footprint.x * 0.5) * 5.0,
		0.0,
		(float(coordinates[1]) + footprint.y * 0.5) * 5.0
	) + saved_map_offset
	var forward: Vector3 = [Vector3.FORWARD, Vector3.LEFT, Vector3.BACK, Vector3.RIGHT][turns]
	var reverse_lanes := int(definition.module_rules.get("lanes_reverse", 0))
	var offset := 0.0 if reverse_lanes == 0 else 2.5
	return {"position": center, "forward": forward, "lane_offset": offset}


func circuit_spawn(progress: float) -> Dictionary:
	var segment_lengths: Array[float] = []
	var total_length: float = 0.0
	for index in circuit.size():
		var length: float = circuit[index].distance_to(circuit[(index + 1) % circuit.size()])
		segment_lengths.append(length)
		total_length += length
	var target: float = progress * total_length
	var travelled: float = 0.0
	for index in circuit.size():
		var segment_length: float = segment_lengths[index]
		if target <= travelled + segment_length:
			var ratio := (target - travelled) / maxf(segment_length, 0.001)
			var start: Vector3 = circuit[index]
			var finish: Vector3 = circuit[(index + 1) % circuit.size()]
			return {"position": start.lerp(finish, ratio), "forward": (finish - start).normalized()}
		travelled += segment_length
	return {"position": circuit[0], "forward": (circuit[1] - circuit[0]).normalized()}


func build_pursuit_grid(manager: Node3D) -> void:
	if not saved_map.is_empty():
		BuilderLaneNetwork.build(manager, saved_map, saved_map_offset, BuilderCatalog.create_default())
		return
	var roads := RoadContainerScript.new() as Node3D
	roads.name = "DowntownGridRoads"
	roads.set("material_resource", RoadMaterial)
	roads.set("generate_ai_lanes", true)
	roads.set("use_lowpoly_preview", false)
	manager.add_child(roads)
	for index in circuit.size():
		var point := RoadPointScript.new() as Node3D
		point.name = "GridPoint_%02d" % index
		roads.add_child(point)
		point.position = circuit[index]
		var prior_position: Vector3 = circuit[(index - 1 + circuit.size()) % circuit.size()]
		var next_position: Vector3 = circuit[(index + 1) % circuit.size()]
		var incoming: Vector3 = (circuit[index] - prior_position).normalized()
		var outgoing: Vector3 = (next_position - circuit[index]).normalized()
		var tangent: Vector3 = (incoming + outgoing).normalized()
		if tangent.length() < 0.5:
			tangent = outgoing
		point.look_at(point.position + tangent, Vector3.UP)
		point.set("traffic_dir", [2, 2, 1, 1])
		point.set("lanes", [2, 4, 4, 2])
		point.set("prior_mag", 7.5)
		point.set("next_mag", 7.5)
		# The city uses one continuous asphalt surface. RoadPoint geometry remains
		# available for AI lanes only, avoiding broken corner mesh wedges.
		point.set("create_geo", false)
		point.set("prior_pt_init", NodePath("../GridPoint_%02d" % ((index - 1 + circuit.size()) % circuit.size())))
		point.set("next_pt_init", NodePath("../GridPoint_%02d" % ((index + 1) % circuit.size())))
