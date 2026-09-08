class_name BuilderLaneNetwork
extends RefCounted

const RoadContainerScript = preload("res://addons/road-generator/nodes/road_container.gd")
const RoadLaneScript = preload("res://addons/road-generator/nodes/road_lane.gd")
const RoadModuleRules = preload("res://scripts/map_builder/road_module_rules.gd")


static func build(manager: Node3D, map_data: Dictionary, world_offset: Vector3, catalog: Array) -> Node3D:
	var definitions := {}
	for definition in catalog:
		definitions[definition.id] = definition
	var container := RoadContainerScript.new() as Node3D
	container.name = "BuilderModuleLanes"
	container.set("create_geo", false)
	container.set("generate_ai_lanes", false)
	manager.add_child(container)
	var lanes: Array[RoadLane] = []
	var module_index := 0
	for item in map_data.get("items", []):
		if not item is Dictionary:
			continue
		var definition = definitions.get(String(item.get("id", "")))
		if definition == null or definition.module_rules.is_empty():
			continue
		var coordinates: Array = item.get("cell", [])
		if coordinates.size() < 2:
			continue
		var cell := Vector2i(int(coordinates[0]), int(coordinates[1]))
		var turns := posmod(int(item.get("turns", 0)), 4)
		var module_lanes: Array[RoadLane] = []
		match String(definition.module_rules.get("kind", "")):
			"straight":
				module_lanes = _build_straight_lanes(container, definition.module_rules, cell, turns, world_offset, module_index)
			"curve_90":
				module_lanes = _build_curve_lanes(container, definition.module_rules, cell, turns, world_offset, module_index)
			"transition":
				module_lanes = _build_transition_lanes(container, definition.module_rules, cell, turns, world_offset, module_index)
			"intersection_4":
				module_lanes = _build_intersection_lanes(container, definition.module_rules, cell, turns, world_offset, module_index)
			"intersection_t":
				module_lanes = _build_compact_t_lanes(container, definition.module_rules, cell, turns, world_offset, module_index)
		lanes.append_array(module_lanes)
		module_index += 1
	_link_continuations(lanes)
	var unlinked := 0
	for lane in lanes:
		if lane.lane_next.is_empty():
			unlinked += 1
			print("  UNLINKED ", lane.name, " end=", lane.get_lane_end(), " heading=", _lane_end_forward(lane))
	container.set_meta("lane_count", lanes.size())
	container.set_meta("unlinked_lane_count", unlinked)
	print("BUILDER LANE NETWORK: %d lanes, %d without continuation" % [lanes.size(), unlinked])
	return container


static func _build_straight_lanes(parent: Node3D, rules: Dictionary, cell: Vector2i, turns: int, offset: Vector3, module_index: int) -> Array[RoadLane]:
	var footprint := _rotated_footprint(rules, turns)
	var center := Vector3((cell.x + footprint.x * 0.5) * RoadModuleRules.GRID_SIZE, 0.1, (cell.y + footprint.y * 0.5) * RoadModuleRules.GRID_SIZE) + offset
	var forward := _direction_vector(turns)
	var length := (footprint.y if turns % 2 == 0 else footprint.x) * RoadModuleRules.GRID_SIZE
	var result: Array[RoadLane] = []
	var forward_count := int(rules.lanes_forward)
	var reverse_count := int(rules.lanes_reverse)
	result.append_array(_parallel_lanes(parent, center, forward, length, forward_count, module_index, "F", reverse_count == 0))
	result.append_array(_parallel_lanes(parent, center, -forward, length, reverse_count, module_index, "R", forward_count == 0))
	for lane in result:
		lane.set_meta("road_kind", "straight")
		lane.set_meta("one_way", reverse_count == 0 or forward_count == 0)
		lane.set_meta("same_direction_lane_count", forward_count if String(lane.get_meta("flow", "F")) == "F" else reverse_count)
	return result


static func _parallel_lanes(parent: Node3D, center: Vector3, forward: Vector3, length: float, count: int, module_index: int, flow: String, centered := false) -> Array[RoadLane]:
	var result: Array[RoadLane] = []
	var right := forward.cross(Vector3.UP).normalized()
	for lane_index in count:
		var lateral_offset := (float(lane_index) - float(count - 1) * 0.5) * RoadModuleRules.LANE_WIDTH if centered else (lane_index + 0.5) * RoadModuleRules.LANE_WIDTH
		var lane_center := center + right * lateral_offset
		var start := lane_center - forward * length * 0.5
		var finish := lane_center + forward * length * 0.5
		var lane := _make_lane(parent, "Module_%03d_%s%d" % [module_index, flow, lane_index], [start, finish])
		lane.set_meta("module_index", module_index)
		lane.set_meta("flow", flow)
		lane.set_meta("lane_index", lane_index)
		result.append(lane)
	_link_adjacent_lanes(result)
	return result


static func _build_transition_lanes(parent: Node3D, rules: Dictionary, cell: Vector2i, turns: int, offset: Vector3, module_index: int) -> Array[RoadLane]:
	var footprint := _rotated_footprint(rules, turns)
	var center := Vector3((cell.x + footprint.x * 0.5) * RoadModuleRules.GRID_SIZE, 0.1, (cell.y + footprint.y * 0.5) * RoadModuleRules.GRID_SIZE) + offset
	var forward := _direction_vector(turns)
	var right := forward.cross(Vector3.UP).normalized()
	var length := (footprint.y if turns % 2 == 0 else footprint.x) * RoadModuleRules.GRID_SIZE
	var forward_count := int(rules.get("lanes_forward", 0))
	var reverse_count := int(rules.get("lanes_reverse", 0))
	var one_way := reverse_count == 0
	var result: Array[RoadLane] = []
	var forward_lanes: Array[RoadLane] = []
	for lane_index in forward_count:
		# The one-way transition occupies two cells but its narrow port occupies
		# the first cell, so its lane center begins half a cell left of the module
		# center. This mirrors the explicit port offset used by validation.
		var start_lateral := -RoadModuleRules.LANE_WIDTH * 0.5 if one_way else RoadModuleRules.LANE_WIDTH * 0.5
		var end_lateral := (float(lane_index) - float(forward_count - 1) * 0.5) * RoadModuleRules.LANE_WIDTH if one_way else (lane_index + 0.5) * RoadModuleRules.LANE_WIDTH
		forward_lanes.append(_transition_lane(parent, center, forward, right, length, start_lateral, end_lateral, module_index, "F", lane_index))
	var reverse_lanes: Array[RoadLane] = []
	for lane_index in reverse_count:
		var wide_lateral := -(lane_index + 0.5) * RoadModuleRules.LANE_WIDTH
		var narrow_lateral := -RoadModuleRules.LANE_WIDTH * 0.5
		reverse_lanes.append(_transition_lane(parent, center, -forward, -right, length, -wide_lateral, -narrow_lateral, module_index, "R", lane_index))
	_link_adjacent_lanes(forward_lanes)
	_link_adjacent_lanes(reverse_lanes)
	result.append_array(forward_lanes)
	result.append_array(reverse_lanes)
	for lane in result:
		lane.set_meta("road_kind", "transition")
		lane.set_meta("one_way", one_way)
		lane.set_meta("same_direction_lane_count", forward_count if String(lane.get_meta("flow", "F")) == "F" else reverse_count)
	return result


static func _transition_lane(parent: Node3D, center: Vector3, forward: Vector3, right: Vector3, length: float, start_lateral: float, end_lateral: float, module_index: int, flow: String, lane_index: int) -> RoadLane:
	var points: Array[Vector3] = []
	for sample_index in range(7):
		var ratio := float(sample_index) / 6.0
		var eased := ratio * ratio * (3.0 - 2.0 * ratio)
		var along := lerpf(-length * 0.5, length * 0.5, ratio)
		var lateral := lerpf(start_lateral, end_lateral, eased)
		points.append(center + forward * along + right * lateral)
	var lane := _make_lane(parent, "Module_%03d_%s%d" % [module_index, flow, lane_index], points)
	lane.set_meta("module_index", module_index)
	lane.set_meta("flow", flow)
	lane.set_meta("lane_index", lane_index)
	return lane


static func _build_curve_lanes(parent: Node3D, rules: Dictionary, cell: Vector2i, turns: int, offset: Vector3, module_index: int) -> Array[RoadLane]:
	var width := float(rules.road_width)
	var footprint: Vector2i = _rotated_footprint(rules, turns)
	var pivot := Vector3((cell.x + footprint.x * 0.5) * RoadModuleRules.GRID_SIZE, 0.1, (cell.y + footprint.y * 0.5) * RoadModuleRules.GRID_SIZE) + offset
	# Build in the module's unrotated S->E orientation, then rotate clockwise in
	# grid space. Radius order preserves right-hand traffic through the corner.
	var base_center := Vector3((cell.x + int(rules.footprint[0])) * RoadModuleRules.GRID_SIZE, 0.1, (cell.y + int(rules.footprint[1])) * RoadModuleRules.GRID_SIZE) + offset
	var result: Array[RoadLane] = []
	var divider_radius := width * 0.5
	var forward_lanes: Array[RoadLane] = []
	for lane_index in int(rules.lanes_forward):
		var radius := (lane_index + 0.5) * RoadModuleRules.LANE_WIDTH if int(rules.lanes_reverse) == 0 else divider_radius - (lane_index + 0.5) * RoadModuleRules.LANE_WIDTH
		forward_lanes.append(_curve_lane(parent, base_center, pivot, radius, turns, false, module_index, "F", lane_index))
	var reverse_lanes: Array[RoadLane] = []
	for lane_index in int(rules.lanes_reverse):
		var radius := divider_radius + (lane_index + 0.5) * RoadModuleRules.LANE_WIDTH
		reverse_lanes.append(_curve_lane(parent, base_center, pivot, radius, turns, true, module_index, "R", lane_index))
	_link_adjacent_lanes(forward_lanes)
	_link_adjacent_lanes(reverse_lanes)
	result.append_array(forward_lanes)
	result.append_array(reverse_lanes)
	for lane in result:
		lane.set_meta("road_kind", "curve")
	return result


static func _curve_lane(parent: Node3D, center: Vector3, pivot: Vector3, radius: float, turns: int, reverse: bool, module_index: int, flow: String, lane_index: int) -> RoadLane:
	var points: Array[Vector3] = []
	for sample_index in range(13):
		var ratio := float(sample_index) / 12.0
		if reverse:
			ratio = 1.0 - ratio
		var angle := lerpf(PI, PI * 1.5, ratio)
		var point := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		points.append(_rotate_grid_point(point, pivot, turns))
	var lane := _make_lane(parent, "Module_%03d_%s%d" % [module_index, flow, lane_index], points)
	lane.set_meta("module_index", module_index)
	lane.set_meta("flow", flow)
	lane.set_meta("lane_index", lane_index)
	return lane


static func _build_intersection_lanes(parent: Node3D, rules: Dictionary, cell: Vector2i, turns: int, offset: Vector3, module_index: int) -> Array[RoadLane]:
	# Straight-through paths are the safe default. Turn paths become selectable
	# branches when intersection routing is added to the driver/NPC decision layer.
	var result: Array[RoadLane] = []
	result.append_array(_build_straight_lanes(parent, rules, cell, turns, offset, module_index))
	result.append_array(_build_straight_lanes(parent, rules, cell, (turns + 1) % 4, offset, module_index + 10000))
	for lane in result:
		lane.set_meta("road_kind", "intersection")
	return result


static func _build_compact_t_lanes(parent: Node3D, rules: Dictionary, cell: Vector2i, turns: int, offset: Vector3, module_index: int) -> Array[RoadLane]:
	# Preserve the normal two-way through lanes. The driving controller discovers
	# the perpendicular side road spatially and creates its smooth turn path, so a
	# synthetic lane across the unused half of this compact module is unnecessary.
	var result := _build_straight_lanes(parent, rules, cell, turns, offset, module_index)
	for lane in result:
		lane.set_meta("road_kind", "intersection")
		lane.set_meta("intersection_shape", "compact_t")
	return result


static func _make_lane(parent: Node3D, lane_name: String, points: Array[Vector3]) -> RoadLane:
	var lane := RoadLaneScript.new() as RoadLane
	lane.name = lane_name
	parent.add_child(lane)
	lane.curve = Curve3D.new()
	lane.curve.bake_interval = 0.35
	for point in points:
		lane.curve.add_point(parent.to_local(point))
	lane.add_to_group("road_lanes")
	return lane


static func _link_adjacent_lanes(lanes: Array[RoadLane]) -> void:
	for index in lanes.size():
		if index > 0:
			lanes[index].lane_left = lanes[index].get_path_to(lanes[index - 1])
		if index + 1 < lanes.size():
			lanes[index].lane_right = lanes[index].get_path_to(lanes[index + 1])


static func _link_continuations(lanes: Array[RoadLane]) -> void:
	for lane in lanes:
		var end := lane.get_lane_end()
		var end_forward := _lane_end_forward(lane)
		var best: RoadLane
		var best_score := INF
		for candidate in lanes:
			if candidate == lane:
				continue
			var distance := end.distance_to(candidate.get_lane_start())
			if distance > 0.35:
				continue
			var alignment := end_forward.dot(_lane_start_forward(candidate))
			if alignment < 0.55:
				continue
			var score := distance + (1.0 - alignment)
			if score < best_score:
				best = candidate
				best_score = score
		if best:
			lane.lane_next = lane.get_path_to(best)
			best.lane_prior = best.get_path_to(lane)


static func _lane_end_forward(lane: RoadLane) -> Vector3:
	var count := lane.curve.point_count
	return (lane.to_global(lane.curve.get_point_position(count - 1)) - lane.to_global(lane.curve.get_point_position(count - 2))).normalized()


static func _lane_start_forward(lane: RoadLane) -> Vector3:
	return (lane.to_global(lane.curve.get_point_position(1)) - lane.to_global(lane.curve.get_point_position(0))).normalized()


static func _rotated_footprint(rules: Dictionary, turns: int) -> Vector2i:
	var footprint := Vector2i(int(rules.footprint[0]), int(rules.footprint[1]))
	return Vector2i(footprint.y, footprint.x) if turns % 2 == 1 else footprint


static func _direction_vector(turns: int) -> Vector3:
	return [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)][turns]


static func _rotate_grid_point(point: Vector3, pivot: Vector3, turns: int) -> Vector3:
	var local := point - pivot
	for unused in turns:
		# Builder yaw uses Godot's positive Y rotation, which appears
		# counter-clockwise in X/Z grid coordinates.
		local = Vector3(local.z, local.y, -local.x)
	return pivot + local
