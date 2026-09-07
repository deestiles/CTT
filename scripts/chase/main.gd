extends Node3D

const SafeCaptureMeterScript = preload("res://scripts/interface/safe_capture_meter.gd")
const LANES := [-3.2, 0.0, 3.2]
const ROAD_LENGTH := 24.0
const ROAD_COUNT := 18
const START_TIME := 60.0
const ENABLE_JUNCTIONS := false
const ENABLE_PHYSICAL_INTERSECTIONS := true

@export_range(1, 10, 1) var case_difficulty := 1

var lane_index := 1
var target_x := 0.0
var speed := 22.0
var chase_time := START_TIME
var suspect_distance := 72.0
var damage := 0.0
var nos := 100.0
var apprehend := 0.0
var skill_multiplier := 1.0
var suspect_damage := 0.0
var running := true
var boosting := false
var road_parts: Array[Node3D] = []
var traffic: Array[Node3D] = []
var player_car: Node3D
var suspect_car: Node3D
var camera: Camera3D
var timer_label: Label
var distance_label: Label
var damage_bar: ProgressBar
var nos_bar: ProgressBar
var status_label: Label
var result_panel: Control
var result_title: Label
var result_details: Label
var result_primary_button: Button
var result_secondary_button: Button
var result_protect_button: Button
var last_result_won := false
var failure_life_resolved := false
var peak_skill_multiplier := 1.0
var swipe_start := Vector2.ZERO
var junction_visual: Node3D
var junction_panel: PanelContainer
var junction_timer_bar: ProgressBar
var junction_street_label: Label
var junction_active := false
var junction_choice_made := false
var junction_countdown := 0.0
var next_junction_time := START_TIME - 9.0
var suspect_turn := 0
var turn_direction := 0
var turn_animation := 0.0
var turn_curve := 0.0
var camera_shake := 0.0
var street_index := 0
var streets := ["HARBOR AVENUE", "KING STREET", "FOUNDRY ROAD", "RIVERSIDE DRIVE", "MARKET & 12TH", "UNION STREET"]
var suspect_lane_index := 1
var suspect_decision_timer := 0.0
var suspect_collision_cooldown := 0.0
var apprehend_bar: ProgressBar
var skill_label: Label
var capture_button: Button
var capture_panel: PanelContainer
var capture_meter: Control
var capture_active := false
var capture_cursor := 0.0
var capture_direction := 1.0
var capture_target_min := 38.0
var capture_target_max := 64.0
var capture_base_speed := 62.0
var capture_current_speed := 62.0
var backup_car: Node3D
var backup_active := false
var backup_crashing := false
var backup_timer := 0.0
var backup_crash_timer := 0.0
var backup_available := true
var backup_button: Button
var spike_node: Node3D
var spike_active := false
var spike_lane := 1
var spike_charges := 2
var spike_button: Button
var spike_panel: PanelContainer
var thief_slow_timer := 0.0
var player_slow_timer := 0.0
var camera_mode := 0
var map_active := false
var camera_button: Button
var map_button: Button
var map_overlay: PanelContainer
var physical_intersection_state := 0
var physical_intersection_direction := 1
var physical_intersection_progress := 0.0
var physical_intersection_choice := 99
var next_physical_intersection_time := START_TIME - 10.0
var suspect_turn_start := Vector3.ZERO
var player_turn_start := Vector3.ZERO
var navigation_panel: PanelContainer
var navigation_label: Label
var follow_turn_button: Button
var transition_fade: ColorRect
var turn_world_positions: Array[Vector3] = []
var turn_world_rotations: Array[float] = []
var player_turn_pivot := Vector3.ZERO
var physical_camera_yaw := 0.0
var cockpit_node: Node3D

const PANEL_NAVY := Color("#111629")
const POLICE_BLUE := Color("#3b82ff")
const SIREN_RED := Color("#ff3b4e")
const APPREHEND_GREEN := Color("#2fe0a0")
const HAZARD_AMBER := Color("#ffb23e")
const TACTICAL_VIOLET := Color("#9a6bff")


func _ready() -> void:
	build_world()
	build_hud()
	spawn_traffic()
	target_x = LANES[lane_index]


func _process(delta: float) -> void:
	if not running:
		return
	if map_active:
		update_camera(delta)
		return
	if capture_active:
		update_capture_sequence(delta)
		return

	handle_input()
	chase_time = maxf(0.0, chase_time - delta)
	boosting = Input.is_action_pressed("boost") and nos > 0.0
	var current_speed := speed
	if boosting:
		current_speed += 12.0
		nos = maxf(0.0, nos - 25.0 * delta)
		suspect_distance -= 5.5 * delta
		skill_multiplier = minf(3.0, skill_multiplier + 0.12 * delta)
	else:
		nos = minf(100.0, nos + 8.0 * delta)
		suspect_distance += sin(Time.get_ticks_msec() * 0.0018) * 0.018
	if turn_animation > 0.0:
		current_speed *= 0.74
	if physical_intersection_state >= 2:
		current_speed *= 0.58
	player_slow_timer = maxf(0.0, player_slow_timer - delta)
	thief_slow_timer = maxf(0.0, thief_slow_timer - delta)
	if player_slow_timer > 0.0:
		current_speed *= 0.62
	if thief_slow_timer > 0.0:
		suspect_distance = maxf(12.0, suspect_distance - 4.8 * delta)

	var corner_offset := turn_curve * 1.35
	player_car.position.x = lerpf(player_car.position.x, target_x + corner_offset, delta * 8.5)
	player_car.rotation.z = lerpf(player_car.rotation.z, (target_x - player_car.position.x) * -0.055, delta * 8.0)
	player_car.rotation.y = lerpf(player_car.rotation.y, turn_curve * 0.78, delta * 6.0)

	move_road(delta, current_speed)
	move_traffic(delta, current_speed)
	update_backup(delta)
	update_spikes(delta, current_speed)
	if physical_intersection_state not in [2, 3, 4]:
		update_suspect(delta)
	if ENABLE_PHYSICAL_INTERSECTIONS:
		update_physical_intersection(delta, current_speed)
	if ENABLE_JUNCTIONS:
		update_junction(delta, current_speed)
	update_camera(delta)
	peak_skill_multiplier = maxf(peak_skill_multiplier, skill_multiplier)
	suspect_distance = maxf(12.0, suspect_distance)
	if suspect_distance <= 18.0 and not capture_active:
		apprehend = 100.0
		status_label.text = "CAPTURE RANGE · MATCH SPEED"
		begin_capture_sequence()
	update_hud()

	if chase_time <= 0.0:
		finish_chase(false, "THIEF ESCAPED")
	elif damage >= 100.0:
		finish_chase(false, "UNIT DISABLED")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT:
			if ENABLE_JUNCTIONS and junction_active:
				choose_turn(-1)
			else:
				change_lane(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_RIGHT:
			if ENABLE_JUNCTIONS and junction_active:
				choose_turn(1)
			else:
				change_lane(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_UP and ENABLE_JUNCTIONS and junction_active:
			choose_turn(0)
			get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch:
		if event.pressed:
			swipe_start = event.position
		else:
			var swipe: Vector2 = event.position - swipe_start
			if absf(swipe.x) > 45.0:
				change_lane(1 if swipe.x > 0.0 else -1)


func handle_input() -> void:
	if Input.is_action_just_pressed("move_left"):
		if ENABLE_JUNCTIONS and junction_active:
			choose_turn(-1)
		else:
			change_lane(-1)
	if Input.is_action_just_pressed("move_right"):
		if ENABLE_JUNCTIONS and junction_active:
			choose_turn(1)
		else:
			change_lane(1)


func change_lane(direction: int) -> void:
	lane_index = clampi(lane_index + direction, 0, LANES.size() - 1)
	target_x = LANES[lane_index]


func build_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#142746")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8297bd")
	env.ambient_light_energy = 0.86
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.78
	env.glow_bloom = 0.14
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	sun.light_color = Color("#ffd8ae")
	sun.light_energy = 1.28
	sun.shadow_enabled = true
	add_child(sun)

	for i in ROAD_COUNT:
		var segment := Node3D.new()
		segment.position.z = 12.0 - i * ROAD_LENGTH
		add_child(segment)
		road_parts.append(segment)
		add_box(segment, Vector3(11.0, 0.18, ROAD_LENGTH), Color("#202a34"), Vector3(0.0, -0.12, 0.0))
		add_box(segment, Vector3(0.12, 0.025, ROAD_LENGTH), Color("#d7d4c8"), Vector3(-1.6, 0.0, 0.0))
		add_box(segment, Vector3(0.12, 0.025, ROAD_LENGTH), Color("#d7d4c8"), Vector3(1.6, 0.0, 0.0))
		add_box(segment, Vector3(2.8, 0.28, ROAD_LENGTH), Color("#17212c"), Vector3(-6.9, -0.05, 0.0))
		add_box(segment, Vector3(2.8, 0.28, ROAD_LENGTH), Color("#17212c"), Vector3(6.9, -0.05, 0.0))
		if i % 2 == 0:
			add_buildings(segment, -8.5)
			add_buildings(segment, 8.5)

	player_car = create_car(Color("#123b63"), true)
	player_car.position = Vector3(0.0, 0.75, 6.0)
	add_child(player_car)

	suspect_car = create_car(Color("#b12631"), false)
	suspect_car.position = Vector3(0.0, 0.75, -38.0)
	add_child(suspect_car)

	backup_car = create_car(Color("#174d7a"), true)
	backup_car.position = Vector3(-3.2, 0.75, 24.0)
	backup_car.visible = false
	add_child(backup_car)

	spike_node = create_spike_strip()
	spike_node.visible = false
	add_child(spike_node)

	camera = Camera3D.new()
	camera.position = Vector3(0.0, 7.3, 14.5)
	camera.rotation_degrees = Vector3(-19.0, 0.0, 0.0)
	camera.fov = 56.0
	add_child(camera)
	build_cockpit()

	junction_visual = Node3D.new()
	junction_visual.visible = false
	add_child(junction_visual)
	add_box(junction_visual, Vector3(32.0, 0.2, 12.0), Color("#26333d"), Vector3(0.0, -0.1, 0.0))
	add_box(junction_visual, Vector3(210.0, 0.18, 10.5), Color("#202a34"), Vector3(0.0, -0.11, 0.0))
	add_box(junction_visual, Vector3(0.15, 0.03, 12.0), Color("#d7d4c8"), Vector3(-5.25, 0.03, 0.0))
	add_box(junction_visual, Vector3(0.15, 0.03, 12.0), Color("#d7d4c8"), Vector3(5.25, 0.03, 0.0))
	for side in [-1.0, 1.0]:
		add_box(junction_visual, Vector3(18.0, 0.16, 8.5), Color("#202a34"), Vector3(side * 14.0, -0.08, 0.0))
		add_box(junction_visual, Vector3(18.0, 0.04, 0.12), Color("#d7d4c8"), Vector3(side * 14.0, 0.03, -2.0))
		add_box(junction_visual, Vector3(18.0, 0.04, 0.12), Color("#d7d4c8"), Vector3(side * 14.0, 0.03, 2.0))


func add_buildings(parent: Node3D, side_x: float) -> void:
	for j in 3:
		var height := 4.0 + float((j * 3 + road_parts.size()) % 7)
		var facade_colors := [Color("#31556a"), Color("#73473e"), Color("#445a54"), Color("#66527a")]
		var building_x := side_x + j * signf(side_x) * 2.8
		var building_z := -7.5 + j * 7.2
		var color: Color = facade_colors[(j + road_parts.size()) % facade_colors.size()]
		add_box(parent, Vector3(2.6, height, 5.4), color, Vector3(building_x, height * 0.5, building_z))
		add_box(parent, Vector3(2.82, 0.22, 5.62), color.lightened(0.16), Vector3(building_x, height + 0.08, building_z))
		# Warm modular windows sell the miniature city without texture memory.
		var street_face_x := building_x - signf(side_x) * 1.32
		for floor_index in range(1, mini(3, int(height / 1.45))):
			for window_z in [-1.35, 1.35]:
				add_glow_box(parent, Vector3(0.05, 0.48, 0.58), Color("#ffd28a"), Vector3(street_face_x, floor_index * 1.32, building_z + window_z))
		if j == 0:
			add_box(parent, Vector3(0.82, 0.15, 2.35), color.lightened(0.3), Vector3(street_face_x - signf(side_x) * 0.42, 1.22, building_z))
			add_street_tree(parent, Vector3(side_x - signf(side_x) * 1.55, 0.0, building_z + 2.65))


func add_box(parent: Node, box_size: Vector3, color: Color, local_position: Vector3) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	box.material = material
	mesh_instance.mesh = box
	mesh_instance.position = local_position
	parent.add_child(mesh_instance)
	return mesh_instance


func add_glow_box(parent: Node, box_size: Vector3, color: Color, local_position: Vector3) -> MeshInstance3D:
	var mesh_instance := add_box(parent, box_size, color, local_position)
	var material := mesh_instance.mesh.material as StandardMaterial3D
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.7
	return mesh_instance


func add_street_tree(parent: Node, local_position: Vector3) -> void:
	add_cylinder(parent, 0.12, 1.15, Color("#6d4931"), local_position + Vector3(0.0, 0.58, 0.0))
	for canopy_offset in [Vector3(0.0, 1.65, 0.0), Vector3(-0.25, 1.38, 0.0), Vector3(0.25, 1.38, 0.0)]:
		add_sphere(parent, 0.62, Color("#5b7c3c"), local_position + canopy_offset)


func add_cylinder(parent: Node, radius: float, height: float, color: Color, local_position: Vector3) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius * 1.08
	cylinder.height = height
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.68
	cylinder.material = material
	mesh_instance.mesh = cylinder
	mesh_instance.position = local_position
	parent.add_child(mesh_instance)
	return mesh_instance


func add_sphere(parent: Node, radius: float, color: Color, local_position: Vector3) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	sphere.material = material
	mesh_instance.mesh = sphere
	mesh_instance.position = local_position
	parent.add_child(mesh_instance)
	return mesh_instance


func build_cockpit() -> void:
	cockpit_node = Node3D.new()
	cockpit_node.visible = false
	camera.add_child(cockpit_node)
	add_box(cockpit_node, Vector3(5.8, 0.72, 1.8), Color("#111824"), Vector3(0.0, -1.28, -2.05))
	add_box(cockpit_node, Vector3(2.25, 0.38, 0.78), Color("#172438"), Vector3(0.0, -0.93, -2.0))
	add_glow_box(cockpit_node, Vector3(1.45, 0.06, 0.08), POLICE_BLUE, Vector3(0.0, -0.83, -1.58))
	add_box(cockpit_node, Vector3(0.9, 0.42, 0.18), Color("#243348"), Vector3(-2.0, -1.0, -1.42))
	add_box(cockpit_node, Vector3(0.9, 0.42, 0.18), Color("#243348"), Vector3(2.0, -1.0, -1.42))
	add_glow_box(cockpit_node, Vector3(1.15, 0.07, 0.12), SIREN_RED, Vector3(-0.62, -0.62, -2.82))
	add_glow_box(cockpit_node, Vector3(1.15, 0.07, 0.12), POLICE_BLUE, Vector3(0.62, -0.62, -2.82))


func create_car(color: Color, police: bool) -> Node3D:
	var car := Node3D.new()
	add_box(car, Vector3(2.15, 0.65, 4.25), color, Vector3(0.0, 0.42, 0.0))
	add_box(car, Vector3(1.82, 0.22, 2.55), color.lightened(0.08), Vector3(0.0, 0.78, -0.1))
	add_box(car, Vector3(1.62, 0.62, 1.82), Color("#14283a"), Vector3(0.0, 1.02, -0.16))
	add_box(car, Vector3(1.48, 0.1, 1.68), color.lightened(0.14), Vector3(0.0, 1.37, -0.12))
	add_box(car, Vector3(2.18, 0.12, 0.7), Color("#eef5f7") if police else color.lightened(0.08), Vector3(0.0, 0.5, 0.1))
	var front_wheels: Array[Node3D] = []
	for x in [-1.08, 1.08]:
		for z in [-1.35, 1.35]:
			var wheel := add_box(car, Vector3(0.26, 0.5, 0.76), Color("#080b0e"), Vector3(x, 0.25, z))
			if z < 0.0:
				front_wheels.append(wheel)
	# Lighting makes the front (-Z) unmistakable as it enters a corner.
	add_box(car, Vector3(0.5, 0.18, 0.08), Color("#fff3bd"), Vector3(-0.68, 0.52, -2.15))
	add_box(car, Vector3(0.5, 0.18, 0.08), Color("#fff3bd"), Vector3(0.68, 0.52, -2.15))
	add_box(car, Vector3(0.42, 0.16, 0.08), Color("#e52e3d"), Vector3(-0.7, 0.52, 2.15))
	add_box(car, Vector3(0.42, 0.16, 0.08), Color("#e52e3d"), Vector3(0.7, 0.52, 2.15))
	car.set_meta("front_wheels", front_wheels)
	if police:
		add_glow_box(car, Vector3(0.7, 0.12, 0.22), POLICE_BLUE, Vector3(-0.4, 1.55, 0.0))
		add_glow_box(car, Vector3(0.7, 0.12, 0.22), SIREN_RED, Vector3(0.4, 1.55, 0.0))
	return car


func create_spike_strip() -> Node3D:
	var strip := Node3D.new()
	add_box(strip, Vector3(2.5, 0.08, 0.55), Color("#161b20"), Vector3.ZERO)
	for i in 7:
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.07
		cone.height = 0.25
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#d7dce0")
		cone.material = material
		spike.mesh = cone
		spike.position = Vector3(-1.05 + i * 0.35, 0.15, 0.0)
		strip.add_child(spike)
	return strip


func spawn_traffic() -> void:
	for i in 8:
		var traffic_car := create_car(Color.from_hsv(fmod(float(i) * 0.13, 1.0), 0.35, 0.62), false)
		traffic_car.scale = Vector3.ONE * 0.82
		traffic_car.position = Vector3(LANES[i % 3], 0.62, -35.0 - i * 35.0)
		traffic_car.set_meta("hit", false)
		traffic_car.set_meta("lane", i % 3)
		traffic_car.set_meta("near_miss", false)
		traffic_car.set_meta("suspect_hit", false)
		traffic_car.set_meta("pull_over", false)
		traffic_car.set_meta("pull_over_x", 0.0)
		traffic_car.set_meta("spike_hit", false)
		traffic_car.set_meta("tire_slow", 0.0)
		add_child(traffic_car)
		traffic.append(traffic_car)


func move_road(delta: float, current_speed: float) -> void:
	for part in road_parts:
		part.position.z += current_speed * delta
		if part.position.z > 32.0:
			part.position.z -= ROAD_LENGTH * ROAD_COUNT
		var depth_factor: float = clampf((-part.position.z) / 165.0, 0.0, 1.0)
		part.position.x = -turn_curve * depth_factor * 48.0
		part.rotation.y = -turn_curve * 0.28


func move_traffic(delta: float, current_speed: float) -> void:
	for car in traffic:
		var tire_slow: float = maxf(0.0, float(car.get_meta("tire_slow", 0.0)) - delta)
		car.set_meta("tire_slow", tire_slow)
		var traffic_speed_scale := 0.32 if tire_slow > 0.0 else 0.72
		car.position.z += current_speed * delta * traffic_speed_scale
		if car.position.z > 20.0:
			car.position.z -= 280.0
			var new_lane: int = randi() % LANES.size()
			car.set_meta("lane", new_lane)
			car.set_meta("hit", false)
			car.set_meta("near_miss", false)
			car.set_meta("suspect_hit", false)
			car.set_meta("pull_over", false)
			car.set_meta("spike_hit", false)
			car.set_meta("tire_slow", 0.0)
		var traffic_lane: int = int(car.get_meta("lane", 1))
		var depth_factor: float = clampf((-car.position.z) / 165.0, 0.0, 1.0)
		var traffic_target_x: float = LANES[traffic_lane] - turn_curve * depth_factor * 48.0
		if bool(car.get_meta("pull_over", false)):
			traffic_target_x = float(car.get_meta("pull_over_x", traffic_target_x))
		var traffic_delta_x := traffic_target_x - car.position.x
		car.position.x = lerpf(car.position.x, traffic_target_x, delta * (8.0 if bool(car.get_meta("pull_over", false)) else 5.0))
		car.rotation.y = lerpf(car.rotation.y, turn_curve * 0.46, delta * 5.0)
		car.rotation.z = lerpf(car.rotation.z, -traffic_delta_x * 0.08, delta * 6.0)
		if not car.get_meta("hit") and absf(car.position.z - player_car.position.z) < 2.2 and absf(car.position.x - player_car.position.x) < 1.55:
			car.set_meta("hit", true)
			damage = minf(100.0, damage + 25.0)
			suspect_distance += 9.0
			apprehend = maxf(0.0, apprehend - 18.0)
			skill_multiplier = 1.0
			status_label.text = "COLLISION · DAMAGE +25"
			camera_shake = 0.7
		elif not car.get_meta("near_miss") and car.position.z > player_car.position.z and car.position.z < player_car.position.z + 2.8:
			var side_gap := absf(car.position.x - player_car.position.x)
			if side_gap >= 1.55 and side_gap < 2.9:
				car.set_meta("near_miss", true)
				skill_multiplier = minf(3.0, skill_multiplier + 0.18)

		if suspect_collision_cooldown <= 0.0 and not car.get_meta("suspect_hit") and absf(car.position.z - suspect_car.position.z) < 2.4 and absf(car.position.x - suspect_car.position.x) < 1.48:
			resolve_suspect_collision(car, traffic_lane)


func update_suspect(delta: float) -> void:
	suspect_collision_cooldown = maxf(0.0, suspect_collision_cooldown - delta)
	suspect_decision_timer -= delta
	if suspect_decision_timer <= 0.0 and not junction_active:
		choose_suspect_lane()
		suspect_decision_timer = randf_range(0.8, 1.55) if apprehend > 70.0 else randf_range(1.4, 2.5)
	var suspect_lane: float = LANES[suspect_lane_index]
	suspect_car.position.z = lerpf(suspect_car.position.z, 6.0 - clampf(suspect_distance * 0.62, 13.0, 82.0), delta * 2.5)
	var suspect_depth: float = clampf((-suspect_car.position.z) / 165.0, 0.0, 1.0)
	var suspect_road_offset := -turn_curve * suspect_depth * 48.0
	suspect_car.position.x = lerpf(suspect_car.position.x, suspect_lane + suspect_road_offset, delta * 1.4)
	suspect_car.rotation.y = lerpf(suspect_car.rotation.y, turn_curve * 0.68, delta * 5.5)
	if junction_active:
		var clue_x := LANES[0] if suspect_turn < 0 else (LANES[2] if suspect_turn > 0 else LANES[1])
		suspect_car.position.x = lerpf(suspect_car.position.x, clue_x, delta * 2.3)

	if suspect_distance < 50.0:
		var proximity_gain := 4.5 + (50.0 - suspect_distance) * 0.24
		apprehend = minf(100.0, apprehend + proximity_gain * skill_multiplier * delta)
		skill_multiplier = minf(3.0, skill_multiplier + 0.045 * delta)
	elif suspect_distance > 68.0:
		apprehend = maxf(0.0, apprehend - 4.0 * delta)
		skill_multiplier = maxf(1.0, skill_multiplier - 0.12 * delta)


func choose_suspect_lane() -> void:
	var lane_scores := [0.0, 0.0, 0.0]
	for car in traffic:
		var lane_id: int = int(car.get_meta("lane", 1))
		var relative_z := car.position.z - suspect_car.position.z
		if relative_z > -5.0 and relative_z < 28.0:
			lane_scores[lane_id] += 35.0 - relative_z
	for i in LANES.size():
		lane_scores[i] += absf(float(i - suspect_lane_index)) * 1.5
	var safest_lane := 0
	for i in range(1, LANES.size()):
		if lane_scores[i] < lane_scores[safest_lane]:
			safest_lane = i
	var desperate := apprehend > 75.0
	if desperate and randf() < 0.24:
		suspect_lane_index = randi() % LANES.size()
	else:
		suspect_lane_index = safest_lane


func resolve_suspect_collision(car: Node3D, traffic_lane: int) -> void:
	car.set_meta("suspect_hit", true)
	suspect_collision_cooldown = 1.0
	suspect_damage = minf(100.0, suspect_damage + 18.0)
	suspect_distance = maxf(18.0, suspect_distance - 9.0)
	apprehend = minf(100.0, apprehend + 14.0)
	skill_multiplier = minf(3.0, skill_multiplier + 0.25)
	var escape_lane := traffic_lane + (-1 if traffic_lane >= 2 else 1)
	if traffic_lane == 1:
		escape_lane = 0 if randf() < 0.5 else 2
	car.set_meta("lane", clampi(escape_lane, 0, LANES.size() - 1))
	status_label.text = "SUSPECT COLLISION · TRAFFIC SWERVING"
	camera_shake = 0.35


func start_physical_intersection() -> void:
	physical_intersection_state = 1
	physical_intersection_choice = 99
	physical_intersection_direction = -1 if randf() < 0.5 else 1
	junction_visual.position = Vector3(0.0, 0.0, -125.0)
	junction_visual.rotation = Vector3.ZERO
	junction_visual.visible = true
	status_label.text = "INTERSECTION AHEAD"


func update_physical_intersection(delta: float, current_speed: float) -> void:
	if physical_intersection_state == 0:
		if chase_time <= next_physical_intersection_time:
			start_physical_intersection()
		return

	# Hold the junction still while a car is physically rounding the corner.
	# Moving it and rotating recycled road tiles at the same time caused jitter.
	if physical_intersection_state in [1, 3, 5]:
		junction_visual.position.z += current_speed * delta

	if physical_intersection_state == 1:
		if junction_visual.position.z >= suspect_car.position.z - 1.5:
			physical_intersection_state = 2
			physical_intersection_progress = 0.0
			suspect_turn_start = suspect_car.position
			for car in traffic:
				car.visible = false
			backup_button.disabled = true
			spike_button.disabled = true
			status_label.text = "SUSPECT TURNING"
		return

	if physical_intersection_state == 2:
		physical_intersection_progress = minf(1.0, physical_intersection_progress + delta / 1.15)
		var eased := smoothstep(0.0, 1.0, physical_intersection_progress)
		apply_corner_arc(suspect_car, suspect_turn_start, physical_intersection_direction, 13.0, eased)
		if physical_intersection_progress >= 0.22 and not navigation_panel.visible:
			show_navigation_choice()
		if physical_intersection_progress >= 1.0:
			physical_intersection_state = 3
		return

	if physical_intersection_state == 3:
		suspect_car.position.x += float(physical_intersection_direction) * 7.5 * delta
		suspect_car.position.z = junction_visual.position.z
		if junction_visual.position.z >= player_car.position.z - 3.0:
			if physical_intersection_choice == 99:
				physical_intersection_choice = 0
			if physical_intersection_choice == physical_intersection_direction:
				physical_intersection_state = 4
				physical_intersection_progress = 0.0
				player_turn_start = player_car.position
				player_turn_pivot = Vector3(0.0, 0.0, junction_visual.position.z)
				physical_camera_yaw = 0.0
				capture_turning_environment()
				status_label.text = "FOLLOWING SUSPECT"
			else:
				physical_intersection_state = 5
				physical_intersection_progress = 0.0
				status_label.text = "CONTINUING STRAIGHT · REROUTING"
			navigation_panel.visible = false
		return

	if physical_intersection_state == 4:
		physical_intersection_progress = minf(1.0, physical_intersection_progress + delta / 1.35)
		var eased := smoothstep(0.0, 1.0, physical_intersection_progress)
		apply_corner_arc(player_car, player_turn_start, physical_intersection_direction, 12.0, eased)
		if physical_intersection_progress >= 1.0:
			complete_physical_intersection(true)
		return

	if physical_intersection_state == 5:
		physical_intersection_progress += delta / 0.9
		if physical_intersection_progress >= 1.0:
			complete_physical_intersection(false)


func show_navigation_choice() -> void:
	navigation_panel.visible = true
	var direction_name := "LEFT" if physical_intersection_direction < 0 else "RIGHT"
	navigation_label.text = "SUSPECT TURNED %s" % direction_name
	follow_turn_button.text = "FOLLOW %s" % direction_name
	status_label.text = "CHOOSE ROUTE"


func capture_turning_environment() -> void:
	turn_world_positions.clear()
	turn_world_rotations.clear()
	for part in road_parts:
		turn_world_positions.append(part.position)
		turn_world_rotations.append(part.rotation.y)


func rotate_turning_environment(progress: float) -> void:
	var angle := float(physical_intersection_direction) * deg_to_rad(90.0) * progress
	for i in road_parts.size():
		var relative := turn_world_positions[i] - player_turn_pivot
		road_parts[i].position = player_turn_pivot + relative.rotated(Vector3.UP, angle)
		road_parts[i].rotation.y = turn_world_rotations[i] + angle


func apply_corner_arc(car: Node3D, start: Vector3, direction: int, radius: float, progress: float) -> void:
	# Quarter-circle driven by its tangent: at progress 0 the car faces forward,
	# then its nose naturally leads the body into the side street.
	var angle := progress * PI * 0.5
	car.position.x = start.x + float(direction) * radius * (1.0 - cos(angle))
	car.position.z = start.z - radius * sin(angle)
	# Godot's -Z vehicle-forward convention uses negative Y rotation for a
	# screen-right (+X) turn. Keeping this sign matched to the arc tangent is
	# what makes the nose, rather than the trunk, lead around the corner.
	car.rotation.y = -float(direction) * angle
	steer_front_wheels(car, -float(direction) * deg_to_rad(28.0) * sin(progress * PI))


func steer_front_wheels(car: Node3D, steering_angle: float) -> void:
	var wheels: Array = car.get_meta("front_wheels", [])
	for wheel in wheels:
		if is_instance_valid(wheel):
			wheel.rotation.y = steering_angle


func choose_physical_route(follow_turn: bool) -> void:
	if physical_intersection_state < 2 or physical_intersection_state > 3:
		return
	physical_intersection_choice = physical_intersection_direction if follow_turn else 0
	navigation_panel.visible = false
	status_label.text = "TURN SELECTED" if follow_turn else "STRAIGHT SELECTED"


func complete_physical_intersection(followed: bool) -> void:
	transition_fade.color = Color(0.015, 0.04, 0.07, 1.0)
	if followed:
		suspect_distance = maxf(22.0, suspect_distance - 7.0)
		apprehend = minf(100.0, apprehend + 8.0)
		status_label.text = "ROUTE MATCHED · CONTACT MAINTAINED"
	else:
		suspect_distance += 22.0
		chase_time = maxf(0.0, chase_time - 7.0)
		skill_multiplier = 1.0
		status_label.text = "WRONG ROUTE · CONTACT AT RISK"
	player_car.position = Vector3(LANES[lane_index], 0.75, 6.0)
	player_car.rotation = Vector3.ZERO
	steer_front_wheels(player_car, 0.0)
	suspect_lane_index = 1
	suspect_car.position = Vector3(0.0, 0.75, 6.0 - clampf(suspect_distance * 0.62, 13.0, 82.0))
	suspect_car.rotation = Vector3.ZERO
	steer_front_wheels(suspect_car, 0.0)
	if camera_mode == 1:
		camera.position = Vector3(player_car.position.x, 1.82, 4.65)
		camera.rotation_degrees = Vector3(-3.0, 0.0, 0.0)
	else:
		camera.position = Vector3(player_car.position.x * 0.35, 7.3, 14.5)
		camera.rotation_degrees = Vector3(-19.0, 0.0, 0.0)
	for i in traffic.size():
		traffic[i].visible = true
		traffic[i].position.z = -42.0 - i * 31.0
		traffic[i].set_meta("hit", false)
	for i in road_parts.size():
		road_parts[i].position = Vector3(0.0, 0.0, 12.0 - i * ROAD_LENGTH)
		road_parts[i].rotation = Vector3.ZERO
	junction_visual.visible = false
	navigation_panel.visible = false
	physical_intersection_state = 0
	next_physical_intersection_time = chase_time - randf_range(13.0, 17.0)
	backup_button.disabled = not backup_available
	spike_button.disabled = spike_charges <= 0
	var tween := create_tween()
	tween.tween_property(transition_fade, "color:a", 0.0, 0.38)


func activate_backup() -> void:
	if not running or not backup_available or backup_active:
		return
	backup_available = false
	backup_active = true
	backup_crashing = false
	backup_timer = randf_range(7.0, 10.0)
	backup_car.visible = true
	backup_car.position = Vector3(LANES[0] if suspect_lane_index >= 1 else LANES[2], 0.75, 20.0)
	backup_car.rotation = Vector3.ZERO
	backup_button.disabled = true
	backup_button.text = "BACKUP ACTIVE"
	status_label.text = "BACKUP JOINING PURSUIT"


func update_backup(delta: float) -> void:
	if not backup_active:
		return
	if backup_crashing:
		backup_crash_timer -= delta
		backup_car.rotation.y += delta * 7.0
		backup_car.rotation.z = lerpf(backup_car.rotation.z, 0.65, delta * 4.0)
		backup_car.position.x += delta * 10.0 * signf(backup_car.position.x if backup_car.position.x != 0.0 else 1.0)
		backup_car.position.z += delta * 8.0
		if backup_crash_timer <= 0.0:
			backup_active = false
			backup_car.visible = false
			backup_button.text = "BACKUP USED"
			release_pulled_over_traffic()
		return

	backup_timer -= delta
	var approach_z := suspect_car.position.z + 7.0
	backup_car.position.z = lerpf(backup_car.position.z, approach_z, delta * 1.4)
	var flank_lane := 0 if suspect_lane_index >= 1 else 2
	backup_car.position.x = lerpf(backup_car.position.x, LANES[flank_lane], delta * 2.0)
	clear_traffic_for_backup()
	for car in traffic:
		if absf(car.position.z - backup_car.position.z) < 2.2 and absf(car.position.x - backup_car.position.x) < 1.45:
			backup_crashing = true
			backup_crash_timer = 1.6
			backup_timer = 0.0
			car.set_meta("lane", 1 if flank_lane == 0 else 1)
			status_label.text = "BACKUP COLLISION · ASSIST ENDING"
			camera_shake = 0.5
			break
	if suspect_lane_index == flank_lane:
		suspect_lane_index = 2 if flank_lane == 0 else 0
		suspect_distance = maxf(12.0, suspect_distance - 2.0)
		apprehend = minf(100.0, apprehend + 3.0)
	if backup_timer <= 0.0:
		backup_crashing = true
		backup_crash_timer = 1.6
		status_label.text = "BACKUP UNIT FORCED OFF ROAD"
		camera_shake = 0.35


func clear_traffic_for_backup() -> void:
	for car in traffic:
		var is_behind_thief := car.position.z > suspect_car.position.z
		var is_ahead_of_backup := car.position.z < backup_car.position.z
		var same_path := absf(car.position.x - backup_car.position.x) < 2.15
		if is_behind_thief and is_ahead_of_backup and same_path:
			car.set_meta("pull_over", true)
			var shoulder_x := -6.4 if backup_car.position.x <= 0.0 else 6.4
			car.set_meta("pull_over_x", shoulder_x)


func release_pulled_over_traffic() -> void:
	for car in traffic:
		car.set_meta("pull_over", false)


func open_spike_selector() -> void:
	if not running or spike_active or spike_charges <= 0:
		return
	spike_panel.visible = true


func deploy_spikes(lane_choice: int) -> void:
	if spike_active or spike_charges <= 0:
		return
	spike_lane = clampi(lane_choice, 0, LANES.size() - 1)
	spike_charges -= 1
	spike_active = true
	spike_node.visible = true
	spike_node.position = Vector3(LANES[spike_lane], 0.08, -100.0)
	spike_panel.visible = false
	spike_button.text = "SPIKES ×%d" % spike_charges
	spike_button.disabled = spike_charges <= 0
	status_label.text = "SPIKE STRIP DEPLOYED · CHANGE LANES"


func update_spikes(delta: float, current_speed: float) -> void:
	if not spike_active:
		return
	spike_node.position.z += current_speed * delta
	if absf(spike_node.position.z - suspect_car.position.z) < 2.0 and suspect_lane_index == spike_lane and thief_slow_timer <= 0.0:
		thief_slow_timer = 4.5
		suspect_damage = minf(100.0, suspect_damage + 22.0)
		apprehend = minf(100.0, apprehend + 18.0)
		status_label.text = "THIEF HIT SPIKES · SPEED REDUCED"
	for car in traffic:
		if not bool(car.get_meta("spike_hit", false)) and absf(spike_node.position.z - car.position.z) < 1.5 and absf(spike_node.position.x - car.position.x) < 1.4:
			car.set_meta("spike_hit", true)
			car.set_meta("tire_slow", 4.0)
			var civilian_lane: int = int(car.get_meta("lane", 1))
			var swerve_lane := civilian_lane + (-1 if civilian_lane > 0 else 1)
			car.set_meta("lane", clampi(swerve_lane, 0, LANES.size() - 1))
			apprehend = maxf(0.0, apprehend - 10.0)
			skill_multiplier = 1.0
			status_label.text = "CIVILIAN HIT SPIKES · SKILL PENALTY"
			camera_shake = 0.2
	if backup_active and not backup_crashing and absf(spike_node.position.z - backup_car.position.z) < 1.8 and absf(spike_node.position.x - backup_car.position.x) < 1.4:
		backup_crashing = true
		backup_crash_timer = 1.6
		backup_timer = 0.0
		status_label.text = "BACKUP HIT SPIKES · ASSIST ENDING"
		camera_shake = 0.4
	if absf(spike_node.position.z - player_car.position.z) < 1.8 and lane_index == spike_lane:
		player_slow_timer = 3.5
		suspect_distance += 10.0
		skill_multiplier = 1.0
		status_label.text = "POLICE HIT SPIKES · SPEED REDUCED"
		spike_active = false
		spike_node.visible = false
	elif spike_node.position.z > 18.0:
		spike_active = false
		spike_node.visible = false
		if thief_slow_timer <= 0.0:
			status_label.text = "SPIKE STRIP MISSED"


func start_junction() -> void:
	junction_active = false
	junction_choice_made = false
	junction_countdown = 4.5
	suspect_turn = [-1, 0, 1][randi() % 3]
	street_index = (street_index + 1) % streets.size()
	junction_street_label.text = streets[street_index]
	junction_visual.position = Vector3(0.0, 0.0, -125.0)
	junction_visual.visible = true
	var clue := "SUSPECT DRIFTING LEFT" if suspect_turn < 0 else ("SUSPECT MOVING RIGHT" if suspect_turn > 0 else "SUSPECT HOLDING CENTER")
	status_label.text = clue


func update_junction(delta: float, current_speed: float) -> void:
	if not junction_visual.visible and chase_time <= next_junction_time:
		start_junction()

	if junction_visual.visible:
		junction_visual.position.z += current_speed * delta
		junction_visual.position.x = -turn_curve * 3.5
		junction_visual.rotation.y = -turn_curve * 0.22
		if junction_visual.position.z > -72.0 and not junction_choice_made:
			junction_active = true
			junction_panel.visible = true
			junction_countdown = maxf(0.0, junction_countdown - delta)
			junction_timer_bar.value = junction_countdown
			if junction_countdown <= 0.0:
				choose_turn(0)
		if junction_visual.position.z > 28.0:
			junction_visual.visible = false
			junction_panel.visible = false
			junction_active = false
			next_junction_time = maxf(8.0, chase_time - 13.0)

	if turn_animation > 0.0:
		turn_animation = maxf(0.0, turn_animation - delta)
		var phase := 1.0 - turn_animation / 2.5
		turn_curve = float(turn_direction) * sin(phase * PI)
	else:
		turn_curve = lerpf(turn_curve, 0.0, delta * 5.0)


func choose_turn(direction: int) -> void:
	if not junction_active or junction_choice_made:
		return
	junction_choice_made = true
	junction_active = false
	junction_panel.visible = false
	turn_direction = direction
	turn_animation = 2.5
	var difference := absi(direction - suspect_turn)
	if difference == 0:
		suspect_distance = maxf(18.0, suspect_distance - 12.0)
		status_label.text = "CORRECT ROUTE · CLOSING IN"
	elif difference == 1:
		suspect_distance += 12.0
		chase_time = maxf(0.0, chase_time - 4.0)
		status_label.text = "WRONG STREET · DISPATCH REROUTING"
	else:
		suspect_distance += 22.0
		chase_time = maxf(0.0, chase_time - 7.0)
		status_label.text = "SUSPECT DOUBLED BACK · CONTACT AT RISK"


func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 26.0
	top.offset_top = 22.0
	top.offset_right = -26.0
	root.add_child(top)

	status_label = Label.new()
	status_label.text = "VISUAL CONTACT"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color("#27dcff"))
	status_label.add_theme_font_size_override("font_size", 18)
	top.add_child(status_label)

	var info := HBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(info)
	timer_label = Label.new()
	timer_label.custom_minimum_size.x = 220.0
	timer_label.add_theme_font_size_override("font_size", 34)
	info.add_child(timer_label)
	distance_label = Label.new()
	distance_label.custom_minimum_size.x = 220.0
	distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	distance_label.add_theme_font_size_override("font_size", 34)
	info.add_child(distance_label)

	damage_bar = ProgressBar.new()
	damage_bar.max_value = 100.0
	damage_bar.show_percentage = false
	damage_bar.custom_minimum_size.y = 13.0
	style_progress_bar(damage_bar, SIREN_RED)
	top.add_child(damage_bar)
	nos_bar = ProgressBar.new()
	nos_bar.max_value = 100.0
	nos_bar.show_percentage = false
	nos_bar.custom_minimum_size.y = 13.0
	style_progress_bar(nos_bar, POLICE_BLUE)
	top.add_child(nos_bar)
	apprehend_bar = ProgressBar.new()
	apprehend_bar.max_value = 100.0
	apprehend_bar.show_percentage = false
	apprehend_bar.custom_minimum_size.y = 18.0
	style_progress_bar(apprehend_bar, APPREHEND_GREEN)
	top.add_child(apprehend_bar)
	skill_label = Label.new()
	skill_label.text = "SKILLED DRIVING ×1.0"
	skill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skill_label.add_theme_color_override("font_color", Color("#ffb23e"))
	skill_label.add_theme_font_size_override("font_size", 18)
	top.add_child(skill_label)

	var controls := HBoxContainer.new()
	controls.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_left = 28.0
	controls.offset_right = -28.0
	controls.offset_top = -170.0
	controls.offset_bottom = -30.0
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 26)
	root.add_child(controls)
	controls.add_child(make_button("LEFT", func(): change_lane(-1)))
	var boost_button := make_button("BOOST", func(): boosting = true)
	boost_button.button_down.connect(func(): Input.action_press("boost"))
	boost_button.button_up.connect(func(): Input.action_release("boost"))
	controls.add_child(boost_button)
	controls.add_child(make_button("RIGHT", func(): change_lane(1)))

	capture_button = Button.new()
	capture_button.text = "SAFE CAPTURE"
	capture_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	capture_button.position = Vector2(-135.0, -285.0)
	capture_button.size = Vector2(270.0, 82.0)
	capture_button.add_theme_font_size_override("font_size", 22)
	capture_button.visible = false
	style_button(capture_button, APPREHEND_GREEN)
	capture_button.pressed.connect(begin_capture_sequence)
	root.add_child(capture_button)

	backup_button = Button.new()
	backup_button.text = "CALL BACKUP"
	backup_button.position = Vector2(24.0, 245.0)
	backup_button.size = Vector2(190.0, 70.0)
	backup_button.add_theme_font_size_override("font_size", 16)
	style_button(backup_button, POLICE_BLUE)
	backup_button.pressed.connect(activate_backup)
	root.add_child(backup_button)

	spike_button = Button.new()
	spike_button.text = "SPIKES ×2"
	spike_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	spike_button.position = Vector2(-214.0, 245.0)
	spike_button.size = Vector2(190.0, 70.0)
	spike_button.add_theme_font_size_override("font_size", 16)
	style_button(spike_button, TACTICAL_VIOLET)
	spike_button.pressed.connect(open_spike_selector)
	root.add_child(spike_button)

	camera_button = Button.new()
	camera_button.text = "VIEW: CHASE"
	camera_button.position = Vector2(24.0, 330.0)
	camera_button.size = Vector2(190.0, 62.0)
	camera_button.add_theme_font_size_override("font_size", 14)
	style_button(camera_button, Color("#41627b"))
	camera_button.pressed.connect(toggle_camera_mode)
	root.add_child(camera_button)

	map_button = Button.new()
	map_button.text = "3D MAP"
	map_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	map_button.position = Vector2(-214.0, 330.0)
	map_button.size = Vector2(190.0, 62.0)
	map_button.add_theme_font_size_override("font_size", 14)
	style_button(map_button, Color("#167b9c"))
	map_button.pressed.connect(open_3d_map)
	root.add_child(map_button)

	junction_panel = PanelContainer.new()
	junction_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	junction_panel.position = Vector2(-285.0, 180.0)
	junction_panel.size = Vector2(570.0, 210.0)
	junction_panel.visible = false
	style_panel(junction_panel, HAZARD_AMBER)
	root.add_child(junction_panel)
	var junction_box := VBoxContainer.new()
	junction_box.alignment = BoxContainer.ALIGNMENT_CENTER
	junction_panel.add_child(junction_box)
	var junction_caption := Label.new()
	junction_caption.text = "INTERSECTION AHEAD · CHOOSE ROUTE"
	junction_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	junction_caption.add_theme_color_override("font_color", Color("#ffb23e"))
	junction_box.add_child(junction_caption)
	junction_street_label = Label.new()
	junction_street_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	junction_street_label.add_theme_font_size_override("font_size", 24)
	junction_box.add_child(junction_street_label)
	junction_timer_bar = ProgressBar.new()
	junction_timer_bar.max_value = 4.5
	junction_timer_bar.value = 4.5
	junction_timer_bar.show_percentage = false
	style_progress_bar(junction_timer_bar, HAZARD_AMBER)
	junction_box.add_child(junction_timer_bar)
	var turn_buttons := HBoxContainer.new()
	turn_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	turn_buttons.add_theme_constant_override("separation", 10)
	junction_box.add_child(turn_buttons)
	turn_buttons.add_child(make_small_button("↰ LEFT", func(): choose_turn(-1)))
	turn_buttons.add_child(make_small_button("↑ STRAIGHT", func(): choose_turn(0)))
	turn_buttons.add_child(make_small_button("↱ RIGHT", func(): choose_turn(1)))

	spike_panel = PanelContainer.new()
	spike_panel.set_anchors_preset(Control.PRESET_CENTER)
	spike_panel.position = Vector2(-275.0, -100.0)
	spike_panel.size = Vector2(550.0, 200.0)
	spike_panel.visible = false
	style_panel(spike_panel, TACTICAL_VIOLET)
	root.add_child(spike_panel)
	var spike_box := VBoxContainer.new()
	spike_box.alignment = BoxContainer.ALIGNMENT_CENTER
	spike_panel.add_child(spike_box)
	var spike_title := Label.new()
	spike_title.text = "DEPLOY SPIKES · SELECT LANE"
	spike_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spike_title.add_theme_color_override("font_color", Color("#ffb23e"))
	spike_title.add_theme_font_size_override("font_size", 20)
	spike_box.add_child(spike_title)
	var spike_buttons := HBoxContainer.new()
	spike_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	spike_buttons.add_theme_constant_override("separation", 10)
	spike_box.add_child(spike_buttons)
	spike_buttons.add_child(make_small_button("LEFT", func(): deploy_spikes(0)))
	spike_buttons.add_child(make_small_button("CENTER", func(): deploy_spikes(1)))
	spike_buttons.add_child(make_small_button("RIGHT", func(): deploy_spikes(2)))

	map_overlay = PanelContainer.new()
	map_overlay.set_anchors_preset(Control.PRESET_CENTER_TOP)
	map_overlay.position = Vector2(-260.0, 28.0)
	map_overlay.size = Vector2(520.0, 150.0)
	map_overlay.visible = false
	style_panel(map_overlay, POLICE_BLUE)
	root.add_child(map_overlay)
	var map_box := VBoxContainer.new()
	map_box.alignment = BoxContainer.ALIGNMENT_CENTER
	map_overlay.add_child(map_box)
	var map_title := Label.new()
	map_title.text = "LIVE 3D TACTICAL MAP"
	map_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_title.add_theme_color_override("font_color", Color("#22d9ff"))
	map_title.add_theme_font_size_override("font_size", 20)
	map_box.add_child(map_title)
	var map_help := Label.new()
	map_help.text = "Blue: police · Red: thief · Grey: civilian traffic"
	map_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_box.add_child(map_help)
	map_box.add_child(make_small_button("RETURN TO CHASE", close_3d_map))

	navigation_panel = PanelContainer.new()
	navigation_panel.set_anchors_preset(Control.PRESET_CENTER)
	navigation_panel.position = Vector2(-270.0, -115.0)
	navigation_panel.size = Vector2(540.0, 230.0)
	navigation_panel.visible = false
	style_panel(navigation_panel, HAZARD_AMBER)
	root.add_child(navigation_panel)
	var navigation_box := VBoxContainer.new()
	navigation_box.alignment = BoxContainer.ALIGNMENT_CENTER
	navigation_box.add_theme_constant_override("separation", 12)
	navigation_panel.add_child(navigation_box)
	navigation_label = Label.new()
	navigation_label.text = "SUSPECT TURNING"
	navigation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	navigation_label.add_theme_color_override("font_color", Color("#ffb23e"))
	navigation_label.add_theme_font_size_override("font_size", 22)
	navigation_box.add_child(navigation_label)
	var navigation_buttons := HBoxContainer.new()
	navigation_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	navigation_buttons.add_theme_constant_override("separation", 12)
	navigation_box.add_child(navigation_buttons)
	follow_turn_button = make_small_button("FOLLOW TURN", func(): choose_physical_route(true))
	navigation_buttons.add_child(follow_turn_button)
	navigation_buttons.add_child(make_small_button("GO STRAIGHT", func(): choose_physical_route(false)))

	transition_fade = ColorRect.new()
	transition_fade.color = Color(0.015, 0.04, 0.07, 0.0)
	transition_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(transition_fade)

	capture_panel = PanelContainer.new()
	capture_panel.set_anchors_preset(Control.PRESET_CENTER)
	capture_panel.position = Vector2(-260.0, -115.0)
	capture_panel.size = Vector2(520.0, 230.0)
	capture_panel.visible = false
	style_panel(capture_panel, APPREHEND_GREEN)
	root.add_child(capture_panel)
	var capture_box := VBoxContainer.new()
	capture_box.alignment = BoxContainer.ALIGNMENT_CENTER
	capture_panel.add_child(capture_box)
	var capture_title := Label.new()
	capture_title.text = "SAFE-CAPTURE ALIGNMENT"
	capture_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	capture_title.add_theme_color_override("font_color", Color("#2fe0a0"))
	capture_title.add_theme_font_size_override("font_size", 22)
	capture_box.add_child(capture_title)
	var capture_help := Label.new()
	capture_help.text = "Lock the moving marker inside the green bracket"
	capture_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	capture_box.add_child(capture_help)
	capture_meter = SafeCaptureMeterScript.new()
	capture_box.add_child(capture_meter)
	capture_box.add_child(make_small_button("LOCK CAPTURE", resolve_capture_attempt))

	result_panel = ColorRect.new()
	result_panel.color = Color(0.02, 0.06, 0.1, 0.94)
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_panel.visible = false
	root.add_child(result_panel)
	var results := VBoxContainer.new()
	results.set_anchors_preset(Control.PRESET_CENTER)
	results.position = Vector2(-250.0, -300.0)
	results.size = Vector2(500.0, 600.0)
	results.alignment = BoxContainer.ALIGNMENT_CENTER
	result_panel.add_child(results)
	result_title = Label.new()
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_title.add_theme_font_size_override("font_size", 42)
	result_title.add_theme_color_override("font_color", Color("#27dcff"))
	results.add_child(result_title)
	result_details = Label.new()
	result_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_details.add_theme_font_size_override("font_size", 17)
	result_details.add_theme_color_override("font_color", Color("#c5d6df"))
	results.add_child(result_details)
	result_protect_button = make_button("PROTECT LIFE · SIMULATED AD", protect_life)
	results.add_child(result_protect_button)
	result_primary_button = make_button("NEXT CASE", result_primary_action)
	results.add_child(result_primary_button)
	result_secondary_button = make_button("RETURN TO STATION", return_to_station)
	results.add_child(result_secondary_button)


func make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(170.0, 96.0)
	button.add_theme_font_size_override("font_size", 20)
	style_button(button, POLICE_BLUE)
	button.pressed.connect(callback)
	return button


func make_small_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(165.0, 64.0)
	button.add_theme_font_size_override("font_size", 16)
	style_button(button, Color("#315675"))
	button.pressed.connect(callback)
	return button


func make_hud_style(fill: Color, border: Color, radius: int = 18, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func style_panel(panel: PanelContainer, accent: Color) -> void:
	panel.add_theme_stylebox_override("panel", make_hud_style(Color(0.067, 0.086, 0.16, 0.93), Color(accent, 0.78), 20, 2))


func style_button(button: Button, accent: Color) -> void:
	button.add_theme_color_override("font_color", Color("#eef8ff"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", make_hud_style(Color(0.067, 0.086, 0.16, 0.9), Color(accent, 0.72), 18, 2))
	button.add_theme_stylebox_override("hover", make_hud_style(Color(accent, 0.26), accent, 18, 3))
	button.add_theme_stylebox_override("pressed", make_hud_style(Color(accent, 0.42), accent.lightened(0.18), 18, 3))
	button.add_theme_stylebox_override("disabled", make_hud_style(Color(0.05, 0.06, 0.09, 0.76), Color(0.3, 0.34, 0.4, 0.5), 18, 1))


func style_progress_bar(bar: ProgressBar, accent: Color) -> void:
	bar.add_theme_stylebox_override("background", make_hud_style(Color(0.035, 0.05, 0.09, 0.88), Color(accent, 0.32), 8, 1))
	bar.add_theme_stylebox_override("fill", make_hud_style(Color(accent, 0.94), accent.lightened(0.15), 8, 1))


func update_camera(delta: float) -> void:
	if map_active:
		cockpit_node.visible = false
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = lerpf(camera.size, 58.0, delta * 5.0)
		camera.position = camera.position.lerp(Vector3(player_car.position.x, 58.0, -18.0), delta * 6.0)
		camera.rotation.x = lerp_angle(camera.rotation.x, deg_to_rad(-90.0), delta * 7.0)
		camera.rotation.y = lerp_angle(camera.rotation.y, 0.0, delta * 7.0)
		camera.rotation.z = lerp_angle(camera.rotation.z, 0.0, delta * 7.0)
		return

	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	cockpit_node.visible = camera_mode == 1
	if physical_intersection_state == 4:
		var car_yaw := player_car.rotation.y
		physical_camera_yaw = lerp_angle(physical_camera_yaw, car_yaw, delta * 2.0)
		var forward := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, car_yaw)
		if camera_mode == 1:
			# The hood camera is attached to the police car, so the entire view
			# follows the new street heading as the car rounds the corner.
			var pov_offset := Vector3(0.0, 1.05, -0.55).rotated(Vector3.UP, car_yaw)
			camera.position = camera.position.lerp(player_car.position + pov_offset, delta * 10.0)
			camera.look_at(player_car.position + forward * 10.0 + Vector3.UP * 1.0, Vector3.UP)
			camera.fov = lerpf(camera.fov, 72.0, delta * 5.0)
		else:
			# A small amount of camera lag exposes the side of the car during the
			# turn before the camera settles behind it on the new street.
			var chase_offset := Vector3(0.0, 6.4, 10.5).rotated(Vector3.UP, physical_camera_yaw)
			camera.position = camera.position.lerp(player_car.position + chase_offset, delta * 6.0)
			camera.look_at(player_car.position + forward * 4.0 + Vector3.UP * 0.8, Vector3.UP)
			camera.fov = lerpf(camera.fov, 60.0, delta * 5.0)
		return
	if camera_mode == 1:
		var pov_position := Vector3(player_car.position.x, 1.82, 4.65)
		camera.position = camera.position.lerp(pov_position, delta * 9.0)
		camera.rotation.x = lerp_angle(camera.rotation.x, deg_to_rad(-3.0), delta * 8.0)
		camera.rotation.y = lerp_angle(camera.rotation.y, 0.0, delta * 8.0)
		camera.rotation.z = lerp_angle(camera.rotation.z, player_car.rotation.z * 0.18, delta * 7.0)
		var pov_fov := 78.0 if boosting else 68.0
		camera.fov = lerpf(camera.fov, pov_fov, delta * 5.0)
		return

	var target_camera_x := player_car.position.x * 0.35 - turn_curve * 1.1
	camera.position.x = lerpf(camera.position.x, target_camera_x, delta * 4.0)
	var target_fov := 66.0 if boosting else 56.0
	camera.fov = lerpf(camera.fov, target_fov, delta * 4.5)
	var target_roll := player_car.rotation.z * 0.35 - turn_curve * 0.055
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, delta * 5.0)
	camera.rotation.y = lerpf(camera.rotation.y, turn_curve * 0.48, delta * 4.5)
	if camera_shake > 0.0:
		camera_shake = maxf(0.0, camera_shake - delta)
		camera.position.x += randf_range(-0.08, 0.08) * camera_shake
		camera.position.y = 7.3 + randf_range(-0.06, 0.06) * camera_shake
	else:
		camera.position.y = lerpf(camera.position.y, 7.3, delta * 7.0)


func toggle_camera_mode() -> void:
	if map_active:
		return
	camera_mode = 1 - camera_mode
	cockpit_node.visible = camera_mode == 1
	camera_button.text = "VIEW: POV" if camera_mode == 1 else "VIEW: CHASE"
	status_label.text = "HOOD CAMERA" if camera_mode == 1 else "CHASE CAMERA"


func open_3d_map() -> void:
	if capture_active or not running:
		return
	map_active = true
	map_overlay.visible = true
	status_label.text = "TACTICAL MAP"


func close_3d_map() -> void:
	map_active = false
	map_overlay.visible = false
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	cockpit_node.visible = camera_mode == 1
	if camera_mode == 1:
		camera.position = Vector3(player_car.position.x, 1.82, 4.65)
		camera.rotation_degrees = Vector3(-3.0, 0.0, 0.0)
	else:
		camera.position = Vector3(player_car.position.x * 0.35, 7.3, 14.5)
		camera.rotation_degrees = Vector3(-19.0, 0.0, 0.0)


func update_hud() -> void:
	timer_label.text = "TIME %02d" % int(ceil(chase_time))
	distance_label.text = "%dm" % int(ceil(suspect_distance))
	damage_bar.value = damage
	nos_bar.value = nos
	apprehend_bar.value = apprehend
	skill_label.text = "APPREHEND %d%%   ·   SKILL ×%.1f" % [int(apprehend), skill_multiplier]
	capture_button.visible = apprehend >= 100.0 and suspect_distance <= 34.0 and not capture_active
	if damage < 100.0 and status_label.text.begins_with("COLLISION"):
		await get_tree().create_timer(1.0).timeout
		if running:
			status_label.text = "VISUAL CONTACT"


func finish_chase(won: bool, title: String) -> void:
	running = false
	last_result_won = won
	failure_life_resolved = false
	result_title.text = title
	result_title.add_theme_color_override("font_color", Color("#2fe0a0") if won else Color("#ff4d58"))
	var elapsed := START_TIME - chase_time
	if won:
		var time_bonus := maxi(0, int(chase_time) * 2)
		var damage_bonus := maxi(0, 100 - int(damage))
		var skill_bonus := int(peak_skill_multiplier * 25.0)
		var reward := 100 + time_bonus + damage_bonus + skill_bonus
		var xp_reward := 75 + int(peak_skill_multiplier * 15.0)
		GameState.record_success(reward, xp_reward)
		result_details.text = "CASE TIME  %02d:%02d\nDAMAGE  %d%%\nBEST SKILL  ×%.1f\n\n+%d CR   +%d XP\nRANK  %s" % [int(elapsed) / 60, int(elapsed) % 60, int(damage), peak_skill_multiplier, reward, xp_reward, GameState.rank_name()]
		result_protect_button.visible = false
		result_primary_button.text = "NEXT CASE"
		result_secondary_button.text = "REPLAY CASE"
	else:
		result_details.text = "FAILURE  %s\nDAMAGE  %d%%\nLIVES REMAINING  %d / %d\n\nProtect this life or accept the loss." % [title, int(damage), GameState.lives, GameState.MAX_LIVES]
		result_protect_button.visible = true
		result_protect_button.text = "LIFE PROTECTED · AD-FREE" if GameState.ad_free else "PROTECT LIFE · SIMULATED AD"
		result_primary_button.text = "LOSE LIFE & RETRY"
		result_secondary_button.text = "RETURN TO STATION"
	result_panel.visible = true


func result_primary_action() -> void:
	if last_result_won:
		get_tree().change_scene_to_file("res://scenes/interface/main_menu.tscn")
	else:
		accept_life_loss_and_retry()


func protect_life() -> void:
	if last_result_won:
		return
	failure_life_resolved = true
	get_tree().reload_current_scene()


func accept_life_loss_and_retry() -> void:
	if not failure_life_resolved:
		GameState.consume_life()
		failure_life_resolved = true
	if GameState.lives > 0:
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file("res://scenes/interface/main_menu.tscn")


func return_to_station() -> void:
	if last_result_won:
		get_tree().reload_current_scene()
		return
	if not failure_life_resolved:
		GameState.consume_life()
		failure_life_resolved = true
	get_tree().change_scene_to_file("res://scenes/interface/main_menu.tscn")


func begin_capture_sequence() -> void:
	if not running or capture_active or apprehend < 100.0 or suspect_distance > 34.0:
		return
	capture_active = true
	capture_cursor = 0.0
	capture_direction = 1.0
	configure_capture_target()
	capture_button.visible = false
	capture_panel.visible = true
	status_label.text = "MATCH SPEED · HOLD ALIGNMENT"


func update_capture_sequence(delta: float) -> void:
	capture_cursor += capture_direction * capture_current_speed * delta
	if capture_cursor >= 100.0:
		capture_cursor = 100.0
		capture_direction = -1.0
		randomize_capture_pass_speed()
	elif capture_cursor <= 0.0:
		capture_cursor = 0.0
		capture_direction = 1.0
		randomize_capture_pass_speed()
	capture_meter.call("set_cursor", capture_cursor)
	player_car.rotation.y = lerpf(player_car.rotation.y, 0.0, delta * 5.0)
	suspect_car.rotation.y = lerpf(suspect_car.rotation.y, 0.0, delta * 5.0)


func resolve_capture_attempt() -> void:
	if not capture_active:
		return
	if capture_cursor >= capture_target_min and capture_cursor <= capture_target_max:
		capture_active = false
		capture_panel.visible = false
		finish_chase(true, "SAFE CAPTURE")
	else:
		capture_active = false
		capture_panel.visible = false
		apprehend = 55.0
		skill_multiplier = 1.0
		suspect_distance += 16.0
		chase_time = maxf(0.0, chase_time - 5.0)
		status_label.text = "CAPTURE MISSED · SUSPECT BREAKING AWAY"


func configure_capture_target() -> void:
	var difficulty_ratio := float(case_difficulty - 1) / 9.0
	var window_width := lerpf(28.0, 8.0, difficulty_ratio)
	var half_width := window_width * 0.5
	var center := randf_range(24.0 + half_width, 76.0 - half_width)
	capture_target_min = center - half_width
	capture_target_max = center + half_width
	capture_base_speed = lerpf(58.0, 132.0, difficulty_ratio)
	capture_current_speed = capture_base_speed * randf_range(0.94, 1.06)
	capture_meter.call("configure_window", capture_target_min, capture_target_max)
	capture_meter.call("set_cursor", 0.0)


func randomize_capture_pass_speed() -> void:
	var difficulty_ratio := float(case_difficulty - 1) / 9.0
	var variation := lerpf(0.04, 0.22, difficulty_ratio)
	capture_current_speed = capture_base_speed * randf_range(1.0 - variation, 1.0 + variation)
