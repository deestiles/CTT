extends Node3D
class_name DriveCity
## Bootstrap for the free-drive Synty city sandbox. Spawns ambient pedestrians,
## drives the HUD (speed + camera mode), and wires the on-screen buttons. The
## static city, lighting, player car, and camera are placed in the scene tree;
## this script only adds the moving life and the UI glue.

const PED_SCENES: Array[PackedScene] = [
	preload("res://Assets/Synty/PolygonCity/Prefabs/Characters/Character_Male_Jacket.tscn"),
	preload("res://Assets/Synty/PolygonCity/Prefabs/Characters/Character_Female_Coat.tscn"),
	preload("res://Assets/Synty/PolygonCity/Prefabs/Characters/Character_BusinessMan_Suit.tscn"),
	preload("res://Assets/Synty/PolygonCity/Prefabs/Characters/Character_Male_Hoodie.tscn"),
	preload("res://Assets/Synty/PolygonCity/Prefabs/Characters/Character_BusinessWoman.tscn"),
]
const PED_SCRIPT := preload("res://scripts/drive/pedestrian.gd")
const SIGNAL_SHADER := preload("res://Assets/Synty/PolygonCity/Materials/Misc/Signal_Color.gdshader")
const ATLAS_TEX := preload("res://Assets/Synty/PolygonCity/Textures/PolygonCity_01_A.png")
const TRAFFIC_GREEN := 6.0
const TRAFFIC_AMBER := 1.4

## Autopilot patrol confined to ONE verified two-way avenue (E-W, centreline
## z=0, running x=-15..-145 — the stretch that drives clean). The car cruises
## west in the north lane (z=+3), U-turns at the west end, cruises east in the
## south lane (z=-3), U-turns at the east end, and repeats. No one-way street is
## involved, so there is no wrong-way/arrow conflict. Y is ignored (raycast).
var ROUTE: PackedVector3Array = PackedVector3Array([
	Vector3(-15, 0, 3),
	Vector3(-145, 0, 3),
	Vector3(-145, 0, -3),
	Vector3(-15, 0, -3),
])

@export var player_path: NodePath = ^"Player"
@export var camera_path: NodePath = ^"Camera3D"
@export var pedestrian_count: int = 10
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
		_setup_sky(city)
	if _cam:
		_cam.current = true

	# The car drives by pathfinding on the baked road NavMesh (set via the scene's
	# use_navigation flag); no fixed route needed.

	_pedestrians = Node3D.new()
	_pedestrians.name = "Pedestrians"
	add_child(_pedestrians)
	_spawn_pedestrians()

	if OS.has_environment("CTT_SHOT"):
		call_deferred("_capture_topdown")
	if OS.has_environment("CTT_ISHOT"):
		call_deferred("_capture_signals")

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
			# All signals share one phase so every pole and overhead gantry stays in
			# sync (per-intersection cross-street opposition is a future enhancement).
			_signals.append({"group": true, "mat": mat})
	_update_traffic_state(true)

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
	if PED_SCENES.is_empty():
		return
	for i in pedestrian_count:
		var ped := Node3D.new()
		ped.set_script(PED_SCRIPT)
		_pedestrians.add_child(ped)
		var scene: PackedScene = PED_SCENES[i % PED_SCENES.size()]
		ped.setup(scene, _make_loop(), randf_range(1.1, 1.8))

## A small rectangular stroll loop somewhere in the district, on the ground plane.
func _make_loop() -> PackedVector3Array:
	var cx := district_center.x + randf_range(-district_extent.x * 0.5, district_extent.x * 0.5)
	var cz := district_center.z + randf_range(-district_extent.y * 0.5, district_extent.y * 0.5)
	var w := randf_range(4.0, 12.0)
	var h := randf_range(4.0, 12.0)
	var pts := PackedVector3Array()
	pts.append(Vector3(cx - w, ground_y, cz - h))
	pts.append(Vector3(cx + w, ground_y, cz - h))
	pts.append(Vector3(cx + w, ground_y, cz + h))
	pts.append(Vector3(cx - w, ground_y, cz + h))
	return pts

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
