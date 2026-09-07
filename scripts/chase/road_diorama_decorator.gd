class_name RoadDioramaDecorator
extends Node3D

var debug_root: Node3D
var presentation_root: Node3D
var safe_prop_positions: Array[Vector3] = []
var exclusion_centers: Array[Vector3] = []
var exclusion_radii: Array[float] = []
var piece_count := 0
var district_root: Node3D

const MAX_PRESENTATION_PIECES := 420
const CURB_COLOR := Color("#9ba3a8")
const SIDEWALK_COLOR := Color("#89949b")
const CROSSWALK_COLOR := Color("#e7edf0")


func setup(district: Node3D) -> void:
	district_root = district
	presentation_root = Node3D.new()
	presentation_root.name = "RoadPresentation"
	add_child(presentation_root)
	debug_root = Node3D.new()
	debug_root.name = "RoadClearanceDebug"
	debug_root.visible = false
	add_child(debug_root)
	collect_exclusions(district)
	if district.has_meta("grid_city"):
		build_grid_block_surfaces()
	else:
		build_standard_road_edges(district)
		build_standard_crosswalks(district)
	build_safe_prop_zones(district)


func build_grid_block_surfaces() -> void:
	# One continuous raised surface per block avoids seams and reserves a
	# consistent 24 metre street corridor between neighboring blocks.
	for z in [-60.0, 0.0, 60.0]:
		for x in [-60.0, 0.0, 60.0]:
			oriented_box(presentation_root, Vector3(x, 0.13, z), Vector3.FORWARD, Vector3(36.0, 0.26, 36.0), SIDEWALK_COLOR)
			oriented_box(debug_root, Vector3(x, 0.02, z), Vector3.FORWARD, Vector3(36.0, 0.04, 36.0), Color(0.12, 1.0, 0.45, 0.18), true)


func toggle_debug() -> bool:
	debug_root.visible = not debug_root.visible
	return debug_root.visible


func collect_exclusions(district: Node3D) -> void:
	var seen: Dictionary = {}
	for node in district.find_children("*", "Node3D", true, false):
		var lowered := node.name.to_lower()
		var radius := 0.0
		if lowered.contains("roundabout"):
			radius = 24.0
		elif lowered.contains("splitter") or lowered.contains("ramp") or lowered.contains("highway"):
			radius = 19.0
		elif lowered.contains("3way") or lowered.contains("4way"):
			radius = 15.0
		if radius <= 0.0:
			continue
		var grid_key := "%d:%d:%d" % [roundi(node.global_position.x / 4.0), roundi(node.global_position.y / 4.0), roundi(node.global_position.z / 4.0)]
		if seen.has(grid_key):
			continue
		seen[grid_key] = true
		exclusion_centers.append(node.global_position)
		exclusion_radii.append(radius)
		debug_disc(node.global_position + Vector3.UP * 0.08, radius, Color(1.0, 0.12, 0.16, 0.18))


func build_standard_road_edges(district: Node3D) -> void:
	for node in district.find_children("*", "Node3D", true, false):
		if piece_count >= MAX_PRESENTATION_PIECES:
			break
		if not node.has_method("is_road_segment") or is_excluded_node(node):
			continue
		var curve := node.get("curve") as Curve3D
		var start_point := node.get("start_point") as RoadPoint
		var end_point := node.get("end_point") as RoadPoint
		if not curve or not start_point or not end_point:
			continue
		var curve_length := curve.get_baked_length()
		if curve_length < 3.0:
			continue
		var sample_count := maxi(1, ceili(curve_length / 7.0))
		for index in sample_count:
			if piece_count + 4 > MAX_PRESENTATION_PIECES:
				break
			var offset_a := curve_length * float(index) / float(sample_count)
			var offset_b := curve_length * float(index + 1) / float(sample_count)
			var point_a: Vector3 = (node as Node3D).to_global(curve.sample_baked(offset_a))
			var point_b: Vector3 = (node as Node3D).to_global(curve.sample_baked(offset_b))
			var direction: Vector3 = point_b - point_a
			direction.y = 0.0
			if direction.length() < 0.2:
				continue
			direction = direction.normalized()
			var right: Vector3 = direction.cross(Vector3.UP).normalized()
			var ratio := (float(index) + 0.5) / float(sample_count)
			var half_width := lerpf(float(start_point.get_width_with_shoulders()), float(end_point.get_width_with_shoulders()), ratio) * 0.5
			var center: Vector3 = (point_a + point_b) * 0.5
			for side_value in [-1.0, 1.0]:
				var side := float(side_value)
				var curb_center: Vector3 = center + right * side * (half_width + 0.28) + Vector3.UP * 0.16
				oriented_box(presentation_root, curb_center, direction, Vector3(0.5, 0.32, point_a.distance_to(point_b) + 0.15), CURB_COLOR)
				var sidewalk_center: Vector3 = center + right * side * (half_width + 1.55) + Vector3.UP * 0.08
				oriented_box(presentation_root, sidewalk_center, direction, Vector3(2.05, 0.16, point_a.distance_to(point_b) + 0.12), SIDEWALK_COLOR)
				piece_count += 2
			var debug_center: Vector3 = center + Vector3.UP * 0.05
			oriented_box(debug_root, debug_center, direction, Vector3(half_width * 2.0, 0.05, point_a.distance_to(point_b)), Color(1.0, 0.64, 0.1, 0.18), true)


func build_standard_crosswalks(district: Node3D) -> void:
	var placed: Array[Vector3] = []
	for node in district.find_children("*", "RoadPoint", true, false):
		var point := node as RoadPoint
		if not point or has_blocked_ancestor(point, ["roundabout", "splitter", "ramp", "highway"]):
			continue
		var connected: Node3D
		var prior := point.get_node_or_null(point.prior_pt_init)
		var next := point.get_node_or_null(point.next_pt_init)
		if prior is RoadIntersection:
			connected = prior
		elif next is RoadIntersection:
			connected = next
		if not connected:
			continue
		var toward := connected.global_position - point.global_position
		toward.y = 0.0
		if toward.length() < 0.5:
			continue
		toward = toward.normalized()
		var center := point.global_position + toward * 1.8 + Vector3.UP * 0.12
		var duplicate := false
		for existing in placed:
			if existing.distance_to(center) < 7.0:
				duplicate = true
				break
		if duplicate:
			continue
		placed.append(center)
		var road_width := float(point.get_width_without_shoulders()) * 0.82
		for stripe_index in 6:
			var stripe_center := center + toward * (float(stripe_index) - 2.5) * 0.68
			oriented_box(presentation_root, stripe_center, toward, Vector3(road_width, 0.045, 0.34), CROSSWALK_COLOR)


func build_safe_prop_zones(district: Node3D) -> void:
	for node in district.find_children("*", "RoadPoint", true, false):
		var point := node as RoadPoint
		if not point or is_excluded_node(point):
			continue
		var clearance := float(point.get_width_with_shoulders()) * 0.5 + point.gutter_profile.x + 4.2
		for side_value in [-1.0, 1.0]:
			var position := point.global_position + point.global_transform.basis.x.normalized() * clearance * float(side_value)
			if is_inside_exclusion(position):
				continue
			var too_close := false
			for existing in safe_prop_positions:
				if existing.distance_to(position) < 18.0:
					too_close = true
					break
			if too_close:
				continue
			safe_prop_positions.append(position)
			debug_disc(position + Vector3.UP * 0.06, 3.2, Color(0.12, 1.0, 0.45, 0.24))


func is_excluded_node(node: Node) -> bool:
	return has_blocked_ancestor(node, ["roundabout", "intersection", "splitter", "ramp", "highway", "3way", "4way"])


func has_blocked_ancestor(node: Node, tokens: Array[String]) -> bool:
	var current := node
	while current and current != district_root:
		var lowered := current.name.to_lower()
		for token in tokens:
			if lowered.contains(token):
				return true
		current = current.get_parent()
	return false


func is_inside_exclusion(position: Vector3) -> bool:
	for index in exclusion_centers.size():
		if exclusion_centers[index].distance_to(position) < exclusion_radii[index]:
			return true
	return false


func oriented_box(parent: Node3D, center: Vector3, forward: Vector3, size: Vector3, color: Color, transparent := false) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	mesh_instance.global_position = center
	mesh_instance.look_at(center + forward, Vector3.UP)


func debug_disc(position: Vector3, radius: float, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.04
	mesh.radial_segments = 28
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	mesh_instance.mesh = mesh
	debug_root.add_child(mesh_instance)
	mesh_instance.global_position = position
