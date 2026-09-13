extends Node3D
class_name Pedestrian
## Ambient kinematic walker. Holds a Mixamo-rigged Synty character (built by
## MixamoChar) and strolls it around a loop of sidewalk points, facing the direction
## of travel, playing "walk" while moving and "idle" while paused. Intentionally
## non-physical (no collision fights with the car) — background life, not an obstacle.

const MIXAMO_CHAR := preload("res://scripts/drive/mixamo_char.gd")
const WALK_FBX := "res://Assets/Animations/Walking_01.fbx"
const IDLE_FBX := "res://Assets/Animations/idle.fbx"

var speed: float = 1.4
var turn_speed: float = 7.0
var _points: PackedVector3Array = PackedVector3Array()
var _i: int = 0
var _char: Node3D
var _anim: AnimationPlayer
var _pause: float = 0.0
var _state: String = ""

## character_path: a with-skin Mixamo FBX (Assets/Animations/Character/*.fbx).
func setup(character_path: String, points: PackedVector3Array, walk_speed: float = 1.4) -> void:
	speed = walk_speed
	_points = points
	if _points.size() > 0:
		global_position = _points[0]
	_char = MIXAMO_CHAR.build(character_path, {"walk": WALK_FBX, "idle": IDLE_FBX})
	if _char:
		add_child(_char)
		_disable_collision(_char)
		_anim = _find_animation_player(_char)
		_play("walk")

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var found := _find_animation_player(c)
		if found:
			return found
	return null

## Play an "act/<name>" clip, ignoring repeats. Falls back gracefully if absent.
func _play(name: String) -> void:
	if _anim == null or _state == name:
		return
	var key := "act/%s" % name
	if _anim.has_animation(key):
		_anim.play(key)
		_state = name

func _disable_collision(node: Node) -> void:
	for c in node.get_children():
		if c is CollisionObject3D:
			(c as CollisionObject3D).collision_layer = 0
			(c as CollisionObject3D).collision_mask = 0
		_disable_collision(c)

func _physics_process(delta: float) -> void:
	if _points.size() < 2:
		return
	if _pause > 0.0:
		_pause -= delta
		_play("idle")
		return
	var goal := _points[_i]
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var dist := to_goal.length()
	if dist < 0.25:
		_i = (_i + 1) % _points.size()
		if randf() < 0.25:
			_pause = randf_range(0.6, 2.0)   # brief loiter, feels less robotic
		return
	_play("walk")
	var dir := to_goal / dist
	global_position += dir * speed * delta
	# Smoothly face travel direction.
	var target_yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))
	_ground()

## Seat feet on whatever sidewalk/road is beneath, at any world height.
func _ground() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 4.0
	var to := global_position + Vector3.DOWN * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(q)
	if hit:
		var p := global_position
		p.y = float(hit.position.y)
		global_position = p
