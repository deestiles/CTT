extends CharacterBody3D

enum DriveState {
	PARK,
	AUTO,
	PLAYER
}

@export var drive_state: DriveState = DriveState.AUTO

# Target speed in meters per second
@export var acceleration := 1 # in meters per sec squared
@export var target_speed := 30  # in meters per sec
@export var visualize_lane := false
@export var seek_ahead := 5.0 # How many meters in front of agent to seek position
@export var auto_register: bool = true

@onready var agent:RoadLaneAgent = get_node("%road_lane_agent")

# how big car difference triggers lane change
var lane_change_tolerance = 3
var pending_lane: RoadLane
var lane_change_progress := 0.0
var lane_change_duration := 1.15
var lane_change_speed := 18.0
var lane_change_start := Vector3.ZERO
var lane_change_control_a := Vector3.ZERO
var lane_change_control_b := Vector3.ZERO
var lane_change_end := Vector3.ZERO
var turn_speed_restore := -1
var intersection_turn_active := false
var lateral_lane_offset := 0.0
var target_lateral_lane_offset := 0.0

const transition_time_close := 0.05 # how close to end of a transition lane actor has to switch lane

const DEBUG_OUT: bool = false

func _ready() -> void:
	agent.visualize_lane = visualize_lane
	agent.auto_register = auto_register
	if DEBUG_OUT:
		print("Agent state: %s par, %s lane, %s manager" % [
			agent.actor, agent.current_lane, agent.road_manager
		])

	if not visible:
		set_process(false)
		set_physics_process(false)


## Generic function to calc speed
func get_signed_speed() -> float:
	return -velocity.z


func get_input() -> Vector3:
	match drive_state:
		DriveState.AUTO:
			return _get_auto_input()
		DriveState.PLAYER:
			return _get_player_input()
		_:
			return Vector3.ZERO


func _get_auto_input() -> Vector3:
	if ! is_instance_valid(agent.current_lane):
		return Vector3.ZERO

	var lane_move:int = 0
	var speed = get_signed_speed()
	var travel_direction: int = int(sign(speed))
	if agent.close_to_lane_end(abs(speed * transition_time_close), travel_direction):
		# Preserve the physical lane through the turn. Only use the original
		# left-search behavior if the intersection has no matching continuation.
		var continuation_found := agent.assign_spatial_continuation(travel_direction)
		if not continuation_found and agent.lane_index_from_identity(agent.current_lane) < 0:
			lane_move = agent.find_continued_lane(agent.LaneChangeDir.LEFT, sign(speed))
	else:
		# Traffic in the pursuit prototype uses its own clearance-aware lane-change
		# decisions. Do not let the demo actor independently jump to another lane.
		if bool(get_meta("managed_lane_changes", false)):
			return Vector3(0, 0, -1)
		var cur_cars:int = agent.cars_in_lane(RoadLaneAgent.LaneChangeDir.CURRENT)
		if (cur_cars > 1):
			var cur_cars_l:int = agent.cars_in_lane(agent.LaneChangeDir.LEFT)
			var cur_cars_r:int = agent.cars_in_lane(agent.LaneChangeDir.RIGHT)
			if (cur_cars_l >= 0) && (cur_cars - cur_cars_l > lane_change_tolerance):
				lane_move -= 1
			elif (cur_cars_r >= 0) && (cur_cars - cur_cars_r > lane_change_tolerance):
				lane_move += 1
	return Vector3(lane_move, 0, -1) # neg z is "forward"


func _get_player_input() -> Vector3:
	if ! is_instance_valid(agent.current_lane):
		return Vector3.ZERO

	var dir:float = 0
	var lane_move:int = 0
	if Input.is_action_pressed("ui_up"):
		dir += 1
	if Input.is_action_pressed("ui_down"):
		dir -= 1

	var speed = get_signed_speed()
	var travel_direction: int = int(sign(speed))
	if agent.close_to_lane_end(abs(speed* transition_time_close), travel_direction):
		if not agent.assign_spatial_continuation(travel_direction) and agent.lane_index_from_identity(agent.current_lane) < 0:
			lane_move = agent.find_continued_lane(agent.LaneChangeDir.LEFT, travel_direction)
	else:
		if Input.is_action_just_pressed("ui_left"):
			lane_move -= 1
		if Input.is_action_just_pressed("ui_right"):
			lane_move += 1
	return Vector3(lane_move, 0, -dir) # neg z is "forward"


func request_lane_change(direction: int) -> int:
	if direction == 0:
		return OK
	if is_instance_valid(pending_lane) or not is_instance_valid(agent.current_lane):
		return FAILED
	var candidate_path: NodePath = agent.current_lane.lane_right if direction > 0 else agent.current_lane.lane_left
	var candidate := agent.current_lane.get_node_or_null(candidate_path) as RoadLane
	if not is_instance_valid(candidate):
		return FAILED
	lane_change_progress = 0.0
	lane_change_duration = 1.05
	lane_change_start = global_position
	var forward := -global_transform.basis.z.normalized()
	var closest_local := candidate.curve.get_closest_point(candidate.to_local(global_position))
	var closest_offset := candidate.curve.get_closest_offset(closest_local)
	var approach_speed := maxf(18.0, absf(get_signed_speed()))
	lane_change_speed = approach_speed
	var forward_distance := clampf(approach_speed * lane_change_duration, 18.0, 48.0)
	var target := lane_target_across_modules(candidate, closest_offset, forward_distance)
	var prior := lane_target_across_modules(candidate, closest_offset, maxf(0.0, forward_distance - 4.0))
	pending_lane = target["lane"] as RoadLane
	lane_change_end = target["position"] as Vector3
	lane_change_end.y = global_position.y
	var lane_prior := prior["position"] as Vector3
	var lane_forward := (lane_change_end - lane_prior).normalized()
	lane_change_control_a = lane_change_start + forward * 6.0
	lane_change_control_b = lane_change_end - lane_forward * 6.0
	return OK


func lane_target_across_modules(start_lane: RoadLane, start_offset: float, distance: float) -> Dictionary:
	var lane := start_lane
	var offset := start_offset + distance
	var safety := 0
	while safety < 32:
		var length := lane.curve.get_baked_length()
		if offset <= length:
			break
		var next_lane := lane.get_node_or_null(lane.lane_next) as RoadLane
		if not is_instance_valid(next_lane):
			offset = length
			break
		offset -= length
		lane = next_lane
		safety += 1
	offset = clampf(offset, 0.0, lane.curve.get_baked_length())
	return {
		"lane": lane,
		"position": lane.to_global(lane.curve.sample_baked(offset)),
	}


func request_intersection_turn(target_lane: RoadLane, exit_position: Vector3, exit_forward: Vector3) -> int:
	if is_instance_valid(pending_lane) or not is_instance_valid(target_lane):
		return FAILED
	pending_lane = target_lane
	intersection_turn_active = true
	turn_speed_restore = target_speed
	# Cornering at cruising speed looks weightless. This affects only junction
	# turns; ordinary lane changes retain their full approach speed.
	target_speed = mini(target_speed, 9)
	lane_change_progress = 0.0
	lane_change_speed = maxf(9.0, absf(get_signed_speed()))
	lane_change_start = global_position
	lane_change_end = exit_position
	lane_change_end.y = global_position.y
	var current_forward := -global_transform.basis.z.normalized()
	# Scale the handles to compact builder junctions. Fixed eight-metre handles
	# bulged beyond a one-cell T-junction and crossed its corner sidewalk.
	var handle_length := clampf(lane_change_start.distance_to(lane_change_end) * 0.34, 3.0, 6.0)
	lane_change_control_a = lane_change_start + current_forward * handle_length
	lane_change_control_b = lane_change_end - exit_forward.normalized() * handle_length
	return OK


func cancel_lane_change() -> void:
	pending_lane = null
	lane_change_progress = 0.0
	if intersection_turn_active:
		target_speed = turn_speed_restore
		turn_speed_restore = -1
		intersection_turn_active = false


func bezier_position(t: float) -> Vector3:
	var inverse := 1.0 - t
	var position := inverse * inverse * inverse * lane_change_start
	position += 3.0 * inverse * inverse * t * lane_change_control_a
	position += 3.0 * inverse * t * t * lane_change_control_b
	position += t * t * t * lane_change_end
	return position


func sample_maneuver_ahead(distance: float) -> Vector3:
	if not is_instance_valid(pending_lane):
		return agent.test_move_along_lane(distance)
	var previous := bezier_position(lane_change_progress)
	var travelled := 0.0
	var sample_t := lane_change_progress
	while sample_t < 1.0:
		var next_t := minf(1.0, sample_t + 0.025)
		var next_position := bezier_position(next_t)
		var segment_length := previous.distance_to(next_position)
		if travelled + segment_length >= distance:
			return previous.lerp(next_position, (distance - travelled) / maxf(segment_length, 0.001))
		travelled += segment_length
		previous = next_position
		sample_t = next_t
	var exit_forward := (lane_change_end - lane_change_control_b).normalized()
	return lane_change_end + exit_forward * (distance - travelled)


func update_lane_change(delta: float) -> void:
	# Advance by local derivative so lane changes retain constant world speed;
	# intersection turns alone ease down toward their safe corner speed.
	if intersection_turn_active:
		lane_change_speed = move_toward(lane_change_speed, 9.0, 22.0 * delta)
	var current_t := lane_change_progress
	var current_inverse := 1.0 - current_t
	var current_tangent := 3.0 * current_inverse * current_inverse * (lane_change_control_a - lane_change_start)
	current_tangent += 6.0 * current_inverse * current_t * (lane_change_control_b - lane_change_control_a)
	current_tangent += 3.0 * current_t * current_t * (lane_change_end - lane_change_control_b)
	var parameter_step := lane_change_speed * delta / maxf(0.1, current_tangent.length())
	lane_change_progress = minf(1.0, lane_change_progress + parameter_step)
	var t := lane_change_progress
	var inverse := 1.0 - t
	var target_position := bezier_position(t)
	var tangent := 3.0 * inverse * inverse * (lane_change_control_a - lane_change_start)
	tangent += 6.0 * inverse * t * (lane_change_control_b - lane_change_control_a)
	tangent += 3.0 * t * t * (lane_change_end - lane_change_control_b)
	tangent.y = 0.0
	move_and_collide(target_position - global_position)
	if tangent.length_squared() > 0.001:
		look_at(global_position + tangent.normalized(), Vector3.UP)
	if lane_change_progress >= 1.0:
		agent.assign_lane(pending_lane)
		pending_lane = null
		if intersection_turn_active:
			target_speed = turn_speed_restore
			turn_speed_restore = -1
			intersection_turn_active = false


func lane_point_ahead(lane: RoadLane, distance: float) -> Vector3:
	var closest_local := lane.curve.get_closest_point(lane.to_local(global_position))
	var closest_offset := lane.curve.get_closest_offset(closest_local)
	var target_offset := clampf(closest_offset + distance, 0.0, lane.curve.get_baked_length())
	return lane.to_global(lane.curve.sample_baked(target_offset))


func _physics_process(delta: float) -> void:
	lateral_lane_offset = move_toward(lateral_lane_offset, target_lateral_lane_offset, 2.4 * delta)
	velocity.y = 0
	var target_dir:Vector3 = get_input()
	var target_velz = lerp(velocity.z, target_dir.z * target_speed, delta * acceleration)
	velocity.z = target_velz

	if int(target_dir.x) != 0:
		if bool(get_meta("smooth_lane_changes", false)):
			request_lane_change(int(target_dir.x))
		else:
			agent.change_lane(int(target_dir.x))

	if not is_instance_valid(agent.current_lane):
		var res = agent.assign_nearest_lane()
		if not res == OK:
			# A temporary lane miss must not delete the vehicle. This can happen at
			# modular seams while a maneuver completes; hold position and retry.
			velocity = Vector3.ZERO
			if not has_meta("reported_lane_miss"):
				set_meta("reported_lane_miss", true)
				push_warning("Vehicle could not find a lane; holding for recovery")
			return
		remove_meta("reported_lane_miss")
	if is_instance_valid(pending_lane):
		update_lane_change(delta)
		return

	# Find the next position to jump to; note that the car's forward is the
	# negative Z direction (conventional with Vector3.FORWARD), and thus
	# we flip the direction along the Z axis so that positive move direction
	# matches a positive move_along_lane call, while negative would be
	# going in reverse in the lane's intended direction.
	var move_dist: float = get_signed_speed() * delta

	var next_pos: Vector3 = agent.move_along_lane(move_dist)
	next_pos = _offset_lane_point(next_pos, agent.test_move_along_lane(1.0), lateral_lane_offset)
	# Road vehicles follow the lane across the ground plane.  A discontinuous
	# height sample at an intersection must never pitch or launch the body.
	next_pos.y = global_position.y
	var requested_motion := next_pos - global_position
	if bool(get_meta("smooth_lane_changes", false)):
		# Treat the new lane as a steering target, never as a position to teleport
		# toward. The body moves only in its current forward direction, so the nose
		# must turn first and the rear follows along the resulting driving arc.
		var steering_distance := maxf(7.0, absf(move_dist) * 12.0)
		if String(agent.current_lane.get_meta("road_kind", "")) == "curve":
			steering_distance = float(get_meta("curve_lookahead", steering_distance))
		var steering_target := agent.test_move_along_lane(steering_distance)
		# A curb yield is a controlled lateral pull-over, not a turn toward another
		# lane. Keep the nose following the lane while translating toward its edge.
		if absf(lateral_lane_offset) < 0.01:
			steering_target = _offset_lane_point(steering_target, agent.test_move_along_lane(steering_distance + 1.0), lateral_lane_offset)
		var desired_direction := steering_target - global_position
		desired_direction.y = 0.0
		if desired_direction.length_squared() > 0.001:
			var desired_yaw := atan2(-desired_direction.x, -desired_direction.z)
			var maximum_yaw_step := deg_to_rad(float(get_meta("lane_change_turn_rate", 72.0))) * delta
			rotation.y = rotate_toward(rotation.y, desired_yaw, maximum_yaw_step)
		requested_motion = -global_transform.basis.z * move_dist
		if absf(lateral_lane_offset) >= 0.01 or absf(target_lateral_lane_offset) >= 0.01:
			var lane := agent.current_lane
			var center_local := lane.curve.get_closest_point(lane.to_local(global_position))
			var center_world := lane.to_global(center_local)
			var center_offset := lane.curve.get_closest_offset(center_local)
			var future_offset := minf(lane.curve.get_baked_length(), center_offset + 1.0)
			var future_world := lane.to_global(lane.curve.sample_baked(future_offset))
			var shoulder_position := _offset_lane_point(center_world, future_world, lateral_lane_offset)
			shoulder_position.y = global_position.y
			var lateral_correction := shoulder_position - global_position
			lateral_correction.y = 0.0
			var maximum_pull := float(get_meta("curb_yield_lateral_speed", 4.2)) * delta
			if lateral_correction.length() > maximum_pull:
				lateral_correction = lateral_correction.normalized() * maximum_pull
			# Resolve the pull-over separately so a police bumper touching the rear
			# cannot cancel the sideways escape along with forward motion.
			move_and_collide(lateral_correction)
	# The lane-envelope bound is only meaningful on straight roads. Transitions,
	# curves and intersections legitimately move the lane laterally, so applying
	# the bound there wrongly rejects motion and strands the player (e.g. stuck at
	# a 1->2 lane expansion). Civilians have no bound and pass freely, so match
	# that everywhere except straights.
	if bool(get_meta("road_bounds_enabled", false)) \
			and String(agent.current_lane.get_meta("road_kind", "")) == "straight" \
			and not motion_stays_on_road(requested_motion):
		# Retain free movement between lanes, but reject the frame that would put
		# the vehicle center beyond the drivable lane envelope.
		requested_motion = Vector3.ZERO
		velocity.z = move_toward(velocity.z, 0.0, target_speed * delta * 7.0)
	var collision := move_and_collide(requested_motion)
	if collision:
		# Road lanes provide steering, while CharacterBody collision prevents
		# vehicles from being advanced through a stopped or slower vehicle.
		velocity.z = move_toward(velocity.z, 0.0, target_speed * delta * 5.0)

	# Get another point a little further in front for orientation seeking,
	# without actually moving the vehicle (ie don't update the assign lane
	# if this margin puts us into the next lane in front)
	var orientation:Vector3 = agent.test_move_along_lane(0.25)
	var flat_direction := orientation - global_position
	flat_direction.y = 0.0
	if flat_direction.length_squared() > 0.0001:
		# Yaw-only steering keeps every vehicle upright after bumper contact and
		# prevents wheels from leaving the flat road surface at lane joins.
		if not bool(get_meta("smooth_lane_changes", false)):
			look_at(global_position + flat_direction.normalized(), Vector3.UP)


func _offset_lane_point(point: Vector3, future_point: Vector3, offset: float) -> Vector3:
	if absf(offset) < 0.001:
		return point
	var forward := future_point - point
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = -global_transform.basis.z
	var right := forward.normalized().cross(Vector3.UP).normalized()
	return point + right * offset


func motion_stays_on_road(motion: Vector3) -> bool:
	if not is_instance_valid(agent.current_lane):
		return false
	var predicted := global_position + motion
	var closest_local := agent.current_lane.curve.get_closest_point(agent.current_lane.to_local(predicted))
	var closest_world := agent.current_lane.to_global(closest_local)
	closest_world.y = predicted.y
	# Adjacent same-direction lanes are five metres apart. This radius permits
	# crossing their divider but keeps the vehicle body inside the outer curb.
	return predicted.distance_to(closest_world) <= 3.35
