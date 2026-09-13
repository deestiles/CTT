extends Node3D
## Asset Isolator — view any single Polygon City prefab on a small stage with the
## Sky3D day/night cycle, so lighting (emissive lenses, lamp glow, etc.) can be
## perfected on ONE asset before applying it to the full city.
##
## Pick an asset from the dropdown. Controls: T cycle time · arrows rotate.
## Headless capture: CTT_SHOT=1 (SHOT_ASSET substring, SHOT_TIME 0/1/2) saves
## user://isolator.png and quits.

const PREFAB_DIRS := [
	"res://Assets/Synty/PolygonCity/Prefabs/Props",
	"res://Assets/Synty/PolygonCity/Prefabs/Environments",
	"res://Assets/Synty/PolygonCity/Prefabs/Buildings",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles",
	"res://Assets/Synty/PolygonCity/Prefabs/Characters",
]
const TOD := [["DAY", 12.0, 1.0], ["DUSK", 18.6, 0.7], ["NIGHT", 22.5, 0.4]]
const SIGNAL_SHADER := preload("res://Assets/Synty/PolygonCity/Materials/Misc/Signal_Color.gdshader")
const ATLAS := preload("res://Assets/Synty/PolygonCity/Textures/PolygonCity_01_A.png")

var _assets: Array[String] = []
var _asset_idx: int = 0
var _time_idx: int = 2
var _sky: Sky3D
var _cam: Camera3D
var _asset: Node3D
var _label: Label
var _picker: OptionButton
var _yaw: float = 0.5
var _pitch: float = 0.35
var _zoom: float = 1.0
var _center: Vector3 = Vector3.ZERO
var _base_radius: float = 3.0
var _dragging: bool = false
var _signal_mat: ShaderMaterial
var _signal_time: float = 0.0
var _last_signal_state: int = -1

func _ready() -> void:
	_scan_assets()
	# Default to the traffic-signal head; overridable via SHOT_ASSET substring.
	_asset_idx = _find_asset("LightPole_Lights_01")
	if OS.has_environment("SHOT_ASSET"):
		_asset_idx = _find_asset(OS.get_environment("SHOT_ASSET"))
	if OS.has_environment("SHOT_TIME"):
		_time_idx = clampi(int(OS.get_environment("SHOT_TIME")), 0, TOD.size() - 1)
	if OS.has_environment("SHOT_YAW"):
		_yaw = float(OS.get_environment("SHOT_YAW"))
	if OS.has_environment("SHOT_PITCH"):
		_pitch = float(OS.get_environment("SHOT_PITCH"))
	if OS.has_environment("SHOT_ZOOM"):
		_zoom = float(OS.get_environment("SHOT_ZOOM"))

	_build_stage()
	_build_hud()
	_load_asset()
	_apply_time()
	if OS.has_environment("CTT_SHOT"):
		call_deferred("_capture")

func _scan_assets() -> void:
	for dir_path in PREFAB_DIRS:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".tscn"):
				_assets.append("%s/%s" % [dir_path, f])
	_assets.sort()

func _find_asset(substr: String) -> int:
	for i in _assets.size():
		if _assets[i].get_file().contains(substr):
			return i
	return 0

func _build_stage() -> void:
	var ground := StaticBody3D.new()
	add_child(ground)
	var gmesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(60, 1, 60)
	gmesh.mesh = plane
	gmesh.position = Vector3(0, -0.5, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#3b4048")
	gmesh.material_override = gm
	ground.add_child(gmesh)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)

	_sky = Sky3D.new()
	add_child(_sky)
	_sky.game_time_enabled = false
	_sky.editor_time_enabled = false

	_cam = Camera3D.new()
	_cam.current = true
	_cam.far = 500.0
	add_child(_cam)

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	_picker = OptionButton.new()
	_picker.offset_left = 16
	_picker.offset_top = 12
	_picker.offset_right = 360
	_picker.offset_bottom = 48
	for a in _assets:
		_picker.add_item(a.get_file())
	_picker.select(_asset_idx)
	_picker.item_selected.connect(_on_pick)
	hud.add_child(_picker)

	var tb := Button.new()
	tb.text = "Time (T)"
	tb.offset_left = 16
	tb.offset_top = 56
	tb.offset_right = 150
	tb.offset_bottom = 92
	tb.pressed.connect(_cycle_time)
	hud.add_child(tb)

	_label = Label.new()
	_label.offset_left = 160
	_label.offset_top = 58
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(_label)

func _on_pick(idx: int) -> void:
	_asset_idx = idx
	_load_asset()
	_apply_time()

func _load_asset() -> void:
	if _asset:
		_asset.queue_free()
	_asset = (load(_assets[_asset_idx]) as PackedScene).instantiate()
	add_child(_asset)
	_signal_mat = null
	# If this is a traffic-signal head, apply the runtime lens shader so we can
	# see whether the pack's baked lenses light up and cycle.
	var nm := _assets[_asset_idx].get_file()
	if nm.contains("TrafficLight") or nm.contains("LightPole_Lights") or nm.contains("LightPole_Arm"):
		var mesh_node := _asset as MeshInstance3D
		if mesh_node and mesh_node.mesh:
			_signal_mat = ShaderMaterial.new()
			_signal_mat.shader = SIGNAL_SHADER
			_signal_mat.set_shader_parameter("source_texture", ATLAS)
			_signal_mat.set_shader_parameter("signal_state", 2)
			_signal_mat.set_shader_parameter("boost", 6.0)
			if nm.contains("LightPole_Arm"):
				var ab := mesh_node.get_aabb()
				_signal_mat.set_shader_parameter("emit_zmask", 1.0)
				_signal_mat.set_shader_parameter("zmask_low", ab.position.z + ab.size.z * 0.28)
				_signal_mat.set_shader_parameter("zmask_high", ab.position.z + ab.size.z * 0.72)
			mesh_node.set_surface_override_material(0, _signal_mat)
	# Seat the asset's base on the ground (many Synty pieces are authored with
	# their origin up a pole or below the floor).
	var ab0 := _combined_aabb(_asset)
	_asset.position.y -= ab0.position.y
	if OS.has_environment("CTT_LC"):
		var mn := _asset as MeshInstance3D
		if mn and mn.mesh:
			print("[ISO] %s mesh_aabb=%s surfaces=%d" % [nm, mn.get_aabb(), mn.mesh.get_surface_count()])
	_frame_camera()
	_update_label()

## Build a self-calibrating signal material from a signal mesh's local AABB.
## Lens centres: red/amber/green at 83%/49%/15% of head height, x-centred, at the
## recessed front depth (~46% into the z span). Verified to reproduce the pack's
## hand-tuned TrafficLight values exactly.
static func make_signal_material(ab: AABB) -> ShaderMaterial:
	var xc: float = ab.position.x + ab.size.x * 0.5
	var zf: float = ab.position.z + ab.size.z * 0.46
	var m := ShaderMaterial.new()
	m.shader = SIGNAL_SHADER
	m.set_shader_parameter("source_texture", ATLAS)
	m.set_shader_parameter("red_center", Vector3(xc, ab.position.y + ab.size.y * 0.83, zf))
	m.set_shader_parameter("amber_center", Vector3(xc, ab.position.y + ab.size.y * 0.49, zf))
	m.set_shader_parameter("green_center", Vector3(xc, ab.position.y + ab.size.y * 0.15, zf))
	m.set_shader_parameter("lens_radius", ab.size.x * 0.27)
	m.set_shader_parameter("depth_tol", 0.07)
	m.set_shader_parameter("axis", 0.0)
	m.set_shader_parameter("signal_state", 2)
	return m

func _make_signal_material(ab: AABB) -> ShaderMaterial:
	return make_signal_material(ab)

## Override lens params via env vars for fast calibration of the gantry-arm head:
## SHOT_AXIS, SHOT_LX (depth), SHOT_LZ (head z), SHOT_LYR/A/G (lens Y), SHOT_LR (radius).
func _apply_signal_env_overrides(m: ShaderMaterial) -> void:
	var axis := float(OS.get_environment("SHOT_AXIS")) if OS.has_environment("SHOT_AXIS") else -1.0
	if axis < 0.0:
		return
	var lx := float(OS.get_environment("SHOT_LX"))
	var lz := float(OS.get_environment("SHOT_LZ"))
	var yr := float(OS.get_environment("SHOT_LYR"))
	var ya := float(OS.get_environment("SHOT_LYA"))
	var yg := float(OS.get_environment("SHOT_LYG"))
	var lr := float(OS.get_environment("SHOT_LR")) if OS.has_environment("SHOT_LR") else 0.09
	# For axis=1 the mask plane is ZY and depth is X: center=(x_depth, y, z_head).
	m.set_shader_parameter("axis", axis)
	m.set_shader_parameter("red_center", Vector3(lx, yr, lz))
	m.set_shader_parameter("amber_center", Vector3(lx, ya, lz))
	m.set_shader_parameter("green_center", Vector3(lx, yg, lz))
	m.set_shader_parameter("lens_radius", lr)
	m.set_shader_parameter("depth_tol", 0.09)

func _frame_camera() -> void:
	var ab := _combined_aabb(_asset)
	_center = ab.position + ab.size * 0.5
	if OS.has_environment("SHOT_LOOKZ"):
		_center.z = float(OS.get_environment("SHOT_LOOKZ"))
	if OS.has_environment("SHOT_LOOKY"):
		_center.y = float(OS.get_environment("SHOT_LOOKY"))
	_base_radius = maxf(ab.size.length() * 0.7, 1.2)
	_update_orbit()

## Orbit camera: yaw/pitch around the asset, zoom in/out. Drag to rotate, wheel
## to zoom (arrow keys also rotate).
func _update_orbit() -> void:
	var d: float = _base_radius * _zoom + 0.4
	var cp := cos(_pitch)
	var dir := Vector3(sin(_yaw) * cp, sin(_pitch), cos(_yaw) * cp)
	_cam.global_position = _center + dir * d
	_cam.look_at(_center, Vector3.UP)

func _combined_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var has := false
	var nodes := root.find_children("*", "VisualInstance3D", true, false)
	if root is VisualInstance3D:
		nodes.append(root)
	for n in nodes:
		var vi := n as VisualInstance3D
		var world := vi.global_transform * vi.get_aabb()
		if not has:
			out = world
			has = true
		else:
			out = out.merge(world)
	if not has:
		out = AABB(Vector3(-1, 0, -1), Vector3(2, 3, 2))
	return out

func _apply_time() -> void:
	var t: Array = TOD[_time_idx]
	if _sky:
		_sky.current_time = float(t[1])
		_sky.tonemap_exposure = float(t[2])
	_update_label()

func _update_label() -> void:
	if _label:
		var ab := _combined_aabb(_asset)
		_label.text = "%s\nTIME: %s   size ~ (%.2f, %.2f, %.2f)\ndrag rotate · wheel zoom · T time" % [
			_assets[_asset_idx].get_file(), TOD[_time_idx][0], ab.size.x, ab.size.y, ab.size.z]

func _cycle_time() -> void:
	_time_idx = (_time_idx + 1) % TOD.size()
	_apply_time()

func _process(delta: float) -> void:
	var turn := Input.get_axis("ui_left", "ui_right")
	var pitch := Input.get_axis("ui_down", "ui_up")
	if absf(turn) > 0.01 or absf(pitch) > 0.01:
		_yaw += turn * delta * 1.5
		_pitch = clampf(_pitch + pitch * delta * 1.2, -1.4, 1.4)
		_update_orbit()
	if _signal_mat:
		_signal_time += delta
		var st := int(_signal_time / 2.0) % 3        # cycle every 2s
		if OS.has_environment("SHOT_STATE"):
			st = int(OS.get_environment("SHOT_STATE"))
		if st != _last_signal_state:
			_signal_mat.set_shader_parameter("signal_state", st)
			_last_signal_state = st

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_T:
		_cycle_time()
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * 0.9, 0.15, 6.0)
			_update_orbit()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * 1.1, 0.15, 6.0)
			_update_orbit()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
	elif e is InputEventMouseMotion and _dragging:
		var mm := e as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.01
		_pitch = clampf(_pitch + mm.relative.y * 0.01, -1.4, 1.4)
		_update_orbit()

func _capture() -> void:
	await get_tree().create_timer(1.2).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://isolator.png")
	print("[ISO] ", ProjectSettings.globalize_path("user://isolator.png"))
	get_tree().quit()
