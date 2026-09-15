extends Camera3D
class_name DriveCameraRig
## Follows the player car with two modes:
##   0 = top-down "map" view (high, steeply angled, follows and rotates with car)
##   1 = POV chase (just above/behind the car, looking where it drives)
## Toggle with the `toggle_camera` action (C).

@export var target_path: NodePath

@export_group("Top-down")
@export var td_height: float = 5.5
@export var td_back: float = 11.8
@export var td_pitch_deg: float = -25.0
@export var td_lerp: float = 6.0

# Map-view framing expressed as distance + angle so a HUD slider can sweep the view
# from a low chase angle (small deg) up to straight overhead (90 deg) at a constant
# distance from the car. Initialised in _ready from td_height/td_back; the authored
# baseline is the owner's approved 25-degree close chase-map view.
var td_distance: float = 13.0
var view_angle_deg: float = 25.0

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
	# Derive distance + angle from the authored height/back so the initial framing
	# matches the exported defaults; the slider then drives view_angle_deg.
	td_distance = sqrt(td_height * td_height + td_back * td_back)
	view_angle_deg = rad_to_deg(atan2(td_height, td_back))
	if _target:
		snap_to_target()

## Map-view offset split into (horizontal behind-distance, height) for the current
## angle at td_distance. angle 90 = straight overhead, small angle = low chase.
func _td_ground_up() -> Vector2:
	var a := deg_to_rad(clampf(view_angle_deg, 5.0, 90.0))
	return Vector2(td_distance * cos(a), td_distance * sin(a))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		toggle_mode()

func toggle_mode() -> void:
	mode = 1 - mode
	snap_to_target()

func _process(delta: float) -> void:
	if _target == null:
		return
	var t := _target.global_transform
	if mode == 0:
		var back := t.basis.z.normalized()          # +z is "behind" the car
		var gu := _td_ground_up()
		var desired := t.origin + back * gu.x + Vector3.UP * gu.y
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

func snap_to_target() -> void:
	if _target == null:
		return
	var t := _target.global_transform
	if mode == 0:
		var back := t.basis.z.normalized()
		var gu := _td_ground_up()
		global_position = t.origin + back * gu.x + Vector3.UP * gu.y
		look_at(t.origin, Vector3.UP)
	else:
		var forward := -t.basis.z.normalized()
		global_position = t.origin + forward * pov_front + Vector3.UP * pov_height
		look_at(t.origin + forward * pov_forward_look + Vector3.UP * (pov_height - 0.3), Vector3.UP)
