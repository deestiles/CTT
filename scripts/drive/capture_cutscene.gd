extends Node3D
class_name CaptureCutscene
## Plays the "thief caught" beat: an officer steps out of the police car, draws a
## revolver, and holds it aimed at the thief car. Built on the shared-skeleton Mixamo
## pipeline (see MixamoChar / the character-animation-pipeline note) -- the police
## character and every action clip share one 48-bone skeleton, so clips play with no
## retargeting.
##
## The officer identity follows GameState.player_character ("male" | "female"), so the
## future character-customization screen automatically decides who appears on scene.
##
## Usage:
##   var cs := CaptureCutscene.start(self, police_car, thief_car)
##   cs.aim_ready.connect(func(): show_capture_overlay())
##
## The revolver mesh is not shipped yet: a "RevolverMount" BoneAttachment3D is created
## on the right-hand bone (Hand_R) so the prop drops in later with no code change.

signal aim_ready  ## Emitted once the officer settles into the aimed hold.

const MIXAMO_CHAR := preload("res://scripts/drive/mixamo_char.gd")

const CHAR_MALE := "res://Assets/Animations/Character/SK_Character_Male_Police.fbx"
const CHAR_FEMALE := "res://Assets/Animations/Character/SK_Character_Female_Police.fbx"

# Action clips. Names are the keys used under animation library "act".
const CLIPS := {
	"exit": "res://Assets/Animations/Exiting Car_3.fbx",
	"draw": "res://Assets/Animations/Drawing Gun_2.fbx",
	"idle": "res://Assets/Animations/Pistol Idle_2.fbx",
}
# One-shot beats (played once, in order); "idle" is the looped hold afterwards.
const SEQUENCE := ["exit", "draw"]

# All three clips share one baked front (they chain cleanly in the character preview), so
# the officer is oriented ONCE toward the thief and the clips just play in sequence -- no
# per-beat re-rotation. This single offset turns his baked front onto the aim point; flip
# it (0 <-> PI) if he faces away.
const FACE_OFFSET := PI
# Reference aim point on the thief: cabin/window height, biased toward the rear window
# that faces the pursuing officer. Local offset from the thief origin.
const AIM_WINDOW_OFFSET := Vector3(0.0, 1.15, 0.55)
# The officer first faces the police car's own front window (the car he is stepping out
# of -- the door stays shut, so this sells the exit), then turns onto the thief as he
# draws. Front-window point = police car forward * FWD + up * UP.
const FRONT_WINDOW_FWD := 1.7
const FRONT_WINDOW_UP := 1.1
const TURN_SECONDS := 0.6
# Beat between the pistol coming up (idle hold starts) and the end-game overlay, so the
# officer is visibly pointing the gun before the screen appears.
const OVERLAY_DELAY := 0.5

# The Synty/Mixamo right-hand bone (verified: 48-bone skeleton, bone 26).
const HAND_BONE := "Hand_R"

# Placement of the officer relative to the police car, in the car's local frame:
# out to the driver side and slightly back toward the door. Tune SIDE sign if the
# officer appears on the passenger side.
const SIDE_OFFSET := -1.45
const BACK_OFFSET := 0.15
# The pistol clips aim along the officer's front (node -Z), so he is oriented at the
# Safety net: if the clip chain never reports finished (e.g. a missing clip), reveal the
# capture overlay anyway after this many seconds so the player is never left frozen.
const WATCHDOG_SECONDS := 12.0

var _officer: Node3D
var _anim: AnimationPlayer
var _seq_index: int = 0
var _aim_emitted: bool = false
var _stand_pos: Vector3     # spot beside the driver door where he stands
var _thief: Node3D          # target the officer aims at
var _police_car: Node3D     # the car he steps out of (faced during the exit)
var _aim_marker: Node3D     # reference point on the thief window we point the gun at
var _turn_tween: Tween      # exit-window -> thief turn during the draw
var _cam: Camera3D          # camera taken over for the cinematic (may be null)
var _cam_phase: String = "" # "closeup" while he exits/turns, "pov" for the aim hold


## Build the cutscene, add it under `parent`, and begin the sequence. `police_car` and
## `thief_car` are the live ArcadeCar nodes; `cam` (optional) is the Camera3D to take
## over for the cinematic zoom-in / POV. Returns the CaptureCutscene node.
static func start(parent: Node, police_car: Node3D, thief_car: Node3D, cam: Camera3D = null) -> CaptureCutscene:
	var cs := CaptureCutscene.new()
	cs.name = "CaptureCutscene"
	parent.add_child(cs)
	cs._cam = cam
	cs._begin(police_car, thief_car)
	return cs


func _begin(police_car: Node3D, thief_car: Node3D) -> void:
	var char_path := CHAR_FEMALE if _is_female() else CHAR_MALE
	_officer = MIXAMO_CHAR.build(char_path, CLIPS)
	if _officer == null:
		push_warning("CaptureCutscene: failed to build officer; emitting aim_ready immediately")
		_emit_aim_ready()
		return
	add_child(_officer)
	_place_officer(police_car, thief_car)
	_add_revolver_mount()
	_anim = _find_player(_officer)
	if _anim == null:
		_emit_aim_ready()
		return
	# The shared builder force-loops every clip; the one-shot beats must play once so we
	# can chain them. Only the final hold ("idle") stays looped.
	_set_loop("exit", false)
	_set_loop("draw", false)
	_set_loop("aim", false)
	_set_loop("idle", true)
	_anim.animation_finished.connect(_on_clip_finished)
	# Take over the camera: stop it following the car and drive it ourselves. Zoom in on
	# the officer while he exits/turns, then settle into a POV behind him for the aim.
	if _cam:
		_cam.set_process(false)
		_cam_phase = "closeup"
		set_process(true)
	_seq_index = 0
	_play_current()
	# Watchdog against a stalled clip chain.
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(_emit_aim_ready)


## True once the officer has been instanced (used by headless capture verification).
func has_officer() -> bool:
	return _officer != null


## Drive the taken-over camera each frame: sit BEHIND the officer while he steps out
## (his back to us, thief ahead), then ease slowly into a tight over-the-shoulder POV
## down the gun once he draws.
func _process(delta: float) -> void:
	if _cam == null or _officer == null or _cam_phase.is_empty():
		return
	var head := _officer.global_position + Vector3.UP * 1.6
	# He always faces the window marker, so derive framing from that direction (robust to
	# the node-yaw flip between the exit and pistol clips).
	var aim := _aim_point()
	var front := (aim - _officer.global_position)
	front.y = 0.0
	front = front.normalized() if front.length() > 0.001 else Vector3.FORWARD
	var right := front.cross(Vector3.UP)
	var desired_pos: Vector3
	var focus: Vector3
	var weight: float
	if _cam_phase == "pov":
		# Tight over-the-shoulder, sighting down the gun at the window marker. Slow ease-in.
		desired_pos = head - front * 0.75 + Vector3.UP * 0.2 + right * 0.32
		focus = aim
		weight = 1.3 * delta
	else:
		# Behind him, holding steady so we watch his back as he faces the thief.
		desired_pos = head - front * 3.2 + Vector3.UP * 0.9
		focus = head + front * 4.0
		weight = 1.6 * delta
	_cam.global_position = _cam.global_position.lerp(desired_pos, clampf(weight, 0.0, 1.0))
	var target_xf := _cam.global_transform.looking_at(focus, Vector3.UP)
	_cam.global_transform.basis = _cam.global_transform.basis.slerp(target_xf.basis, clampf(weight, 0.0, 1.0)).orthonormalized()


func _is_female() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs and "player_character" in gs:
		return String(gs.player_character).to_lower() == "female"
	return false


## Place the officer beside the driver door, pin a reference aim point on the thief
## window, and orient him to face it for the exit.
func _place_officer(police_car: Node3D, thief_car: Node3D) -> void:
	_thief = thief_car
	_police_car = police_car
	var xf := police_car.global_transform
	var side := xf.basis.x.normalized()           # car local +X
	var back := xf.basis.z.normalized()            # car local +Z (rearward; forward is -Z)
	var foot_y := _road_y(police_car)
	_stand_pos = police_car.global_position + side * SIDE_OFFSET + back * BACK_OFFSET
	_stand_pos.y = foot_y
	_officer.global_position = _stand_pos
	# Reference point on the thief window: a marker parented to the thief so it tracks it.
	_aim_marker = Marker3D.new()
	_aim_marker.name = "GunAimTarget"
	thief_car.add_child(_aim_marker)
	_aim_marker.position = AIM_WINDOW_OFFSET
	# Exit facing: look at the police car's own front window (the car he is exiting). He
	# turns onto the thief as he draws (see _play_current / _turn_to_thief).
	_officer.rotation.y = _yaw_to(_exit_point() - _stand_pos) + FACE_OFFSET


## World-space reference point on the thief window the gun should track.
func _aim_point() -> Vector3:
	if _aim_marker:
		return _aim_marker.global_position
	if _thief:
		return _thief.global_position + Vector3.UP * AIM_WINDOW_OFFSET.y
	return _stand_pos + Vector3.FORWARD


## World-space point at the police car's front window, faced during the exit.
func _exit_point() -> Vector3:
	if _police_car == null:
		return _aim_point()
	var xf := _police_car.global_transform
	var forward := -xf.basis.z.normalized()
	return _police_car.global_position + forward * FRONT_WINDOW_FWD + Vector3.UP * FRONT_WINDOW_UP


## Yaw that points the officer's front along `dir` (before FACE_OFFSET).
func _yaw_to(dir: Vector3) -> float:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.001:
		return _officer.rotation.y
	return atan2(-flat.x, -flat.z)


## Road surface height for the officer's feet: prefer the car's own grounded pivot,
## fall back to a raycast, then to the car body height.
func _road_y(police_car: Node3D) -> float:
	if "_grounded_y" in police_car:
		return float(police_car._grounded_y)
	var space := police_car.get_world_3d().direct_space_state
	var from := police_car.global_position + Vector3.UP * 2.0
	var to := police_car.global_position + Vector3.DOWN * 6.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit:
		return float(hit.position.y)
	return police_car.global_position.y


## Attach an (empty) mount to the right-hand bone so the revolver mesh drops in later.
func _add_revolver_mount() -> void:
	var skel := _find_skeleton(_officer)
	if skel == null:
		return
	var idx := skel.find_bone(HAND_BONE)
	if idx < 0:
		return
	var mount := BoneAttachment3D.new()
	mount.name = "RevolverMount"
	mount.bone_name = HAND_BONE
	skel.add_child(mount)
	# When the handgun mesh exists: mount.add_child(load(REVOLVER).instantiate())


func _play_current() -> void:
	if _anim == null:
		return
	if _seq_index >= SEQUENCE.size():
		# Make sure he is settled onto the thief for the hold.
		if _turn_tween and _turn_tween.is_valid():
			_turn_tween.kill()
		_officer.rotation.y = _yaw_to(_aim_point() - _officer.global_position) + FACE_OFFSET
		_anim.play("act/idle")
		if OS.has_environment("CTT_CAPTURE_TEST"):
			print("[CUTSCENE] hold idle (aimed)")
		# Let him point the gun for a beat before the end-game overlay appears.
		get_tree().create_timer(OVERLAY_DELAY).timeout.connect(_emit_aim_ready)
		return
	var beat: String = SEQUENCE[_seq_index]
	# As he draws: gun comes out -> ease the camera into the POV and turn from the police
	# car's window onto the thief.
	if beat == "draw":
		_cam_phase = "pov"
		_turn_to_thief()
	if OS.has_environment("CTT_CAPTURE_TEST"):
		var a := _anim.get_animation("act/" + beat)
		print("[CUTSCENE] play %s len=%.2f" % [beat, a.length if a else -1.0])
	_anim.play("act/" + beat)


## Smoothly turn the officer from the police-car window onto the thief as he draws.
func _turn_to_thief() -> void:
	var target := _yaw_to(_aim_point() - _officer.global_position) + FACE_OFFSET
	var target_y := _officer.rotation.y + angle_difference(_officer.rotation.y, target)
	if _turn_tween and _turn_tween.is_valid():
		_turn_tween.kill()
	_turn_tween = create_tween()
	_turn_tween.tween_property(_officer, "rotation:y", target_y, TURN_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_clip_finished(anim_name: StringName) -> void:
	# Only advance on the current one-shot beat (ignore the looped idle, which does not
	# emit finished, but guard anyway).
	if _seq_index >= SEQUENCE.size():
		return
	if String(anim_name) != "act/" + SEQUENCE[_seq_index]:
		return
	_seq_index += 1
	_play_current()


func _emit_aim_ready() -> void:
	if _aim_emitted:
		return
	_aim_emitted = true
	aim_ready.emit()


func _set_loop(clip: String, looped: bool) -> void:
	if _anim == null or not _anim.has_animation("act/" + clip):
		return
	var a := _anim.get_animation("act/" + clip)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var f := _find_player(c)
		if f:
			return f
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var f := _find_skeleton(c)
		if f:
			return f
	return null
