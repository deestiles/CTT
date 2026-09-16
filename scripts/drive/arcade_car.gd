extends CharacterBody3D
class_name ArcadeCar
## Kinematic arcade car. It does NOT use gravity or physics-settling to find the
## ground — that approach let the body be shoved upward by ground colliders and
## climb buildings (the "floating" bug). Instead the car is *pinned* to the road
## height every frame, exactly like the city's own placed cars, and moves only in
## the horizontal plane. Buildings still block it (its collision box sits just
## above the road so it meets walls but never the ground).
##
## Autopilot follows a fixed route of ground waypoints (real road coordinates);
## any manual input (W/A/S/D) overrides it.

@export_group("Visual")
## Child Node3D holding the Synty car mesh. Empty => a child named "Visual".
@export var visual_path: NodePath
## Auto-scale the visual so its longest horizontal extent matches this many
## world units. 0 (default) keeps native scale, matching the city's own cars.
@export var target_length: float = 0.0
## Fine vertical nudge applied after raycast seating (metres). Tune if the
## wheels sit slightly into or above the road.
@export var seat_offset: float = 0.0

@export_group("Handling")
@export var max_speed: float = 24.0          # m/s manual top (~86 km/h)
@export var max_reverse_speed: float = 7.0
@export var accel: float = 16.0
@export var brake_decel: float = 30.0
@export var coast_decel: float = 9.0
@export var turn_rate: float = 1.6           # rad/s at full steer authority
## How quickly steering eases toward the input (per second). Lower = smoother.
@export var steer_response: float = 4.0
## Fraction of turn rate retained at top speed (speed-sensitive steering).
@export var high_speed_turn: float = 0.45
@export var boost_mult: float = 1.5

@export_group("Autopilot")
@export var autopilot: bool = false
@export var autopilot_speed: float = 12.0    # cruise m/s on city streets
@export var route: PackedVector3Array = PackedVector3Array()
@export var waypoint_reach: float = 7.0      # advance when this close (XZ)
## Drive by pathfinding on the baked road NavMesh instead of a fixed route.
@export var use_navigation: bool = false
## When assigned, navigation targets are chosen to increase distance from this
## pursuer instead of wandering randomly. This remains road-NavMesh bounded.
@export var evasion_enabled: bool = false
@export var evasion_retarget_seconds: float = 5.0

@export_group("Ambient traffic rules")
@export var obey_traffic_rules: bool = false
@export var following_distance: float = 9.0
@export var traffic_stop_points: PackedVector3Array = PackedVector3Array()
@export var traffic_axis_x: bool = true

var _agent: NavigationAgent3D
var _nav_ready_frames: int = 0
var _evasion_target: Node3D
var _evasion_retarget_time: float = 0.0

const VEHICLE_LIGHT_SHADER := preload("res://Assets/Synty/PolygonCity/Materials/Misc/Vehicle_Runtime_Lights.gdshader")
const VEHICLE_TEXTURE := preload("res://Assets/Synty/PolygonCity/Textures/PolygonCity_01_A.png")

var speed: float = 0.0                        # signed: + forward, - reverse
var _steer_smooth: float = 0.0                # eased steering value
var night_lights: bool = false               # headlights + running lights on
var _body: MeshInstance3D
var _light_mat: ShaderMaterial
var _braking: bool = false
var _reversing: bool = false
## On-screen joystick vector (x=right, y=down); set by the HUD joystick.
var touch_input: Vector2 = Vector2.ZERO

var _visual: Node3D
var _shape: CollisionShape3D
var _spawn: Transform3D
var _wp: int = 0
var _wheel_offset: float = -0.1      # car's lowest point relative to its pivot
var _grounded_y: float = 0.0         # last good road height for the pivot
var _grounded_once: bool = false
var _last_pos: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0
var _reverse_time: float = 0.0       # >0 => backing out of an obstacle

# Mesh-audited lamp positions and rear-lens bounds. Values are body-local and
# intentionally keyed per model: these vehicles do not share lamp geometry.
const VEHICLE_LIGHT_PROFILES := {
	"SM_Veh_Car_Police_01": {"head": Vector3(0.78, 0.75, 2.63), "tail_z": Vector2(-2.30, -2.05), "tail_y": Vector2(0.75, 1.06), "tail_x": Vector2(0.50, 0.98)},
	"SM_Veh_Car_Sedan_01": {"head": Vector3(0.55, 0.75, 2.58), "tail_z": Vector2(-2.30, -2.05), "tail_y": Vector2(0.75, 1.06), "tail_x": Vector2(0.50, 0.98)},
	"SM_Veh_Car_Taxi_01": {"head": Vector3(0.55, 0.75, 2.58), "tail_z": Vector2(-2.30, -2.05), "tail_y": Vector2(0.75, 1.06), "tail_x": Vector2(0.50, 0.98)},
	"SM_Veh_Car_Small_01": {"head": Vector3(0.62, 0.60, 2.02), "tail_z": Vector2(-1.85, -1.44), "tail_y": Vector2(0.72, 1.22), "tail_x": Vector2(0.48, 0.82)},
	"SM_Veh_Car_Van_01": {"head": Vector3(0.90, 0.88, 2.48), "tail_z": Vector2(-2.33, -2.16), "tail_y": Vector2(0.75, 1.07), "tail_x": Vector2(0.73, 1.08)},
	"SM_Veh_Car_Muscle_01": {"head": Vector3(0.94, 0.58, 2.82), "tail_z": Vector2(-2.67, -2.49), "tail_y": Vector2(0.47, 0.88), "tail_x": Vector2(0.34, 1.08)},
}

func set_night_lights(enabled: bool) -> void:
	night_lights = enabled
	_update_vehicle_lights()

func _ready() -> void:
	add_to_group("arcade_vehicle")
	_spawn = global_transform
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING   # no gravity / floor logic
	_visual = get_node_or_null(visual_path)
	if _visual == null:
		_visual = get_node_or_null("Visual")
	_neutralize_prefab_colliders(self)
	_fit_visual_and_collision()
	_setup_pedestrian_impact_sensor()
	_setup_vehicle_lights()
	_grounded_y = global_position.y
	_last_pos = global_position
	if use_navigation:
		_agent = NavigationAgent3D.new()
		_agent.radius = 1.4
		_agent.path_desired_distance = 3.0
		_agent.target_desired_distance = 4.0
		_agent.path_max_distance = 50.0
		_agent.avoidance_enabled = false
		add_child(_agent)
	# Store the respawn only after live physics has seated the wheels on the road.
	call_deferred("_seat_and_capture_spawn")

func _seat_and_capture_spawn() -> void:
	await get_tree().physics_frame
	_grounded_once = false
	_ground_car()
	_spawn = global_transform

## A non-blocking overlap volume lets the fast arcade car trigger pedestrian
## reactions without pedestrians becoming hard walls that can wedge the vehicle.
func _setup_pedestrian_impact_sensor() -> void:
	if _shape == null or _shape.shape == null:
		return
	var sensor := Area3D.new()
	sensor.name = "PedestrianImpactSensor"
	sensor.collision_layer = 4
	sensor.collision_mask = 2
	sensor.monitoring = true
	sensor.monitorable = true
	var sensor_shape := CollisionShape3D.new()
	sensor_shape.shape = _shape.shape.duplicate()
	sensor_shape.transform = _shape.transform
	sensor.add_child(sensor_shape)
	add_child(sensor)

## The Synty vehicle prefab ships its own StaticBody3D colliders (body + wheels).
## Disable them so they never interfere with our single kinematic body.
func _neutralize_prefab_colliders(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D and child != self:
			var co := child as CollisionObject3D
			co.collision_layer = 0
			co.collision_mask = 0
		_neutralize_prefab_colliders(child)

## Build a collision box that spans the car body but starts just ABOVE the road,
## so the car meets building walls but is never touched (and pushed up) by the
## flat ground colliders. The visual keeps its native pivot (wheels on the road).
func _fit_visual_and_collision() -> void:
	_shape = get_node_or_null("Collision") as CollisionShape3D
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "Collision"
		add_child(_shape)
	var box := BoxShape3D.new()

	var s: float = 1.0
	var aabb := AABB()
	if _visual:
		aabb = _combined_aabb(_visual)
	if _visual == null or aabb.size == Vector3.ZERO:
		box.size = Vector3(2.0, 1.3, 4.6)
		_shape.shape = box
		_shape.position = Vector3(0, 0.9, 0)
		return

	var longest: float = max(aabb.size.x, aabb.size.z)
	if target_length > 0.0 and longest > 0.001:
		s = target_length / longest
		_visual.scale = Vector3(s, s, s)

	var scaled := AABB(aabb.position * s, aabb.size * s)
	_wheel_offset = scaled.position.y               # lowest visual point vs pivot
	var top_y: float = scaled.position.y + scaled.size.y
	var bottom_y: float = 0.15                       # clear the road surface
	box.size = Vector3(
		max(scaled.size.x, 0.5),
		max(top_y - bottom_y, 0.6),
		max(scaled.size.z, 0.5))
	_shape.shape = box
	_shape.position = Vector3(scaled.get_center().x, (bottom_y + top_y) * 0.5, scaled.get_center().z)

func _combined_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var has_any := false
	for node in _all_visual_instances(root):
		var vi := node as VisualInstance3D
		var local: AABB = vi.get_aabb()
		var xf: Transform3D = root.global_transform.affine_inverse() * vi.global_transform
		var node_aabb: AABB = xf * local
		if not has_any:
			result = node_aabb
			has_any = true
		else:
			result = result.merge(node_aabb)
	return result

func _all_visual_instances(node: Node) -> Array:
	var out: Array = []
	if node is VisualInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_visual_instances(c))
	return out

## Call after assigning `route` so autopilot starts at the nearest waypoint.
func begin_autopilot() -> void:
	autopilot = true
	if route.size() < 2:
		return
	var best := 0
	var best_d := INF
	for i in route.size():
		var d: float = global_position.distance_squared_to(route[i])
		if d < best_d:
			best_d = d
			best = i
	_wp = best

func set_evasion_target(target: Node3D) -> void:
	_evasion_target = target
	evasion_enabled = target != null
	_evasion_retarget_time = 0.0

func _physics_process(delta: float) -> void:
	_evasion_retarget_time = maxf(0.0, _evasion_retarget_time - delta)
	# Stuck-recovery: if the autopilot is wedged against something, back straight
	# out for a moment and skip ahead, so it never freezes on stray geometry.
	if autopilot and _reverse_time > 0.0:
		_reverse_time -= delta
		speed = -6.0
		var back := -global_transform.basis.z
		back.y = 0.0
		velocity = back.normalized() * speed
		move_and_slide()
		_ground_car()
		_constrain_to_road()
		_last_pos = global_position
		_braking = false
		_update_vehicle_lights()
		return

	var accel_cmd := 0.0
	var brake_cmd := 0.0
	var steer_cmd := 0.0
	var boosting := false

	# Combine keyboard and on-screen joystick (up = throttle, down = brake/reverse,
	# left/right = steer).
	var m_accel := maxf(Input.get_action_strength("accelerate"), maxf(0.0, -touch_input.y))
	var m_brake := maxf(Input.get_action_strength("brake_reverse"), maxf(0.0, touch_input.y))
	var m_steer := clampf(Input.get_action_strength("move_left") - Input.get_action_strength("move_right") - touch_input.x, -1.0, 1.0)
	var manual := m_accel > 0.05 or m_brake > 0.05 or absf(m_steer) > 0.05

	if use_navigation and _agent != null and not manual:
		var cmd := _nav_command()
		accel_cmd = cmd.x
		brake_cmd = cmd.y
		steer_cmd = cmd.z
	elif autopilot and route.size() >= 2 and not manual:
		var cmd := _autopilot_command()
		accel_cmd = cmd.x
		brake_cmd = cmd.y
		steer_cmd = cmd.z
	else:
		accel_cmd = m_accel
		brake_cmd = m_brake
		steer_cmd = m_steer
		boosting = Input.is_action_pressed("boost")

	if obey_traffic_rules and not manual:
		var rule_brake := _traffic_rule_brake()
		if rule_brake > 0.0:
			accel_cmd = 0.0
			brake_cmd = maxf(brake_cmd, rule_brake)

	var top := max_speed * (boost_mult if boosting else 1.0)

	if accel_cmd > 0.0:
		if speed < 0.0:
			speed += brake_decel * accel_cmd * delta
		else:
			speed += accel * accel_cmd * delta
	elif brake_cmd > 0.0:
		if speed > 0.1:
			speed -= brake_decel * brake_cmd * delta
		elif not autopilot:
			speed -= accel * 0.6 * brake_cmd * delta   # reverse (manual only)
	else:
		if speed > 0.0:
			speed = max(speed - coast_decel * delta, 0.0)
		elif speed < 0.0:
			speed = min(speed + coast_decel * delta, 0.0)

	speed = clampf(speed, -max_reverse_speed, top)
	_braking = brake_cmd > 0.05 and speed > 0.3      # brake pedal while moving fwd

	# Ease steering toward the command, and turn more gently the faster we go.
	_steer_smooth = move_toward(_steer_smooth, steer_cmd, steer_response * delta)
	var authority := clampf(absf(speed) / 4.0, 0.0, 1.0)
	var speed_factor := lerpf(1.0, high_speed_turn, clampf(absf(speed) / max_speed, 0.0, 1.0))
	if absf(speed) > 0.15:
		rotate_y(_steer_smooth * turn_rate * authority * speed_factor * signf(speed) * delta)

	# Move only in the horizontal plane; walls (buildings) block via move_and_slide.
	var forward := -global_transform.basis.z
	forward.y = 0.0
	velocity = forward.normalized() * speed
	move_and_slide()
	_push_knockable_props()

	_ground_car()
	_constrain_to_road()

	# Detect a wedge: commanded to drive but barely moving.
	if autopilot:
		var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
		if absf(speed) > 2.0 and moved < 0.02:      # wants to move but is wedged
			_stuck_time += delta
			if _stuck_time > 0.7:
				_stuck_time = 0.0
				_reverse_time = 0.6
				if use_navigation and _agent != null:
					_pick_new_target()               # reroute after backing out
				elif route.size() > 0:
					_wp = (_wp + 2) % route.size()   # aim past the blockage
		else:
			_stuck_time = maxf(0.0, _stuck_time - delta)
	_last_pos = global_position
	_update_vehicle_lights()

## Maintain a safe queue gap and stop before authored signal lines. These checks
## supplement the lane route; they never choose a new direction or cross a lane.
func _traffic_rule_brake() -> float:
	var forward := -global_transform.basis.z.normalized()
	var from := global_position + Vector3.UP * 0.7
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * following_distance)
	query.exclude = [get_rid()]
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var other := hit.collider as Node
		if other and other.is_in_group("arcade_vehicle"):
			var distance := from.distance_to(hit.position)
			return clampf(1.0 - distance / following_distance, 0.35, 1.0)
	var city := get_parent()
	if city == null or not city.has_method("get_traffic_state_for_axis"):
		return 0.0
	if int(city.get_traffic_state_for_axis(traffic_axis_x)) == 2:
		return 0.0
	for stop_point in traffic_stop_points:
		var offset := stop_point - global_position
		offset.y = 0.0
		var ahead := offset.dot(forward)
		var lateral := (offset - forward * ahead).length()
		if ahead > 0.0 and ahead < 13.0 and lateral < 2.2:
			return clampf(1.0 - ahead / 13.0, 0.45, 1.0)
	return 0.0

## CharacterBody motion does not automatically transfer satisfying momentum to
## lightweight rigid props, so explicitly turn slide contacts into an arcade hit.
func _push_knockable_props() -> void:
	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		var body := hit.get_collider() as RigidBody3D
		if body == null or not body.is_in_group("knockable_city_prop"):
			continue
		body.freeze = false
		body.sleeping = false
		var direction := Vector3(velocity.x, 0.0, velocity.z).normalized()
		if direction == Vector3.ZERO:
			direction = -global_transform.basis.z.normalized()
		var strength := clampf(absf(speed) * body.mass * 0.75, 2.0, 22.0)
		body.apply_central_impulse(direction * strength + Vector3.UP * strength * 0.22)

## Apply the Polygon City runtime-light shader to the car body so its real
## tail/brake/reverse lens meshes can emit, and add forward headlight spots.
func _setup_vehicle_lights() -> void:
	if _visual == null:
		return
	for c in _visual.get_children():
		if c is MeshInstance3D:
			_body = c as MeshInstance3D
			break
	if _body == null:
		return
	_light_mat = ShaderMaterial.new()
	_light_mat.shader = VEHICLE_LIGHT_SHADER
	_light_mat.set_shader_parameter("albedo_texture", VEHICLE_TEXTURE)
	_light_mat.set_shader_parameter("tail_energy", 0.0)
	_light_mat.set_shader_parameter("brake_energy", 0.0)
	_light_mat.set_shader_parameter("reverse_energy", 0.0)
	var profile: Dictionary = VEHICLE_LIGHT_PROFILES.get(String(_body.name), VEHICLE_LIGHT_PROFILES["SM_Veh_Car_Police_01"])
	_light_mat.set_shader_parameter("tail_z_range", profile["tail_z"])
	_light_mat.set_shader_parameter("tail_y_range", profile["tail_y"])
	_light_mat.set_shader_parameter("tail_abs_x_range", profile["tail_x"])
	_body.set_surface_override_material(0, _light_mat)
	var head: Vector3 = profile["head"]
	# Each source sits at that model's authored front lamp in body-local space.
	for i in 2:
		var hl := SpotLight3D.new()
		hl.name = "Headlight%d" % i
		hl.position = Vector3(-head.x if i == 0 else head.x, head.y, head.z)
		hl.rotation_degrees.y = 180.0
		hl.light_color = Color("#fff3cf")
		hl.light_energy = 7.0
		hl.spot_range = 42.0
		hl.spot_angle = 34.0
		hl.spot_attenuation = 1.2
		hl.visible = false
		_body.add_child(hl)

func _update_vehicle_lights() -> void:
	if _light_mat == null:
		return
	_reversing = speed < -0.2
	_light_mat.set_shader_parameter("tail_energy", 3.0 if night_lights else 0.0)
	_light_mat.set_shader_parameter("brake_energy", 6.0 if _braking else 0.0)
	_light_mat.set_shader_parameter("reverse_energy", 3.2 if _reversing else 0.0)
	if _body:
		for hl in _body.find_children("Headlight*", "SpotLight3D", false, false):
			(hl as SpotLight3D).visible = night_lights

func get_vehicle_light_debug() -> Dictionary:
	var headlights := 0
	var visible_headlights := 0
	if _body:
		for node in _body.find_children("Headlight*", "SpotLight3D", false, false):
			headlights += 1
			if (node as SpotLight3D).visible:
				visible_headlights += 1
	return {
		"material_ready": _light_mat != null,
		"headlights": headlights,
		"visible_headlights": visible_headlights,
		"night_lights": night_lights,
		"tail_energy": float(_light_mat.get_shader_parameter("tail_energy")) if _light_mat else 0.0,
		"body": String(_body.name) if _body else "none",
		"headlight_position": (_body.get_node_or_null("Headlight0") as SpotLight3D).position if _body and _body.get_node_or_null("Headlight0") else Vector3.ZERO,
	}

## Keep the car on the drivable NavMesh: if it strays too far off (onto a
## sidewalk during a wide/U-turn), pull it back toward the nearest road point.
func _constrain_to_road() -> void:
	if not use_navigation or _agent == null or _nav_ready_frames < 5:
		return
	var map := get_world_3d().navigation_map
	var cp := NavigationServer3D.map_get_closest_point(map, global_position)
	if cp == Vector3.ZERO:
		return
	var dx := global_position.x - cp.x
	var dz := global_position.z - cp.z
	var d := sqrt(dx * dx + dz * dz)
	if d > 2.0:
		var pull := (d - 2.0) / d
		var p := global_position
		p.x -= dx * pull
		p.z -= dz * pull
		global_position = p

## Raycast straight down onto whatever road is beneath the car and seat the
## wheels on it. Self-correcting for any location/height; keeps the last good
## height if the ray misses (e.g. over a gap) so the car never falls or floats.
func _ground_car() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 4.0
	var to := global_position + Vector3.DOWN * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collision_mask = collision_mask
	var hit := space.intersect_ray(q)
	if hit:
		var hy := float(hit.position.y) - _wheel_offset + seat_offset
		# Accept curbs/ramps, but reject snapping up onto a building base/roof
		# (which would let the car "climb" structures). Buildings still block it.
		if not _grounded_once or absf(hy - _grounded_y) < 1.5:
			_grounded_y = hy
			_grounded_once = true
	var p := global_position
	p.y = _grounded_y
	global_position = p

## Returns Vector3(accel_cmd, brake_cmd, steer_cmd) to roam the road NavMesh.
func _nav_command() -> Vector3:
	if _nav_ready_frames < 5:
		_nav_ready_frames += 1
		if _nav_ready_frames == 5:
			# Snap onto the nearest road so we never start on a sidewalk.
			var map := get_world_3d().navigation_map
			var snapped := NavigationServer3D.map_get_closest_point(map, global_position)
			if snapped != Vector3.ZERO:
				global_position = Vector3(snapped.x, global_position.y, snapped.z)
			_pick_new_target()
		return Vector3.ZERO
	if _agent.is_navigation_finished():
		_pick_new_target()
	elif evasion_enabled and _evasion_retarget_time <= 0.0:
		_pick_new_target()
	return _steer_towards(_agent.get_next_path_position())

func _pick_new_target() -> void:
	var map := get_world_3d().navigation_map
	var chosen := NavigationServer3D.map_get_random_point(map, 1, false)
	if evasion_enabled and is_instance_valid(_evasion_target):
		var best_score := -INF
		var away_now := global_position - _evasion_target.global_position
		away_now.y = 0.0
		away_now = away_now.normalized()
		# Sampling the entire baked road surface lets the thief use every connected
		# street. Distance, forward escape direction, and useful trip length keep it
		# fleeing rather than oscillating around the nearest intersection.
		for _sample_index in 18:
			var candidate := NavigationServer3D.map_get_random_point(map, 1, false)
			if candidate == Vector3.ZERO:
				continue
			var trip := candidate - global_position
			trip.y = 0.0
			var trip_length := trip.length()
			if trip_length < 22.0:
				continue
			var escape_alignment := trip.normalized().dot(away_now)
			var police_distance := candidate.distance_to(_evasion_target.global_position)
			var score := police_distance * 1.35 + trip_length * 0.22 + escape_alignment * 18.0
			if score > best_score:
				best_score = score
				chosen = candidate
	_agent.target_position = chosen
	_evasion_retarget_time = evasion_retarget_seconds * randf_range(0.8, 1.25)

func get_navigation_debug() -> Dictionary:
	if _agent == null:
		return {"ready": false}
	var map := get_world_3d().navigation_map
	var closest := NavigationServer3D.map_get_closest_point(map, global_position)
	return {
		"ready": _nav_ready_frames >= 5,
		"target": _agent.target_position,
		"off_navmesh": global_position.distance_to(closest),
		"evading": evasion_enabled and is_instance_valid(_evasion_target),
	}

## Shared seek: accel/brake/steer to head toward a world point on the road.
func _steer_towards(target: Vector3) -> Vector3:
	var to := target - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return Vector3(0.3, 0.0, 0.0)
	var desired := to.normalized()
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var cross_y := fwd.cross(desired).y
	var facing := fwd.dot(desired)
	var steer_cmd := clampf(cross_y * 3.0, -1.0, 1.0)
	if facing < 0.4:
		steer_cmd = 1.0 if cross_y >= 0.0 else -1.0
	var turn_factor := clampf(facing, 0.25, 1.0)
	var target_v := autopilot_speed * turn_factor
	var accel_cmd := 0.0
	var brake_cmd := 0.0
	if speed < target_v:
		accel_cmd = 1.0
	elif speed > target_v + 1.5:
		brake_cmd = clampf((speed - target_v) / 3.0, 0.0, 1.0)
	return Vector3(accel_cmd, brake_cmd, steer_cmd)

## Returns Vector3(accel_cmd, brake_cmd, steer_cmd) to follow the route.
func _autopilot_command() -> Vector3:
	var wp: Vector3 = route[_wp]
	var to := wp - global_position
	to.y = 0.0
	if to.length() < waypoint_reach:
		_wp = (_wp + 1) % route.size()
		wp = route[_wp]
		to = wp - global_position
		to.y = 0.0
	if to.length() < 0.01:
		return Vector3(0, 1, 0)
	var desired := to.normalized()
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var cross_y := fwd.cross(desired).y
	var facing := fwd.dot(desired)
	var steer_cmd := clampf(cross_y * 3.0, -1.0, 1.0)
	# When the target is off to the side or behind, commit to a full turn toward
	# it (breaks the dead-ahead/dead-behind symmetry and drives the U-turns).
	if facing < 0.4:
		steer_cmd = 1.0 if cross_y >= 0.0 else -1.0
	var turn_factor := clampf(facing, 0.25, 1.0)
	var target_v := autopilot_speed * turn_factor
	var accel_cmd := 0.0
	var brake_cmd := 0.0
	if speed < target_v:
		accel_cmd = 1.0
	elif speed > target_v + 1.5:
		brake_cmd = clampf((speed - target_v) / 3.0, 0.0, 1.0)
	return Vector3(accel_cmd, brake_cmd, steer_cmd)

func reset_to_spawn() -> void:
	speed = 0.0
	velocity = Vector3.ZERO
	_steer_smooth = 0.0
	_stuck_time = 0.0
	_reverse_time = 0.0
	touch_input = Vector2.ZERO
	global_transform = _spawn
	_grounded_y = _spawn.origin.y
	_grounded_once = false
	_ground_car()
	_last_pos = global_position
	_evasion_retarget_time = 0.0
	if autopilot:
		begin_autopilot()

func get_speed_kmh() -> float:
	return absf(speed) * 3.6

func get_impact_velocity() -> Vector3:
	return velocity
