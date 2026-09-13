extends Node3D
class_name Pedestrian
## Ambient kinematic walker. Holds a Synty character prefab as its only child and
## walks it around a loop of ground points, facing the direction of travel and
## playing a walk clip if the rig ships one. Intentionally non-physical (no
## collision fights with the car) — this is background life, not an obstacle.

var speed: float = 1.4
var turn_speed: float = 7.0
var _points: PackedVector3Array = PackedVector3Array()
var _i: int = 0
var _char: Node3D
var _anim: AnimationPlayer
var _pause: float = 0.0

func setup(character_scene: PackedScene, points: PackedVector3Array, walk_speed: float = 1.4) -> void:
	speed = walk_speed
	_points = points
	if _points.size() > 0:
		global_position = _points[0]
	if character_scene:
		_char = character_scene.instantiate()
		add_child(_char)
		_disable_collision(_char)
		_anim = _find_animation_player(_char)
		_play_walk()

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var found := _find_animation_player(c)
		if found:
			return found
	return null

func _play_walk() -> void:
	if _anim == null:
		return
	var names := _anim.get_animation_list()
	if names.is_empty():
		return
	var chosen := ""
	for want in ["walk", "walking", "move", "run", "idle"]:
		for n in names:
			if String(n).to_lower().contains(want):
				chosen = n
				break
		if chosen != "":
			break
	if chosen == "":
		chosen = names[0]
	_anim.play(chosen)

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
