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
const THIEF_CAR := preload("res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Muscle_01.tscn")
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
@export var player_path: NodePath = ^"Player"
@export var camera_path: NodePath = ^"Camera3D"
@export var pedestrian_count: int = 5
@export_range(0, 180) var max_knockable_props: int = 180
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
var _thief: ArcadeCar
var _thief_damage: float = 0.0
var _player_damage: float = 0.0
var _capture_cooldown: float = 0.0
var _chase_won: bool = false
var _distance_label: Label
var _damage_label: Label
var _damage_bar: ProgressBar
var _player_damage_label: Label
var _player_damage_bar: ProgressBar
var _win_overlay: Control
var _thief_indicator: Control
var _thief_arrow: Node2D
var _thief_indicator_label: Label
var _vehicle_smoke: Dictionary = {}
var _vehicle_contacting_world: Dictionary = {}

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
		_setup_chase_hud(hud_top)

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
	_spawn_thief_vehicle()
	_setup_vehicle_smoke(_car, "PoliceDamageSmoke")
	_setup_vehicle_smoke(_thief, "ThiefDamageSmoke")
	if OS.has_environment("CTT_NPC_LIGHT_TEST"):
		_tod_index = 2
		_apply_time_preset()
		call_deferred("_run_npc_light_test")
	if OS.has_environment("CTT_RESET_TEST"):
		call_deferred("_run_reset_test")
	if OS.has_environment("CTT_KNOCKABLE_TEST"):
		call_deferred("_run_knockable_test")
	if OS.has_environment("CTT_TRAFFIC_TEST"):
		call_deferred("_run_traffic_lane_test")
	if OS.has_environment("CTT_CAPTURE_TEST"):
		call_deferred("_run_capture_test")
	if OS.has_environment("CTT_DAMAGE_TEST"):
		call_deferred("_run_damage_test")
	if OS.has_environment("CTT_ESCAPE_TEST"):
		call_deferred("_run_escape_test")
	if OS.has_environment("CTT_INDICATOR_TEST"):
		call_deferred("_run_indicator_test")
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
	_distance_label.text = "35 m TO THIEF"
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
## child with a lightweight rigid wrapper. Bodies remain frozen until first hit,
## keeping the expanded prop set inexpensive while idle.
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
	var category_counts := {"trash": 0, "bin": 0, "dumpster": 0, "cardboard": 0, "mailbox": 0, "cone": 0, "barrier": 0}
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
			category = "cardboard"
			body.mass = 0.8
		elif prop_name.contains("Mailbox"):
			category = "mailbox"
			body.mass = 5.0
		elif prop_name.contains("Cone"):
			category = "cone"
			body.mass = 0.7
		elif prop_name.contains("Barrier"):
			category = "barrier"
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
			# Skip_01 uses a concave imported collider, which is unsuitable for a
			# moving rigid body. A mesh-sized convex box is stable and cannot be
			# phased through by the CharacterBody car.
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
		category_counts[category] = int(category_counts[category]) + 1
		converted += 1
	if OS.has_environment("CTT_CITY_FEATURES"):
		print("[KNOCKABLES] candidates=%d converted=%d categories=%s" % [candidates.size(), converted, category_counts])

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

## The arcade chase has one target and no ambient vehicle traffic. The thief
## starts ahead on the road, then uses the complete baked road NavMesh to flee
## police. It ignores lanes and signals, but cannot navigate beyond the city.
func _spawn_thief_vehicle() -> void:
	var car := CharacterBody3D.new()
	car.name = "ThiefCar"
	car.set_script(ARCADE_CAR_SCRIPT)
	car.set("visual_path", NodePath("Visual"))
	car.set("use_navigation", true)
	car.set("autopilot", true)
	car.set("obey_traffic_rules", false)
	car.set("evasion_enabled", true)
	car.set("evasion_retarget_seconds", 5.0)
	car.set("autopilot_speed", 14.0)
	car.set("max_speed", 19.0)
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.rotation.y = PI
	visual.add_child(THIEF_CAR.instantiate())
	car.add_child(visual)
	car.transform = Transform3D(Basis.from_euler(Vector3(0, PI * 0.5, 0)), Vector3(-65.0, 1.0, -8.0))
	add_child(car)
	_thief = car as ArcadeCar
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
	if OS.has_environment("CTT_CITY_FEATURES"):
		print("[CHASE] ambient_traffic=0 thief_spawned=true")

## Stylized hood smoke communicates damage without requiring destructive mesh
## variants. It begins at 25%, then becomes denser and darker toward 100%.
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

func _run_npc_light_test() -> void:
	await get_tree().physics_frame
	for node in get_tree().get_nodes_in_group("arcade_vehicle"):
		if node == _car:
			continue
		var vehicle := node as ArcadeCar
		if vehicle:
			print("[NPC LIGHT TEST] %s %s" % [vehicle.name, vehicle.get_vehicle_light_debug()])

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

func _run_escape_test() -> void:
	await get_tree().create_timer(1.5).timeout
	var start := _thief.global_position
	var initial_distance := _thief.global_position.distance_to(_car.global_position)
	await get_tree().create_timer(7.0).timeout
	var debug := _thief.get_navigation_debug()
	print("[ESCAPE TEST] moved=%.2f police_distance=%.2f->%.2f nav_error=%.2f evading=%s target=%s" % [
		_thief.global_position.distance_to(start), initial_distance,
		_thief.global_position.distance_to(_car.global_position), float(debug.get("off_navmesh", -1.0)),
		debug.get("evading", false), debug.get("target", Vector3.ZERO)])

func _run_indicator_test() -> void:
	await get_tree().create_timer(0.5).timeout
	_thief.set_physics_process(false)
	_thief.global_position = _car.global_position + Vector3(80.0, 0.0, 0.0)
	_update_chase(0.016)
	print("[INDICATOR TEST] far_visible=%s distance_text=%s position=%s rotation=%.2f" % [
		_thief_indicator.visible, _thief_indicator_label.text,
		_thief_indicator.position, _thief_arrow.rotation])
	var forward := -_car.global_transform.basis.z.normalized()
	_thief.global_position = _car.global_position + forward * 10.0
	_update_chase(0.016)
	print("[INDICATOR TEST] near_ahead_visible=%s" % _thief_indicator.visible)
	_thief.global_position = _car.global_position - forward * 20.0
	_update_chase(0.016)
	print("[INDICATOR TEST] near_behind_visible=%s distance_text=%s" % [
		_thief_indicator.visible, _thief_indicator_label.text])

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
	# The combined vehicle length is a little over five metres. Lateral gating
	# prevents a parallel lane from counting as a ram.
	var local_offset := _car.global_transform.basis.inverse() * separation
	if _capture_cooldown <= 0.0 and distance < 5.6 and absf(local_offset.x) < 2.25:
		var relative_speed := absf(_car.speed - _thief.speed)
		if relative_speed > 1.5 or absf(_car.speed) > 8.0:
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
	# Keep the cue clear of the chase panel at the top and driving controls at
	# the bottom, then intersect the direction ray with that safe HUD rectangle.
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
	if _damage_bar:
		_damage_bar.value = _thief_damage
	if _damage_label:
		_damage_label.text = "THIEF DAMAGE %d%%  ·  HIT +%d" % [int(round(_thief_damage)), int(round(hit_damage))]
	if _player_damage_bar:
		_player_damage_bar.value = _player_damage
	if _player_damage_label:
		_player_damage_label.text = "POLICE DAMAGE %d%%" % int(round(_player_damage))
	_update_vehicle_smoke(_car, _player_damage)
	_update_vehicle_smoke(_thief, _thief_damage)
	if OS.has_environment("CTT_CAPTURE_TEST"):
		print("[CAPTURE TEST] hit=%.1f total=%.1f police_damage=%.1f police_shove=%.2f thief_shove=%.2f fx=%d" % [
			hit_damage, _thief_damage, _player_damage,
			_car.get_collision_shove_debug().length(), _thief.get_collision_shove_debug().length(),
			get_tree().get_nodes_in_group("vehicle_impact_fx").size()])
	if _thief_damage >= 100.0:
		_win_chase()

## Charge one speed-scaled impact per contact, rather than damage every frame
## while a car is scraping a wall. Vehicle-to-vehicle rams are handled above.
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
		# Environmental mistakes can weaken the thief but cannot win the chase for
		# the player; the final point of damage must still come from a police ram.
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
	# Reactive street props are gameplay spectacle, not hazards. They may receive
	# momentum and collide physically, but never add vehicle damage.
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
	sparks.name = "Sparks"
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
	debris.name = "Debris"
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
	if OS.has_environment("CTT_CAPTURE_TEST"):
		print("[CAPTURE TEST] won=true overlay=%s" % (_win_overlay != null and _win_overlay.visible))

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

func _run_capture_test() -> void:
	await get_tree().create_timer(0.5).timeout
	_thief_damage = 92.0
	_car.speed = 20.0
	_thief.speed = 4.0
	var forward := -_car.global_transform.basis.z.normalized()
	_thief.global_position = _car.global_position + forward * 4.8
	_update_chase(0.016)

func _run_damage_test() -> void:
	await get_tree().create_timer(0.5).timeout
	_player_damage = 55.0
	_thief_damage = 78.0
	_update_vehicle_smoke(_car, _player_damage)
	_update_vehicle_smoke(_thief, _thief_damage)
	var police_smoke := _vehicle_smoke.get(_car) as GPUParticles3D
	var thief_smoke := _vehicle_smoke.get(_thief) as GPUParticles3D
	print("[DAMAGE TEST] police=%.0f smoke=%s ratio=%.2f thief=%.0f smoke=%s ratio=%.2f" % [
		_player_damage, police_smoke.emitting, police_smoke.amount_ratio,
		_thief_damage, thief_smoke.emitting, thief_smoke.amount_ratio])

func _run_reset_test() -> void:
	await get_tree().create_timer(0.5).timeout
	for i in 5:
		_on_toggle_camera()
	var displaced := _car.global_position
	displaced.y = -25.0
	_car.global_position = displaced
	_on_reset()
	await get_tree().physics_frame
	print("[RESET TEST] car=%s camera=%s mode=%d" % [_car.global_position, _cam.global_position, _cam.mode])

func _run_knockable_test() -> void:
	await get_tree().physics_frame
	var tested := {}
	for node in get_tree().get_nodes_in_group("knockable_city_prop"):
		var body := node as RigidBody3D
		if body == null:
			continue
		var name_text := String(body.name)
		var category := ""
		for candidate in ["Skip", "Cardboard", "Bag", "Mailbox", "Cone", "Trashbin", "TrashCan"]:
			if name_text.contains(candidate):
				category = candidate
				break
		if category.is_empty() or tested.has(category):
			continue
		var start := body.global_position
		body.freeze = false
		if body.is_in_group("heavy_sliding_prop"):
			body.apply_central_impulse(Vector3(24.0, 0.0, 3.0))
		else:
			body.apply_central_impulse(Vector3(2.0, 4.0, 0.5) * body.mass)
		await get_tree().create_timer(0.25).timeout
		print("[KNOCKABLE TEST] %s displacement=%.2f vertical=%.2f heavy_slide=%s" % [
			body.name, body.global_position.distance_to(start),
			absf(body.global_position.y - start.y), body.is_in_group("heavy_sliding_prop")])
		print("[PROP DAMAGE TEST] %s causes_damage=%s" % [
			body.name, _collider_causes_vehicle_damage(body)])
		if category == "Skip":
			var collision_shapes := body.find_children("*", "CollisionShape3D", true, false)
			print("[DUMPSTER COLLISION TEST] shapes=%d layer=%d mask=%d shape_type=%s" % [
				collision_shapes.size(), body.collision_layer, body.collision_mask,
				collision_shapes[0].shape.get_class() if not collision_shapes.is_empty() else "none"])
		tested[category] = true
		if tested.has("Skip") and tested.size() >= 6:
			break
