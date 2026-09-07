extends Node3D

const ASSET_ROOT := "res://Assets/Synty/PolygonCity/Prefabs/"

@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var camera_rig: Node3D = $CameraRig
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var time_button: Button = $UI/TimeButton
@onready var brake_button: Button = $UI/BrakeButton
@onready var reverse_button: Button = $UI/ReverseButton

var camera_yaw := 0.0
var camera_pitch := -0.48
var camera_distance := 38.0
var time_index := 0
var time_names := ["DAY", "DUSK", "NIGHT"]
var brake_test_active := false
var reverse_test_active := false
var test_car: Node3D
var tail_emission_material: ShaderMaterial
var building_window_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	_build_test_block()
	time_button.pressed.connect(_cycle_time)
	brake_button.pressed.connect(_toggle_brake_test)
	reverse_button.pressed.connect(_toggle_reverse_test)
	_apply_time_of_day()
	_update_camera()


func _process(delta: float) -> void:
	var orbit := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	camera_yaw -= orbit.x * delta * 1.25
	camera_pitch = clamp(camera_pitch - orbit.y * delta * 0.8, -1.05, -0.18)
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(14.0, camera_distance - 2.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(55.0, camera_distance + 2.0)


func _update_camera() -> void:
	camera_rig.rotation = Vector3(0.0, camera_yaw, 0.0)
	camera.position = Vector3(0.0, sin(-camera_pitch) * camera_distance, cos(camera_pitch) * camera_distance)
	camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)


func _build_test_block() -> void:
	# One intentional two-way block: 10 m roads, a clear 10 x 10 m crossroads,
	# and sidewalks occupying the immediately adjacent 5 m grid cells.
	var occupied := {}
	for step in range(-5, 5):
		for width in range(-1, 1):
			occupied[Vector2i(width, step)] = true
			occupied[Vector2i(step, width)] = true
	for cell: Vector2i in occupied:
		_add_grid_asset("Environments/SM_Env_Road_Bare_01.tscn", cell, 0)

	# Markings are independent of the asphalt modules. Keeping them out of the
	# intersection removes the false transverse "extra lane" seams.
	_add_road_marking(Vector3(0, 0.035, -15), Vector3(0.12, 0.018, 20))
	_add_road_marking(Vector3(0, 0.035, 15), Vector3(0.12, 0.018, 20))
	_add_road_marking(Vector3(-15, 0.035, 0), Vector3(20, 0.018, 0.12))
	_add_road_marking(Vector3(15, 0.035, 0), Vector3(20, 0.018, 0.12))

	for step in range(-5, 5):
		if step < -1 or step > 0:
			_add_sidewalk_segment(Vector2i(-2, step), "left")
			_add_sidewalk_segment(Vector2i(1, step), "right")
			_add_sidewalk_segment(Vector2i(step, -2), "top")
			_add_sidewalk_segment(Vector2i(step, 1), "bottom")
			_add_asphalt_curb_strip(step, "left")
			_add_asphalt_curb_strip(step, "right")
			_add_asphalt_curb_strip(step, "top")
			_add_asphalt_curb_strip(step, "bottom")

	# Intersection corners use the same exact 5 x 5 footprint as the straight
	# pavement. This prevents the kit's landscaped curb strip from overlapping it.
	_add_curved_sidewalk_corner(Vector2(-7.5, -7.5), 0.0)
	_add_curved_sidewalk_corner(Vector2(7.5, -7.5), PI * 0.5)
	_add_curved_sidewalk_corner(Vector2(7.5, 7.5), PI)
	_add_curved_sidewalk_corner(Vector2(-7.5, 7.5), PI * 1.5)

	# A shop frontage with two apartment modules above it demonstrates the kit's
	# intended stacked-building workflow and restores believable car/building scale.
	var building_parts: Array[Node3D] = []
	building_parts.append(_add_grid_asset("Buildings/SM_Bld_Shop_01.tscn", Vector2i(2, 2), 2, 0.08))
	building_parts.append(_add_grid_asset("Buildings/SM_Bld_Apartment_01.tscn", Vector2i(2, 2), 2, 3.1))
	building_parts.append(_add_grid_asset("Buildings/SM_Bld_Apartment_01.tscn", Vector2i(2, 2), 2, 6.1))
	building_parts.append(_add_grid_asset("Buildings/SM_Bld_Shop_01.tscn", Vector2i(3, 2), 2, 0.08))
	building_parts.append(_add_grid_asset("Buildings/SM_Bld_Apartment_01.tscn", Vector2i(3, 2), 2, 3.1))
	building_parts.append(_add_grid_asset("Buildings/SM_Bld_Apartment_01.tscn", Vector2i(3, 2), 2, 6.1))
	for part in building_parts:
		part.position += Vector3(-1.0, 0, -2.0)
		_configure_existing_building_windows(part)

	test_car = _add_asset("Vehicles/SM_Veh_Car_Sedan_01.tscn", Vector3(1.8, 0.18, 10.0), Vector3(0, PI, 0))
	_add_vehicle_lights(test_car)
	_add_asset("Characters/Character_BusinessMan_Shirt.tscn", Vector3(-7.2, 0.18, 7.4), Vector3(0, PI * 0.7, 0))
	_add_traffic_signal(Vector3(6.2, 0.18, 6.2), 0.0)
	# Poles use the sidewalk's outer furnishing edge. This keeps the grass parcel
	# completely buildable while leaving the walking path and curb unobstructed.
	_add_street_lamp(Vector3(-7.28, 0.22, -13.0), PI * 0.5)
	_add_street_lamp(Vector3(7.28, 0.22, 13.0), -PI * 0.5)


func _add_grid_asset(relative_path: String, cell: Vector2i, quarter_turns: int, elevation := 0.02) -> Node3D:
	# Synty's 5 m modules occupy local X 0..5 and Z -5..0. These offsets keep
	# that footprint in the requested grid cell after rotating its corner pivot.
	var q := posmod(quarter_turns, 4)
	var offsets := [Vector2(0, 5), Vector2(5, 5), Vector2(5, 0), Vector2(0, 0)]
	var offset: Vector2 = offsets[q]
	return _add_asset(
		relative_path,
		Vector3(cell.x * 5.0 + offset.x, elevation, cell.y * 5.0 + offset.y),
		Vector3(0, q * PI * 0.5, 0)
	)


func _add_road_marking(at: Vector3, size: Vector3) -> void:
	var marking := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.92, 0.72, 0.08)
	material.roughness = 0.78
	mesh.material = material
	marking.mesh = mesh
	marking.position = at
	$ImportedAssets.add_child(marking)


func _add_sidewalk_segment(cell: Vector2i, side: String) -> void:
	var size := Vector3(5.0, 0.22, 5.0)
	var center := Vector3(cell.x * 5.0 + 2.5, 0.11, cell.y * 5.0 + 2.5)
	match side:
		"left":
			size.x = 2.5
			center.x = -6.25
		"right":
			size.x = 2.5
			center.x = 6.25
		"top":
			size.z = 2.5
			center.z = -6.25
		"bottom":
			size.z = 2.5
			center.z = 6.25
	_add_sidewalk_mesh(center, size)


func _add_curved_sidewalk_corner(center: Vector2, start_angle: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := 2.5
	var segments := 12
	for index in range(segments):
		var angle_a := start_angle + (PI * 0.5) * float(index) / segments
		var angle_b := start_angle + (PI * 0.5) * float(index + 1) / segments
		var point_a := center + Vector2(cos(angle_a), sin(angle_a)) * radius
		var point_b := center + Vector2(cos(angle_b), sin(angle_b)) * radius
		surface.set_normal(Vector3.UP)
		surface.set_uv(Vector2(0.5, 0.5))
		surface.add_vertex(Vector3(center.x, 0.22, center.y))
		surface.set_normal(Vector3.UP)
		surface.set_uv(Vector2(0.5 + cos(angle_a) * 0.5, 0.5 + sin(angle_a) * 0.5))
		surface.add_vertex(Vector3(point_a.x, 0.22, point_a.y))
		surface.set_normal(Vector3.UP)
		surface.set_uv(Vector2(0.5 + cos(angle_b) * 0.5, 0.5 + sin(angle_b) * 0.5))
		surface.add_vertex(Vector3(point_b.x, 0.22, point_b.y))
	var corner := MeshInstance3D.new()
	corner.mesh = surface.commit()
	corner.material_override = _make_sidewalk_material()
	$ImportedAssets.add_child(corner)


func _add_asphalt_curb_strip(step: int, side: String) -> void:
	var size := Vector3(5.0, 0.10, 5.0)
	var center := Vector3.ZERO
	match side:
		"left":
			size.x = 0.20
			center = Vector3(-4.90, 0.05, step * 5.0 + 2.5)
		"right":
			size.x = 0.20
			center = Vector3(4.90, 0.05, step * 5.0 + 2.5)
		"top":
			size.z = 0.20
			center = Vector3(step * 5.0 + 2.5, 0.05, -4.90)
		"bottom":
			size.z = 0.20
			center = Vector3(step * 5.0 + 2.5, 0.05, 4.90)
	var strip := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.23, 0.23)
	material.roughness = 0.88
	mesh.material = material
	strip.mesh = mesh
	strip.position = center
	$ImportedAssets.add_child(strip)


func _add_sidewalk_mesh(center: Vector3, size: Vector3) -> void:
	var sidewalk := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := _make_sidewalk_material()
	material.uv1_scale = Vector3(maxf(size.x / 2.5, 1.0), maxf(size.z / 2.5, 1.0), 1.0)
	mesh.material = material
	sidewalk.mesh = mesh
	sidewalk.position = center
	$ImportedAssets.add_child(sidewalk)


func _make_sidewalk_material() -> StandardMaterial3D:
	var source := load("res://Assets/Synty/PolygonCity/Materials/Misc/Generic_Concrete_mat.tres") as StandardMaterial3D
	var material := source.duplicate() as StandardMaterial3D
	material.albedo_color = Color(0.82, 0.79, 0.72)
	material.roughness = 0.92
	return material


func _configure_existing_building_windows(building: Node3D) -> void:
	var body := building as MeshInstance3D
	if body == null:
		return
	var base := body.get_surface_override_material(0) as StandardMaterial3D
	if base == null or base.albedo_texture == null:
		return
	base = base.duplicate() as StandardMaterial3D
	body.set_surface_override_material(0, base)
	var window_emission := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform sampler2D source_texture : source_color;
uniform float glow_strength = 0.0;
void fragment() {
	vec3 source = texture(source_texture, UV).rgb;
	float blue_window_mask = smoothstep(0.025, 0.12, source.b - max(source.r, source.g));
	float dark_glass_mask = 1.0 - smoothstep(0.48, 0.72, max(source.r, max(source.g, source.b)));
	float mask = blue_window_mask * dark_glass_mask;
	if (mask < 0.08 || glow_strength <= 0.0) { discard; }
	ALBEDO = vec3(1.0, 0.55, 0.18);
	EMISSION = vec3(1.0, 0.32, 0.055) * mask * glow_strength;
}
"""
	window_emission.shader = shader
	window_emission.set_shader_parameter("source_texture", base.albedo_texture)
	base.next_pass = window_emission
	building_window_materials.append(window_emission)


func _add_street_lamp(at: Vector3, yaw: float) -> void:
	var lamp := _add_asset("Props/SM_Prop_LightPole_Base_01.tscn", at, Vector3(0, yaw, 0))
	if lamp == null:
		return
	var light := OmniLight3D.new()
	light.name = "NightLight"
	light.position = Vector3(0, 5.9, 1.9)
	light.light_color = Color(1.0, 0.72, 0.38)
	light.light_energy = 3.2
	light.omni_range = 12.0
	light.shadow_enabled = true
	light.add_to_group("synty_night_lights")
	lamp.add_child(light)


func _add_traffic_signal(at: Vector3, yaw: float) -> void:
	# The pack's TrafficLight prefab is the signal head, not a complete pole.
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.07
	pole_mesh.bottom_radius = 0.09
	pole_mesh.height = 3.8
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.08, 0.1, 0.11)
	pole_material.metallic = 0.65
	pole_material.roughness = 0.35
	pole_mesh.material = pole_material
	pole.mesh = pole_mesh
	pole.position = at + Vector3(0, 1.9, 0)
	$ImportedAssets.add_child(pole)
	_add_asset("Props/SM_Prop_TrafficLight_01.tscn", at + Vector3(0, 3.8, 0), Vector3(0, yaw, 0))


func _add_vehicle_lights(car: Node3D) -> void:
	if car == null:
		return
	for side in [-1.0, 1.0]:
		var headlight := SpotLight3D.new()
		headlight.name = "Headlight"
		headlight.position = Vector3(side * 0.64, 0.62, 2.46)
		headlight.rotation_degrees = Vector3(-5, 180, 0)
		headlight.light_color = Color(1.0, 0.92, 0.72)
		headlight.light_energy = 12.0
		headlight.spot_range = 22.0
		headlight.spot_angle = 38.0
		headlight.shadow_enabled = false
		headlight.add_to_group("synty_headlights")
		car.add_child(headlight)
	_configure_existing_tail_lights(car)


func _configure_existing_tail_lights(car: Node3D) -> void:
	var body := car as MeshInstance3D
	if body == null:
		return
	var base := body.get_surface_override_material(0) as StandardMaterial3D
	if base == null:
		return
	base = base.duplicate() as StandardMaterial3D
	body.set_surface_override_material(0, base)
	tail_emission_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform sampler2D source_texture : source_color;
uniform float tail_strength = 0.0;
uniform float reverse_strength = 0.0;
varying float rear_factor;
void vertex() {
	rear_factor = 1.0 - smoothstep(-2.20, -1.45, VERTEX.z);
}
void fragment() {
	vec3 source = texture(source_texture, UV).rgb;
	float red_mask = smoothstep(0.10, 0.32, source.r - max(source.g, source.b)) * rear_factor;
	float minimum_channel = min(source.r, min(source.g, source.b));
	float maximum_channel = max(source.r, max(source.g, source.b));
	float neutral_mask = smoothstep(0.48, 0.82, minimum_channel) * (1.0 - smoothstep(0.06, 0.20, maximum_channel - minimum_channel)) * rear_factor;
	float active_mask = max(red_mask * tail_strength, neutral_mask * reverse_strength);
	if (active_mask < 0.05) { discard; }
	vec3 light_color = vec3(1.0, 0.012, 0.006) * red_mask * tail_strength;
	light_color += vec3(0.82, 0.9, 1.0) * neutral_mask * reverse_strength;
	ALBEDO = light_color;
	EMISSION = light_color;
}
"""
	tail_emission_material.shader = shader
	tail_emission_material.set_shader_parameter("source_texture", base.albedo_texture)
	base.next_pass = tail_emission_material


func _toggle_brake_test() -> void:
	brake_test_active = not brake_test_active
	brake_button.text = "BRAKE TEST: " + ("ON" if brake_test_active else "OFF")
	_update_vehicle_lights()


func _toggle_reverse_test() -> void:
	reverse_test_active = not reverse_test_active
	reverse_button.text = "REVERSE TEST: " + ("ON" if reverse_test_active else "OFF")
	_update_vehicle_lights()


func _update_vehicle_lights() -> void:
	var night_lights_on := time_index != 0
	for node in get_tree().get_nodes_in_group("synty_headlights"):
		(node as SpotLight3D).visible = night_lights_on
	if tail_emission_material:
		var tail_strength := 0.0
		if night_lights_on:
			tail_strength = 0.55
		if brake_test_active:
			tail_strength = 4.5
		tail_emission_material.set_shader_parameter("tail_strength", tail_strength)
		tail_emission_material.set_shader_parameter("reverse_strength", 3.6 if reverse_test_active else 0.0)


func _add_asset(relative_path: String, at: Vector3, rotation := Vector3.ZERO) -> Node3D:
	var packed := load(ASSET_ROOT + relative_path) as PackedScene
	if packed == null:
		push_error("Synty compatibility test could not load: " + relative_path)
		return null
	var instance := packed.instantiate() as Node3D
	$ImportedAssets.add_child(instance)
	instance.position = at
	instance.rotation = rotation
	return instance


func _cycle_time() -> void:
	time_index = (time_index + 1) % time_names.size()
	_apply_time_of_day()


func _apply_time_of_day() -> void:
	var environment := world_environment.environment
	for node in get_tree().get_nodes_in_group("synty_night_lights"):
		var street_light := node as OmniLight3D
		street_light.visible = time_index != 0
		street_light.light_energy = 2.2 if time_index == 1 else 3.2
	for window_material in building_window_materials:
		window_material.set_shader_parameter("glow_strength", 2.4 if time_index != 0 else 0.0)
	_update_vehicle_lights()
	match time_index:
		0:
			sun.rotation_degrees = Vector3(-52, -35, 0)
			sun.light_color = Color(1.0, 0.9, 0.78)
			sun.light_energy = 1.35
			environment.ambient_light_color = Color(0.72, 0.78, 0.9)
			environment.ambient_light_energy = 0.55
			environment.background_energy_multiplier = 1.0
		1:
			sun.rotation_degrees = Vector3(-12, -70, 0)
			sun.light_color = Color(1.0, 0.48, 0.25)
			sun.light_energy = 0.75
			environment.ambient_light_color = Color(0.38, 0.42, 0.62)
			environment.ambient_light_energy = 0.42
			environment.background_energy_multiplier = 0.48
		2:
			sun.rotation_degrees = Vector3(-38, 35, 0)
			sun.light_color = Color(0.48, 0.62, 1.0)
			sun.light_energy = 0.32
			environment.ambient_light_color = Color(0.25, 0.34, 0.58)
			environment.ambient_light_energy = 0.38
			environment.background_energy_multiplier = 0.12
	time_button.text = "TIME: " + time_names[time_index]
