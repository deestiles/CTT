extends Node3D

const VehicleBuilder = preload("res://scripts/vehicles/stylized_vehicle_builder.gd")
const PolygonVehicleBuilder = preload("res://scripts/vehicles/polygon_city_vehicle_builder.gd")
const RoadDecorator = preload("res://scripts/chase/road_diorama_decorator.gd")
const CityBuilder = preload("res://scripts/chase/downtown_city_builder.gd")
const ResidentialBuilder = preload("res://scripts/chase/residential_house_builder.gd")
const START_TIME := 120.0
const CRUISE_SPEED := 48
const BOOST_SPEED := 64

@export var exploration_mode := false
@export_range(0, 24, 1) var exploration_traffic_count := 0

var player: Node3D
var suspect: Node3D
var backup: Node3D
var player_agent: RoadLaneAgent
var suspect_agent: RoadLaneAgent
var backup_agent: RoadLaneAgent
var chase_camera: Camera3D
var traffic: Array[Node3D] = []
var traffic_signal_lamps: Array[MeshInstance3D] = []
var traffic_signal_centers: Array[Vector3] = []
var builder_traffic_signals: Array[MeshInstance3D] = []
var chase_time := START_TIME
var damage := 0.0
var nos := 100.0
var apprehend := 0.0
var suspect_damage := 0.0
var ram_upgrade_level := 1
var skill := 1.0
var boosting := false
var nos_armed := false
var joystick_throttle := 0.0
var previous_player_speed := 0.0
var running := true
var camera_mode := 0
var map_active := false
var backup_available := true
var backup_timer := 0.0
var spike_charges := 2
var suspect_slow_timer := 0.0
var player_spike_slow_timer := 0.0
var collision_cooldown := 0.0
var last_forward := Vector3.FORWARD
var joystick_lane_armed := true
var buffered_turn_direction := 0
var buffered_turn_armed := true
var buffered_turn_input_sign := 0
var last_turn_position := Vector3(1000000, 0, 1000000)
var camera_shake := 0.0
var camera_shake_strength := 0.0
var chase_camera_yaw := 0.0
var chase_camera_initialized := false
var debris_pieces: Array[Node3D] = []
var pileup_check_timer := 0.0
var backup_overtake_timer := 0.0
var spike_strip: Node3D
var spike_active := false
var spike_timer := 0.0
var spike_hit_suspect := false
var spike_hit_player := false
var spike_hit_backup := false
var spike_hit_traffic: Dictionary = {}
var smoke_puffs: Array[MeshInstance3D] = []
var player_smoke_timer := 0.0
var suspect_smoke_timer := 0.0
var recovery_check_timer := 0.0
var recovery_positions: Dictionary = {}
var recovery_stall_times: Dictionary = {}
var recovery_cooldowns: Dictionary = {}
var status_label: Label
var distance_label: Label
var timer_label: Label
var damage_bar: ProgressBar
var nos_bar: ProgressBar
var apprehend_bar: ProgressBar
var skill_label: Label
var backup_button: Button
var spike_button: Button
var map_button: Button
var nos_button: Button
var result_panel: PanelContainer
var result_title: Label
var cockpit_node: Node3D
var route_markers: Array[Label3D] = []
var time_of_day := "dusk"
var street_lamps: Array[Node3D] = []
var npc_awareness_timer := 0.0
var road_decorator: Node3D
var city_builder: Node3D
var debug_zones_button: Button
var time_button: Button
var residential_builder: Node3D

const PANEL_NAVY := Color("#111629")
const POLICE_BLUE := Color("#3b82ff")
const SIREN_RED := Color("#ff3b4e")
const APPREHEND_GREEN := Color("#2fe0a0")
const HAZARD_AMBER := Color("#ffb23e")
const TACTICAL_VIOLET := Color("#9a6bff")


func _ready() -> void:
	configure_render_quality()
	time_of_day = "day"
	var district := $IntersectionDistrict
	configure_diorama_world(district)
	restyle_road_network(district)
	if not district.has_meta("streets_only"):
		road_decorator = RoadDecorator.new()
		road_decorator.name = "RoadDioramaDecorator"
		add_child(road_decorator)
		road_decorator.setup(district)
	# The experimental runtime grid is intentionally isolated. The production
	# pursuit uses the editor-authored road graph until a replacement district
	# has equivalent lane and intersection data.
	if district.has_meta("grid_city") and not district.has_meta("streets_only"):
		city_builder = CityBuilder.new()
		add_child(city_builder)
		city_builder.setup(district, road_decorator)
	if not district.has_meta("streets_only"):
		build_safe_street_lamps(district)
	var demo_ui := district.get_node_or_null("UI")
	if demo_ui:
		demo_ui.visible = false
	var vehicles := district.get_node("RoadManager/vehicles")
	player = vehicles.get_node("Player")
	player_agent = player.get_node("road_lane_agent")
	chase_camera = player.get_node("Camera3D")
	if exploration_mode:
		setup_exploration_mode(vehicles)
		return
	suspect = vehicles.get_node("NOC1")
	backup = vehicles.get_node("NOC10")
	player_agent = player.get_node("road_lane_agent")
	suspect_agent = suspect.get_node("road_lane_agent")
	backup_agent = backup.get_node("road_lane_agent")
	chase_camera = player.get_node("Camera3D")
	build_cockpit()
	build_route_markers()
	for actor in vehicles.get_children():
		if actor == player or actor == suspect:
			continue
		if actor == backup:
			actor.visible = false
			actor.process_mode = Node.PROCESS_MODE_DISABLED
		elif traffic.size() < 5:
			traffic.append(actor)
			actor.visible = true
			actor.process_mode = Node.PROCESS_MODE_INHERIT
			# Consistent civilian flow prevents faster rear traffic from compressing
			# into a stopped queue on this compact downtown circuit.
			var traffic_speed := 24
			actor.set("target_speed", traffic_speed)
			actor.set_meta("cruise_speed", traffic_speed)
			actor.set_meta("collision_stun", 0.0)
			actor.set_meta("impact_ready", true)
			actor.set_meta("lane_change_cooldown", 0.0)
			actor.set_meta("managed_lane_changes", true)
			actor.set_meta("smooth_lane_changes", true)
			actor.set_meta("lane_change_lateral_speed", 2.4)
			actor.set_meta("yielding_to_police", false)
			var traffic_profile := "compact" if traffic.size() % 3 == 0 else "patrol"
			paint_actor(actor, Color.from_hsv(fmod(traffic.size() * 0.14, 1.0), 0.34, 0.68), false, traffic_profile)
		else:
			actor.visible = false
			actor.process_mode = Node.PROCESS_MODE_DISABLED
	player.set("drive_state", 2)
	player.set("target_speed", CRUISE_SPEED)
	player.set("acceleration", 4)
	player.set_meta("smooth_lane_changes", true)
	player.set_meta("lane_change_turn_rate", 72.0)
	player.set_meta("road_bounds_enabled", true)
	suspect.set("drive_state", 1)
	suspect.set("target_speed", 34)
	suspect.set("acceleration", 3)
	paint_actor(player, Color(GameState.vehicle_color), true, police_profile(), GameState.vehicle_upgrades)
	paint_actor(suspect, Color("#b12631"), false, suspect_profile())
	paint_actor(backup, Color("#174d7a"), true, "patrol", {"armor": 1})
	spike_strip = create_spike_strip()
	spike_strip.visible = false
	add_child(spike_strip)
	build_hud()
	await get_tree().physics_frame
	player_agent.unassign_lane()
	player_agent.assign_nearest_lane()
	var spawn_position := player_agent.test_move_along_lane(0.0)
	player.global_position = spawn_position
	var spawn_heading := player_agent.test_move_along_lane(3.0)
	if spawn_position.distance_squared_to(spawn_heading) > 0.01:
		player.look_at(spawn_heading, Vector3.UP)
	suspect.global_transform = player.global_transform
	suspect.global_position = player_agent.test_move_along_lane(22.0)
	suspect_agent.unassign_lane()
	suspect_agent.assign_nearest_lane()
	suspect.global_position = suspect_agent.test_move_along_lane(0.0)
	configure_backup_availability()
	initialize_recovery_watchdog()
	last_forward = -player.global_transform.basis.z
	status_label.text = "DISPATCH LIVE · %s PURSUIT" % time_of_day.to_upper()


func configure_render_quality() -> void:
	var viewport := get_viewport()
	viewport.scaling_3d_scale = 1.0
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport.use_debanding = true


func _process(delta: float) -> void:
	update_smoke_puffs(delta)
	if not running:
		return
	if exploration_mode:
		update_exploration_mode(delta)
		return
	chase_time = maxf(0.0, chase_time - delta)
	collision_cooldown = maxf(0.0, collision_cooldown - delta)
	player_spike_slow_timer = maxf(0.0, player_spike_slow_timer - delta)
	var signed_speed := float(player.call("get_signed_speed"))
	var moving_forward := joystick_throttle > 0.14 or signed_speed > 2.0
	boosting = nos_armed and moving_forward and nos > 0.0 and player_spike_slow_timer <= 0.0
	player.set("target_speed", 24 if player_spike_slow_timer > 0.0 else (BOOST_SPEED if boosting and nos > 0.0 else CRUISE_SPEED))
	if boosting and nos > 0.0:
		nos = maxf(0.0, nos - 24.0 * delta)
		skill = minf(3.0, skill + 0.08 * delta)
		if nos <= 0.0:
			boosting = false
			nos_armed = false
			status_label.text = "NOS DEPLETED · EMPTY FOR THIS MISSION"
	if suspect_slow_timer > 0.0:
		suspect_slow_timer -= delta
		suspect.set("target_speed", 19)
	else:
		suspect.set("target_speed", 34)
	var distance := player.global_position.distance_to(suspect.global_position)
	if distance < 34.0:
		skill = minf(3.0, skill + 0.025 * delta)
	elif distance > 65.0:
		skill = maxf(1.0, skill - 0.1 * delta)
	check_traffic_collisions()
	update_traffic_recovery(delta)
	update_pileup_avoidance(delta)
	update_npc_awareness(delta)
	update_recovery_watchdog(delta)
	update_debris(delta)
	update_damage_smoke(delta)
	update_spike_strip(delta)
	update_backup(delta)
	update_recovery_watchdog(delta)
	update_navigation_feedback()
	update_route_markers()
	update_vehicle_lights()
	if map_active:
		update_map_camera()
	else:
		update_camera_impact(delta)
	update_hud(distance)
	if chase_time <= 0.0:
		finish(false, "THIEF ESCAPED")
	elif damage >= 100.0:
		finish(false, "UNIT DISABLED")
	elif distance > 145.0:
		finish(false, "CONTACT LOST")
	elif suspect_damage >= 100.0:
		finish(true, "SUSPECT VEHICLE DISABLED")


func setup_exploration_mode(vehicles: Node) -> void:
	if not $IntersectionDistrict.has_meta("builder_map"):
		residential_builder = ResidentialBuilder.new()
		$IntersectionDistrict.add_child(residential_builder)
		residential_builder.setup()
	var kept_traffic := 0
	for actor in vehicles.get_children():
		if actor == player:
			continue
		if kept_traffic >= exploration_traffic_count:
			actor.queue_free()
			continue
		kept_traffic += 1
		traffic.append(actor)
		actor.visible = true
		actor.process_mode = Node.PROCESS_MODE_INHERIT
		actor.set("drive_state", 1)
		var exploration_speed := 18 + (kept_traffic % 3) * 2
		actor.set("target_speed", exploration_speed)
		actor.set_meta("managed_lane_changes", true)
		actor.set_meta("smooth_lane_changes", true)
		actor.set_meta("npc_lane_changes_enabled", true)
		actor.set_meta("lane_change_lateral_speed", 2.2)
		actor.set_meta("curve_lookahead", 2.4)
		actor.set_meta("lane_change_turn_rate", 135.0)
		actor.set_meta("curb_yield_lateral_speed", 4.2)
		actor.set_meta("cruise_speed", exploration_speed)
		actor.set_meta("collision_stun", 0.0)
		actor.set("acceleration", 3)
		paint_actor(actor, Color.from_hsv(fmod(float(kept_traffic) * 0.13, 1.0), 0.3, 0.72), false, "compact")
	player.set("drive_state", 2)
	player.set_meta("road_bounds_enabled", true)
	player.set("target_speed", CRUISE_SPEED)
	player.set("acceleration", 4)
	paint_actor(player, Color(GameState.vehicle_color), true, police_profile(), GameState.vehicle_upgrades)
	if not $IntersectionDistrict.has_meta("builder_map"):
		build_grid_traffic_signals()
	else:
		setup_builder_traffic_signals()
	build_cockpit()
	build_route_markers()
	build_hud()
	apply_time_of_day(false)
	backup_button.visible = false
	spike_button.visible = false
	damage_bar.visible = false
	apprehend_bar.visible = false
	skill_label.text = "GOD MODE · DAMAGE DISABLED"
	timer_label.text = "FREE DRIVE"
	distance_label.text = "GRID EXPLORATION"
	await get_tree().physics_frame
	player_agent.unassign_lane()
	player_agent.assign_nearest_lane()
	player.global_position = player_agent.test_move_along_lane(0.0)
	last_forward = -player.global_transform.basis.z
	status_label.text = "FREE DRIVE · EXPLORE THE GRID"
	call_deferred("place_exploration_player")
	call_deferred("place_exploration_traffic")


func place_exploration_player() -> void:
	# Use a known straight-street lane instead of nearest-lane selection. The
	# nearest search only compares distance, so at a two-way road it may choose
	# either direction and previously retained the car's old perpendicular pose.
	var north_street := $IntersectionDistrict/RoadManager.get_node_or_null("Street_H_0_0")
	if not is_instance_valid(north_street):
		return
	var spawn_lane: RoadLane
	for candidate in north_street.find_children("*", "RoadLane", true, false):
		if candidate is RoadLane and not candidate.transition:
			spawn_lane = candidate
			break
	if not is_instance_valid(spawn_lane):
		return
	player_agent.unassign_lane()
	player_agent.assign_lane(spawn_lane)
	var lane_length := spawn_lane.curve.get_baked_length()
	var spawn_offset := clampf(lane_length * 0.25, 2.0, maxf(2.0, lane_length - 5.0))
	var heading_offset := minf(spawn_offset + 3.0, lane_length)
	var spawn_position := spawn_lane.to_global(spawn_lane.curve.sample_baked(spawn_offset))
	var spawn_heading := spawn_lane.to_global(spawn_lane.curve.sample_baked(heading_offset))
	player.global_position = spawn_position + Vector3.UP * 0.08
	if spawn_position.distance_squared_to(spawn_heading) > 0.01:
		player.look_at(spawn_heading, Vector3.UP)
	player.set("velocity", Vector3.ZERO)
	last_forward = -player.global_transform.basis.z


func place_exploration_traffic() -> void:
	# Bind each test car to a known straight road. Nearest-lane assignment can
	# select a perpendicular intersection lane when several paths overlap.
	var street_names := [
		"Street_H_0_0", "Street_H_0_1", "Street_H_1_0", "Street_H_1_1",
		"Street_H_2_0", "Street_H_2_1", "Street_V_0_0", "Street_V_2_1",
	]
	var fractions := [0.68, 0.30, 0.34, 0.72, 0.66, 0.28, 0.62, 0.38]
	var road_manager := $IntersectionDistrict/RoadManager
	for index in mini(traffic.size(), street_names.size()):
		var actor := traffic[index]
		var street := road_manager.get_node_or_null(street_names[index])
		if not is_instance_valid(street):
			continue
		var lanes: Array[RoadLane] = []
		for candidate in street.find_children("*", "RoadLane", true, false):
			if candidate is RoadLane and not candidate.transition:
				lanes.append(candidate)
		if lanes.is_empty():
			continue
		var lane: RoadLane = lanes[index % lanes.size()]
		var agent := actor.get_node("road_lane_agent") as RoadLaneAgent
		agent.unassign_lane()
		agent.assign_lane(lane)
		var lane_length := lane.curve.get_baked_length()
		var offset := clampf(lane_length * fractions[index], 4.0, maxf(4.0, lane_length - 4.0))
		var heading_offset := minf(offset + 2.5, lane_length)
		if heading_offset - offset < 0.2:
			heading_offset = maxf(0.0, offset - 2.5)
		var road_position := lane.to_global(lane.curve.sample_baked(offset))
		var road_heading := lane.to_global(lane.curve.sample_baked(heading_offset))
		actor.global_position = road_position + Vector3.UP * 0.08
		var flat_heading := road_heading - road_position
		flat_heading.y = 0.0
		if flat_heading.length_squared() > 0.001:
			actor.look_at(actor.global_position + flat_heading.normalized(), Vector3.UP)
		actor.set("velocity", Vector3.ZERO)


func build_grid_traffic_signals() -> void:
	var road_manager := $IntersectionDistrict/RoadManager
	var signal_root := Node3D.new()
	signal_root.name = "TrafficSignals"
	$IntersectionDistrict.add_child(signal_root)
	for intersection in road_manager.get_children():
		if not intersection.name.begins_with("Intersection_R"):
			continue
		var center: Vector3 = intersection.global_position
		traffic_signal_centers.append(center)
		for approach in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
			var side := Vector3(-approach.z, 0, approach.x)
			# One clear signal sits on the approaching driver's right side.
			for lateral_offset in [-10.5]:
				var assembly := Node3D.new()
				assembly.position = center - approach * 12.8 + side * lateral_offset
				signal_root.add_child(assembly)
				# Local +Z is the colored face. Point it toward approaching traffic.
				assembly.look_at(assembly.global_position - approach, Vector3.UP)
				var pole := MeshInstance3D.new()
				var pole_mesh := CylinderMesh.new()
				pole_mesh.top_radius = 0.17
				pole_mesh.bottom_radius = 0.22
				pole_mesh.height = 6.0
				pole.mesh = pole_mesh
				pole.position.y = 3.0
				pole.material_override = make_signal_material(Color("#26343b"), false)
				assembly.add_child(pole)
				var housing := MeshInstance3D.new()
				var housing_mesh := BoxMesh.new()
				housing_mesh.size = Vector3(0.98, 2.7, 0.75)
				housing.mesh = housing_mesh
				housing.position = Vector3(0, 6.05, 0)
				housing.material_override = make_signal_material(Color("#172127"), false)
				assembly.add_child(housing)
				var axis := "NS" if absf(approach.z) > 0.5 else "EW"
				for lamp_index in 3:
					var lamp := MeshInstance3D.new()
					var lamp_mesh := QuadMesh.new()
					lamp_mesh.size = Vector2(0.56, 0.56)
					lamp.mesh = lamp_mesh
					lamp.position = Vector3(0, 6.82 - lamp_index * 0.8, 0.386)
					lamp.set_meta("signal_axis", axis)
					lamp.set_meta("signal_color", ["red", "amber", "green"][lamp_index])
					assembly.add_child(lamp)
					traffic_signal_lamps.append(lamp)
	update_grid_traffic_signals()


func make_signal_material(color: Color, lit: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.metallic = 0.15
	material.roughness = 0.48
	if lit:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 4.0
	return material


func current_signal_state(axis: String) -> String:
	var phase := fmod(float(Time.get_ticks_msec()) / 1000.0, 16.0)
	if axis == "NS":
		if phase < 6.5:
			return "green"
		if phase < 8.0:
			return "amber"
		return "red"
	if phase < 8.0:
		return "red"
	if phase < 14.5:
		return "green"
	return "amber"


func update_grid_traffic_signals() -> void:
	for lamp in traffic_signal_lamps:
		var lamp_color := String(lamp.get_meta("signal_color"))
		var active := current_signal_state(String(lamp.get_meta("signal_axis"))) == lamp_color
		if bool(lamp.get_meta("signal_active", not active)) == active:
			continue
		lamp.set_meta("signal_active", active)
		var color := Color("#ff3e4f") if lamp_color == "red" else (Color("#ffc247") if lamp_color == "amber" else Color("#35e67a"))
		lamp.material_override = make_signal_material(color if active else color.darkened(0.78), active)
	update_builder_traffic_signals()
	for actor in traffic:
		if is_instance_valid(actor) and actor.visible and float(actor.get_meta("collision_stun", 0.0)) <= 0.0:
			apply_signal_response(actor)


func setup_builder_traffic_signals() -> void:
	var signal_shader := load("res://Assets/Synty/PolygonCity/Materials/Misc/Traffic_Light_Runtime.gdshader") as Shader
	for fixture in get_tree().get_nodes_in_group("builder_traffic_lights"):
		if not fixture is Node3D:
			continue
		traffic_signal_centers.append((fixture as Node3D).global_position)
		var fixture_meshes: Array[Node] = []
		# Polygon's traffic-light prefab is itself the signal MeshInstance3D;
		# find_children() does not include that root node.
		if fixture is MeshInstance3D:
			fixture_meshes.append(fixture)
		fixture_meshes.append_array((fixture as Node3D).find_children("*", "MeshInstance3D", true, false))
		for mesh_node in fixture_meshes:
			var signal_mesh := mesh_node as MeshInstance3D
			if signal_mesh.mesh == null or signal_mesh.mesh.get_surface_count() == 0:
				continue
			var source := signal_mesh.get_active_material(0) as StandardMaterial3D
			if source == null or source.albedo_texture == null:
				continue
			var runtime_material := ShaderMaterial.new()
			runtime_material.shader = signal_shader
			runtime_material.set_shader_parameter("source_texture", source.albedo_texture)
			runtime_material.set_shader_parameter("signal_state", 0)
			signal_mesh.material_override = runtime_material
			signal_mesh.set_meta("signal_axis", String((fixture as Node3D).get_meta("signal_axis", "NS")))
			builder_traffic_signals.append(signal_mesh)
	update_builder_traffic_signals()


func update_builder_traffic_signals() -> void:
	for signal_mesh in builder_traffic_signals:
		if not is_instance_valid(signal_mesh):
			continue
		var material := signal_mesh.material_override as ShaderMaterial
		if material == null:
			continue
		var state := current_signal_state(String(signal_mesh.get_meta("signal_axis", "NS")))
		material.set_shader_parameter("signal_state", {"red": 0, "amber": 1, "green": 2}.get(state, 0))


func apply_signal_response(actor: Node3D) -> void:
	var forward := -actor.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		return
	forward = forward.normalized()
	var axis := "NS" if absf(forward.z) > absf(forward.x) else "EW"
	var nearest_ahead := INF
	for center in traffic_signal_centers:
		var to_center := center - actor.global_position
		to_center.y = 0.0
		var distance := to_center.length()
		if distance > 0.01 and distance < 38.0 and forward.dot(to_center / distance) > 0.78:
			nearest_ahead = minf(nearest_ahead, distance)
	var cruise_speed := int(actor.get_meta("cruise_speed", 20))
	var state := current_signal_state(axis)
	actor.set_meta("stopped_for_signal", state != "green" and nearest_ahead < 32.0)
	if nearest_ahead < 11.0 or nearest_ahead == INF or state == "green":
		actor.set("target_speed", cruise_speed)
	elif state == "amber":
		actor.set("target_speed", maxi(5, int(cruise_speed * 0.35)) if nearest_ahead < 24.0 else cruise_speed)
	elif nearest_ahead < 19.0:
		actor.set("target_speed", 0)
	elif nearest_ahead < 32.0:
		actor.set("target_speed", maxi(4, int(cruise_speed * 0.25)))
	else:
		actor.set("target_speed", cruise_speed)


func update_exploration_mode(delta: float) -> void:
	damage = 0.0
	nos = 100.0
	var signed_speed := float(player.call("get_signed_speed"))
	var moving_forward := joystick_throttle > 0.14 or signed_speed > 2.0
	boosting = nos_armed and moving_forward
	player.set("target_speed", BOOST_SPEED if boosting else CRUISE_SPEED)
	# Holding a deliberate turn direction should select a later junction too.
	# Distance-based rearming avoids the former double-turn on short blocks.
	if buffered_turn_direction == 0 and not buffered_turn_armed and buffered_turn_input_sign != 0 and not is_instance_valid(player.get("pending_lane")) and planar_distance_to_point(player, last_turn_position) > 22.0:
		buffered_turn_direction = buffered_turn_input_sign
	attempt_buffered_joystick_turn()
	redirect_npcs_before_dead_ends()
	update_traffic_recovery(delta)
	update_pileup_avoidance(delta)
	update_npc_awareness(delta)
	# Signal braking is applied last so general traffic awareness cannot override
	# a red or amber light in the same frame.
	update_grid_traffic_signals()
	update_navigation_feedback()
	update_route_markers()
	var player_reversing := signed_speed < -0.5
	var player_braking := (Input.is_action_pressed("ui_down") and not player_reversing) or bool(player.get("intersection_turn_active")) or (signed_speed > 0.5 and signed_speed < previous_player_speed - 0.02)
	VehicleBuilder.update_lights(player, player_reversing, player_braking, time_of_day in ["dusk", "night"])
	PolygonVehicleBuilder.update_lights(player, player_reversing, player_braking, time_of_day in ["dusk", "night"])
	previous_player_speed = signed_speed
	for actor in traffic:
		if is_instance_valid(actor) and actor.visible:
			var traffic_speed := float(actor.call("get_signed_speed"))
			PolygonVehicleBuilder.update_lights(actor, traffic_speed < -0.5, traffic_speed < 3.0, time_of_day in ["dusk", "night"])
	if map_active:
		update_map_camera()
	else:
		update_camera_impact(delta)
	timer_label.text = "FREE DRIVE"
	distance_label.text = "GRID EXPLORATION"
	skill_label.text = "GOD MODE · DAMAGE DISABLED"
	nos_bar.value = 100.0
	if is_instance_valid(nos_button):
		nos_button.text = ("BOOST\n∞" if boosting else "NOS\n∞")


func update_navigation_feedback() -> void:
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	if last_forward.length_squared() > 0.0 and forward.dot(last_forward) < 0.992:
		status_label.text = "NAVIGATION TURN · NEW STREET"
	last_forward = last_forward.lerp(forward, 0.08).normalized()


func redirect_npcs_before_dead_ends() -> void:
	for actor in traffic:
		if not is_instance_valid(actor) or not actor.visible or is_instance_valid(actor.get("pending_lane")):
			continue
		var agent := actor.get_node("road_lane_agent") as RoadLaneAgent
		if not is_instance_valid(agent.current_lane) or agent.current_lane.transition:
			continue
		var current_lane := agent.current_lane
		if is_instance_valid(current_lane.get_node_or_null(current_lane.lane_next)):
			continue
		var lane_length := current_lane.curve.get_baked_length()
		var closest_local := current_lane.curve.get_closest_point(current_lane.to_local(actor.global_position))
		var current_offset := current_lane.curve.get_closest_offset(closest_local)
		# Do not guess a turn when the road kit exposes no connection. Recycle well
		# before the endpoint so the car cannot enter or orbit the intersection.
		if lane_length - current_offset < 16.0:
			recycle_traffic_to_safe_lane(actor, agent)


func attempt_buffered_joystick_turn() -> void:
	if buffered_turn_direction == 0 or not is_instance_valid(player_agent.current_lane):
		return
	if is_instance_valid(player.get("pending_lane")):
		return
	var forward := -player.global_transform.basis.z.normalized()
	var upcoming_center := Vector3.ZERO
	var upcoming_distance := INF
	for center in traffic_signal_centers:
		var offset := center - player.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < upcoming_distance and distance < 26.0 and forward.dot(offset.normalized()) > 0.82:
			upcoming_center = center
			upcoming_distance = distance
	if upcoming_distance == INF:
		if attempt_spatial_builder_turn(forward):
			buffered_turn_direction = 0
		return
	var desired_exit_direction := forward.cross(Vector3.UP).normalized() * float(buffered_turn_direction)
	var desired_exit_point := upcoming_center + desired_exit_direction * 18.0
	var best_lane: RoadLane
	var best_point := Vector3.ZERO
	var best_heading := Vector3.ZERO
	var best_score := INF
	for node in $IntersectionDistrict/RoadManager.find_children("*", "RoadLane", true, false):
		var lane := node as RoadLane
		if not is_instance_valid(lane) or lane.transition or lane == player_agent.current_lane:
			continue
		var local_closest := lane.curve.get_closest_point(lane.to_local(desired_exit_point))
		var lane_offset := lane.curve.get_closest_offset(local_closest)
		var lane_point := lane.to_global(local_closest)
		var ahead_offset := minf(lane.curve.get_baked_length(), lane_offset + 1.5)
		var lane_ahead := lane.to_global(lane.curve.sample_baked(ahead_offset))
		var lane_heading := (lane_ahead - lane_point).normalized()
		var alignment := lane_heading.dot(desired_exit_direction)
		if alignment < 0.72:
			continue
		var score := lane_point.distance_to(desired_exit_point) + (1.0 - alignment) * 5.0
		if score < best_score:
			best_score = score
			best_lane = lane
			best_point = lane_point
			best_heading = lane_heading
	if not is_instance_valid(best_lane) or best_score > 8.0:
		return
	if int(player.call("request_intersection_turn", best_lane, best_point, best_heading)) == OK:
		last_turn_position = player.global_position
		buffered_turn_direction = 0
		status_label.text = "BUFFERED TURN · ENTERING %s" % ("RIGHT" if desired_exit_direction.dot(forward.cross(Vector3.UP)) > 0.0 else "LEFT")


func attempt_spatial_builder_turn(forward: Vector3) -> bool:
	if not $IntersectionDistrict.has_meta("builder_map"):
		return false
	var desired_direction := forward.cross(Vector3.UP).normalized() * float(buffered_turn_direction)
	var junction_point := Vector3.ZERO
	var junction_distance := INF
	# Only an authored intersection module may open a side street. Merely placing
	# a perpendicular road beyond a sidewalk is not a driveable connection.
	for node in $IntersectionDistrict/RoadManager.find_children("*", "RoadLane", true, false):
		var junction_lane := node as RoadLane
		if String(junction_lane.get_meta("road_kind", "")) != "intersection":
			continue
		var local_point := junction_lane.curve.get_closest_point(junction_lane.to_local(player.global_position))
		var world_point := junction_lane.to_global(local_point)
		var relative := world_point - player.global_position
		relative.y = 0.0
		var ahead := forward.dot(relative)
		var sideways := absf(forward.cross(Vector3.UP).dot(relative))
		if ahead >= 0.5 and ahead < 24.0 and sideways < 4.5 and ahead < junction_distance:
			junction_distance = ahead
			junction_point = world_point
	if junction_distance == INF:
		return attempt_direct_t_junction_turn(forward, desired_direction)
	var best_lane: RoadLane
	var best_point := Vector3.ZERO
	var best_heading := Vector3.ZERO
	var best_score := INF
	for node in $IntersectionDistrict/RoadManager.find_children("*", "RoadLane", true, false):
		var lane := node as RoadLane
		if not is_instance_valid(lane) or lane == player_agent.current_lane:
			continue
		var closest_local := lane.curve.get_closest_point(lane.to_local(junction_point))
		var offset_on_lane := lane.curve.get_closest_offset(closest_local)
		var lane_point := lane.to_global(closest_local)
		var ahead_offset := minf(lane.curve.get_baked_length(), offset_on_lane + 3.5)
		var ahead_point := lane.to_global(lane.curve.sample_baked(ahead_offset))
		var lane_heading := ahead_point - lane_point
		lane_heading.y = 0.0
		if lane_heading.length_squared() < 0.01:
			var prior_offset := maxf(0.0, offset_on_lane - 1.5)
			var prior_point := lane.to_global(lane.curve.sample_baked(prior_offset))
			lane_heading = lane_point - prior_point
			lane_heading.y = 0.0
		if lane_heading.length_squared() < 0.01:
			continue
		lane_heading = lane_heading.normalized()
		var alignment := lane_heading.dot(desired_direction)
		if alignment < 0.78:
			continue
		var relative := lane_point - junction_point
		relative.y = 0.0
		var longitudinal := absf(forward.dot(relative))
		var lateral := desired_direction.dot(relative)
		if longitudinal > 8.0 or lateral < 1.5 or lateral > 14.0:
			continue
		var score := longitudinal * 0.35 + lateral * 0.18 + (1.0 - alignment) * 8.0
		if score < best_score:
			best_score = score
			best_lane = lane
			best_point = ahead_point
			best_heading = lane_heading
	if not is_instance_valid(best_lane):
		return false
	if int(player.call("request_intersection_turn", best_lane, best_point, best_heading)) != OK:
		return false
	last_turn_position = player.global_position
	status_label.text = "BUFFERED TURN · SLOWING INTO %s SIDE STREET" % ("RIGHT" if buffered_turn_direction > 0 else "LEFT")
	return true


func attempt_direct_t_junction_turn(forward: Vector3, desired_direction: Vector3) -> bool:
	var lanes := $IntersectionDistrict/RoadManager.find_children("*", "RoadLane", true, false)
	var best_lane: RoadLane
	var best_exit := Vector3.ZERO
	var best_heading := Vector3.ZERO
	var best_score := INF
	for node in lanes:
		var exit_lane := node as RoadLane
		if not is_instance_valid(exit_lane) or String(exit_lane.get_meta("road_kind", "")) != "straight":
			continue
		var start := exit_lane.get_lane_start()
		var start_heading := lane_heading_at_start(exit_lane)
		if start_heading.dot(desired_direction) < 0.8:
			continue
		var relative := start - player.global_position
		relative.y = 0.0
		var ahead := forward.dot(relative)
		var side := desired_direction.dot(relative)
		if ahead < 1.0 or ahead > 24.0 or side < 1.5 or side > 15.0:
			continue
		var touches_approach := false
		for approach_node in lanes:
			var approach := approach_node as RoadLane
			if not is_instance_valid(approach) or lane_heading_at_start(approach).dot(forward) < 0.8:
				continue
			var closest := approach.to_global(approach.curve.get_closest_point(approach.to_local(start)))
			if closest.distance_to(start) <= 3.8:
				touches_approach = true
				break
		if not touches_approach:
			continue
		var exit_offset := minf(3.8, exit_lane.curve.get_baked_length())
		var exit_point := exit_lane.to_global(exit_lane.curve.sample_baked(exit_offset))
		var score := ahead + side * 0.2
		if score < best_score:
			best_score = score
			best_lane = exit_lane
			best_exit = exit_point
			best_heading = start_heading
	if not is_instance_valid(best_lane):
		return false
	if int(player.call("request_intersection_turn", best_lane, best_exit, best_heading)) != OK:
		return false
	last_turn_position = player.global_position
	status_label.text = "BUFFERED TURN · ENTERING ONE-WAY SIDE STREET"
	return true


func lane_heading_at_start(lane: RoadLane) -> Vector3:
	var length := lane.curve.get_baked_length()
	var start := lane.to_global(lane.curve.sample_baked(0.0))
	var ahead := lane.to_global(lane.curve.sample_baked(minf(1.5, length)))
	var heading := ahead - start
	heading.y = 0.0
	return heading.normalized() if heading.length_squared() > 0.001 else Vector3.ZERO


func check_traffic_collisions() -> void:
	# Resolve the police push bumper first. Solid CharacterBodies settle about
	# one combined car length apart, so contact must be recognized before any
	# nearby civilian pair can consume this frame's collision response.
	if collision_cooldown <= 0.0 and is_push_bumper_contact():
		resolve_player_suspect_ram()
		return
	for actor in traffic:
		if not actor.visible:
			continue
		if collision_cooldown <= 0.0 and is_vehicle_contact(player, actor) and bool(actor.get_meta("impact_ready", true)):
			resolve_player_traffic_collision(actor)
			return
		if is_vehicle_contact(suspect, actor) and bool(actor.get_meta("impact_ready", true)):
			resolve_suspect_traffic_collision(actor)
			return
		if backup_timer > 0.0 and backup.visible and is_vehicle_contact(backup, actor) and bool(actor.get_meta("impact_ready", true)):
			resolve_backup_traffic_collision(actor)
			return


func is_vehicle_contact(first: Node3D, second: Node3D) -> bool:
	var separation := second.global_position - first.global_position
	separation.y = 0.0
	if separation.length_squared() > 27.04:
		return false
	# Test the separation in both vehicle coordinate systems. This preserves
	# legitimate head-on and crossing impacts while rejecting cars that are
	# merely close in an adjacent or opposing lane.
	var first_local := first.global_transform.basis.inverse() * separation
	var second_local := second.global_transform.basis.inverse() * -separation
	var overlaps_first := absf(first_local.x) < 2.25 and absf(first_local.z) < 4.65
	var overlaps_second := absf(second_local.x) < 2.25 and absf(second_local.z) < 4.65
	return overlaps_first and overlaps_second


func is_push_bumper_contact() -> bool:
	var separation := suspect.global_position - player.global_position
	separation.y = 0.0
	if separation.length() > 5.6 or separation.length_squared() < 0.01:
		return false
	var player_forward := -player.global_transform.basis.z
	player_forward.y = 0.0
	var suspect_ahead := player_forward.normalized().dot(separation.normalized()) > 0.55
	return suspect_ahead and Input.is_action_pressed("ui_up")


func resolve_player_suspect_ram() -> void:
	var base_ram_damage := 6.0 + float(ram_upgrade_level) * 2.0
	var ram_damage := base_ram_damage * 1.5 if boosting else base_ram_damage
	suspect_damage = minf(100.0, suspect_damage + ram_damage)
	skill = minf(3.0, skill + 0.2)
	collision_cooldown = 1.05
	# The push bumper absorbs suspect contact; civilian impacts still damage police.
	player.set("velocity", player.get("velocity") * 0.72)
	suspect.set("velocity", Vector3(0.0, 0.0, -18.0 if boosting else -10.0))
	suspect_slow_timer = maxf(suspect_slow_timer, 1.25)
	push_suspect_forward(5.5 if boosting else 2.8)
	trigger_impact_feedback(suspect.global_position, Color("#b12631"), 0.82 if boosting else 0.62)
	if randf() < 0.45:
		var deflect := -1 if randf() < 0.5 else 1
		if suspect_agent.change_lane(deflect) != OK:
			suspect_agent.change_lane(-deflect)
	status_label.text = "NOS PUSH HIT · SUSPECT DAMAGE +%d" % int(ram_damage) if boosting else "PUSH BUMPER HIT · SUSPECT DAMAGE +%d" % int(ram_damage)


func resolve_player_traffic_collision(actor: Node3D) -> void:
	damage = minf(100.0, damage + 24.0)
	skill = 1.0
	apprehend = maxf(0.0, apprehend - 14.0)
	collision_cooldown = 1.2
	player.set("velocity", Vector3.ZERO)
	stun_traffic(actor, 1.35)
	trigger_impact_feedback(actor.global_position, Color("#8b9299"), 0.95)
	status_label.text = "TRAFFIC COLLISION · BOTH VEHICLES SLOWED"


func resolve_suspect_traffic_collision(actor: Node3D) -> void:
	suspect.set("velocity", Vector3.ZERO)
	suspect_slow_timer = maxf(suspect_slow_timer, 2.4)
	suspect_damage = minf(100.0, suspect_damage + 6.0)
	stun_traffic(actor, 1.1)
	trigger_impact_feedback(suspect.global_position, Color("#b12631"), 0.65)
	status_label.text = "CHAIN COLLISION · SUSPECT DAMAGE +6"


func resolve_backup_traffic_collision(actor: Node3D) -> void:
	stun_traffic(actor, 1.4)
	trigger_impact_feedback(backup.global_position, Color("#174d7a"), 0.8)
	backup.set("velocity", Vector3.ZERO)
	backup_timer = 0.0
	backup.visible = false
	backup.process_mode = Node.PROCESS_MODE_DISABLED
	backup_button.text = "BACKUP CRASHED"
	status_label.text = "BACKUP COLLISION · ASSIST ENDED"


func stun_traffic(actor: Node3D, duration: float) -> void:
	actor.set("velocity", Vector3.ZERO)
	actor.set("target_speed", 5)
	actor.set_meta("collision_stun", duration)
	actor.set_meta("impact_ready", false)


func update_traffic_recovery(delta: float) -> void:
	for actor in traffic:
		var stun := maxf(0.0, float(actor.get_meta("collision_stun", 0.0)) - delta)
		actor.set_meta("collision_stun", stun)
		if stun <= 0.0 and not bool(actor.get_meta("impact_ready", true)):
			actor.set("target_speed", int(actor.get_meta("cruise_speed", 26)))
			actor.set_meta("impact_ready", true)


func update_pileup_avoidance(delta: float) -> void:
	pileup_check_timer -= delta
	if pileup_check_timer > 0.0:
		return
	pileup_check_timer = 0.45
	for approaching in traffic:
		if not approaching.visible or float(approaching.get_meta("collision_stun", 0.0)) > 0.0:
			continue
		var approaching_agent := approaching.get_node("road_lane_agent") as RoadLaneAgent
		for blocked in traffic:
			if blocked == approaching or float(blocked.get_meta("collision_stun", 0.0)) <= 0.0:
				continue
			var blocked_agent := blocked.get_node("road_lane_agent") as RoadLaneAgent
			if approaching_agent.current_lane == blocked_agent.current_lane and planar_distance(approaching, blocked) < 16.0:
				try_safe_lane_change(approaching, 1)
				break


func update_npc_awareness(delta: float) -> void:
	for actor in traffic:
		actor.set_meta("lane_change_cooldown", maxf(0.0, float(actor.get_meta("lane_change_cooldown", 0.0)) - delta))
	npc_awareness_timer -= delta
	if npc_awareness_timer > 0.0:
		return
	npc_awareness_timer = 0.12
	for actor in traffic:
		if not actor.visible or float(actor.get_meta("collision_stun", 0.0)) > 0.0:
			continue
		# Keep a yield command stable until the next awareness decision. Clearing it
		# every physics frame made the car begin and cancel its pull-over repeatedly.
		actor.set("target_lateral_lane_offset", 0.0)
		var cruise_speed := int(actor.get_meta("cruise_speed", 26))
		var handled := false
		for police_unit in [player, backup]:
			if police_unit == backup and (backup_timer <= 0.0 or not backup.visible):
				continue
			if should_yield_to_police(actor, police_unit):
				handled = yield_to_police(actor, police_unit, cruise_speed)
				if handled:
					break
		if handled:
			continue
		actor.set_meta("yielding_to_police", false)
		if npc_is_cornering(actor):
			actor.set("target_speed", 7)
			continue
		var threat := find_predicted_threat(actor)
		if threat:
			avoid_predicted_collision(actor, threat, cruise_speed)
		else:
			actor.set("target_speed", cruise_speed)


func npc_is_cornering(actor: Node3D) -> bool:
	var actor_agent := actor.get_node_or_null("road_lane_agent") as RoadLaneAgent
	if not is_instance_valid(actor_agent) or not is_instance_valid(actor_agent.current_lane):
		return false
	var lane := actor_agent.current_lane
	if String(lane.get_meta("road_kind", "")) == "curve":
		return true
	if not actor_agent.close_to_lane_end(11.0, 1):
		return false
	var next_lane := lane.get_node_or_null(lane.lane_next) as RoadLane
	return is_instance_valid(next_lane) and String(next_lane.get_meta("road_kind", "")) == "curve"


func should_yield_to_police(actor: Node3D, police_unit: Node3D) -> bool:
	if not is_instance_valid(police_unit):
		return false
	var to_police := police_unit.global_position - actor.global_position
	to_police.y = 0.0
	var distance := to_police.length()
	if distance < 0.01 or distance > 34.0:
		return false
	var actor_forward := -actor.global_transform.basis.z
	var actor_agent := actor.get_node_or_null("road_lane_agent") as RoadLaneAgent
	if is_instance_valid(actor_agent) and is_instance_valid(actor_agent.current_lane):
		# The lane is authoritative while the vehicle is still aligning after a
		# turn. Transform-only detection intermittently rejected police that were
		# physically behind a civilian but whose body had not finished rotating.
		var lane := actor_agent.current_lane
		var closest_local := lane.curve.get_closest_point(lane.to_local(actor.global_position))
		var closest_offset := lane.curve.get_closest_offset(closest_local)
		var ahead_offset := minf(lane.curve.get_baked_length(), closest_offset + 1.0)
		var behind_offset := maxf(0.0, closest_offset - 1.0)
		actor_forward = lane.to_global(lane.curve.sample_baked(ahead_offset)) - lane.to_global(lane.curve.sample_baked(behind_offset))
	actor_forward.y = 0.0
	if actor_forward.length_squared() < 0.001:
		return false
	actor_forward = actor_forward.normalized()
	var police_forward := -police_unit.global_transform.basis.z
	police_forward.y = 0.0
	police_forward = police_forward.normalized()
	var same_direction := actor_forward.dot(police_forward) > 0.62
	var police_behind := actor_forward.dot(to_police.normalized()) < -0.48
	if bool(actor.get_meta("yielding_to_police", false)) and same_direction:
		# Stay at the curb while the police unit is beside the civilian. Recenter
		# only after the unit is safely ahead instead of moving into its flank.
		return actor_forward.dot(to_police) < 9.0
	return same_direction and police_behind


func yield_to_police(actor: Node3D, police_unit: Node3D, cruise_speed: int) -> bool:
	actor.set_meta("yielding_to_police", true)
	var actor_agent := actor.get_node_or_null("road_lane_agent") as RoadLaneAgent
	if is_instance_valid(actor_agent) and is_instance_valid(actor_agent.current_lane):
		var lane := actor_agent.current_lane
		var single_lane_one_way := bool(lane.get_meta("one_way", false)) and int(lane.get_meta("same_direction_lane_count", 0)) == 1
		var road_kind := String(lane.get_meta("road_kind", ""))
		# Straight-through intersection lanes are part of the same one-way
		# approach. A stopped signal must not disable emergency yielding.
		if single_lane_one_way and road_kind in ["straight", "intersection"]:
			# Pull toward the passenger-side curb. A 2.65 m offset places part of the
			# vehicle over the sidewalk without sending its lane agent off-network.
			actor.set("target_lateral_lane_offset", 2.9)
			var curb_distance := planar_distance(actor, police_unit)
			var current_offset := float(actor.get("lateral_lane_offset"))
			# It must keep rolling long enough to steer onto the shoulder. Stopping at
			# lane center would leave both vehicles blocked.
			actor.set("target_speed", 0 if curb_distance < 13.0 and current_offset > 2.5 else maxi(6, int(cruise_speed * 0.30)))
			return true
	# On roads with additional lanes, civilian traffic holds its lane. The police
	# driver must use the existing same-direction lane-change controls to pass.
	actor.set_meta("yielding_to_police", false)
	return false


func find_predicted_threat(actor: Node3D) -> Node3D:
	var candidates: Array[Node3D] = [player, suspect]
	if backup_timer > 0.0 and backup.visible:
		candidates.append(backup)
	for other in traffic:
		if other != actor and other.visible:
			candidates.append(other)
	var nearest_threat: Node3D
	var nearest_distance := INF
	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue
		var distance := planar_distance(actor, candidate)
		if distance >= nearest_distance or distance > 30.0:
			continue
		if predicts_vehicle_conflict(actor, candidate):
			nearest_threat = candidate
			nearest_distance = distance
	return nearest_threat


func predicts_vehicle_conflict(actor: Node3D, other: Node3D) -> bool:
	var separation := other.global_position - actor.global_position
	separation.y = 0.0
	var actor_velocity: Vector3 = actor.get("velocity")
	var other_velocity: Vector3 = other.get("velocity")
	actor_velocity.y = 0.0
	other_velocity.y = 0.0
	var relative_velocity := other_velocity - actor_velocity
	var relative_speed_sq := relative_velocity.length_squared()
	if relative_speed_sq < 0.08:
		return separation.length() < 7.0
	var closest_time := clampf(-separation.dot(relative_velocity) / relative_speed_sq, 0.0, 2.4)
	if closest_time <= 0.04:
		return false
	var closest_offset := separation + relative_velocity * closest_time
	return closest_offset.length() < 3.3


func avoid_predicted_collision(actor: Node3D, threat: Node3D, cruise_speed: int) -> void:
	var actor_forward := -actor.global_transform.basis.z.normalized()
	var local_threat := actor.global_transform.basis.inverse() * (threat.global_position - actor.global_position)
	var threat_ahead := actor_forward.dot((threat.global_position - actor.global_position).normalized()) > 0.15
	var preferred_direction := -1 if local_threat.x > 0.0 else 1
	if threat_ahead and (try_safe_lane_change(actor, preferred_direction) or try_safe_lane_change(actor, -preferred_direction)):
		actor.set("target_speed", maxi(9, int(cruise_speed * 0.58)))
		return
	var distance := planar_distance(actor, threat)
	if distance < 8.0:
		actor.set("target_speed", 0)
	elif distance < 15.0:
		actor.set("target_speed", maxi(4, int(cruise_speed * 0.24)))
	else:
		actor.set("target_speed", maxi(8, int(cruise_speed * 0.52)))


func try_safe_lane_change(actor: Node3D, direction: int) -> bool:
	if actor in traffic and not bool(actor.get_meta("npc_lane_changes_enabled", false)):
		return false
	if float(actor.get_meta("lane_change_cooldown", 0.0)) > 0.0:
		return false
	# Hold the selected lane through junctions. Lane changes resume once the
	# complete vehicle is clear of the intersection conflict area.
	for center in traffic_signal_centers:
		if planar_distance_to_point(actor, center) < 24.0:
			return false
	var agent := actor.get_node("road_lane_agent") as RoadLaneAgent
	if not is_instance_valid(agent.current_lane):
		return false
	var candidate_path: NodePath = agent.current_lane.lane_right if direction > 0 else agent.current_lane.lane_left
	var candidate := agent.current_lane.get_node_or_null(candidate_path) as RoadLane
	if not is_instance_valid(candidate) or lane_direction_prefix(candidate) != lane_direction_prefix(agent.current_lane):
		return false
	# A Bezier lane change that enters a bend will naturally cut across the verge.
	# Require the full maneuver distance to remain on connected straight modules.
	if actor in traffic and (String(agent.current_lane.get_meta("road_kind", "")) != "straight" or not lane_has_straight_clearance(candidate, 32.0)):
		return false
	for other in traffic:
		if other == actor or not other.visible:
			continue
		var other_agent := other.get_node("road_lane_agent") as RoadLaneAgent
		if other_agent.current_lane == candidate:
			var local_other: Vector3 = actor.global_transform.basis.inverse() * (other.global_position - actor.global_position)
			# Godot vehicle-forward is local -Z: reserve more room ahead than behind.
			if (local_other.z < 0.0 and -local_other.z < 19.0) or (local_other.z >= 0.0 and local_other.z < 13.0):
				return false
	for priority_unit in [player, suspect, backup]:
		if is_instance_valid(priority_unit) and planar_distance(actor, priority_unit) < 10.0:
			var local_unit: Vector3 = actor.global_transform.basis.inverse() * (priority_unit.global_position - actor.global_position)
			if signf(local_unit.x) == float(direction):
				return false
	if int(actor.call("request_lane_change", direction)) != OK:
		return false
	actor.set_meta("lane_change_cooldown", 2.4)
	return true


func lane_has_straight_clearance(start_lane: RoadLane, required_distance: float) -> bool:
	var lane := start_lane
	var remaining := required_distance
	var safety := 0
	while is_instance_valid(lane) and safety < 16:
		if String(lane.get_meta("road_kind", "")) != "straight":
			return false
		remaining -= lane.curve.get_baked_length()
		if remaining <= 0.0:
			return true
		lane = lane.get_node_or_null(lane.lane_next) as RoadLane
		safety += 1
	return false


func push_suspect_forward(distance: float) -> void:
	if not is_instance_valid(suspect_agent.current_lane):
		return
	var pushed_position := suspect_agent.test_move_along_lane(distance)
	var motion := pushed_position - suspect.global_position
	# CharacterBody collision clips the shove against solid traffic, allowing
	# a hard NOS ram to create a pile-up without phasing through the lead car.
	suspect.call("move_and_collide", motion)


func initialize_recovery_watchdog() -> void:
	for actor in get_recoverable_actors():
		recovery_positions[actor] = actor.global_position
		recovery_stall_times[actor] = 0.0
		recovery_cooldowns[actor] = 0.0


func update_recovery_watchdog(delta: float) -> void:
	for actor in recovery_cooldowns.keys():
		recovery_cooldowns[actor] = maxf(0.0, float(recovery_cooldowns[actor]) - delta)
	recovery_check_timer -= delta
	if recovery_check_timer > 0.0:
		return
	var sample_time := 0.4
	recovery_check_timer = sample_time
	for actor in get_recoverable_actors():
		if not is_instance_valid(actor) or not actor.visible:
			continue
		var agent := get_actor_agent(actor)
		if not is_instance_valid(agent):
			continue
		var previous: Vector3 = recovery_positions.get(actor, actor.global_position)
		var moved := planar_vector_distance(previous, actor.global_position)
		recovery_positions[actor] = actor.global_position
		var expects_motion := actor != player or Input.is_action_pressed("ui_up")
		if actor in traffic and bool(actor.get_meta("stopped_for_signal", false)):
			expects_motion = false
		# Pulling over and holding at the curb is intentional. Without this state
		# exemption, the four-second stall watchdog teleported the yielding car and
		# cleared the lateral offset just as police reached it.
		var intentionally_yielding := actor in traffic and bool(actor.get_meta("yielding_to_police", false))
		if intentionally_yielding:
			expects_motion = false
		if actor == backup:
			expects_motion = backup_timer > 0.0
		if expects_motion and moved < 0.18:
			recovery_stall_times[actor] = float(recovery_stall_times.get(actor, 0.0)) + sample_time
		else:
			recovery_stall_times[actor] = 0.0
		var off_map := absf(actor.global_position.x) > 116.0 or absf(actor.global_position.z) > 116.0 or actor.global_position.y < -2.0 or actor.global_position.y > 12.0
		var nearest_lane := agent.find_nearest_lane(actor.global_position, 18.0)
		var off_road := not is_instance_valid(nearest_lane)
		if is_instance_valid(nearest_lane):
			var nearest_point := agent.get_closest_path_point(nearest_lane, actor.global_position)
			off_road = planar_vector_distance(actor.global_position, nearest_point) > 10.5
		var overturned := actor.global_transform.basis.y.normalized().dot(Vector3.UP) < 0.35
		var reversed := is_actor_reversed(actor, agent)
		var stalled := not intentionally_yielding and float(recovery_stall_times[actor]) >= (5.0 if actor == player else 4.0)
		if float(recovery_cooldowns.get(actor, 0.0)) <= 0.0 and (off_map or off_road or overturned or reversed or stalled):
			if actor in traffic:
				recycle_traffic_to_safe_lane(actor, agent)
			else:
				recover_actor_to_lane(actor, agent, "AUTO RECOVERY · VEHICLE RESET TO ROAD")


func recycle_traffic_to_safe_lane(actor: Node3D, agent: RoadLaneAgent) -> void:
	var best_lane: RoadLane
	var best_position := Vector3.ZERO
	var best_score := INF
	for node in $IntersectionDistrict/RoadManager.find_children("*", "RoadLane", true, false):
		var lane := node as RoadLane
		if not is_instance_valid(lane) or lane.transition or lane.curve.get_baked_length() < 20.0:
			continue
		# Recycle only onto routes already connected by the road kit. This prevents
		# moving a car from one unlinked boundary lane directly onto another.
		if not is_instance_valid(lane.get_node_or_null(lane.lane_next)):
			continue
		var offset := lane.curve.get_baked_length() * 0.5
		var candidate := lane.to_global(lane.curve.sample_baked(offset))
		if not is_recovery_point_clear(actor, candidate):
			continue
		var player_clearance := planar_distance_to_point(player, candidate)
		if player_clearance < 24.0:
			continue
		if is_instance_valid(suspect) and suspect.visible and planar_distance_to_point(suspect, candidate) < 24.0:
			continue
		var score := absf(player_clearance - 55.0)
		if score < best_score:
			best_score = score
			best_lane = lane
			best_position = candidate
	if not is_instance_valid(best_lane):
		return
	actor.call("cancel_lane_change")
	agent.unassign_lane()
	agent.assign_lane(best_lane)
	actor.global_position = best_position + Vector3.UP * 0.08
	var heading := agent.test_move_along_lane(3.0)
	actor.look_at(heading, Vector3.UP)
	actor.set("velocity", Vector3.ZERO)
	actor.set("target_speed", int(actor.get_meta("cruise_speed", 18)))
	actor.set_meta("collision_stun", 0.0)
	actor.set_meta("impact_ready", true)
	actor.set_meta("stopped_for_signal", false)
	actor.set_meta("lane_change_cooldown", 1.5)
	recovery_positions[actor] = actor.global_position
	recovery_stall_times[actor] = 0.0
	recovery_cooldowns[actor] = 5.0


func get_recoverable_actors() -> Array[Node3D]:
	var actors: Array[Node3D] = [player]
	if is_instance_valid(suspect):
		actors.append(suspect)
	if is_instance_valid(backup) and backup_timer > 0.0:
		actors.append(backup)
	for actor in traffic:
		if is_instance_valid(actor) and actor.visible:
			actors.append(actor)
	return actors


func get_actor_agent(actor: Node3D) -> RoadLaneAgent:
	return actor.get_node_or_null("road_lane_agent") as RoadLaneAgent


func is_actor_reversed(actor: Node3D, agent: RoadLaneAgent) -> bool:
	if not is_instance_valid(agent.current_lane):
		return true
	var path_ahead := agent.test_move_along_lane(1.5) - actor.global_position
	path_ahead.y = 0.0
	if path_ahead.length_squared() < 0.04:
		return false
	var actor_forward := -actor.global_transform.basis.z
	actor_forward.y = 0.0
	return actor_forward.normalized().dot(path_ahead.normalized()) < -0.35


func recover_player() -> void:
	if running:
		recover_actor_to_lane(player, player_agent, "MANUAL RECOVERY · UNIT RESET TO ROAD")


func recover_actor_to_lane(actor: Node3D, agent: RoadLaneAgent, message: String) -> void:
	if actor.get("target_lateral_lane_offset") != null:
		actor.set("target_lateral_lane_offset", 0.0)
		actor.set("lateral_lane_offset", 0.0)
	if not is_instance_valid(agent.current_lane) and agent.assign_nearest_lane() != OK:
		return
	var recovery_point := agent.test_move_along_lane(6.0)
	for distance in [6.0, 12.0, 18.0, 24.0]:
		var candidate := agent.test_move_along_lane(distance)
		if is_recovery_point_clear(actor, candidate):
			recovery_point = candidate
			break
	actor.global_position = recovery_point + Vector3.UP * 0.08
	var look_target := agent.test_move_along_lane(1.8)
	if not actor.global_position.is_equal_approx(look_target):
		actor.look_at(look_target, Vector3.UP)
	actor.set("velocity", Vector3.ZERO)
	recovery_positions[actor] = actor.global_position
	recovery_stall_times[actor] = 0.0
	recovery_cooldowns[actor] = 4.0
	status_label.text = message


func is_recovery_point_clear(actor: Node3D, point: Vector3) -> bool:
	for other in get_recoverable_actors():
		if other != actor and is_instance_valid(other) and planar_distance_to_point(other, point) < 5.5:
			return false
	return true


func planar_vector_distance(a: Vector3, b: Vector3) -> float:
	var offset := a - b
	offset.y = 0.0
	return offset.length()


func planar_distance(a: Node3D, b: Node3D) -> float:
	var offset := a.global_position - b.global_position
	offset.y = 0.0
	return offset.length()


func trigger_impact_feedback(impact_position: Vector3, debris_color: Color, strength: float) -> void:
	camera_shake = maxf(camera_shake, 0.34 + strength * 0.18)
	camera_shake_strength = maxf(camera_shake_strength, strength)
	spawn_impact_debris(impact_position, debris_color, 5 + int(strength * 4.0))


func spawn_impact_debris(impact_position: Vector3, debris_color: Color, count: int) -> void:
	for i in count:
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(randf_range(0.08, 0.28), randf_range(0.05, 0.18), randf_range(0.12, 0.38))
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#ffb13b") if i < 2 else debris_color.darkened(randf_range(0.0, 0.45))
		material.metallic = 0.55
		material.roughness = 0.4
		if i < 2:
			material.emission_enabled = true
			material.emission = Color("#ff7b24")
		mesh.material = material
		piece.mesh = mesh
		add_child(piece)
		piece.global_position = impact_position + Vector3(randf_range(-0.9, 0.9), randf_range(0.35, 1.1), randf_range(-0.9, 0.9))
		piece.set_meta("velocity", Vector3(randf_range(-5.5, 5.5), randf_range(3.5, 8.0), randf_range(-5.0, 5.0)))
		piece.set_meta("life", randf_range(0.7, 1.4))
		debris_pieces.append(piece)


func update_debris(delta: float) -> void:
	for i in range(debris_pieces.size() - 1, -1, -1):
		var piece := debris_pieces[i]
		if not is_instance_valid(piece):
			debris_pieces.remove_at(i)
			continue
		var life := float(piece.get_meta("life", 0.0)) - delta
		var velocity: Vector3 = piece.get_meta("velocity", Vector3.ZERO)
		velocity.y -= 15.0 * delta
		piece.global_position += velocity * delta
		piece.rotation += Vector3(7.0, 10.0, 5.0) * delta
		piece.set_meta("velocity", velocity)
		piece.set_meta("life", life)
		if life <= 0.0 or piece.global_position.y < -1.0:
			piece.queue_free()
			debris_pieces.remove_at(i)


func update_damage_smoke(delta: float) -> void:
	player_smoke_timer = update_vehicle_smoke(player, damage, player_smoke_timer, delta)
	suspect_smoke_timer = update_vehicle_smoke(suspect, suspect_damage, suspect_smoke_timer, delta)


func update_vehicle_smoke(actor: Node3D, vehicle_damage: float, timer: float, delta: float) -> float:
	if vehicle_damage < 50.0 or not is_instance_valid(actor):
		return 0.0
	var severity := clampf((vehicle_damage - 50.0) / 50.0, 0.0, 1.0)
	timer -= delta
	if timer <= 0.0:
		spawn_smoke_puff(actor, severity)
		if severity > 0.72:
			spawn_smoke_puff(actor, severity)
		timer = lerpf(0.3, 0.065, severity)
	return timer


func spawn_smoke_puff(actor: Node3D, severity: float) -> void:
	var puff := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	var start_size := lerpf(0.62, 1.18, severity)
	sphere.radius = start_size
	sphere.height = start_size * 2.0
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var gray := lerpf(0.58, 0.055, severity)
	material.albedo_color = Color(gray, gray, gray, lerpf(0.68, 0.94, severity))
	sphere.material = material
	puff.mesh = sphere
	add_child(puff)
	# Smoke originates around the hood/engine compartment at the front (-Z).
	puff.global_position = actor.global_position - actor.global_transform.basis.z * 1.35 + Vector3.UP * 1.25
	puff.global_position += Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.25, 0.25))
	puff.set_meta("life", lerpf(1.9, 2.8, severity))
	puff.set_meta("max_life", lerpf(1.9, 2.8, severity))
	puff.set_meta("velocity", Vector3(randf_range(-0.35, 0.35), lerpf(1.4, 2.5, severity), randf_range(-0.3, 0.3)))
	puff.set_meta("material", material)
	puff.set_meta("severity", severity)
	smoke_puffs.append(puff)


func update_smoke_puffs(delta: float) -> void:
	for i in range(smoke_puffs.size() - 1, -1, -1):
		var puff := smoke_puffs[i]
		if not is_instance_valid(puff):
			smoke_puffs.remove_at(i)
			continue
		var life := float(puff.get_meta("life", 0.0)) - delta
		var max_life := float(puff.get_meta("max_life", 1.0))
		var velocity: Vector3 = puff.get_meta("velocity", Vector3.UP)
		puff.global_position += velocity * delta
		puff.scale += Vector3.ONE * delta * 0.52
		var material := puff.get_meta("material") as StandardMaterial3D
		if material:
			var color := material.albedo_color
			color.a = clampf(life / max_life, 0.0, 1.0) * lerpf(0.7, 0.96, float(puff.get_meta("severity", 0.0)))
			material.albedo_color = color
		puff.set_meta("life", life)
		if life <= 0.0:
			puff.queue_free()
			smoke_puffs.remove_at(i)


func update_camera_impact(delta: float) -> void:
	if camera_mode == 0:
		if not chase_camera_initialized:
			chase_camera_yaw = player.global_rotation.y
			chase_camera_initialized = true
		chase_camera_yaw = lerp_angle(chase_camera_yaw, player.global_rotation.y, minf(1.0, delta * 2.2))
		var follow_basis := Basis(Vector3.UP, chase_camera_yaw)
		var desired_position := player.global_position + follow_basis * Vector3(0.0, 6.5, 13.0)
		var roll := 0.0
		if camera_shake > 0.0:
			camera_shake = maxf(0.0, camera_shake - delta)
			var fade := clampf(camera_shake / 0.5, 0.0, 1.0)
			var amount := camera_shake_strength * fade
			desired_position += Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(-0.45, 0.2)) * amount
			roll = randf_range(-0.035, 0.035) * amount
		else:
			camera_shake_strength = 0.0
		chase_camera.global_position = chase_camera.global_position.lerp(desired_position, minf(1.0, delta * 7.0))
		chase_camera.global_rotation = Vector3(deg_to_rad(-12.0), chase_camera_yaw, roll)
		return
	var base_position := Vector3(0.0, 1.8, -0.4) if camera_mode == 1 else Vector3(0.0, 6.5, 13.0)
	if camera_shake > 0.0:
		camera_shake = maxf(0.0, camera_shake - delta)
		var fade := clampf(camera_shake / 0.5, 0.0, 1.0)
		var amount := camera_shake_strength * fade
		chase_camera.position = base_position + Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(-0.45, 0.2)) * amount
		chase_camera.rotation.z = randf_range(-0.035, 0.035) * amount
	else:
		camera_shake_strength = 0.0
		chase_camera.position = chase_camera.position.lerp(base_position, minf(1.0, delta * 12.0))
		chase_camera.rotation.z = lerp_angle(chase_camera.rotation.z, 0.0, minf(1.0, delta * 12.0))


func update_backup(delta: float) -> void:
	if backup_timer <= 0.0:
		return
	backup_timer -= delta
	backup_overtake_timer -= delta
	if backup_timer <= 0.0:
		backup.visible = false
		backup.process_mode = Node.PROCESS_MODE_DISABLED
		backup_button.text = "BACKUP USED"
		status_label.text = "BACKUP CLEARING PURSUIT"
	elif backup.global_position.distance_to(suspect.global_position) < 18.0:
		suspect_damage = minf(100.0, suspect_damage + 0.7 * delta)
	elif backup_overtake_timer <= 0.0 and planar_distance(backup, player) < 13.0:
		backup_overtake_timer = 0.55
		attempt_backup_overtake()


func activate_backup() -> void:
	if not backup_available or not running:
		return
	backup_available = false
	backup_timer = 8.0
	backup.visible = true
	backup.process_mode = Node.PROCESS_MODE_INHERIT
	backup.global_transform = player.global_transform
	backup.global_position += player.global_transform.basis.z * 11.0
	backup.set("drive_state", 1)
	backup.set("target_speed", 56)
	backup.set("acceleration", 5)
	backup_agent.unassign_lane()
	backup_agent.assign_nearest_lane()
	attempt_backup_overtake()
	for actor in traffic:
		if actor.global_position.distance_to(player.global_position) < 55.0:
			var agent := actor.get_node("road_lane_agent") as RoadLaneAgent
			agent.change_lane(1)
	backup_button.disabled = true
	backup_button.text = "BACKUP 8 SEC"
	status_label.text = "BACKUP JOINED CORRECT-DIRECTION LANES"


func deploy_spikes() -> void:
	if spike_charges <= 0 or not running or spike_active:
		return
	if not is_instance_valid(suspect_agent.current_lane):
		status_label.text = "SPIKES OUT OF RANGE"
		return
	spike_charges -= 1
	spike_active = true
	spike_timer = 6.0
	spike_hit_suspect = false
	spike_hit_player = false
	spike_hit_backup = false
	spike_hit_traffic.clear()
	var placement := suspect_agent.test_move_along_lane(16.0)
	var look_target := suspect_agent.test_move_along_lane(17.0)
	spike_strip.global_position = placement + Vector3.UP * 0.12
	spike_strip.look_at(look_target + Vector3.UP * 0.12, Vector3.UP)
	spike_strip.visible = true
	spike_button.text = "SPIKES ×%d" % spike_charges
	spike_button.disabled = true
	status_label.text = "SPIKE STRIP VISIBLE · DEPLOYED AHEAD"


func create_spike_strip() -> Node3D:
	var strip := Node3D.new()
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(3.4, 0.1, 0.62)
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = Color("#121820")
	base_material.metallic = 0.45
	base_mesh.material = base_material
	base.mesh = base_mesh
	strip.add_child(base)
	for i in 9:
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.075
		cone.height = 0.32
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#dce4e8")
		material.metallic = 0.9
		cone.material = material
		spike.mesh = cone
		spike.position = Vector3(-1.45 + i * 0.36, 0.2, 0.0)
		strip.add_child(spike)
	return strip


func update_spike_strip(delta: float) -> void:
	if not spike_active:
		return
	spike_timer -= delta
	if not spike_hit_suspect and planar_distance_to_point(suspect, spike_strip.global_position) < 3.0:
		spike_hit_suspect = true
		suspect_slow_timer = 4.5
		suspect_damage = minf(100.0, suspect_damage + 4.0)
		trigger_impact_feedback(suspect.global_position, Color("#3e4650"), 0.3)
		status_label.text = "SUSPECT HIT VISIBLE SPIKES · DAMAGE +4"
	if not spike_hit_player and planar_distance_to_point(player, spike_strip.global_position) < 3.0:
		spike_hit_player = true
		player_spike_slow_timer = 3.5
		player.set("velocity", player.get("velocity") * 0.25)
		status_label.text = "POLICE HIT SPIKES · TEMPORARY SLOWDOWN"
	if backup_timer > 0.0 and backup.visible and not spike_hit_backup and planar_distance_to_point(backup, spike_strip.global_position) < 3.0:
		spike_hit_backup = true
		backup_timer = 0.0
		backup.visible = false
		backup.process_mode = Node.PROCESS_MODE_DISABLED
		backup_button.text = "BACKUP HIT SPIKES"
		status_label.text = "BACKUP HIT SPIKES · ASSIST ENDED"
	for actor in traffic:
		if spike_hit_traffic.has(actor) or planar_distance_to_point(actor, spike_strip.global_position) >= 3.0:
			continue
		spike_hit_traffic[actor] = true
		stun_traffic(actor, 2.3)
		status_label.text = "CIVILIAN HIT SPIKES · TRAFFIC REROUTING"
	if spike_timer <= 0.0:
		spike_active = false
		spike_strip.visible = false
		spike_button.disabled = spike_charges <= 0
		if not spike_hit_suspect:
			status_label.text = "SPIKE STRIP MISSED"


func planar_distance_to_point(actor: Node3D, point: Vector3) -> float:
	var offset := actor.global_position - point
	offset.y = 0.0
	return offset.length()


func configure_backup_availability() -> void:
	if get_passing_lane_direction(player_agent) == 0:
		backup_available = false
		backup_button.disabled = true
		backup_button.text = "BACKUP UNAVAILABLE · ONE LANE"


func attempt_backup_overtake() -> void:
	var direction := get_passing_lane_direction(backup_agent)
	if direction == 0:
		return
	backup_agent.change_lane(direction)
	status_label.text = "BACKUP MOVING TO PASSING LANE"


func get_passing_lane_direction(agent: RoadLaneAgent) -> int:
	if not is_instance_valid(agent.current_lane):
		return 0
	var current_prefix := lane_direction_prefix(agent.current_lane)
	for direction in [1, -1]:
		var path: NodePath = agent.current_lane.lane_right if direction > 0 else agent.current_lane.lane_left
		var candidate := agent.current_lane.get_node_or_null(path) as RoadLane
		if is_instance_valid(candidate) and lane_direction_prefix(candidate) == current_prefix:
			return direction
	return 0


func lane_direction_prefix(lane: RoadLane) -> String:
	var tag := lane.lane_next_tag if not lane.lane_next_tag.is_empty() else lane.lane_prior_tag
	return tag.left(1)


func configure_diorama_world(district: Node3D) -> void:
	var sky_3d := district.get_node_or_null("Sky3D")
	if sky_3d:
		var sky_time: float = float({"day": 13.25, "dusk": 17.75, "night": 21.5, "dawn": 6.5}.get(time_of_day, 13.25))
		sky_3d.set("current_time", sky_time)
		sky_3d.set("camera_exposure", 1.6 if time_of_day == "night" else (1.25 if time_of_day == "dusk" else 0.9))
		sky_3d.set("tonemap_exposure", 1.3 if time_of_day == "night" else (1.12 if time_of_day == "dusk" else 0.95))
		sky_3d.set("skydome_energy", 0.72 if time_of_day == "night" else (0.9 if time_of_day == "dusk" else 0.9))
		sky_3d.set("sun_energy", 0.12 if time_of_day == "night" else (0.62 if time_of_day == "dusk" else 0.95))
		sky_3d.set("moon_energy", 1.15 if time_of_day == "night" else 0.55)
		sky_3d.set("ambient_energy", 0.82 if time_of_day == "night" else (0.72 if time_of_day == "dusk" else 0.55))
		sky_3d.set("night_ambient_boost", true)
		sky_3d.set("night_sky_contribution", 0.32)
	var night_fill := district.get_node_or_null("NightVehicleFill") as DirectionalLight3D
	if not night_fill:
		night_fill = DirectionalLight3D.new()
		night_fill.name = "NightVehicleFill"
		night_fill.rotation_degrees = Vector3(-52.0, 32.0, 0.0)
		night_fill.light_color = Color("#86aee0")
		night_fill.shadow_enabled = false
		district.add_child(night_fill)
	night_fill.visible = time_of_day in ["dusk", "night"]
	night_fill.light_energy = 0.62 if time_of_day == "night" else 0.28
	var world_environment := district.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment and world_environment.environment:
		var env := world_environment.environment
		env.background_mode = Environment.BG_COLOR
		var preset := time_preset()
		env.background_color = preset.sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = preset.ambient
		env.ambient_light_energy = preset.ambient_energy
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.glow_enabled = true
		env.glow_intensity = 0.78
		env.glow_bloom = 0.14
	var sun := district.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun:
		sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
		var preset := time_preset()
		sun.light_color = preset.sun_color
		sun.light_energy = preset.sun_energy
		sun.shadow_enabled = true
	var ground := district.get_node_or_null("ground") as MeshInstance3D
	if ground:
		var ground_material := StandardMaterial3D.new()
		ground_material.albedo_color = Color("#29423f")
		ground_material.roughness = 0.9
		ground.material_override = ground_material


func case_time_of_day() -> String:
	var schedule := ["day", "dusk", "night", "dawn"]
	return schedule[(maxi(1, GameState.current_case) - 1) % schedule.size()]


func time_preset() -> Dictionary:
	match time_of_day:
		"day":
			return {"sky": Color("#668fa8"), "ambient": Color("#b7cad6"), "ambient_energy": 0.7, "sun_color": Color("#ffe4bd"), "sun_energy": 1.05}
		"night":
			return {"sky": Color("#071329"), "ambient": Color("#36537c"), "ambient_energy": 0.48, "sun_color": Color("#789bd0"), "sun_energy": 0.34}
		"dawn":
			return {"sky": Color("#805b76"), "ambient": Color("#8c88a8"), "ambient_energy": 0.7, "sun_color": Color("#ffd2ad"), "sun_energy": 0.9}
		_:
			return {"sky": Color("#142746"), "ambient": Color("#8297bd"), "ambient_energy": 0.86, "sun_color": Color("#ffd8ae"), "sun_energy": 1.28}


func restyle_road_network(district: Node3D) -> void:
	for node in district.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if not mesh_instance or not mesh_instance.mesh or mesh_instance.mesh.get_surface_count() == 0:
			continue
		var active_material := mesh_instance.get_active_material(0)
		if not active_material or (not active_material.resource_path.ends_with("road_texture.material") and not mesh_instance.has_meta("diorama_road_surface")):
			continue
		mesh_instance.set_meta("diorama_road_surface", true)
		var road_material := active_material.duplicate() as StandardMaterial3D
		if road_material:
			# Preserve the authored white/yellow marking texture at night. Scene
			# lighting supplies darkness; a dark material multiplier erased lines.
			road_material.albedo_color = Color("#4a5663") if time_of_day == "day" else (Color("#707b86") if time_of_day == "dusk" else Color("#929aa3"))
			road_material.roughness = 0.86
			road_material.metallic = 0.02
			mesh_instance.material_override = road_material


func build_safe_street_lamps(district: Node3D) -> void:
	if district.has_meta("grid_city"):
		build_grid_street_lamps(district)
		return
	var accepted_positions: Array[Vector3] = []
	var points := district.find_children("*", "RoadPoint", true, false)
	for point_node in points:
		if street_lamps.size() >= 34:
			break
		var point := point_node as RoadPoint
		if not point or not is_safe_lamp_point(point):
			continue
		var road_half_width: float = float(point.get_width_with_shoulders()) * 0.5 + point.gutter_profile.x + 2.3
		for side_value in [-1.0, 1.0]:
			var side: float = float(side_value)
			var position: Vector3 = point.global_position + point.global_transform.basis.x.normalized() * road_half_width * side
			var too_close := false
			for accepted in accepted_positions:
				if accepted.distance_to(position) < 22.0:
					too_close = true
					break
			if too_close:
				continue
			var lamp := create_street_lamp()
			district.add_child(lamp)
			lamp.global_position = position
			lamp.global_rotation.y = point.global_rotation.y
			street_lamps.append(lamp)
			accepted_positions.append(position)


func build_grid_street_lamps(district: Node3D) -> void:
	for z in [-60.0, 0.0, 60.0]:
		for x in [-60.0, 0.0, 60.0]:
			# Poles stay three metres inside the raised sidewalk; lamp arms face
			# outward over the street instead of across the block or intersection.
			var east_lamp := create_street_lamp()
			district.add_child(east_lamp)
			east_lamp.global_position = Vector3(x + 15.0, 0.26, z)
			east_lamp.global_rotation.y = 0.0
			street_lamps.append(east_lamp)
			var south_lamp := create_street_lamp()
			district.add_child(south_lamp)
			south_lamp.global_position = Vector3(x, 0.26, z + 15.0)
			south_lamp.global_rotation.y = PI * 0.5
			street_lamps.append(south_lamp)


func is_safe_lamp_point(point: RoadPoint) -> bool:
	var current: Node = point
	while current and current != $IntersectionDistrict:
		var lowered := current.name.to_lower()
		for blocked_name in ["roundabout", "intersection", "splitter", "ramp", "3way", "4way", "highway"]:
			if lowered.contains(blocked_name):
				return false
		current = current.get_parent()
	var prior := point.get_node_or_null(point.prior_pt_init)
	var next := point.get_node_or_null(point.next_pt_init)
	if prior is RoadIntersection or next is RoadIntersection:
		return false
	return is_instance_valid(prior) and is_instance_valid(next)


func create_street_lamp() -> Node3D:
	var lamp := Node3D.new()
	lamp.name = "StreetLamp"
	make_box_part(lamp, Vector3(0.24, 4.8, 0.24), Color("#17212b"), Vector3(0.0, 2.4, 0.0))
	make_box_part(lamp, Vector3(1.15, 0.18, 0.18), Color("#17212b"), Vector3(0.46, 4.72, 0.0))
	make_glow_box(lamp, Vector3(0.48, 0.2, 0.42), Color("#ffd38f"), Vector3(0.96, 4.55, 0.0))
	if time_of_day in ["night", "dusk"]:
		var light := OmniLight3D.new()
		light.name = "LampLight"
		light.position = Vector3(0.96, 4.35, 0.0)
		light.light_color = Color("#ffd39c")
		light.light_energy = 2.8 if time_of_day == "night" else 1.35
		light.omni_range = 13.0
		light.shadow_enabled = false
		lamp.add_child(light)
	return lamp


func build_route_markers() -> void:
	for index in 3:
		var marker := Label3D.new()
		marker.name = "RouteMarker%d" % index
		marker.text = "▲"
		marker.font_size = 72
		marker.modulate = POLICE_BLUE if index == 0 else (HAZARD_AMBER if index == 1 else Color("#f4f8fb"))
		marker.outline_modulate = Color(0.02, 0.05, 0.09, 0.85)
		marker.outline_size = 8
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = false
		add_child(marker)
		route_markers.append(marker)


func update_route_markers() -> void:
	if not is_instance_valid(player_agent.current_lane):
		for marker in route_markers:
			marker.visible = false
		return
	var forward := -player.global_transform.basis.z.normalized()
	var turn_center := Vector3.ZERO
	var turn_distance := INF
	if buffered_turn_direction != 0:
		for center in traffic_signal_centers:
			var to_center := center - player.global_position
			to_center.y = 0.0
			var distance := to_center.length()
			if distance < turn_distance and distance < 58.0 and forward.dot(to_center.normalized()) > 0.82:
				turn_center = center
				turn_distance = distance
	var turn_side := forward.cross(Vector3.UP).normalized() * float(buffered_turn_direction)
	var turn_start_distance := maxf(0.0, turn_distance - 10.0)
	var arc_length := PI * 5.0
	for index in route_markers.size():
		var marker := route_markers[index]
		var distance_ahead := 10.0 + index * 7.0
		var active_maneuver := is_instance_valid(player.get("pending_lane"))
		var placement: Vector3 = player.call("sample_maneuver_ahead", distance_ahead) if active_maneuver else player_agent.test_move_along_lane(distance_ahead)
		if not active_maneuver and turn_distance < INF and distance_ahead > turn_start_distance:
			var arc_distance := distance_ahead - turn_start_distance
			if arc_distance <= arc_length:
				var angle := arc_distance / 10.0
				placement = turn_center - forward * cos(angle) * 10.0 + turn_side * sin(angle) * 10.0
			else:
				placement = turn_center + turn_side * (10.0 + arc_distance - arc_length)
		marker.global_position = placement + Vector3.UP * 0.16
		marker.visible = not map_active


func build_cockpit() -> void:
	cockpit_node = Node3D.new()
	cockpit_node.name = "ToyCockpit"
	cockpit_node.visible = false
	chase_camera.add_child(cockpit_node)
	make_box_part(cockpit_node, Vector3(5.8, 0.72, 1.8), Color("#111824"), Vector3(0.0, -1.28, -2.05))
	make_box_part(cockpit_node, Vector3(2.25, 0.38, 0.78), Color("#172438"), Vector3(0.0, -0.93, -2.0))
	make_glow_box(cockpit_node, Vector3(1.45, 0.06, 0.08), POLICE_BLUE, Vector3(0.0, -0.83, -1.58))
	make_box_part(cockpit_node, Vector3(0.9, 0.42, 0.18), Color("#243348"), Vector3(-2.0, -1.0, -1.42))
	make_box_part(cockpit_node, Vector3(0.9, 0.42, 0.18), Color("#243348"), Vector3(2.0, -1.0, -1.42))
	make_glow_box(cockpit_node, Vector3(1.15, 0.07, 0.12), SIREN_RED, Vector3(-0.62, -0.62, -2.82))
	make_glow_box(cockpit_node, Vector3(1.15, 0.07, 0.12), POLICE_BLUE, Vector3(0.62, -0.62, -2.82))


func update_vehicle_lights() -> void:
	var player_speed := float(player.call("get_signed_speed"))
	var player_reversing := player_speed < -0.5
	var player_braking := (Input.is_action_pressed("ui_down") and not player_reversing) or bool(player.get("intersection_turn_active")) or (player_speed > 0.5 and player_speed < previous_player_speed - 0.02)
	VehicleBuilder.update_lights(player, player_reversing, player_braking, time_of_day in ["dusk", "night"])
	PolygonVehicleBuilder.update_lights(player, player_reversing, player_braking, time_of_day in ["dusk", "night"])
	previous_player_speed = player_speed
	VehicleBuilder.update_lights(suspect, false, suspect_slow_timer > 0.0, time_of_day in ["dusk", "night"])
	PolygonVehicleBuilder.update_lights(suspect, false, suspect_slow_timer > 0.0, time_of_day in ["dusk", "night"])
	if backup.visible:
		var backup_speed := float(backup.call("get_signed_speed"))
		VehicleBuilder.update_lights(backup, backup_speed < -0.5, backup_speed < 3.0, time_of_day in ["dusk", "night"])
		PolygonVehicleBuilder.update_lights(backup, backup_speed < -0.5, backup_speed < 3.0, time_of_day in ["dusk", "night"])
	for actor in traffic:
		if not actor.visible:
			continue
		var traffic_speed := float(actor.call("get_signed_speed"))
		var traffic_braking := float(actor.get_meta("collision_stun", 0.0)) > 0.0 or traffic_speed < 3.0
		VehicleBuilder.update_lights(actor, traffic_speed < -0.5, traffic_braking, time_of_day in ["dusk", "night"])
		PolygonVehicleBuilder.update_lights(actor, traffic_speed < -0.5, traffic_braking, time_of_day in ["dusk", "night"])


func make_box_part(parent: Node3D, size: Vector3, color: Color, position: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.68
	mesh.material = material
	part.mesh = mesh
	part.position = position
	parent.add_child(part)
	return part


func make_glow_box(parent: Node3D, size: Vector3, color: Color, position: Vector3) -> MeshInstance3D:
	var part := make_box_part(parent, size, color, position)
	var material := part.mesh.material as StandardMaterial3D
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.7
	return part


func build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 22.0
	top.offset_top = 14.0
	top.offset_right = -22.0
	root.add_child(top)
	status_label = make_label("PREPARING PURSUIT", 17, Color("#27dcff"))
	top.add_child(status_label)
	var info := HBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(info)
	timer_label = make_label("TIME 60", 28, Color.WHITE)
	timer_label.custom_minimum_size.x = 250.0
	info.add_child(timer_label)
	distance_label = make_label("32m TO SUSPECT", 25, Color.WHITE)
	distance_label.custom_minimum_size.x = 330.0
	info.add_child(distance_label)
	damage_bar = make_bar(Color("#ff4d58"))
	damage_bar.custom_minimum_size.y = 13.0
	top.add_child(damage_bar)
	nos_bar = make_bar(Color("#27bfff"))
	nos_bar.custom_minimum_size.y = 13.0
	top.add_child(nos_bar)
	apprehend_bar = make_bar(APPREHEND_GREEN)
	apprehend_bar.custom_minimum_size.y = 18.0
	top.add_child(apprehend_bar)
	skill_label = make_label("SUSPECT DAMAGE 0% · SKILL ×1.0", 16, Color("#ffca55"))
	top.add_child(skill_label)
	var station := make_button("STATION", return_to_station, Vector2(145.0, 58.0))
	station.position = Vector2(18.0, 235.0)
	root.add_child(station)
	var view := make_button("VIEW", toggle_camera, Vector2(145.0, 58.0))
	view.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	view.position = Vector2(-163.0, 235.0)
	root.add_child(view)
	map_button = make_button("MAP", toggle_map, Vector2(145.0, 58.0))
	map_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	map_button.position = Vector2(-163.0, 305.0)
	root.add_child(map_button)
	var recover_button := make_button("RECOVER", recover_player, Vector2(145.0, 58.0))
	recover_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	recover_button.position = Vector2(-163.0, 375.0)
	root.add_child(recover_button)
	debug_zones_button = make_button("ZONES", toggle_clearance_debug, Vector2(145.0, 58.0))
	debug_zones_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	debug_zones_button.position = Vector2(-163.0, 445.0)
	root.add_child(debug_zones_button)
	time_button = make_button("TIME: DAY", cycle_time_of_day, Vector2(175.0, 62.0))
	time_button.position = Vector2(18.0, 378.0)
	time_button.visible = exploration_mode
	root.add_child(time_button)
	backup_button = make_button("CALL BACKUP", activate_backup, Vector2(175.0, 62.0))
	style_button(backup_button, POLICE_BLUE)
	backup_button.position = Vector2(18.0, 305.0)
	root.add_child(backup_button)
	spike_button = make_button("SPIKES ×2", deploy_spikes, Vector2(175.0, 62.0))
	style_button(spike_button, TACTICAL_VIOLET)
	spike_button.position = Vector2(18.0, 378.0)
	root.add_child(spike_button)
	var joystick_script := load("res://scripts/interface/virtual_joystick.gd")
	var joystick := Control.new()
	joystick.set_script(joystick_script)
	joystick.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	joystick.position = Vector2(-135.0, -292.0)
	joystick.size = Vector2(270.0, 270.0)
	joystick.connect("vector_changed", _on_joystick_changed)
	root.add_child(joystick)
	var joystick_help := make_label("FORWARD: DRIVE   ·   BACK: BRAKE   ·   LEFT / RIGHT: ROUTE", 12, Color("#d9edf5"))
	joystick_help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	joystick_help.offset_bottom = -8.0
	joystick_help.offset_top = -30.0
	root.add_child(joystick_help)
	nos_button = make_button("NOS\n100%", toggle_nos, Vector2(122.0, 96.0))
	style_button(nos_button, HAZARD_AMBER)
	nos_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	nos_button.position = Vector2(152.0, -188.0)
	root.add_child(nos_button)
	result_panel = PanelContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.position = Vector2(-260.0, -180.0)
	result_panel.size = Vector2(520.0, 360.0)
	result_panel.visible = false
	style_panel(result_panel, APPREHEND_GREEN)
	root.add_child(result_panel)
	var result_box := VBoxContainer.new()
	result_box.alignment = BoxContainer.ALIGNMENT_CENTER
	result_panel.add_child(result_box)
	result_title = make_label("", 34, Color.WHITE)
	result_box.add_child(result_title)
	result_box.add_child(make_button("RESTART PURSUIT", func(): get_tree().reload_current_scene()))
	result_box.add_child(make_button("RETURN TO STATION", return_to_station))


func make_label(caption: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func make_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", make_hud_style(Color(0.035, 0.05, 0.09, 0.88), Color(color, 0.32), 8, 1))
	bar.add_theme_stylebox_override("fill", make_hud_style(Color(color, 0.94), color.lightened(0.15), 8, 1))
	return bar


func make_button(caption: String, callback: Callable, minimum := Vector2(190.0, 90.0)) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = minimum
	button.add_theme_font_size_override("font_size", 15)
	style_button(button, POLICE_BLUE)
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


func update_hud(distance: float) -> void:
	timer_label.text = "TIME %02d" % int(ceil(chase_time))
	distance_label.text = "%dm TO SUSPECT" % int(round(distance))
	damage_bar.value = damage
	nos_bar.value = nos
	apprehend_bar.value = suspect_damage
	skill_label.text = "SUSPECT DAMAGE %d%% · SKILL ×%.1f" % [int(suspect_damage), skill]
	if backup_timer > 0.0:
		backup_button.text = "BACKUP %.0f SEC" % ceil(backup_timer)
	if is_instance_valid(nos_button):
		var nos_state := "BOOST" if boosting else ("ARMED" if nos_armed else "NOS")
		nos_button.text = "%s\n%d%%" % [nos_state, int(nos)]
		nos_button.disabled = nos <= 0.0


func _on_joystick_changed(input_vector: Vector2) -> void:
	if not running:
		return
	var throttle := -input_vector.y
	joystick_throttle = maxf(0.0, throttle)
	if throttle > 0.14:
		Input.action_press("ui_up", clampf(throttle, 0.0, 1.0))
	else:
		Input.action_release("ui_up")
	if input_vector.y > 0.18:
		Input.action_press("ui_down", clampf(input_vector.y, 0.0, 1.0))
	else:
		Input.action_release("ui_down")
	# Buffer an intersection turn only when the stick is deliberately more than
	# 45 degrees left/right of forward. Small failure to recenter stays neutral.
	var turn_angle_degrees := rad_to_deg(atan2(absf(input_vector.x), maxf(throttle, 0.001)))
	var diagonal_turn := throttle > 0.14 and turn_angle_degrees > 45.0
	var requested_turn_sign := 1 if input_vector.x > 0.0 else -1
	if not diagonal_turn and (turn_angle_degrees < 35.0 or throttle <= 0.14):
		if not is_instance_valid(player.get("pending_lane")):
			buffered_turn_direction = 0
		buffered_turn_armed = true
		buffered_turn_input_sign = 0
	elif diagonal_turn and (buffered_turn_armed or requested_turn_sign != buffered_turn_input_sign):
		buffered_turn_direction = requested_turn_sign
		buffered_turn_armed = false
		buffered_turn_input_sign = requested_turn_sign
	if absf(input_vector.x) < 0.18:
		joystick_lane_armed = true
	elif not diagonal_turn and absf(input_vector.x) > 0.34 and joystick_lane_armed:
		var lane_direction := 1 if input_vector.x > 0.0 else -1
		var changed_lane := int(player.call("request_lane_change", lane_direction)) == OK
		joystick_lane_armed = false
		if changed_lane and not is_instance_valid(player.get("pending_lane")):
			status_label.text = "RIGHT LANE SELECTED" if input_vector.x > 0.0 else "LEFT LANE SELECTED"
		elif not changed_lane:
			status_label.text = "LANE BLOCKED · HOLD COURSE"


func toggle_nos() -> void:
	if not running or nos <= 0.0:
		return
	nos_armed = not nos_armed
	if nos_armed:
		status_label.text = "NOS ARMED · DRIVE FORWARD TO ENGAGE"
	else:
		boosting = false
		status_label.text = "NOS CANCELLED · CHARGE SAVED"


func toggle_clearance_debug() -> void:
	if not road_decorator:
		return
	var visible: bool = bool(road_decorator.toggle_debug())
	debug_zones_button.text = "HIDE ZONES" if visible else "ZONES"
	status_label.text = "CLEARANCE ZONES · RED EXCLUSION · AMBER ROAD · GREEN SAFE" if visible else "CLEARANCE ZONES HIDDEN"


func cycle_time_of_day() -> void:
	var cycle := ["day", "dusk", "night"]
	var current_index := cycle.find(time_of_day)
	time_of_day = cycle[(current_index + 1) % cycle.size()]
	apply_time_of_day(true)


func apply_time_of_day(show_status: bool) -> void:
	configure_diorama_world($IntersectionDistrict)
	restyle_road_network($IntersectionDistrict)
	var lights_on := time_of_day in ["dusk", "night"]
	for light_node in $IntersectionDistrict.find_children("SidewalkStreetLight", "SpotLight3D", true, false):
		var street_light := light_node as SpotLight3D
		street_light.visible = lights_on
		street_light.light_energy = 4.2 if time_of_day == "night" else 2.0
	for lens_node in $IntersectionDistrict.find_children("StreetLampLens", "MeshInstance3D", true, false):
		var street_lamp_lens := lens_node as MeshInstance3D
		var lamp_material := street_lamp_lens.material_override as StandardMaterial3D
		if lamp_material:
			lamp_material.emission_energy_multiplier = 2.2 if lights_on else 0.0
	var headlights_on := time_of_day in ["dusk", "night"]
	VehicleBuilder.update_lights(player, false, false, headlights_on)
	PolygonVehicleBuilder.update_police_lights(player, headlights_on)
	for actor in traffic:
		if is_instance_valid(actor):
			VehicleBuilder.update_lights(actor, false, false, headlights_on)
	time_button.text = "TIME: %s" % time_of_day.to_upper()
	if show_status:
		status_label.text = "%s LIGHTING · STREET LAMPS %s" % [time_of_day.to_upper(), "ON" if lights_on else "OFF"]


func paint_actor(actor: Node3D, color: Color, police: bool, profile: String = "patrol", upgrades: Dictionary = {}) -> void:
	if police:
		PolygonVehicleBuilder.build_police(actor)
		return
	PolygonVehicleBuilder.build_civilian(actor)


func police_profile() -> String:
	match GameState.vehicle_id:
		"interceptor":
			return "interceptor"
		"suv":
			return "van"
		_:
			return "patrol"


func suspect_profile() -> String:
	var profiles := ["interceptor", "muscle", "van"]
	return profiles[(maxi(1, GameState.current_case) - 1) % profiles.size()]


func toggle_camera() -> void:
	if map_active:
		return
	camera_mode = 1 - camera_mode
	apply_camera_mode()
	status_label.text = "POV CAMERA · WORLD FOLLOWS HEADING" if camera_mode == 1 else "CHASE CAMERA"


func apply_camera_mode() -> void:
	chase_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	if camera_mode == 1:
		chase_camera.top_level = false
		chase_camera_initialized = false
		cockpit_node.visible = true
		chase_camera.position = Vector3(0.0, 1.8, -0.4)
		chase_camera.rotation_degrees = Vector3(-3.0, 0.0, 0.0)
		chase_camera.fov = 70.0
	else:
		chase_camera.top_level = true
		chase_camera_initialized = false
		cockpit_node.visible = false
		chase_camera.global_position = player.global_position + player.global_transform.basis * Vector3(0.0, 6.5, 13.0)
		chase_camera.global_rotation = Vector3(deg_to_rad(-12.0), player.global_rotation.y, 0.0)
		chase_camera.fov = 62.0


func toggle_map() -> void:
	map_active = not map_active
	map_button.text = "CLOSE MAP" if map_active else "MAP"
	if not map_active:
		apply_camera_mode()
		status_label.text = "RETURNING TO PURSUIT"
	else:
		cockpit_node.visible = false
		status_label.text = "TACTICAL PURSUIT · LIVE POSITIONS"


func update_map_camera() -> void:
	chase_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	chase_camera.size = 85.0
	chase_camera.global_position = player.global_position + Vector3.UP * 72.0
	chase_camera.global_rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)


func finish(won: bool, title: String) -> void:
	if not running:
		return
	running = false
	boosting = false
	if suspect_damage >= 100.0:
		for i in 4:
			spawn_smoke_puff(suspect, 1.0)
	Input.action_release("ui_up")
	Input.action_release("ui_down")
	stop_actor(player)
	stop_actor(suspect)
	if is_instance_valid(backup) and backup.visible:
		stop_actor(backup)
	result_title.text = title
	result_title.add_theme_color_override("font_color", Color("#2fe0a0") if won else Color("#ff4d58"))
	result_panel.visible = true


func stop_actor(actor: Node3D) -> void:
	if not is_instance_valid(actor):
		return
	actor.set("drive_state", 0)
	actor.set("target_speed", 0)
	actor.set("velocity", Vector3.ZERO)


func return_to_station() -> void:
	Input.action_release("ui_up")
	Input.action_release("ui_down")
	get_tree().change_scene_to_file("res://scenes/interface/main_menu.tscn")
