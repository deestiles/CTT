class_name DowntownCityBuilder
extends Node3D

const BUILDING_COLORS := [
	Color("#d9896a"), Color("#e1b16f"), Color("#6e91a6"),
	Color("#8b7899"), Color("#b8a27e"), Color("#668678")
]
const GLASS_COLOR := Color("#8bc5d5")
const TREE_TRUNK := Color("#74533d")
const TREE_COLORS := [Color("#42745a"), Color("#568466"), Color("#6d9368")]

var rng := RandomNumberGenerator.new()
var road_points: Array[RoadPoint] = []
var placed_buildings: Array[Vector3] = []


func setup(district: Node3D, decorator: Node3D) -> void:
	rng.seed = 731947
	name = "DowntownCity"
	for node in district.find_children("*", "RoadPoint", true, false):
		road_points.append(node as RoadPoint)
	if district.has_meta("grid_city"):
		build_fixed_grid_blocks()
	else:
		build_city_blocks(decorator)


func build_fixed_grid_blocks() -> void:
	var lot_centers := [-60.0, 0.0, 60.0]
	var building_index := 0
	for block_z in lot_centers:
		for block_x in lot_centers:
			var center := Vector3(block_x, 0, block_z)
			# Two compact lots per 46x46 metre block leave a landscaped courtyard.
			for offset_sign in [-1.0, 1.0]:
				var lot_center := center + Vector3(8.0 * offset_sign, 0, 7.0 * offset_sign)
				add_building(lot_center, Vector3.FORWARD, building_index)
				placed_buildings.append(lot_center)
				building_index += 1
			add_grid_block_scenery(center, building_index)


func add_grid_block_scenery(center: Vector3, index: int) -> void:
	var scenery := Node3D.new()
	scenery.name = "BlockScenery_%02d" % index
	add_child(scenery)
	for offset in [Vector3(-14, 0, -14), Vector3(14, 0, -14), Vector3(-14, 0, 14), Vector3(14, 0, 14)]:
		add_tree(scenery, center + offset)
	add_bush(scenery, center + Vector3(-13, 0, 0), index)
	add_bush(scenery, center + Vector3(13, 0, 0), index + 1)
	add_bench(scenery, center + Vector3(0, 0, -12), Vector3.RIGHT)
	add_person(scenery, center + Vector3(-4, 0, -13), index)
	add_person(scenery, center + Vector3(5, 0, 12), index + 1)


func build_city_blocks(decorator: Node3D) -> void:
	var building_index := 0
	for safe_position in decorator.safe_prop_positions:
		var nearest := nearest_road_point(safe_position)
		if not nearest:
			continue
		var outward: Vector3 = safe_position - nearest.global_position
		outward.y = 0.0
		if outward.length() < 0.5:
			continue
		outward = outward.normalized()
		var building_center: Vector3 = safe_position + outward * 6.2
		if decorator.is_inside_exclusion(building_center) or not has_building_clearance(building_center, 7.0):
			continue
		if is_near_existing(building_center, 15.0):
			continue
		var road_forward := -nearest.global_transform.basis.z
		road_forward.y = 0.0
		if road_forward.length() < 0.5:
			road_forward = Vector3.FORWARD
		add_building(building_center, road_forward.normalized(), building_index)
		placed_buildings.append(building_center)
		add_streetscape(safe_position, road_forward.normalized(), outward, building_index)
		building_index += 1
		if building_index >= 34:
			break


func nearest_road_point(position: Vector3) -> RoadPoint:
	var nearest: RoadPoint
	var best_distance := INF
	for point in road_points:
		var distance := point.global_position.distance_squared_to(position)
		if distance < best_distance:
			best_distance = distance
			nearest = point
	return nearest


func has_building_clearance(position: Vector3, footprint_radius: float) -> bool:
	for point in road_points:
		var road_clearance := float(point.get_width_with_shoulders()) * 0.5 + 3.2 + footprint_radius
		if flat_distance(point.global_position, position) < road_clearance:
			return false
	return true


func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func is_near_existing(position: Vector3, minimum_distance: float) -> bool:
	for existing in placed_buildings:
		if flat_distance(existing, position) < minimum_distance:
			return true
	return false


func add_building(center: Vector3, forward: Vector3, index: int) -> void:
	var building := Node3D.new()
	building.name = "Building_%02d" % index
	add_child(building)
	building.global_position = center
	building.look_at(center + forward, Vector3.UP)
	var width := rng.randf_range(7.5, 11.5)
	var depth := rng.randf_range(8.0, 12.0)
	var height := rng.randf_range(8.0, 19.0)
	var body_color: Color = BUILDING_COLORS[index % BUILDING_COLORS.size()]
	add_box(building, Vector3(width, height, depth), body_color, Vector3.UP * height * 0.5)
	add_box(building, Vector3(width + 0.3, 0.35, depth + 0.3), body_color.lightened(0.18), Vector3.UP * (height + 0.12))
	# A stepped rooftop keeps the silhouette toy-like and readable.
	if index % 3 == 0:
		add_box(building, Vector3(width * 0.42, 1.0, depth * 0.38), body_color.darkened(0.12), Vector3(0, height + 0.65, 0))
	add_windows(building, width, depth, height)
	add_awning(building, width, depth, body_color, index)


func add_windows(building: Node3D, width: float, depth: float, height: float) -> void:
	var floors := clampi(floori(height / 2.4), 3, 7)
	for floor_index in range(1, floors):
		var y := 1.45 + floor_index * 2.05
		if y > height - 0.7:
			break
		for side in [-1.0, 1.0]:
			add_box(building, Vector3(0.9, 0.72, 0.08), GLASS_COLOR, Vector3(side * width * 0.24, y, -depth * 0.505))


func add_awning(building: Node3D, width: float, depth: float, body_color: Color, index: int) -> void:
	var awning_color := Color("#f2c94c") if index % 2 == 0 else Color("#e76f73")
	add_box(building, Vector3(width * 0.62, 0.22, 1.05), awning_color, Vector3(0, 2.2, -depth * 0.55))
	add_box(building, Vector3(width * 0.34, 1.55, 0.08), body_color.lightened(0.3), Vector3(0, 1.0, -depth * 0.51))


func add_streetscape(anchor: Vector3, forward: Vector3, outward: Vector3, index: int) -> void:
	var streetscape := Node3D.new()
	streetscape.name = "Streetscape_%02d" % index
	add_child(streetscape)
	var lateral := forward.normalized()
	add_tree(streetscape, anchor + lateral * 4.1 + outward * 0.4)
	add_tree(streetscape, anchor - lateral * 4.1 + outward * 0.4)
	add_bush(streetscape, anchor + lateral * 2.2 + outward * 1.25, index)
	if index % 2 == 0:
		add_person(streetscape, anchor - lateral * 1.5, index)
	if index % 3 == 0:
		add_bench(streetscape, anchor + lateral * 0.8 + outward * 0.7, forward)


func add_tree(parent: Node3D, position: Vector3) -> void:
	var tree := Node3D.new()
	parent.add_child(tree)
	tree.global_position = position
	add_cylinder(tree, 0.26, 2.2, TREE_TRUNK, Vector3.UP * 1.1)
	add_sphere(tree, Vector3(1.35, 1.45, 1.35), TREE_COLORS[rng.randi_range(0, TREE_COLORS.size() - 1)], Vector3.UP * 2.65)


func add_bush(parent: Node3D, position: Vector3, index: int) -> void:
	var bush := Node3D.new()
	parent.add_child(bush)
	bush.global_position = position
	add_sphere(bush, Vector3(1.05, 0.72, 0.82), TREE_COLORS[index % TREE_COLORS.size()], Vector3.UP * 0.46)


func add_person(parent: Node3D, position: Vector3, index: int) -> void:
	var person := Node3D.new()
	parent.add_child(person)
	person.global_position = position + Vector3.UP * 0.04
	var shirt: Color = [Color("#52a7c8"), Color("#e56d68"), Color("#e2b45f"), Color("#755b9b")][index % 4]
	add_capsule(person, 0.28, 0.95, shirt, Vector3.UP * 0.82)
	add_sphere(person, Vector3.ONE * 0.43, Color("#d7a17c"), Vector3.UP * 1.58)


func add_bench(parent: Node3D, position: Vector3, forward: Vector3) -> void:
	var bench := Node3D.new()
	parent.add_child(bench)
	bench.global_position = position
	bench.look_at(position + forward, Vector3.UP)
	add_box(bench, Vector3(1.7, 0.18, 0.52), Color("#9a7047"), Vector3.UP * 0.52)
	add_box(bench, Vector3(1.7, 0.62, 0.15), Color("#9a7047"), Vector3(0, 0.82, 0.22))


func add_box(parent: Node3D, size: Vector3, color: Color, position: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = make_material(color)
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	mesh_instance.position = position


func add_cylinder(parent: Node3D, radius: float, height: float, color: Color, position: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.08
	mesh.height = height
	mesh.radial_segments = 10
	mesh.material = make_material(color)
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	mesh_instance.position = position


func add_sphere(parent: Node3D, scale_value: Vector3, color: Color, position: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 7
	mesh.material = make_material(color)
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	mesh_instance.position = position
	mesh_instance.scale = scale_value


func add_capsule(parent: Node3D, radius: float, height: float, color: Color, position: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 5
	mesh.material = make_material(color)
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	mesh_instance.position = position


func make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	return material
