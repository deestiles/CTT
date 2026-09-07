extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/chase/grid_streets_test.tscn") as PackedScene
	var world := packed.instantiate()
	root.add_child(world)
	for frame in 12:
		await physics_frame

	var player := world.get("player") as Node3D
	var traffic: Array = world.get("traffic")
	if not is_instance_valid(player) or traffic.is_empty():
		_fail("test scene did not provide a player and civilian traffic")
		return
	var civilian := traffic[0] as Node3D
	var player_agent := player.get_node("road_lane_agent") as RoadLaneAgent
	var civilian_agent := civilian.get_node("road_lane_agent") as RoadLaneAgent
	var start_lane := _find_test_lane(world, "straight")
	if not is_instance_valid(start_lane):
		_fail("no connected straight single-lane one-way test lane exists")
		return
	var civilian_lane := start_lane
	for step in 2:
		civilian_lane = civilian_lane.get_node_or_null(civilian_lane.lane_next) as RoadLane
		if not is_instance_valid(civilian_lane):
			_fail("test lane continuation ended before the civilian placement")
			return

	_place_actor(player, player_agent, start_lane, 1.0)
	_place_actor(civilian, civilian_agent, civilian_lane, civilian_lane.curve.get_baked_length() * 0.5)
	world.set("npc_awareness_timer", 0.0)
	world.call("update_npc_awareness", 0.2)

	var commanded_offset := float(civilian.get("target_lateral_lane_offset"))
	var yielding := bool(civilian.get_meta("yielding_to_police", false))
	print("YIELD CHECK lane=", civilian_lane.name,
		" road_kind=", civilian_lane.get_meta("road_kind", "missing"),
		" one_way=", civilian_lane.get_meta("one_way", "missing"),
		" lane_count=", civilian_lane.get_meta("same_direction_lane_count", "missing"),
		" distance=", player.global_position.distance_to(civilian.global_position),
		" yielding=", yielding,
		" target_offset=", commanded_offset)
	if not yielding or commanded_offset < 2.5:
		_fail("police-behind detection did not issue the curb-yield command")
		return

	var before := _distance_from_lane_center(civilian, civilian_lane)
	for frame in 90:
		await physics_frame
	var after := _distance_from_lane_center(civilian, civilian_agent.current_lane)
	print("YIELD MOTION before=", before, " after=", after,
		" actual_offset=", civilian.get("lateral_lane_offset"),
		" still_yielding=", civilian.get_meta("yielding_to_police", false))
	if after < 2.2:
		_fail("civilian received the command but did not move to the curb")
		return
	var intersection_lane := _find_test_lane(world, "intersection")
	if is_instance_valid(intersection_lane):
		_place_actor(civilian, civilian_agent, intersection_lane, intersection_lane.curve.get_baked_length() * 0.5)
		var prior_lane := intersection_lane.get_node_or_null(intersection_lane.lane_prior) as RoadLane
		if is_instance_valid(prior_lane):
			_place_actor(player, player_agent, prior_lane, maxf(0.0, prior_lane.curve.get_baked_length() - 1.0))
			civilian.set_meta("yielding_to_police", false)
			civilian.set("target_lateral_lane_offset", 0.0)
			civilian.set("lateral_lane_offset", 0.0)
			world.set("npc_awareness_timer", 0.0)
			world.call("update_npc_awareness", 0.2)
			print("SIGNAL APPROACH CHECK yielding=", civilian.get_meta("yielding_to_police", false),
				" target_offset=", civilian.get("target_lateral_lane_offset"))
			if not bool(civilian.get_meta("yielding_to_police", false)) or float(civilian.get("target_lateral_lane_offset")) < 2.5:
				_fail("one-way straight-through intersection lane rejected curb yielding")
				return
	print("NPC_CURB_YIELD_TEST: PASS")
	quit(0)


func _find_test_lane(world: Node, road_kind: String) -> RoadLane:
	for node in world.get_node("IntersectionDistrict/RoadManager").find_children("*", "RoadLane", true, false):
		var lane := node as RoadLane
		if not is_instance_valid(lane):
			continue
		if String(lane.get_meta("road_kind", "")) != road_kind:
			continue
		if not bool(lane.get_meta("one_way", false)) or int(lane.get_meta("same_direction_lane_count", 0)) != 1:
			continue
		var next_lane := lane.get_node_or_null(lane.lane_next) as RoadLane
		if not is_instance_valid(next_lane):
			continue
		var next_next := next_lane.get_node_or_null(next_lane.lane_next) as RoadLane
		if is_instance_valid(next_next) and String(next_next.get_meta("road_kind", "")) == "straight":
			return lane
	return null


func _place_actor(actor: Node3D, agent: RoadLaneAgent, lane: RoadLane, offset: float) -> void:
	agent.unassign_lane()
	agent.assign_lane(lane)
	actor.global_position = lane.to_global(lane.curve.sample_baked(offset)) + Vector3.UP * 0.08
	var ahead := lane.to_global(lane.curve.sample_baked(minf(lane.curve.get_baked_length(), offset + 1.0)))
	actor.look_at(ahead, Vector3.UP)
	actor.set("velocity", Vector3.ZERO)


func _distance_from_lane_center(actor: Node3D, lane: RoadLane) -> float:
	if not is_instance_valid(lane):
		return 0.0
	var closest := lane.to_global(lane.curve.get_closest_point(lane.to_local(actor.global_position)))
	closest.y = actor.global_position.y
	return actor.global_position.distance_to(closest)


func _fail(message: String) -> void:
	push_error("NPC_CURB_YIELD_TEST: FAIL — " + message)
	quit(1)
