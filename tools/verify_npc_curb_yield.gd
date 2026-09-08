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
	if not is_instance_valid(player) or traffic.size() < 4:
		_fail("exploration scene did not restore four civilian vehicles")
		return
	var civilian := traffic[0] as Node3D
	var player_agent := player.get_node("road_lane_agent") as RoadLaneAgent
	var civilian_agent := civilian.get_node("road_lane_agent") as RoadLaneAgent
	var start_lane := _find_test_lane(world)
	if not is_instance_valid(start_lane):
		_fail("no connected straight single-lane one-way test lane exists")
		return
	var civilian_lane := start_lane
	for step in 2:
		civilian_lane = civilian_lane.get_node_or_null(civilian_lane.lane_next) as RoadLane
		if not is_instance_valid(civilian_lane):
			_fail("test route ended before the civilian placement")
			return

	_place_actor(player, player_agent, start_lane, 0.5)
	_place_actor(civilian, civilian_agent, civilian_lane, civilian_lane.curve.get_baked_length() * 0.5)
	world.set("npc_awareness_timer", 0.0)
	world.call("update_npc_awareness", 0.2)
	if not bool(civilian.get_meta("yielding_to_police", false)) or float(civilian.get("target_lateral_lane_offset")) < 2.5:
		_fail("police-behind detection did not command a curb yield")
		return

	for frame in 90:
		await physics_frame
	var curb_distance := _distance_from_lane_center(civilian, civilian_agent.current_lane)
	print("YIELD MOTION distance_from_center=", curb_distance,
		" actual_offset=", civilian.get("lateral_lane_offset"),
		" traffic_count=", traffic.size())
	if curb_distance < 2.2:
		_fail("civilian received the yield command but did not reach the curb")
		return

	# Simulate more than the civilian stall timeout while the yield is held. The
	# watchdog must neither accumulate stall time nor recycle this actor.
	var held_lane := civilian_agent.current_lane
	civilian.set("target_speed", 0)
	civilian.set("velocity", Vector3.ZERO)
	world.set("recovery_positions", {civilian: civilian.global_position})
	world.set("recovery_stall_times", {civilian: 3.9})
	world.set("recovery_cooldowns", {civilian: 0.0})
	for sample in 12:
		world.set("recovery_check_timer", 0.0)
		world.call("update_recovery_watchdog", 0.4)
	if civilian_agent.current_lane != held_lane:
		_fail("watchdog recycled a deliberately yielding civilian")
		return
	if float(world.get("recovery_stall_times").get(civilian, -1.0)) != 0.0:
		_fail("watchdog accumulated stall time during an intentional yield")
		return

	print("NPC_CURB_YIELD_TEST: PASS")
	world.queue_free()
	quit(0)


func _find_test_lane(world: Node) -> RoadLane:
	for node in world.get_node("IntersectionDistrict/RoadManager").find_children("*", "RoadLane", true, false):
		var lane := node as RoadLane
		if not is_instance_valid(lane) or String(lane.get_meta("road_kind", "")) != "straight":
			continue
		if not bool(lane.get_meta("one_way", false)) or int(lane.get_meta("same_direction_lane_count", 0)) != 1:
			continue
		var next_lane := lane.get_node_or_null(lane.lane_next) as RoadLane
		var next_next := next_lane.get_node_or_null(next_lane.lane_next) as RoadLane if is_instance_valid(next_lane) else null
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
