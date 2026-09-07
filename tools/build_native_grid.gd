extends SceneTree

const RoadManagerScript = preload("res://addons/road-generator/nodes/road_manager.gd")
const RoadContainerScript = preload("res://addons/road-generator/nodes/road_container.gd")
const RoadPointScript = preload("res://addons/road-generator/nodes/road_point.gd")
const RoadMaterial = preload("res://addons/road-generator/resources/road_texture.material")
const FourWay = preload("res://addons/road-generator/custom_containers/4way_2x2.tscn")
const RoadActor = preload("res://road_demos/demo_resources/actors/RoadActor.tscn")
const Sky3DScript = preload("res://addons/sky_3d/src/Sky3D.gd")

const GRID_SPACING := 92.0
const GRID_SIZE := 3
var scene_root: Node3D
var manager: RoadManager
var intersections: Dictionary = {}
var bridges: Array[RoadContainer] = []


func _init() -> void:
	build.call_deferred()


func build() -> void:
	scene_root = Node3D.new()
	scene_root.name = "NativeGridDistrict"
	scene_root.set_meta("streets_only", true)
	root.add_child(scene_root)
	build_world()
	manager = RoadManagerScript.new() as RoadManager
	manager.name = "RoadManager"
	manager.auto_refresh = false
	scene_root.add_child(manager)
	build_intersections()
	await process_frame
	build_grid_connections()
	build_vehicles()
	await process_frame
	manager.rebuild_all_containers(true)
	await process_frame
	if not validate_grid():
		quit(1)
		return
	remove_generated_bridge_segments()
	set_owners(scene_root, scene_root)
	var packed := PackedScene.new()
	var pack_error := packed.pack(scene_root)
	if pack_error != OK:
		push_error("Unable to pack native grid: %s" % pack_error)
		quit(pack_error)
		return
	var save_error := ResourceSaver.save(packed, "res://scenes/districts/native_grid_streets.tscn")
	if save_error != OK:
		push_error("Unable to save native grid: %s" % save_error)
		quit(save_error)
		return
	print("NATIVE_GRID_SAVED intersections=9 bridges=12 terminated_edges=12")
	quit()


func build_world() -> void:
	var sky := Sky3DScript.new() as Sky3D
	sky.name = "Sky3D"
	scene_root.add_child(sky)
	# Fixed daytime while the roads are being evaluated. Screen-space fog is
	# disabled because it can artifact on recent Godot renderers.
	sky.current_time = 13.25
	sky.game_time_enabled = false
	sky.editor_time_enabled = false
	sky.clouds_enabled = true
	sky.fog_enabled = false
	sky.tonemap_exposure = 0.9
	sky.skydome_energy = 0.9
	sky.sun_energy = 0.95
	var ground := MeshInstance3D.new()
	ground.name = "ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(360.0, 360.0)
	ground.mesh = plane
	ground.position.y = -0.08
	scene_root.add_child(ground)


func build_intersections() -> void:
	for row in GRID_SIZE:
		for column in GRID_SIZE:
			var x := (float(column) - 1.0) * GRID_SPACING
			var z := (1.0 - float(row)) * GRID_SPACING
			add_intersection(grid_key(row, column), Vector3(x, 0.0, z))


func add_intersection(key: String, location: Vector3) -> void:
	var intersection := FourWay.instantiate() as RoadContainer
	intersection.name = "Intersection_%s" % key
	manager.add_child(intersection)
	intersection.position = location
	intersections[key] = intersection


func build_grid_connections() -> void:
	for row in GRID_SIZE:
		for column in GRID_SIZE - 1:
			var west: RoadContainer = intersections[grid_key(row, column)]
			var east: RoadContainer = intersections[grid_key(row, column + 1)]
			bridge_edges("Street_H_%d_%d" % [row, column], edge_toward(west, Vector3.RIGHT), edge_toward(east, Vector3.LEFT))
	for row in GRID_SIZE - 1:
		for column in GRID_SIZE:
			var north: RoadContainer = intersections[grid_key(row, column)]
			var south: RoadContainer = intersections[grid_key(row + 1, column)]
			bridge_edges("Street_V_%d_%d" % [row, column], edge_toward(north, Vector3.FORWARD), edge_toward(south, Vector3.BACK))
	for index in GRID_SIZE:
		terminate_edge(edge_toward(intersections[grid_key(0, index)], Vector3.BACK))
		terminate_edge(edge_toward(intersections[grid_key(GRID_SIZE - 1, index)], Vector3.FORWARD))
		terminate_edge(edge_toward(intersections[grid_key(index, 0)], Vector3.LEFT))
		terminate_edge(edge_toward(intersections[grid_key(index, GRID_SIZE - 1)], Vector3.RIGHT))


func grid_key(row: int, column: int) -> String:
	return "R%d_C%d" % [row, column]


func terminate_edge(point: RoadPoint) -> void:
	point.terminated = true


func edge_toward(intersection: RoadContainer, direction: Vector3) -> RoadPoint:
	var best_point: RoadPoint
	var best_dot := -INF
	for child in intersection.get_children():
		if not child is RoadPoint or not child.name.begins_with("RP_"):
			continue
		var offset: Vector3 = (child.global_position - intersection.global_position).normalized()
		var score := offset.dot(direction.normalized())
		if score > best_dot:
			best_dot = score
			best_point = child
	assert(best_point != null, "Intersection has no matching RoadPoint edge")
	return best_point


# Mirrors the add-on's Bridge RoadPoints operation. Endpoint transforms and
# directions come from the prefab RoadPoints and are never guessed.
func bridge_edges(bridge_name: String, edge_a: RoadPoint, edge_b: RoadPoint, handle_magnitude := 0.0) -> void:
	var bridge := RoadContainerScript.new() as RoadContainer
	bridge.name = bridge_name
	bridge.material_resource = RoadMaterial
	bridge.generate_ai_lanes = true
	bridge._auto_refresh = false
	manager.add_child(bridge)
	bridges.append(bridge)
	var point_a := RoadPointScript.new() as RoadPoint
	var point_b := RoadPointScript.new() as RoadPoint
	point_a.name = "Edge_A"
	point_b.name = "Edge_B"
	bridge.add_child(point_a)
	bridge.add_child(point_b)
	point_a.copy_settings_from(edge_a)
	point_b.copy_settings_from(edge_b)
	point_a.global_transform = edge_a.global_transform
	point_b.global_transform = edge_b.global_transform
	var edge_a_open := open_direction(edge_a)
	var edge_b_open := open_direction(edge_b)
	var bridge_a_external := flip_direction(edge_a_open)
	var bridge_b_external := flip_direction(edge_b_open)
	if handle_magnitude > 0.0:
		if edge_a_open == RoadPoint.PointInit.PRIOR:
			point_a.prior_mag = handle_magnitude
		else:
			point_a.next_mag = handle_magnitude
		if edge_b_open == RoadPoint.PointInit.PRIOR:
			point_b.prior_mag = handle_magnitude
		else:
			point_b.next_mag = handle_magnitude
	assert(point_a.connect_roadpoint(edge_a_open, point_b, edge_b_open))
	bridge.update_edges()
	assert(point_a.connect_container(bridge_a_external, edge_a, edge_a_open))
	assert(point_b.connect_container(bridge_b_external, edge_b, edge_b_open))


func open_direction(point: RoadPoint) -> int:
	if point.prior_pt_init.is_empty():
		return RoadPoint.PointInit.PRIOR
	if point.next_pt_init.is_empty():
		return RoadPoint.PointInit.NEXT
	assert(false, "RoadPoint %s has no open edge" % point.name)
	return -1


func flip_direction(direction: int) -> int:
	return RoadPoint.PointInit.NEXT if direction == RoadPoint.PointInit.PRIOR else RoadPoint.PointInit.PRIOR


func validate_grid() -> bool:
	var failures: Array[String] = []
	for intersection: RoadContainer in intersections.values():
		intersection.update_edges()
		for index in intersection.edge_rp_targets.size():
			if intersection.edge_rp_targets[index] != NodePath(""):
				continue
			var local_point := intersection.get_node(intersection.edge_rp_locals[index]) as RoadPoint
			if not local_point.terminated:
				failures.append("%s has an unterminated open edge" % intersection.name)
	for bridge in bridges:
		bridge.update_edges()
		for target in bridge.edge_rp_targets:
			if target == NodePath(""):
				failures.append("%s has an unconnected endpoint" % bridge.name)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		push_error("Native grid validation failed")
		return false
	return true


func build_vehicles() -> void:
	var vehicles := Node3D.new()
	vehicles.name = "vehicles"
	manager.add_child(vehicles)
	# One player plus a small, distributed traffic sample for grid testing.
	var traffic_spawns := [
		Vector3(-48.0, 0.05, GRID_SPACING),
		Vector3(42.0, 0.05, GRID_SPACING),
		Vector3(-45.0, 0.05, 0.0),
		Vector3(48.0, 0.05, 0.0),
		Vector3(-40.0, 0.05, -GRID_SPACING),
		Vector3(46.0, 0.05, -GRID_SPACING),
		Vector3(-GRID_SPACING, 0.05, 40.0),
		Vector3(GRID_SPACING, 0.05, -42.0),
	]
	for index in 9:
		var actor := RoadActor.instantiate() as Node3D
		actor.name = "Player" if index == 0 else "NOC%d" % index
		vehicles.add_child(actor)
		actor.position = Vector3(-GRID_SPACING + 28.0, 0.05, GRID_SPACING) if index == 0 else traffic_spawns[index - 1]
		actor.set("acceleration", 3)
		actor.set("target_speed", 22)
		if index == 0:
			actor.set("drive_state", 2)
			var camera := Camera3D.new()
			camera.name = "Camera3D"
			camera.position = Vector3(0.0, 7.0, 13.5)
			camera.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
			camera.far = 600.0
			actor.add_child(camera)
			camera.owner = scene_root


func remove_generated_bridge_segments() -> void:
	for bridge in bridges:
		for descendant in bridge.find_children("*", "Node3D", true, false):
			if is_instance_valid(descendant) and descendant.has_method("is_road_segment"):
				descendant.free()


func set_owners(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		if child != owner_node:
			child.owner = owner_node
		if not child.scene_file_path.is_empty():
			continue
		set_owners(child, owner_node)
