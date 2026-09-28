extends Node3D
## Proof-of-pipeline: the Synty police car re-authored (in Blender) with its doors, hood
## and trunk as SEPARATE, hinge-pivoted nodes (SM_Veh_Car_Police_Rigged.glb). Godot opens
## each part by rotating that node -- the thing the original welded body could not do.
## SPACE toggles everything; it also auto-toggles on a timer. CTT_SHOT=1 saves a PNG.

const CAR := preload("res://Assets/Vehicles/SM_Veh_Car_Police_Rigged.glb")
const OPEN_TIME := 0.6

# node name -> [axis("y"|"x"), open_degrees]. Doors swing on vertical Y; hood/trunk lift
# on lateral X. Left doors and right doors mirror; hood/trunk lift up.
const PARTS := {
	"Door_FL": ["y", -70.0],
	"Door_RL": ["y", -70.0],
	"Door_FR": ["y", 70.0],
	"Door_RR": ["y", 70.0],
	"Hood":    ["x", 55.0],
	"Trunk":   ["x", -55.0],
}

var _nodes := {}          # name -> Node3D
var _open := false
var _busy := false

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1100, 640))
	var car := CAR.instantiate()
	add_child(car)
	for n in PARTS:
		var node := car.find_child(n, true, false)
		if node:
			_nodes[n] = node

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(4.4, 2.3, -3.2)
	cam.look_at(Vector3(0.1, 0.7, 0.1), Vector3.UP)
	cam.fov = 55.0
	cam.current = true

	var key := DirectionalLight3D.new()
	add_child(key)
	key.rotation_degrees = Vector3(-52.0, -46.0, 0.0)
	key.light_energy = 1.2

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#3b4048")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8090a0")
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)

	var hud := Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 20)
	hud.text = "Doors + hood + trunk are separate nodes — SPACE to open/close"
	var ci := CanvasLayer.new()
	add_child(ci)
	ci.add_child(hud)

	if OS.has_environment("CTT_SHOT"):
		call_deferred("_shot")
	else:
		_auto_loop()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_SPACE:
		_toggle()

func _toggle() -> void:
	if _busy or _nodes.is_empty():
		return
	_busy = true
	_open = not _open
	var tw := create_tween().set_parallel(true)
	for n in _nodes:
		var axis: String = PARTS[n][0]
		var deg: float = PARTS[n][1] if _open else 0.0
		var prop := "rotation:y" if axis == "y" else "rotation:x"
		tw.tween_property(_nodes[n], prop, deg_to_rad(deg), OPEN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func(): _busy = false)

func _auto_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(1.8).timeout
		_toggle()

func _shot() -> void:
	_toggle()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://car_parts_open.png")
	print("[PARTS DEMO] saved user://car_parts_open.png  found=%d/%d" % [_nodes.size(), PARTS.size()])
	get_tree().quit()
