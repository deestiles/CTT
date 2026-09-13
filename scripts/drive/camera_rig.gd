extends Camera3D
class_name DriveCameraRig
## Follows the player car with two modes:
##   0 = top-down "map" view (high, steeply angled, follows and rotates with car)
##   1 = POV chase (just above/behind the car, looking where it drives)
## Toggle with the `toggle_camera` action (C).

@export var target_path: NodePath

@export_group("Top-down")
@export var td_height: float = 24.0
@export var td_back: float = 13.0
@export var td_pitch_deg: float = -63.0
@export var td_lerp: float = 6.0

@export_group("POV (first-person hood cam)")
@export var pov_height: float = 1.5
@export var pov_front: float = 1.6          # forward of car origin, near the hood
@export var pov_forward_look: float = 18.0
@export var pov_lerp: float = 16.0

var mode: int = 0
var _target: Node3D

func _ready() -> void:
	_target = get_node_or_null(target_path)
	current = true
	if _target:
		_snap_to_target()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		mode = 1 - mode

func _process(delta: float) -> void:
	if _target == null:
		return
	var t := _target.global_transform
	if mode == 0:
		var back := t.basis.z.normalized()          # +z is "behind" the car
		var desired := t.origin + back * td_back + Vector3.UP * td_height
		global_position = global_position.lerp(desired, clampf(td_lerp * delta, 0.0, 1.0))
		# Look at the car, keeping a steep map-like pitch.
		var focus := t.origin
		_look_smooth(focus, td_lerp * delta)
	else:
		# First-person hood cam: sit at the front of the car looking down the road.
		var forward := -t.basis.z.normalized()
		var desired := t.origin + forward * pov_front + Vector3.UP * pov_height
		global_position = global_position.lerp(desired, clampf(pov_lerp * delta, 0.0, 1.0))
		var focus := t.origin + forward * pov_forward_look + Vector3.UP * (pov_height - 0.3)
		_look_smooth(focus, pov_lerp * delta)

func _look_smooth(focus: Vector3, weight: float) -> void:
	var current_xf := global_transform
	var target_xf := current_xf.looking_at(focus, Vector3.UP)
	global_transform.basis = current_xf.basis.slerp(target_xf.basis, clampf(weight, 0.0, 1.0)).orthonormalized()

func _snap_to_target() -> void:
	var t := _target.global_transform
	var back := t.basis.z.normalized()
	global_position = t.origin + back * td_back + Vector3.UP * td_height
	look_at(t.origin, Vector3.UP)
