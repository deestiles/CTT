extends Node3D
class_name GeneratedCity
## Runtime orchestrator for a map-builder v2 generated city.
##
## This is the ADDITIVE counterpart to scripts/drive/drive_city.gd. Per owner
## decision (2026-09-17) drive_city.gd is left untouched; this orchestrator
## reuses the same reusable classes (ArcadeCar, DriveCameraRig, pedestrian,
## MixamoChar, CityNavigation) and re-implements the decoration + chase
## orchestration so it reads spawns / sidewalk routes / boundary / time-of-day
## from the map data instead of the Demo-specific hardcoded constants.
##
## The chase, damage, recoil, FX, smoke and thief-indicator logic below is ported
## from the approved drive_city.gd so gameplay feel matches. Decoration passes
## (lamps, signals, windows, knockables, sky, pedestrians) are added in
## generated_city_stage2 — see _decorate_city().

const Schema := preload("res://scripts/map_builder_v2/city_map_schema.gd")
const Loader := preload("res://scripts/drive/generated_city_loader.gd")
const Nav := preload("res://scripts/map_builder_v2/city_navigation.gd")
const ARCADE_CAR_SCRIPT := preload("res://scripts/drive/arcade_car.gd")
const CAMERA_SCRIPT := preload("res://scripts/drive/camera_rig.gd")
const PED_SCRIPT := preload("res://scripts/drive/pedestrian.gd")

const POLICE_CAR := "res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Police_01.tscn"
const THIEF_CAR := "res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Muscle_01.tscn"

const PED_CHARS: Array[String] = [
	"res://Assets/Animations/Character/SK_Character_Male_Jacket.fbx",
	"res://Assets/Animations/Character/SK_Character_Female_Coat.fbx",
	"res://Assets/Animations/Character/SK_Character_BusinessMan_Suit.fbx",
	"res://Assets/Animations/Character/SK_Character_Male_Hoodie.fbx",
	"res://Assets/Animations/Character/SK_Character_BusinessWoman.fbx",
	"res://Assets/Animations/Character/SK_Character_Female_Police.fbx",
]

const SIGNAL_SHADER := preload("res://Assets/Synty/PolygonCity/Materials/Misc/Signal_Color.gdshader")
const WINDOW_SHADER := preload("res://Assets/Synty/PolygonCity/Materials/Misc/Window_Night_Glow.gdshader")
const ATLAS_TEX := preload("res://Assets/Synty/PolygonCity/Textures/PolygonCity_01_A.png")
const TRAFFIC_GREEN := 6.0
const TRAFFIC_AMBER := 1.4

@export_file("*.json") var map_path: String = "res://maps_v2/starter_grid.json"
@export var pedestrian_count: int = 5
@export_range(0, 200) var max_knockable_props: int = 180

## Set by the builder's Test Map action before changing to the runtime scene, so
## a just-authored map plays without an autoload. Cleared once consumed.
static var override_map_path: String = ""

var _map: Dictionary = {}
var _built: Dictionary = {}
var _ground_y: float = 0.0

var _car: ArcadeCar
var _thief: ArcadeCar
var _cam: DriveCameraRig
var _pedestrians: Node3D
var _sky: Sky3D
var nav_region: NavigationRegion3D

# Lighting / signals / windows
var _lamp_lights: Array = []
var _window_lights: Array[ShaderMaterial] = []
var _signals: Array = []
var _last_state_a: int = -1
var _last_state_b: int = -1
var _traffic_time: float = 0.0
var _tod_index: int = 0
var _tod_presets: Array = [["DAY", 12.0, 1.0], ["DUSK", 18.6, 0.7], ["NIGHT", 22.5, 0.4]]
var _time_button: Button

# Chase / HUD
var _label: Label
var _distance_label: Label
var _damage_label: Label
var _damage_bar: ProgressBar
var _player_damage_label: Label
var _player_damage_bar: ProgressBar
var _win_overlay: Control
var _thief_indicator: Control
var _thief_arrow: Node2D
var _thief_indicator_label: Label
var _thief_damage: float = 0.0
var _player_damage: float = 0.0
var _capture_cooldown: float = 0.0
var _chase_won: bool = false
var _vehicle_smoke: Dictionary = {}
var _vehicle_contacting_world: Dictionary = {}


func _ready() -> void:
	randomize()
	if override_map_path != "":
		map_path = override_map_path
		override_map_path = ""
	_map = Schema.load_from(map_path)
	var hud := _build_hud()
	if _map.is_empty():
		if _label:
			_label.text = "MAP LOAD FAILED\n%s" % map_path
		push_error("[GeneratedCity] could not load map: %s" % map_path)
		return

	_built = Loader.build_city(_map)
	_ground_y = float(_built.get("ground_y", 0.0))
	var city: Node3D = _built["city"]
	city.name = "City"
	add_child(city)

	_decorate_city(city)

	_spawn_player()
	_spawn_thief()
	_build_camera()
	_setup_vehicle_smoke(_car, "PoliceDamageSmoke")
	_setup_vehicle_smoke(_thief, "ThiefDamageSmoke")

	# Time of day from the map.
	_tod_index = _tod_index_for(String(_built.get("time_of_day", "DAY")))
	_apply_time_preset()

	# Pedestrians raycast-verify their routes, which needs the freshly added city
	# colliders to be live in the physics world (next physics frame).
	_deferred_setup()

	if OS.has_environment("CTT_GEN_CAPTURE_TEST"):
		call_deferred("_run_capture_test")
	if OS.has_environment("CTT_GEN_REPORT"):
		call_deferred("_run_report")
	if OS.has_environment("CTT_GEN_RAM_TEST"):
		call_deferred("_run_ram_test")


# --- City build + decoration ---------------------------------------------

func _decorate_city(city: Node) -> void:
	_declutter_colliders(city)
	_setup_navigation(city)
	_setup_street_lamps(city)
	_setup_traffic_lights(city)
	_setup_window_lights(city)
	_setup_knockable_garbage(city)
	_setup_sky(city)


func _setup_navigation(city: Node) -> void:
	nav_region = Nav.bake_region(self, city)
	if OS.has_environment("CTT_NAV"):
		var polys := nav_region.navigation_mesh.get_polygon_count()
		print("[NAV] navmesh_polys=%d" % polys)


## Disable collision on street furniture so the car can hold a lane; keep
## buildings, ground, lamps/signals and trees solid. Mirrors drive_city.
func _declutter_colliders(node: Node) -> void:
	var n := String(node.name)
	if n.contains("LightPole"):
		return
	if n.contains("Prop") or n.contains("FireEscape") or n.contains("Billboard") or n.contains("Sign") or n.contains("Aircon") or n.contains("Planter"):
		# Knockable props are re-enabled as rigid bodies in stage 2; others stay off.
		if n.contains("Trash") or n.contains("Cardboard") or n.contains("Mailbox") or n.contains("Cone") or n.contains("Barrier") or n.contains("Skip"):
			return
		_disable_colliders(node)
		return
	for c in node.get_children():
		_declutter_colliders(c)


func _disable_colliders(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	for c in node.get_children():
		_disable_colliders(c)


## Sky3D atmospheric day/night. Time frozen; the TIME button sets it explicitly.
func _setup_sky(city: Node) -> void:
	for we in city.find_children("*", "WorldEnvironment", true, false):
		(we as WorldEnvironment).environment = null
	for dl in city.find_children("*", "DirectionalLight3D", true, false):
		(dl as Node3D).visible = false
	_sky = Sky3D.new()
	_sky.name = "Sky3D"
	add_child(_sky)
	_sky.game_time_enabled = false
	_sky.editor_time_enabled = false


## Downward SpotLight + glow at each street lamp luminaire; hidden by day.
func _setup_street_lamps(city: Node) -> void:
	for pole in city.find_children("*LightPole_Base*", "MeshInstance3D", true, false):
		var p := pole as MeshInstance3D
		if p.mesh == null:
			continue
		var ab: AABB = p.get_aabb()
		if ab.size == Vector3.ZERO or ab.size.y < 3.0:
			continue
		var luminaire := Vector3(
			ab.position.x + ab.size.x * 0.5,
			ab.position.y + ab.size.y - 0.35,
			ab.position.z + ab.size.z * 0.82)
		var sl := SpotLight3D.new()
		sl.light_color = Color("#ffce88")
		sl.light_energy = 16.0
		sl.spot_range = 30.0
		sl.spot_angle = 58.0
		sl.spot_attenuation = 0.8
		sl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		sl.visible = false
		p.add_child(sl)
		sl.position = luminaire
		_lamp_lights.append(sl)
		var glow := OmniLight3D.new()
		glow.light_color = Color("#ffd89a")
		glow.light_energy = 4.0
		glow.omni_range = 6.0
		glow.visible = false
		p.add_child(glow)
		glow.position = luminaire
		_lamp_lights.append(glow)


## Emit on baked signal lens colours; perpendicular heads run opposite phases.
func _setup_traffic_lights(city: Node) -> void:
	for is_arm in [false, true]:
		var pattern := "*LightPole_Arm*" if is_arm else "*LightPole_Lights*"
		for node in city.find_children(pattern, "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			var mat := _make_signal_material()
			if is_arm:
				var ab: AABB = mi.get_aabb()
				mat.set_shader_parameter("emit_zmask", 1.0)
				mat.set_shader_parameter("zmask_low", ab.position.z + ab.size.z * 0.28)
				mat.set_shader_parameter("zmask_high", ab.position.z + ab.size.z * 0.72)
			mi.set_surface_override_material(0, mat)
			_signals.append({"group": _signal_axis_group(mi), "mat": mat})
	_update_traffic_state(true)


func _signal_axis_group(mi: MeshInstance3D) -> bool:
	var facing := mi.global_transform.basis.z.normalized()
	return absf(facing.x) >= absf(facing.z)


func _make_signal_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SIGNAL_SHADER
	m.set_shader_parameter("source_texture", ATLAS_TEX)
	m.set_shader_parameter("signal_state", 2)
	m.set_shader_parameter("boost", 6.0)
	m.set_shader_parameter("emit_zmask", 0.0)
	return m


## Illuminate a deterministic 30% of standalone window meshes (real surface).
func _setup_window_lights(city: Node) -> void:
	var windows: Array[Node] = city.find_children("*Window*", "MeshInstance3D", true, false)
	var eligible: Array[MeshInstance3D] = []
	for node in windows:
		if String(node.name).contains("Prop_Window_"):
			eligible.append(node as MeshInstance3D)
	eligible.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		return String(a.get_path()) < String(b.get_path()))
	var target := int(round(eligible.size() * 0.30))
	for index in target:
		var mi := eligible[index]
		var mat := ShaderMaterial.new()
		mat.shader = WINDOW_SHADER
		mat.set_shader_parameter("source_texture", ATLAS_TEX)
		mat.set_shader_parameter("warm_light", Color("#ff9b45"))
		mat.set_shader_parameter("emission_energy", 0.0)
		mi.set_surface_override_material(0, mat)
		_window_lights.append(mat)


## Replace static collision on reactive props with a frozen rigid wrapper that
## wakes on first car contact. Mirrors drive_city categories/masses exactly.
func _setup_knockable_garbage(city: Node) -> void:
	var candidates: Array[Node] = []
	var seen := {}
	for pattern in ["*Trash*", "*Cardboard*", "*Mailbox*", "*Cone*", "*Barrier*", "*Skip*"]:
		for node in city.find_children(pattern, "MeshInstance3D", true, false):
			var id := node.get_instance_id()
			if not seen.has(id):
				seen[id] = true
				candidates.append(node)
	var converted := 0
	for node in candidates:
		if converted >= max_knockable_props:
			break
		var mesh := node as MeshInstance3D
		var static_body := _first_static_body(mesh)
		if static_body == null:
			continue
		var parent := mesh.get_parent()
		var old_transform := mesh.transform
		var body := RigidBody3D.new()
		body.name = "%s_Knockable" % mesh.name
		body.collision_layer = 1
		body.collision_mask = 1
		var prop_name := String(mesh.name)
		var category := "trash"
		body.mass = 2.2
		if prop_name.contains("Bag"):
			body.mass = 0.55
		elif prop_name.contains("Trashbin"):
			category = "bin"
			body.mass = 18.0
			body.linear_damp = 2.2
			body.angular_damp = 4.0
			body.axis_lock_angular_x = true
			body.axis_lock_angular_z = true
			body.add_to_group("heavy_sliding_prop")
		elif prop_name.contains("Skip"):
			category = "dumpster"
			body.mass = 45.0
			body.linear_damp = 3.0
			body.angular_damp = 5.0
			body.axis_lock_angular_x = true
			body.axis_lock_angular_z = true
			body.add_to_group("heavy_sliding_prop")
		elif prop_name.contains("Cardboard"):
			body.mass = 0.8
		elif prop_name.contains("Mailbox"):
			body.mass = 5.0
		elif prop_name.contains("Cone"):
			body.mass = 0.7
		elif prop_name.contains("Barrier"):
			body.mass = 3.0
		if category != "bin" and category != "dumpster":
			body.linear_damp = 0.7
			body.angular_damp = 0.55
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
		body.add_to_group("knockable_city_prop")
		parent.add_child(body)
		body.transform = old_transform
		mesh.reparent(body, false)
		mesh.transform = Transform3D.IDENTITY
		if category == "dumpster":
			var box_shape := BoxShape3D.new()
			var bounds := mesh.get_aabb()
			box_shape.size = Vector3(
				maxf(bounds.size.x * 0.94, 0.5),
				maxf(bounds.size.y * 0.94, 0.5),
				maxf(bounds.size.z * 0.94, 0.5))
			var solid_collision := CollisionShape3D.new()
			solid_collision.name = "DumpsterCollision"
			solid_collision.shape = box_shape
			solid_collision.position = bounds.get_center()
			body.add_child(solid_collision)
		else:
			for child in static_body.get_children():
				if child is CollisionShape3D:
					var copy := (child as CollisionShape3D).duplicate() as CollisionShape3D
					body.add_child(copy)
		static_body.queue_free()
		converted += 1


func _first_static_body(node: Node) -> StaticBody3D:
	if node is StaticBody3D:
		return node as StaticBody3D
	for child in node.get_children():
		var found := _first_static_body(child)
		if found:
			return found
	return null


# --- Vehicles + camera ----------------------------------------------------

func _spawn_player() -> void:
	var spawns: Dictionary = _built.get("spawns", {})
	var world := Vector3(0, _ground_y, 0)
	var turns := 0
	if spawns.has("police"):
		world = spawns["police"]["world"]
		turns = int(spawns["police"]["turns"])
	_car = _build_car("Player", POLICE_CAR, world, turns, false)


func _spawn_thief() -> void:
	var spawns: Dictionary = _built.get("spawns", {})
	var world := Vector3(10, _ground_y, 0)
	var turns := 0
	if spawns.has("thief"):
		world = spawns["thief"]["world"]
		turns = int(spawns["thief"]["turns"])
	_thief = _build_car("ThiefCar", THIEF_CAR, world, turns, true)
	_thief.set_evasion_target(_car)
	_thief.set_night_lights(_tod_index != 0)
	_thief.begin_autopilot()
	var marker := Label3D.new()
	marker.name = "ThiefMarker"
	marker.text = "THIEF"
	marker.font_size = 48
	marker.modulate = Color("#ff344d")
	marker.outline_size = 10
	marker.position = Vector3(0.0, 2.7, 0.0)
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_thief.add_child(marker)


func _build_car(node_name: String, prefab: String, world: Vector3, turns: int, is_thief: bool) -> ArcadeCar:
	var car := CharacterBody3D.new()
	car.name = node_name
	car.set_script(ARCADE_CAR_SCRIPT)
	car.set("visual_path", NodePath("Visual"))
	if is_thief:
		car.set("use_navigation", true)
		car.set("autopilot", true)
		car.set("obey_traffic_rules", false)
		car.set("evasion_enabled", true)
		car.set("evasion_retarget_seconds", 5.0)
		car.set("autopilot_speed", 14.0)
		car.set("max_speed", 19.0)
	else:
		car.set("use_navigation", false)
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.rotation.y = PI
	var scene: PackedScene = load(prefab)
	if scene:
		visual.add_child(scene.instantiate())
	car.add_child(visual)
	# Seat a metre above the road so the ArcadeCar raycast finds the surface.
	car.transform = Transform3D(Basis(Vector3.UP, _turns_to_yaw(turns)), world + Vector3.UP * 1.0)
	add_child(car)
	return car as ArcadeCar


func _turns_to_yaw(turns: int) -> float:
	return posmod(turns, 4) * (PI * 0.5)


func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.far = 3000.0
	cam.set_script(CAMERA_SCRIPT)
	cam.set("target_path", NodePath("../Player"))
	add_child(cam)
	cam.current = true
	_cam = cam as DriveCameraRig


# --- Pedestrians ----------------------------------------------------------

func _deferred_setup() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_spawn_pedestrians()


func _spawn_pedestrians() -> void:
	_pedestrians = Node3D.new()
	_pedestrians.name = "Pedestrians"
	add_child(_pedestrians)
	var routes: Array = _built.get("sidewalk_routes", [])
	if PED_CHARS.is_empty() or routes.is_empty():
		return
	var verified: Array = []
	for route in routes:
		var grounded := _raycast_verify_loop(route)
		if not grounded.is_empty():
			verified.append(grounded)
	var count: int = mini(pedestrian_count, verified.size())
	for i in count:
		var ped := Node3D.new()
		ped.set_script(PED_SCRIPT)
		_pedestrians.add_child(ped)
		var char_path: String = PED_CHARS[i % PED_CHARS.size()]
		ped.setup(char_path, verified[i], randf_range(1.1, 1.6), PackedInt32Array())


func _raycast_verify_loop(points: PackedVector3Array) -> PackedVector3Array:
	var grounded := PackedVector3Array()
	var first_y := INF
	var space := get_world_3d().direct_space_state
	for point in points:
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 8.0, point + Vector3.DOWN * 20.0)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return PackedVector3Array()
		var hit_y := float(hit.position.y)
		if first_y == INF:
			first_y = hit_y
		elif absf(hit_y - first_y) > 0.6:
			return PackedVector3Array()
		grounded.append(Vector3(point.x, hit_y, point.z))
	return grounded


# --- Time of day ----------------------------------------------------------

func _tod_index_for(name: String) -> int:
	for i in _tod_presets.size():
		if String(_tod_presets[i][0]) == name.to_upper():
			return i
	return 0


func _on_cycle_time() -> void:
	_tod_index = (_tod_index + 1) % _tod_presets.size()
	_apply_time_preset()


func _apply_time_preset() -> void:
	var preset: Array = _tod_presets[_tod_index]
	var dark: bool = _tod_index != 0
	if _sky:
		_sky.current_time = float(preset[1])
		_sky.tonemap_exposure = float(preset[2])
	for node in get_tree().get_nodes_in_group("arcade_vehicle"):
		var vehicle := node as ArcadeCar
		if vehicle:
			vehicle.set_night_lights(dark)
	for l in _lamp_lights:
		(l as Node3D).visible = dark
	for material in _window_lights:
		material.set_shader_parameter("emission_energy", 2.8 if dark else 0.0)
	if _time_button:
		_time_button.text = "Time: %s" % preset[0]


# --- HUD ------------------------------------------------------------------

func _build_hud() -> CanvasLayer:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	_label = Label.new()
	_label.name = "Info"
	_label.offset_left = 16.0
	_label.offset_top = 12.0
	_label.offset_right = 430.0
	_label.offset_bottom = 92.0
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_font_size_override("font_size", 18)
	_label.text = "GENERATED CITY"
	hud.add_child(_label)

	var cam_btn := Button.new()
	cam_btn.name = "CameraButton"
	cam_btn.text = "Camera (C)"
	cam_btn.offset_left = 16.0
	cam_btn.offset_top = 104.0
	cam_btn.offset_right = 168.0
	cam_btn.offset_bottom = 148.0
	hud.add_child(cam_btn)
	cam_btn.pressed.connect(_on_toggle_camera)

	var reset_btn := Button.new()
	reset_btn.name = "ResetButton"
	reset_btn.text = "Reset (R)"
	reset_btn.offset_left = 180.0
	reset_btn.offset_top = 104.0
	reset_btn.offset_right = 300.0
	reset_btn.offset_bottom = 148.0
	hud.add_child(reset_btn)
	reset_btn.pressed.connect(_on_reset)

	_time_button = Button.new()
	_time_button.name = "TimeButton"
	_time_button.text = "Time: DAY"
	_time_button.offset_left = 16.0
	_time_button.offset_top = 156.0
	_time_button.offset_right = 168.0
	_time_button.offset_bottom = 200.0
	hud.add_child(_time_button)
	_time_button.pressed.connect(_on_cycle_time)

	_setup_chase_hud(hud)

	var joy: Control = load("res://scripts/interface/virtual_joystick.gd").new()
	joy.name = "Joystick"
	joy.anchor_top = 1.0
	joy.anchor_bottom = 1.0
	joy.offset_left = 30.0
	joy.offset_top = -300.0
	joy.offset_right = 300.0
	joy.offset_bottom = -30.0
	hud.add_child(joy)
	joy.vector_changed.connect(_on_joystick)
	return hud


func _setup_chase_hud(hud: Node) -> void:
	var panel := PanelContainer.new()
	panel.name = "ChaseStatus"
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-170.0, 14.0)
	panel.size = Vector2(340.0, 133.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.015, 0.035, 0.07, 0.88)
	panel_style.border_color = Color("#268dca")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", panel_style)
	hud.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	_distance_label = Label.new()
	_distance_label.text = "-- m TO THIEF"
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_distance_label.add_theme_font_size_override("font_size", 22)
	_distance_label.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(_distance_label)
	_damage_bar = ProgressBar.new()
	_damage_bar.max_value = 100.0
	_damage_bar.show_percentage = false
	_damage_bar.custom_minimum_size = Vector2(310.0, 18.0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#ff344d")
	fill.set_corner_radius_all(8)
	_damage_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_damage_bar)
	_damage_label = Label.new()
	_damage_label.text = "THIEF DAMAGE 0%"
	_damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_damage_label.add_theme_font_size_override("font_size", 14)
	_damage_label.add_theme_color_override("font_color", Color("#ffb5bd"))
	box.add_child(_damage_label)
	_player_damage_bar = ProgressBar.new()
	_player_damage_bar.max_value = 100.0
	_player_damage_bar.show_percentage = false
	_player_damage_bar.custom_minimum_size = Vector2(310.0, 12.0)
	var police_fill := StyleBoxFlat.new()
	police_fill.bg_color = Color("#28a9ff")
	police_fill.set_corner_radius_all(6)
	_player_damage_bar.add_theme_stylebox_override("fill", police_fill)
	box.add_child(_player_damage_bar)
	_player_damage_label = Label.new()
	_player_damage_label.text = "POLICE DAMAGE 0%"
	_player_damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_damage_label.add_theme_font_size_override("font_size", 13)
	_player_damage_label.add_theme_color_override("font_color", Color("#a8ddff"))
	box.add_child(_player_damage_label)
	_setup_thief_indicator(hud)

	_win_overlay = Control.new()
	_win_overlay.name = "WinOverlay"
	_win_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_win_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_win_overlay.visible = false
	hud.add_child(_win_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.015, 0.035, 0.88)
	_win_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_win_overlay.add_child(center)
	var win_box := VBoxContainer.new()
	win_box.alignment = BoxContainer.ALIGNMENT_CENTER
	win_box.add_theme_constant_override("separation", 22)
	center.add_child(win_box)
	var title := Label.new()
	title.text = "YOU WIN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color("#42f5a7"))
	title.add_theme_color_override("font_outline_color", Color("#062b22"))
	title.add_theme_constant_override("outline_size", 12)
	win_box.add_child(title)
	var captured := Label.new()
	captured.text = "THIEF CAPTURED"
	captured.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	captured.add_theme_font_size_override("font_size", 28)
	captured.add_theme_color_override("font_color", Color.WHITE)
	win_box.add_child(captured)
	var restart := Button.new()
	restart.text = "CHASE AGAIN"
	restart.custom_minimum_size = Vector2(260.0, 64.0)
	restart.add_theme_font_size_override("font_size", 22)
	restart.pressed.connect(func() -> void: get_tree().reload_current_scene())
	win_box.add_child(restart)


func _setup_thief_indicator(hud: Node) -> void:
	_thief_indicator = Control.new()
	_thief_indicator.name = "ThiefDirectionIndicator"
	_thief_indicator.size = Vector2(94.0, 76.0)
	_thief_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thief_indicator.visible = false
	_thief_indicator.z_index = 20
	hud.add_child(_thief_indicator)
	_thief_arrow = Node2D.new()
	_thief_arrow.position = Vector2(47.0, 27.0)
	_thief_indicator.add_child(_thief_arrow)
	var outline := Polygon2D.new()
	outline.polygon = PackedVector2Array([Vector2(0, -27), Vector2(23, 21), Vector2(0, 14), Vector2(-23, 21)])
	outline.color = Color(0.02, 0.035, 0.07, 0.96)
	_thief_arrow.add_child(outline)
	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(0, -21), Vector2(17, 15), Vector2(0, 10), Vector2(-17, 15)])
	arrow.color = Color("#ff344d")
	_thief_arrow.add_child(arrow)
	_thief_indicator_label = Label.new()
	_thief_indicator_label.position = Vector2(0.0, 49.0)
	_thief_indicator_label.size = Vector2(94.0, 25.0)
	_thief_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thief_indicator_label.add_theme_font_size_override("font_size", 17)
	_thief_indicator_label.add_theme_color_override("font_color", Color.WHITE)
	_thief_indicator_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_thief_indicator_label.add_theme_constant_override("outline_size", 5)
	_thief_indicator.add_child(_thief_indicator_label)


# --- Process + chase (ported from drive_city.gd) --------------------------

func _process(delta: float) -> void:
	_traffic_time += delta
	_update_traffic_state(false)
	if not _chase_won:
		_update_chase(delta)
	if Input.is_action_just_pressed("reset_car"):
		_on_reset()
	if _label:
		var mode_txt := "TOP-DOWN" if (_cam == null or _cam.mode == 0) else "POV"
		var kmh := 0.0
		if _car:
			kmh = _car.get_speed_kmh()
		_label.text = "%s  |  %3.0f km/h\nCHASE — catch and ram the thief\nC camera   R reset" % [mode_txt, kmh]


func _update_chase(delta: float) -> void:
	if _car == null or _thief == null:
		return
	_capture_cooldown = maxf(0.0, _capture_cooldown - delta)
	var separation := _thief.global_position - _car.global_position
	separation.y = 0.0
	var distance := separation.length()
	if _distance_label:
		_distance_label.text = "%d m TO THIEF" % int(round(distance))
	_update_thief_indicator(distance)
	if _damage_bar:
		_damage_bar.value = _thief_damage
	if _damage_label:
		_damage_label.text = "THIEF DAMAGE %d%%" % int(round(_thief_damage))
	if _player_damage_bar:
		_player_damage_bar.value = _player_damage
	if _player_damage_label:
		_player_damage_label.text = "POLICE DAMAGE %d%%" % int(round(_player_damage))
	_update_vehicle_smoke(_car, _player_damage)
	_update_vehicle_smoke(_thief, _thief_damage)
	_apply_world_impact_damage(_car, true)
	_apply_world_impact_damage(_thief, false)
	# Register a ram when the cars physically touch (definitive, any angle) OR are
	# closely aligned front-to-back. The physical-contact path matters because the
	# proximity window alone is easy to miss on angled hits or at speed.
	var local_offset := _car.global_transform.basis.inverse() * separation
	var touching := _car_slide_hits(_car, _thief) or _car_slide_hits(_thief, _car)
	var aligned := distance < 6.5 and absf(local_offset.x) < 3.0
	if _capture_cooldown <= 0.0 and (touching or aligned):
		var relative_speed := absf(_car.speed - _thief.speed)
		if relative_speed > 1.0 or absf(_car.speed) > 6.0:
			_register_thief_hit(relative_speed)


func _update_thief_indicator(distance: float) -> void:
	if _thief_indicator == null or _cam == null or _thief == null:
		return
	if _chase_won:
		_thief_indicator.visible = false
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var target_position := _thief.global_position + Vector3.UP * 1.2
	var behind := _cam.is_position_behind(target_position)
	var projected := _cam.unproject_position(target_position)
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size).grow(-34.0)
	var on_screen := not behind and viewport_rect.has_point(projected)
	_thief_indicator.visible = distance > 50.0 or not on_screen
	if not _thief_indicator.visible:
		return
	var viewport_center := viewport_size * 0.5
	var direction := (projected - viewport_center).normalized()
	if behind:
		direction = -direction
	if direction.length_squared() < 0.01:
		direction = Vector2.UP
	var safe_rect := Rect2(Vector2(54.0, 174.0), viewport_size - Vector2(108.0, 314.0))
	var safe_center := safe_rect.get_center()
	var half := safe_rect.size * 0.5
	var edge_scale := minf(
		half.x / maxf(absf(direction.x), 0.001),
		half.y / maxf(absf(direction.y), 0.001))
	var indicator_center := safe_center + direction * edge_scale
	_thief_indicator.position = indicator_center - _thief_indicator.size * 0.5
	_thief_arrow.rotation = direction.angle() + PI * 0.5
	_thief_indicator_label.text = "%d m" % int(round(distance))


func _register_thief_hit(relative_speed: float) -> void:
	var hit_damage := clampf(7.0 + relative_speed * 1.35, 9.0, 28.0)
	_thief_damage = minf(100.0, _thief_damage + hit_damage)
	_capture_cooldown = 0.9
	var impact_direction := _thief.global_position - _car.global_position
	impact_direction.y = 0.0
	if impact_direction.length_squared() < 0.01:
		impact_direction = -_car.global_transform.basis.z
	impact_direction = impact_direction.normalized()
	var shove_strength := clampf(2.5 + relative_speed * 0.48, 3.5, 11.0)
	_thief.apply_impact_impulse(impact_direction * shove_strength)
	_car.apply_impact_impulse(-impact_direction * shove_strength * 0.32)
	_car.speed *= 0.68
	_thief.speed = maxf(3.5, _thief.speed * 0.52)
	_spawn_impact_fx((_car.global_position + _thief.global_position) * 0.5 + Vector3.UP * 0.75, shove_strength)
	_update_vehicle_smoke(_car, _player_damage)
	_update_vehicle_smoke(_thief, _thief_damage)
	if OS.has_environment("CTT_GEN_CAPTURE_TEST"):
		print("[CAPTURE TEST] hit=%.1f total=%.1f police_damage=%.1f" % [hit_damage, _thief_damage, _player_damage])
	if _thief_damage >= 100.0:
		_win_chase()


func _apply_world_impact_damage(vehicle: ArcadeCar, is_player: bool) -> void:
	if vehicle == null:
		return
	var touching := false
	var impact_position := vehicle.global_position + Vector3.UP * 0.7
	var impact_normal := Vector3.ZERO
	for index in vehicle.get_slide_collision_count():
		var collision := vehicle.get_slide_collision(index)
		var collider := collision.get_collider()
		if not _collider_causes_vehicle_damage(collider):
			continue
		touching = true
		impact_position = collision.get_position()
		impact_normal = collision.get_normal()
		break
	var was_touching := bool(_vehicle_contacting_world.get(vehicle, false))
	_vehicle_contacting_world[vehicle] = touching
	if not touching or was_touching or absf(vehicle.speed) < 5.0:
		return
	var impact_damage := clampf((absf(vehicle.speed) - 4.0) * (0.72 if is_player else 0.45), 2.0, 12.0)
	if is_player:
		_player_damage = minf(100.0, _player_damage + impact_damage)
	else:
		_thief_damage = minf(99.0, _thief_damage + impact_damage)
	var rebound := clampf(absf(vehicle.speed) * 0.28, 1.5, 6.5)
	impact_normal.y = 0.0
	if impact_normal.length_squared() > 0.01:
		vehicle.apply_impact_impulse(impact_normal.normalized() * rebound)
	vehicle.speed *= 0.58
	_spawn_impact_fx(impact_position + Vector3.UP * 0.2, rebound)
	_update_vehicle_smoke(vehicle, _player_damage if is_player else _thief_damage)


func _collider_causes_vehicle_damage(collider: Object) -> bool:
	if collider == _car or collider == _thief:
		return false
	var node := collider as Node
	if node and node.is_in_group("knockable_city_prop"):
		return false
	return collider != null


func _spawn_impact_fx(world_position: Vector3, strength: float) -> void:
	var fx := Node3D.new()
	fx.name = "VehicleImpactFX"
	fx.add_to_group("vehicle_impact_fx")
	add_child(fx)
	fx.global_position = world_position
	var sparks := GPUParticles3D.new()
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = int(clampf(strength * 2.2, 8.0, 24.0))
	sparks.lifetime = 0.55
	var spark_process := ParticleProcessMaterial.new()
	spark_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spark_process.emission_sphere_radius = 0.32
	spark_process.direction = Vector3.UP
	spark_process.spread = 78.0
	spark_process.gravity = Vector3(0.0, -13.0, 0.0)
	spark_process.initial_velocity_min = 4.0
	spark_process.initial_velocity_max = 7.0 + strength * 0.35
	spark_process.scale_min = 0.7
	spark_process.scale_max = 1.25
	spark_process.color = Color("#ffb52e")
	sparks.process_material = spark_process
	var spark_quad := QuadMesh.new()
	spark_quad.size = Vector2(0.055, 0.30)
	var spark_material := StandardMaterial3D.new()
	spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark_material.albedo_color = Color("#ffd66b")
	spark_material.emission_enabled = true
	spark_material.emission = Color("#ff8a16")
	spark_material.emission_energy_multiplier = 4.0
	spark_quad.material = spark_material
	sparks.draw_pass_1 = spark_quad
	fx.add_child(sparks)
	var debris := GPUParticles3D.new()
	debris.one_shot = true
	debris.explosiveness = 1.0
	debris.amount = int(clampf(strength * 0.65, 3.0, 8.0))
	debris.lifetime = 0.9
	var debris_process := ParticleProcessMaterial.new()
	debris_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	debris_process.emission_sphere_radius = 0.28
	debris_process.direction = Vector3.UP
	debris_process.spread = 62.0
	debris_process.gravity = Vector3(0.0, -10.0, 0.0)
	debris_process.initial_velocity_min = 2.4
	debris_process.initial_velocity_max = 4.5 + strength * 0.2
	debris_process.scale_min = 0.65
	debris_process.scale_max = 1.2
	debris_process.color = Color(0.12, 0.14, 0.17, 1.0)
	debris.process_material = debris_process
	var fragment := BoxMesh.new()
	fragment.size = Vector3(0.10, 0.045, 0.16)
	var fragment_material := StandardMaterial3D.new()
	fragment_material.albedo_color = Color(0.08, 0.10, 0.13, 1.0)
	fragment.material = fragment_material
	debris.draw_pass_1 = fragment
	fx.add_child(debris)
	sparks.restart()
	debris.restart()
	get_tree().create_timer(1.4).timeout.connect(fx.queue_free)


func _win_chase() -> void:
	if _chase_won:
		return
	_chase_won = true
	_car.speed = 0.0
	_car.velocity = Vector3.ZERO
	_car.touch_input = Vector2.ZERO
	_thief.speed = 0.0
	_thief.velocity = Vector3.ZERO
	_car.set_physics_process(false)
	_thief.set_physics_process(false)
	if _win_overlay:
		_win_overlay.visible = true
	if _thief_indicator:
		_thief_indicator.visible = false


# --- Vehicle smoke --------------------------------------------------------

func _setup_vehicle_smoke(vehicle: ArcadeCar, smoke_name: String) -> void:
	if vehicle == null:
		return
	var smoke := GPUParticles3D.new()
	smoke.name = smoke_name
	smoke.position = Vector3(0.0, 1.05, -0.75)
	smoke.amount = 36
	smoke.lifetime = 1.65
	smoke.randomness = 0.35
	smoke.local_coords = false
	smoke.emitting = false
	smoke.amount_ratio = 0.0
	var particles := ParticleProcessMaterial.new()
	particles.direction = Vector3.UP
	particles.spread = 24.0
	particles.gravity = Vector3(0.0, 0.8, 0.0)
	particles.initial_velocity_min = 0.65
	particles.initial_velocity_max = 1.35
	particles.scale_min = 0.22
	particles.scale_max = 0.58
	particles.color = Color(0.58, 0.62, 0.66, 0.62)
	smoke.process_material = particles
	var quad := QuadMesh.new()
	quad.size = Vector2(0.72, 0.72)
	var smoke_material := StandardMaterial3D.new()
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_material.vertex_color_use_as_albedo = true
	smoke_material.albedo_color = Color(0.7, 0.72, 0.74, 0.58)
	quad.material = smoke_material
	smoke.draw_pass_1 = quad
	vehicle.add_child(smoke)
	_vehicle_smoke[vehicle] = smoke
	_vehicle_contacting_world[vehicle] = false


func _update_vehicle_smoke(vehicle: ArcadeCar, damage: float) -> void:
	var smoke := _vehicle_smoke.get(vehicle) as GPUParticles3D
	if smoke == null:
		return
	var severity := clampf((damage - 20.0) / 80.0, 0.0, 1.0)
	smoke.emitting = damage >= 25.0
	smoke.amount_ratio = severity
	var particles := smoke.process_material as ParticleProcessMaterial
	if particles:
		particles.color = Color(0.6, 0.63, 0.66, 0.58).lerp(Color(0.12, 0.13, 0.14, 0.82), severity)


# --- Traffic signal state (used once stage-2 populates _signals) ----------

func _update_traffic_state(force: bool) -> void:
	if _signals.is_empty():
		return
	var half := TRAFFIC_GREEN + TRAFFIC_AMBER
	var period := 2.0 * half
	var t := fmod(_traffic_time, period)
	var sa := _traffic_state_for(t)
	var sb := _traffic_state_for(fmod(t + half, period))
	if not force and sa == _last_state_a and sb == _last_state_b:
		return
	_last_state_a = sa
	_last_state_b = sb
	for sig in _signals:
		var state: int = sa if sig["group"] else sb
		(sig["mat"] as ShaderMaterial).set_shader_parameter("signal_state", state)


func _traffic_state_for(t: float) -> int:
	if t < TRAFFIC_GREEN:
		return 2
	elif t < TRAFFIC_GREEN + TRAFFIC_AMBER:
		return 1
	return 0


# --- Input handlers -------------------------------------------------------

func _on_joystick(v: Vector2) -> void:
	if _car:
		_car.touch_input = v


func _on_toggle_camera() -> void:
	if _cam:
		_cam.toggle_mode()


func _on_reset() -> void:
	if _chase_won:
		return
	if _car:
		_car.reset_to_spawn()
	if _thief:
		_thief.reset_to_spawn()
	_thief_damage = 0.0
	_player_damage = 0.0
	_capture_cooldown = 0.0
	_vehicle_contacting_world[_car] = false
	_vehicle_contacting_world[_thief] = false
	_update_vehicle_smoke(_car, 0.0)
	_update_vehicle_smoke(_thief, 0.0)
	if _cam:
		_cam.snap_to_target()


# --- Headless diagnostics -------------------------------------------------

func _run_capture_test() -> void:
	await get_tree().create_timer(0.5).timeout
	_thief_damage = 92.0
	_car.speed = 20.0
	_thief.speed = 4.0
	var forward := -_car.global_transform.basis.z.normalized()
	_thief.global_position = _car.global_position + forward * 4.8
	_update_chase(0.016)
	print("[GEN CAPTURE TEST] thief_damage=%.1f won=%s overlay=%s" % [
		_thief_damage, _chase_won, (_win_overlay != null and _win_overlay.visible)])
	get_tree().quit()


func _run_ram_test() -> void:
	await get_tree().create_timer(1.0).timeout
	_thief.set_physics_process(false)
	var thief_pos := _thief.global_position
	var thief_basis := _thief.global_transform.basis
	var fwd := -thief_basis.z.normalized()
	var right := thief_basis.x.normalized()
	# scenario: [name, start offset from thief, facing basis]
	await _ram_scenario("rear head-on", thief_pos - fwd * 9.0)
	await _ram_scenario("side T-bone", thief_pos - right * 9.0)
	print("[RAM] DONE")
	get_tree().quit()


func _ram_scenario(label: String, start: Vector3) -> void:
	_thief_damage = 0.0
	_capture_cooldown = 0.0
	# Orient the police to face the thief (forward = -z points at it).
	var facing := Transform3D(Basis(), start).looking_at(_thief.global_position, Vector3.UP).basis
	_car.global_transform = Transform3D(facing, start)
	_car.speed = 0.0
	await get_tree().physics_frame
	var fired := false
	var min_dist := 999.0
	for i in 120:
		_car.touch_input = Vector2(0.0, -1.0)
		await get_tree().physics_frame
		min_dist = minf(min_dist, _car.global_position.distance_to(_thief.global_position))
		if _thief_damage > 0.0:
			fired = true
			break
	print("[RAM] %s -> fired=%s thief_dmg=%.1f min_dist=%.2f fx=%d" % [
		label, fired, _thief_damage, min_dist, get_tree().get_nodes_in_group("vehicle_impact_fx").size()])


func _car_slide_hits(a: ArcadeCar, b: ArcadeCar) -> bool:
	for i in a.get_slide_collision_count():
		if a.get_slide_collision(i).get_collider() == b:
			return true
	return false


func _run_report() -> void:
	await get_tree().create_timer(1.0).timeout
	var polys := nav_region.navigation_mesh.get_polygon_count() if nav_region else 0
	print("[GEN REPORT] map=%s items=%d navmesh_polys=%d player=%s thief=%s peds=%d signals=%d lamps=%d windows=%d knockables=%d tod=%s" % [
		map_path, int(_built.get("item_count", 0)), polys,
		_car != null, _thief != null,
		_pedestrians.get_child_count() if _pedestrians else 0,
		_signals.size(), _lamp_lights.size(), _window_lights.size(),
		get_tree().get_nodes_in_group("knockable_city_prop").size(),
		_tod_presets[_tod_index][0]])
	get_tree().quit()
