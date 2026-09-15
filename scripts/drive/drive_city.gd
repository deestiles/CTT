extends Node3D
class_name DriveCity
## Bootstrap for the free-drive Synty city sandbox. Spawns ambient pedestrians,
## drives the HUD (speed + camera mode), and wires the on-screen buttons. The
## static city, lighting, player car, and camera are placed in the scene tree;
## this script only adds the moving life and the UI glue.

# With-skin Mixamo characters (rigged; animate at runtime via MixamoChar). The
# extracted-mesh prefabs do NOT skin when posed, so pedestrians use these instead.
const PED_CHARS: Array[String] = [
	"res://Assets/Animations/Character/SK_Character_Male_Jacket.fbx",
	"res://Assets/Animations/Character/SK_Character_Female_Coat.fbx",
	"res://Assets/Animations/Character/SK_Character_BusinessMan_Suit.fbx",
	"res://Assets/Animations/Character/SK_Character_Male_Hoodie.fbx",
	"res://Assets/Animations/Character/SK_Character_BusinessWoman.fbx",
	"res://Assets/Animations/Character/SK_Character_Female_Police.fbx",
]
const PED_SCRIPT := preload("res://scripts/drive/pedestrian.gd")
const ARCADE_CAR_SCRIPT := preload("res://scripts/drive/arcade_car.gd")

# Stroll loops on the two sidewalk strips flanking the drive avenue, verified by
# raycast probe (north strip z=-13, south strip z=2.5, floor y=0). Each loop is a
# thin rectangle kept within the ~4 m sidewalk width and clear of props (hotdog
# stand x=-28, sign x=-38 north; a prop x=-42 south). Y is ignored (raycast-seated).
var SIDEWALK_LOOPS: Array[PackedVector3Array] = [
	PackedVector3Array([Vector3(-16,0,-12.6), Vector3(-26,0,-12.6), Vector3(-26,0,-13.6), Vector3(-16,0,-13.6)]),
	PackedVector3Array([Vector3(-30,0,-12.6), Vector3(-36,0,-12.6), Vector3(-36,0,-13.6), Vector3(-30,0,-13.6)]),
	PackedVector3Array([Vector3(-40,0,-12.6), Vector3(-54,0,-12.6), Vector3(-54,0,-13.6), Vector3(-40,0,-13.6)]),
	PackedVector3Array([Vector3(-14,0,2.0), Vector3(-38,0,2.0), Vector3(-38,0,3.0), Vector3(-14,0,3.0)]),
	PackedVector3Array([Vector3(-46,0,2.0), Vector3(-54,0,2.0), Vector3(-54,0,3.0), Vector3(-46,0,3.0)]),
	PackedVector3Array([Vector3(-58,0,-12.6), Vector3(-72,0,-12.6), Vector3(-72,0,-13.6), Vector3(-58,0,-13.6)]),
	PackedVector3Array([Vector3(-76,0,-12.6), Vector3(-90,0,-12.6), Vector3(-90,0,-13.6), Vector3(-76,0,-13.6)]),
	PackedVector3Array([Vector3(-58,0,2.0), Vector3(-72,0,2.0), Vector3(-72,0,3.0), Vector3(-58,0,3.0)]),
	PackedVector3Array([Vector3(-76,0,2.0), Vector3(-90,0,2.0), Vector3(-90,0,3.0), Vector3(-76,0,3.0)]),
]
# Each entry names waypoints where the character may use nearby street furniture
# (sit/gesture) rather than merely walking through it. Routes themselves remain
# clear of pole footprints and are accepted only after live downward raycasts.
var SIDEWALK_ACTIVITY_POINTS: Array[PackedInt32Array] = [
	PackedInt32Array(), PackedInt32Array([1]), PackedInt32Array(),
	PackedInt32Array([1]), PackedInt32Array(), PackedInt32Array([2]),
	PackedInt32Array(), PackedInt32Array([1]), PackedInt32Array(),
]
const SIGNAL_SHADER := preload("res://Assets/Synty/PolygonCity/Materials/Misc/Signal_Color.gdshader")
const WINDOW_SHADER := preload("res://Assets/Synty/PolygonCity/Materials/Misc/Window_Night_Glow.gdshader")
const ATLAS_TEX := preload("res://Assets/Synty/PolygonCity/Textures/PolygonCity_01_A.png")
const TRAFFIC_CARS: Array[String] = [
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Sedan_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Taxi_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Small_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Van_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Muscle_01.tscn",
]
const TRAFFIC_GREEN := 6.0
const TRAFFIC_AMBER := 1.4

## Autopilot patrol confined to ONE verified two-way avenue (E-W, centreline
## running x=-15..-145 — the stretch that drives clean). Live physics sweeps put
## the road carriageways at z=-8 and z=-2.5; z=+3 is sidewalk. US right-hand
## traffic cruises west in the north lane (z=-8), U-turns at the west end, then
## cruises east in the south lane (z=-2.5). Y is ignored (raycast).
var ROUTE: PackedVector3Array = PackedVector3Array([
	Vector3(-15, 0, -8),
	Vector3(-145, 0, -8),
	Vector3(-145, 0, -2.5),
	Vector3(-15, 0, -2.5),
])
## Stop lines for the two verified cross intersections on the main avenue.
## z=-8 travels west (-X); z=-2.5 travels east (+X).
var MAIN_AVENUE_STOP_LINES := PackedVector3Array([
	Vector3(-34.0, 0.0, -8.0), Vector3(-94.0, 0.0, -8.0),
	Vector3(-106.0, 0.0, -2.5), Vector3(-46.0, 0.0, -2.5),
])

@export var player_path: NodePath = ^"Player"
@export var camera_path: NodePath = ^"Camera3D"
@export var pedestrian_count: int = 5
@export_range(0, 8) var traffic_vehicle_count: int = 4
@export_range(0, 64) var max_knockable_props: int = 24
@export var camera_customization_unlocked: bool = false
## Ground height of the Synty city (road/sidewalk surface sits at ~43.08 m).
@export var ground_y: float = 43.08
## Approximate centre of the drivable district, used to scatter pedestrians.
@export var district_center: Vector3 = Vector3(0.0, 43.08, 25.0)
@export var district_extent: Vector2 = Vector2(40.0, 80.0)

var _car: ArcadeCar
var _cam: DriveCameraRig
var _label: Label
var _pedestrians: Node3D
var _sky: Sky3D
var _time_button: Button
var _tod_index: int = 0
# name, hour-of-day, exposure (night darker than dusk)
var _tod_presets: Array = [["DAY", 12.0, 1.0], ["DUSK", 18.6, 0.7], ["NIGHT", 22.5, 0.4]]
var _lamp_lights: Array = []
var _window_lights: Array[ShaderMaterial] = []
var _signals: Array = []
var _last_state_a: int = -1
var _last_state_b: int = -1
var _traffic_time: float = 0.0

func _ready() -> void:
	randomize()
	_car = get_node_or_null(player_path) as ArcadeCar
	_cam = get_node_or_null(camera_path) as DriveCameraRig
	_label = get_node_or_null(^"HUD/Info") as Label

	var toggle_btn := get_node_or_null(^"HUD/CameraButton") as Button
	if toggle_btn:
		toggle_btn.pressed.connect(_on_toggle_camera)
	var reset_btn := get_node_or_null(^"HUD/ResetButton") as Button
	if reset_btn:
		reset_btn.pressed.connect(_on_reset)

	var hud_top := get_node_or_null(^"HUD")
	if hud_top:
		_time_button = Button.new()
		_time_button.name = "TimeButton"
		_time_button.text = "Time: DAY"
		_time_button.offset_left = 16.0
		_time_button.offset_top = 156.0
		_time_button.offset_right = 168.0
		_time_button.offset_bottom = 200.0
		hud_top.add_child(_time_button)
		_time_button.pressed.connect(_on_cycle_time)

	# Camera customization is reserved for the future garage drone upgrade. The
	# base game uses the authored 25-degree close framing without showing a slider.
	if hud_top and _cam and camera_customization_unlocked:
		var angle_box := VBoxContainer.new()
		angle_box.name = "AngleBox"
		angle_box.anchor_left = 1.0
		angle_box.anchor_right = 1.0
		angle_box.offset_left = -236.0
		angle_box.offset_top = 16.0
		angle_box.offset_right = -16.0
		angle_box.offset_bottom = 90.0
		hud_top.add_child(angle_box)
		var angle_label := Label.new()
		angle_label.text = "Map angle: %d°" % int(round(_cam.view_angle_deg))
		angle_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		angle_label.add_theme_constant_override("outline_size", 4)
		angle_box.add_child(angle_label)
		var slider := HSlider.new()
		slider.min_value = 15.0
		slider.max_value = 90.0
		slider.step = 1.0
		slider.value = _cam.view_angle_deg
		slider.custom_minimum_size = Vector2(220, 24)
		angle_box.add_child(slider)
		slider.value_changed.connect(func(v: float) -> void:
			if _cam:
				_cam.view_angle_deg = v
			angle_label.text = "Map angle: %d°" % int(round(v)))

	# On-screen directional joystick (bottom-left) for touch / free-drive control.
	var hud := get_node_or_null(^"HUD")
	if hud:
		var joy: Control = load("res://scripts/interface/virtual_joystick.gd").new()
		joy.name = "Joystick"
		joy.anchor_left = 0.0
		joy.anchor_top = 1.0
		joy.anchor_right = 0.0
		joy.anchor_bottom = 1.0
		joy.offset_left = 30.0
		joy.offset_top = -300.0
		joy.offset_right = 300.0
		joy.offset_bottom = -30.0
		hud.add_child(joy)
		joy.vector_changed.connect(_on_joystick)

	# The Synty Demo scene ships its own active Camera3D and parked traffic.
	var city := get_node_or_null(^"City")
	if city:
		_deactivate_cameras(city)
		_remove_traffic(city)
		_declutter_colliders(city)
		_setup_navigation(city)
		_setup_street_lamps(city)
		_setup_traffic_lights(city)
		_setup_window_lights(city)
		_setup_knockable_garbage(city)
		_setup_sky(city)
	if _cam:
		_cam.current = true

	# The car drives by pathfinding on the baked road NavMesh (set via the scene's
	# use_navigation flag); no fixed route needed.

	_pedestrians = Node3D.new()
	_pedestrians.name = "Pedestrians"
	add_child(_pedestrians)
	if OS.has_environment("CTT_TRAFFIC_RED_TEST"):
		_traffic_time = TRAFFIC_GREEN + TRAFFIC_AMBER + 0.2
		_update_traffic_state(true)
	_spawn_pedestrians()
	_spawn_traffic_vehicles()
	if OS.has_environment("CTT_TRAFFIC_TEST"):
		call_deferred("_run_traffic_lane_test")
	if OS.has_environment("CTT_PED_HIT_TEST"):
		call_deferred("_run_pedestrian_hit_test")

	if OS.has_environment("CTT_SHOT"):
		call_deferred("_capture_topdown")
	if OS.has_environment("CTT_ISHOT"):
		call_deferred("_capture_signals")
	if OS.has_environment("CTT_PEDSHOT"):
		call_deferred("_capture_pedshot")
	if OS.has_environment("CTT_CAMSHOT"):
		call_deferred("_capture_camshot")

## Screenshot the live game (map) camera at CTT_ANGLE degrees, to preview the angle
## slider's effect. Uses the real DriveCameraRig, not a throwaway camera.
func _capture_camshot() -> void:
	if _cam and OS.has_environment("CTT_ANGLE"):
		_cam.view_angle_deg = float(OS.get_environment("CTT_ANGLE"))
	await get_tree().create_timer(2.0).timeout
	var hud := get_node_or_null(^"HUD") as CanvasLayer
	if hud:
		hud.visible = false
	await get_tree().create_timer(0.3).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://camshot.png")
	print("[CAMSHOT] ", ProjectSettings.globalize_path("user://camshot.png"))
	get_tree().quit()

## Eye-level angled capture aimed at a pedestrian loop, to check the walkers look
## right in the city (textured, walking, grounded on the sidewalk). Env: PED_X/PED_Z
## look target, PED_DIST camera distance, PED_WAIT settle seconds.
func _capture_pedshot() -> void:
	var wait := float(OS.get_environment("PED_WAIT")) if OS.has_environment("PED_WAIT") else 2.0
	await get_tree().create_timer(wait).timeout
	var hud := get_node_or_null(^"HUD") as CanvasLayer
	if hud:
		hud.visible = false
	var tx := float(OS.get_environment("PED_X")) if OS.has_environment("PED_X") else -21.0
	var tz := float(OS.get_environment("PED_Z")) if OS.has_environment("PED_Z") else -13.0
	var dist := float(OS.get_environment("PED_DIST")) if OS.has_environment("PED_DIST") else 6.0
	var target := Vector3(tx, 1.0, tz)
	if OS.has_environment("CTT_PED_HIT_TEST") and _pedestrians and _pedestrians.get_child_count() > 0:
		target = (_pedestrians.get_child(0) as Node3D).global_position + Vector3.UP * 0.8
	var cam := Camera3D.new()
	cam.far = 500.0
	cam.position = target + Vector3(dist * 0.7, maxf(2.2, dist * 0.5), dist * 0.7)
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.current = true
	for i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://pedshot.png")
	print("[PEDSHOT] ", ProjectSettings.globalize_path("user://pedshot.png"))
	get_tree().quit()

func _capture_signals() -> void:
	_tod_index = 2
	_apply_time_preset()
	await get_tree().create_timer(1.2).timeout
	var hud := get_node_or_null(^"HUD") as CanvasLayer
	if hud:
		hud.visible = false
	var cam := Camera3D.new()
	cam.far = 500.0
	cam.position = Vector3(1, 5.2, 5)
	add_child(cam)
	cam.look_at(Vector3(-6, 5.0, 5), Vector3.UP)
	cam.current = true
	for i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://signals.png")
	print("[ISHOT] ", ProjectSettings.globalize_path("user://signals.png"))
	get_tree().quit()

func _capture_topdown() -> void:
	await get_tree().create_timer(1.5).timeout
	var hud := get_node_or_null(^"HUD") as CanvasLayer
	if hud:
		hud.visible = false
	# Kill directional shadows so painted markings read clearly from overhead.
	for l in get_node(^"City").find_children("*", "DirectionalLight3D", true, false):
		(l as DirectionalLight3D).shadow_enabled = false
	if OS.has_environment("SHOT_MARKERS"):
		_add_markers()
	var cx := float(OS.get_environment("SHOT_X")) if OS.has_environment("SHOT_X") else -80.0
	var cz := float(OS.get_environment("SHOT_Z")) if OS.has_environment("SHOT_Z") else -2.0
	var sz := float(OS.get_environment("SHOT_SIZE")) if OS.has_environment("SHOT_SIZE") else 70.0
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = sz
	cam.far = 2000.0
	cam.position = Vector3(cx, 300, cz)
	cam.rotation_degrees = Vector3(-90, 0, 0)     # straight down, +X right, +Z down
	add_child(cam)
	cam.current = true
	for i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://topdown.png")
	print("[SHOT] ", ProjectSettings.globalize_path("user://topdown.png"))
	get_tree().quit()

func _deactivate_cameras(node: Node) -> void:
	if node is Camera3D:
		(node as Camera3D).current = false
	for c in node.get_children():
		_deactivate_cameras(c)

var nav_region: NavigationRegion3D

## Add the Sky3D atmospheric day/night system and hand it the lighting: the Demo
## ships its own WorldEnvironment + sun, which we disable so Sky3D controls sky,
## sun, moon and ambient. Time is frozen; the TIME button sets it explicitly.
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
	_apply_time_preset()

## The street lamp is SM_Prop_LightPole_Base_01 — a tall pole with a cobra arm.
## Put a downward SpotLight at the luminaire (top of the pole, out along the cobra
## arm) plus a glow at the fixture; hidden by day, shown at dusk/night. The
## luminaire is derived from each pole's bounding box (top, far end of the arm).
func _setup_street_lamps(city: Node) -> void:
	for pole in city.find_children("*LightPole_Base*", "MeshInstance3D", true, false):
		var p := pole as MeshInstance3D
		if p.mesh == null:
			continue
		var ab: AABB = p.get_aabb()
		if ab.size == Vector3.ZERO or ab.size.y < 3.0:      # skip short pole segments
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
		sl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)      # point down at the road
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

## Light every traffic signal by emitting on its baked lens colours (Signal_Color
## shader) — works on the pole-mounted heads (LightPole_Lights) AND the overhead
## gantry signals baked into LightPole_Arm, both heads, any orientation, with no
## per-mesh calibration. Signals facing perpendicular directions run opposite phases.
func _setup_traffic_lights(city: Node) -> void:
	var axis_x := 0
	var axis_z := 0
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
			var group_x := _signal_axis_group(mi)
			_signals.append({"group": group_x, "mat": mat})
			if group_x:
				axis_x += 1
			else:
				axis_z += 1
	_update_traffic_state(true)
	if OS.has_environment("CTT_CITY_FEATURES"):
		print("[SIGNALS] x_phase=%d z_phase=%d" % [axis_x, axis_z])

## Signal props retain their placed orientation even though the large Demo road
## tiles cannot be located reliably from node bounds. Perpendicular approaches
## therefore derive phase from each signal's world-facing basis.
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

func _traffic_state_for(t: float) -> int:
	if t < TRAFFIC_GREEN:
		return 2                      # green
	elif t < TRAFFIC_GREEN + TRAFFIC_AMBER:
		return 1                      # amber
	return 0                          # red

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

func get_traffic_state_for_axis(axis_x: bool) -> int:
	return _last_state_a if axis_x else _last_state_b

func _on_cycle_time() -> void:
	_tod_index = (_tod_index + 1) % _tod_presets.size()
	_apply_time_preset()

func _apply_time_preset() -> void:
	var preset: Array = _tod_presets[_tod_index]
	var dark: bool = _tod_index != 0
	if _sky:
		_sky.current_time = float(preset[1])
		_sky.tonemap_exposure = float(preset[2])
	if _car:
		_car.night_lights = dark
	for l in _lamp_lights:
		(l as Node3D).visible = dark
	for material in _window_lights:
		material.set_shader_parameter("emission_energy", 2.8 if dark else 0.0)
	if _time_button:
		_time_button.text = "Time: %s" % preset[0]


## Bake a navigation mesh from ONLY the road tiles, so the car can pathfind on
## roads and is intrinsically unable to route onto sidewalks/buildings/water.
func _setup_navigation(city: Node) -> void:
	var roads := city.find_children("*Road*", "MeshInstance3D", true, false)
	for r in roads:
		r.add_to_group("nav_road")
	# Feed trees into the same source group so their trunks carve holes in the
	# road NavMesh — the car then paths around road/median trees instead of
	# through them. Sidewalk trees have no surrounding road, so they're ignored.
	var trees := city.find_children("*Tree*", "MeshInstance3D", true, false)
	for t in trees:
		t.add_to_group("nav_road")
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 1.4
	nm.agent_height = 1.5
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 30.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = "nav_road"
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	nav_region.bake_navigation_mesh(false)
	if OS.has_environment("CTT_NAV"):
		var poly := nav_region.navigation_mesh.get_polygon_count()
		var verts := nav_region.navigation_mesh.get_vertices().size()
		print("[NAV] road_tiles=%d trees=%d navmesh_polys=%d verts=%d" % [roads.size(), trees.size(), poly, verts])

## Disable collision on street furniture (props, trees) so the car can hold a
## lane without snagging on a hydrant/pole/sapling. Buildings (SM_Bld) and the
## road/sidewalk ground keep their colliders (needed for walls + raycast seating).
func _declutter_colliders(node: Node) -> void:
	var n := String(node.name)
	# Traffic signals and street lamps are intentional driving obstacles.
	if n.contains("LightPole"):
		return
	# NOTE: trees are intentionally NOT decluttered — they stay solid and are fed
	# into the NavMesh bake so the car routes around road-planted trees.
	if n.contains("Prop") or n.contains("FireEscape") or n.contains("Billboard") or n.contains("Sign") or n.contains("Aircon") or n.contains("Planter"):
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

## Illuminate a deterministic 30% of the supplied standalone window meshes. This
## modifies the real window material surface; it does not add fake geometry cards.
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
	if OS.has_environment("CTT_CITY_FEATURES"):
		print("[WINDOWS] eligible=%d lit=%d" % [eligible.size(), _window_lights.size()])

## Preserve existing meshes/transforms while replacing their static collision
## child with a lightweight rigid wrapper. A cap keeps the mobile physics budget
## predictable; trash bags/cans/bins nearest scene order become interactive.
func _setup_knockable_garbage(city: Node) -> void:
	var candidates: Array[Node] = city.find_children("*Trash*", "MeshInstance3D", true, false)
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
		body.mass = 0.65 if String(mesh.name).contains("Bag") else 2.2
		body.linear_damp = 0.7
		body.angular_damp = 0.55
		body.add_to_group("knockable_city_prop")
		parent.add_child(body)
		body.transform = old_transform
		mesh.reparent(body, false)
		mesh.transform = Transform3D.IDENTITY
		for child in static_body.get_children():
			if child is CollisionShape3D:
				var copy := (child as CollisionShape3D).duplicate() as CollisionShape3D
				body.add_child(copy)
		static_body.queue_free()
		converted += 1
	if OS.has_environment("CTT_CITY_FEATURES"):
		print("[KNOCKABLES] candidates=%d converted=%d" % [candidates.size(), converted])

func _first_static_body(node: Node) -> StaticBody3D:
	if node is StaticBody3D:
		return node as StaticBody3D
	for child in node.get_children():
		var found := _first_static_body(child)
		if found:
			return found
	return null

## Debug: drop a coordinate grid of coloured markers so a top-down photo reveals
## exactly which world coords land on asphalt. z=0 magenta, +z red, -z cyan; a
## marker every 2 m in z at several x. Markers float 1.5 m above the road.
func _add_markers() -> void:
	var zs := [-10, -8, -6, -4, -2, 0, 2, 4, 6, 8, 10]
	var xs := [-40, -70, -100, -130]
	for x in xs:
		for z in zs:
			var col := Color.MAGENTA
			var r := 0.9
			if z > 0:
				col = Color.RED
				r = 0.5
			elif z < 0:
				col = Color.CYAN
				r = 0.5
			_marker(Vector3(float(x), 1.5, float(z)), col, r)

func _marker(pos: Vector3, col: Color, r: float) -> void:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = r
	sph.height = r * 2.0
	mi.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)
	# Sit on the actual road surface via raycast, then float 1.5 m for visibility.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 60.0, pos + Vector3.DOWN * 60.0)
	var hit := space.intersect_ray(q)
	var gy: float = float(hit.position.y) if hit else 0.0
	mi.global_position = Vector3(pos.x, gy + 1.5, pos.z)

## Subdivide a closed corner loop into waypoints ~`spacing` metres apart.
func _densify(corners: PackedVector3Array, spacing: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := corners.size()
	for i in n:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % n]
		var seg := b - a
		var steps: int = max(1, int(seg.length() / spacing))
		for s in steps:
			out.append(a + seg * (float(s) / float(steps)))
	return out

## Remove every Synty vehicle instance placed in the Demo city.
func _remove_traffic(node: Node) -> void:
	var doomed: Array[Node] = []
	_collect_vehicles(node, doomed)
	for n in doomed:
		n.queue_free()

func _collect_vehicles(node: Node, out: Array[Node]) -> void:
	if String(node.name).contains("Veh_Car"):
		out.append(node)
		return
	for c in node.get_children():
		_collect_vehicles(c, out)

func _spawn_pedestrians() -> void:
	if PED_CHARS.is_empty() or SIDEWALK_LOOPS.is_empty():
		return
	var verified: Array[PackedVector3Array] = []
	var verified_activity: Array[PackedInt32Array] = []
	for i in SIDEWALK_LOOPS.size():
		var grounded := _raycast_verify_loop(SIDEWALK_LOOPS[i])
		if not grounded.is_empty():
			verified.append(grounded)
			verified_activity.append(SIDEWALK_ACTIVITY_POINTS[i] if i < SIDEWALK_ACTIVITY_POINTS.size() else PackedInt32Array())
	if OS.has_environment("CTT_PED_ROUTES"):
		print("[PED ROUTES] candidates=%d verified=%d" % [SIDEWALK_LOOPS.size(), verified.size()])
	var count: int = mini(pedestrian_count, verified.size())
	for i in count:
		var ped := Node3D.new()
		ped.set_script(PED_SCRIPT)
		_pedestrians.add_child(ped)
		var char_path: String = PED_CHARS[i % PED_CHARS.size()]
		ped.setup(char_path, verified[i], randf_range(1.1, 1.6), verified_activity[i])

func _run_pedestrian_hit_test() -> void:
	await get_tree().create_timer(0.2).timeout
	if _pedestrians == null or _pedestrians.get_child_count() == 0:
		print("[PED HIT TEST] no pedestrian")
		return
	var ped := _pedestrians.get_child(0) as Node3D
	var start := ped.global_position
	ped.debug_simulate_vehicle_hit(Vector3(0.0, 0.0, -12.0))
	await get_tree().create_timer(0.35).timeout
	print("[PED HIT TEST] displacement=%.2f" % ped.global_position.distance_to(start))

## Spawn a small, varied ambient fleet on verified points along the main avenue.
## They reuse the road-only NavMesh and arcade grounding instead of lane-graph AI.
func _spawn_traffic_vehicles() -> void:
	var spawns: Array[Transform3D] = [
		Transform3D(Basis.from_euler(Vector3(0, PI * 0.5, 0)), Vector3(-22, 1.0, -8.0)),
		Transform3D(Basis.from_euler(Vector3(0, PI * 0.5, 0)), Vector3(-72, 1.0, -8.0)),
		Transform3D(Basis.from_euler(Vector3(0, -PI * 0.5, 0)), Vector3(-132, 1.0, -2.5)),
		Transform3D(Basis.from_euler(Vector3(0, -PI * 0.5, 0)), Vector3(-78, 1.0, -2.5)),
	]
	var legal_route := _densify(ROUTE, 10.0)
	var count := mini(traffic_vehicle_count, mini(spawns.size(), TRAFFIC_CARS.size()))
	for index in count:
		var packed := load(TRAFFIC_CARS[index]) as PackedScene
		if packed == null:
			continue
		var car := CharacterBody3D.new()
		car.name = "AmbientTraffic_%02d" % (index + 1)
		car.set_script(ARCADE_CAR_SCRIPT)
		car.set("visual_path", NodePath("Visual"))
		car.set("use_navigation", false)
		car.set("autopilot", true)
		car.set("route", legal_route)
		car.set("waypoint_reach", 3.5)
		car.set("obey_traffic_rules", true)
		car.set("following_distance", 10.0)
		car.set("traffic_stop_points", MAIN_AVENUE_STOP_LINES)
		car.set("traffic_axis_x", true)
		car.set("autopilot_speed", 7.5 + index * 0.65)
		car.set("max_speed", 13.0)
		var visual := Node3D.new()
		visual.name = "Visual"
		# Polygon vehicle art faces +Z, while ArcadeCar drives along local -Z.
		# Match the player's authored 180-degree visual correction.
		visual.rotation.y = PI
		visual.add_child(packed.instantiate())
		car.add_child(visual)
		car.transform = spawns[index]
		add_child(car)
		car.begin_autopilot()
	if OS.has_environment("CTT_CITY_FEATURES"):
		print("[TRAFFIC] requested=%d spawned=%d" % [traffic_vehicle_count, count])

func _run_traffic_lane_test() -> void:
	await get_tree().create_timer(1.5).timeout
	var max_lane_error := 0.0
	for car in get_tree().get_nodes_in_group("arcade_vehicle"):
		if car == _car:
			continue
		var node := car as Node3D
		var lane_error := minf(absf(node.global_position.z + 8.0), absf(node.global_position.z + 2.5))
		max_lane_error = maxf(max_lane_error, lane_error)
		var forward := -node.global_transform.basis.z.normalized()
		print("[TRAFFIC TEST] %s pos=%s forward=%s speed=%.2f" % [node.name, node.global_position, forward, float(car.speed)])
	print("[TRAFFIC TEST] max_lane_error=%.2f" % max_lane_error)

## Accept a route only when every waypoint hits live walkable physics at a
## consistent height. Demo mesh transforms/AABBs are not trusted for placement.
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

func _process(delta: float) -> void:
	_traffic_time += delta
	_update_traffic_state(false)
	if Input.is_action_just_pressed("reset_car"):
		_on_reset()
	if _label:
		var mode_txt := "TOP-DOWN" if (_cam == null or _cam.mode == 0) else "POV"
		var kmh := 0.0
		if _car:
			kmh = _car.get_speed_kmh()
		_label.text = "%s  |  %3.0f km/h\nFREE DRIVE — joystick or W/A/S/D\nC camera   R reset" % [mode_txt, kmh]

func _on_joystick(v: Vector2) -> void:
	if _car:
		_car.touch_input = v

func _on_toggle_camera() -> void:
	if _cam:
		_cam.mode = 1 - _cam.mode

func _on_reset() -> void:
	if _car:
		_car.reset_to_spawn()
