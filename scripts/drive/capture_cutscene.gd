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
	"exit": "res://Assets/Animations/Exiting Car.fbx",
	"draw": "res://Assets/Animations/Drawing Gun.fbx",
	"aim": "res://Assets/Animations/Aiming.fbx",
	"idle": "res://Assets/Animations/pistol idle.fbx",
}
# One-shot beats (played once, in order); "idle" is the looped hold afterwards.
const SEQUENCE := ["exit", "draw", "aim"]

# The Synty/Mixamo right-hand bone (verified: 48-bone skeleton, bone 26).
const HAND_BONE := "Hand_R"

# Placement of the officer relative to the police car, in the car's local frame:
# out to the driver side and slightly back toward the door. Tune SIDE sign if the
# officer appears on the passenger side.
const SIDE_OFFSET := 1.45
const BACK_OFFSET := 0.15
# The imported Synty characters face +Z in their own space; look_at aims -Z, so we spin
# 180 deg to point the officer's front (and the revolver) at the target.
const FACE_FLIP := true

# Safety net: if the clip chain never reports finished (e.g. a missing clip), reveal the
# capture overlay anyway after this many seconds so the player is never left frozen.
const WATCHDOG_SECONDS := 12.0

var _officer: Node3D
var _anim: AnimationPlayer
var _seq_index: int = 0
var _aim_emitted: bool = false


## Build the cutscene, add it under `parent`, and begin the sequence. `police_car` and
## `thief_car` are the live ArcadeCar nodes. Returns the CaptureCutscene node.
static func start(parent: Node, police_car: Node3D, thief_car: Node3D) -> CaptureCutscene:
	var cs := CaptureCutscene.new()
	cs.name = "CaptureCutscene"
	parent.add_child(cs)
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
	_seq_index = 0
	_play_current()
	# Watchdog against a stalled clip chain.
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(_emit_aim_ready)


## True once the officer has been instanced (used by headless capture verification).
func has_officer() -> bool:
	return _officer != null


func _is_female() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs and "player_character" in gs:
		return String(gs.player_character).to_lower() == "female"
	return false


## Seat the officer's feet on the road beside the driver door and turn to face the thief.
func _place_officer(police_car: Node3D, thief_car: Node3D) -> void:
	var xf := police_car.global_transform
	var side := xf.basis.x.normalized()           # car local +X
	var back := xf.basis.z.normalized()            # car local +Z (rearward; forward is -Z)
	var foot_y := _road_y(police_car)
	var pos := police_car.global_position + side * SIDE_OFFSET + back * BACK_OFFSET
	pos.y = foot_y
	_officer.global_position = pos
	# Face the thief on the horizontal plane only.
	var target := thief_car.global_position
	target.y = pos.y
	if not pos.is_equal_approx(target):
		_officer.look_at(target, Vector3.UP)
		if FACE_FLIP:
			_officer.rotate_y(PI)


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
		_anim.play("act/idle")
		if OS.has_environment("CTT_CAPTURE_TEST"):
			print("[CUTSCENE] hold idle (aimed)")
		_emit_aim_ready()
		return
	if OS.has_environment("CTT_CAPTURE_TEST"):
		var a := _anim.get_animation("act/" + SEQUENCE[_seq_index])
		print("[CUTSCENE] play %s len=%.2f" % [SEQUENCE[_seq_index], a.length if a else -1.0])
	_anim.play("act/" + SEQUENCE[_seq_index])


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
