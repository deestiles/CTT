extends Node3D
class_name Pedestrian
## Ambient kinematic walker. Holds a Mixamo-rigged Synty character (built by
## MixamoChar) and strolls it around a loop of sidewalk points, facing the direction
## of travel, playing "walk" while moving and "idle" while paused. Intentionally
## non-physical (no collision fights with the car) — background life, not an obstacle.

const MIXAMO_CHAR := preload("res://scripts/drive/mixamo_char.gd")
const WALK_FBX := "res://Assets/Animations/Walking_01.fbx"
const IDLE_FBX := "res://Assets/Animations/idle.fbx"
const IDLE_ALT_FBX := "res://Assets/Animations/idle (3).fbx"
const TURN_LEFT_FBX := "res://Assets/Animations/left turn 90.fbx"
const TURN_RIGHT_FBX := "res://Assets/Animations/right turn 90.fbx"
const GESTURE_FBX := "res://Assets/Animations/happy hand gesture.fbx"
const SIT_FBX := "res://Assets/Animations/Sitting_01.fbx"
const FALLEN_FBX := "res://Assets/Animations/falling idle.fbx"
const HIT_CLIPS: Array[String] = [
	"res://Assets/Animations/Getting Hit Backwards.fbx",
	"res://Assets/Animations/Hit By Car.fbx",
	"res://Assets/Animations/Hit On Side Of Body.fbx",
	"res://Assets/Animations/Hit To Side Of Body.fbx",
]

var speed: float = 1.4
var turn_speed: float = 7.0
var _points: PackedVector3Array = PackedVector3Array()
var _i: int = 0
var _char: Node3D
var _anim: AnimationPlayer
var _pause: float = 0.0
var _state: String = ""
var _activity_points: PackedInt32Array = PackedInt32Array()
var _next_action: String = ""
var _direction: int = 1
var _hit_velocity: Vector3 = Vector3.ZERO
var _hit_spin: Vector3 = Vector3.ZERO
var _airborne: bool = false
var _recover_time: float = 0.0
var _hit_cooldown: float = 0.0

## character_path: a with-skin Mixamo FBX (Assets/Animations/Character/*.fbx).
func setup(character_path: String, points: PackedVector3Array, walk_speed: float = 1.4,
		activity_points: PackedInt32Array = PackedInt32Array()) -> void:
	speed = walk_speed
	_points = points
	_activity_points = activity_points
	if _points.size() > 0:
		global_position = _points[0]
	_char = MIXAMO_CHAR.build(character_path, {
		"walk": WALK_FBX,
		"idle": IDLE_FBX,
		"idle_alt": IDLE_ALT_FBX,
		"turn_left": TURN_LEFT_FBX,
		"turn_right": TURN_RIGHT_FBX,
		"gesture": GESTURE_FBX,
		"sit": SIT_FBX,
		"fallen": FALLEN_FBX,
		"hit_0": HIT_CLIPS[0],
		"hit_1": HIT_CLIPS[1],
		"hit_2": HIT_CLIPS[2],
		"hit_3": HIT_CLIPS[3],
	})
	if _char:
		add_child(_char)
		_disable_collision(_char)
		_anim = _find_animation_player(_char)
		for hit_index in HIT_CLIPS.size():
			var hit_animation := _anim.get_animation("act/hit_%d" % hit_index)
			if hit_animation:
				hit_animation.loop_mode = Animation.LOOP_NONE
		_play("walk")
	_setup_vehicle_hitbox()

func _setup_vehicle_hitbox() -> void:
	var hitbox := Area3D.new()
	hitbox.name = "VehicleHitbox"
	hitbox.collision_layer = 2
	hitbox.collision_mask = 4
	hitbox.monitoring = true
	hitbox.monitorable = true
	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.65
	shape_node.shape = capsule
	shape_node.position.y = 0.82
	hitbox.add_child(shape_node)
	add_child(hitbox)
	hitbox.area_entered.connect(_on_vehicle_area_entered)

func _on_vehicle_area_entered(area: Area3D) -> void:
	if _airborne or _recover_time > 0.0 or _hit_cooldown > 0.0:
		return
	var car := area.get_parent()
	if car == null or not car.is_in_group("arcade_vehicle"):
		return
	var impact_velocity: Vector3 = car.get_impact_velocity()
	var impact_speed := Vector2(impact_velocity.x, impact_velocity.z).length()
	if impact_speed < 2.5:
		return
	_hit_by_vehicle(impact_velocity, impact_speed)

func _hit_by_vehicle(impact_velocity: Vector3, impact_speed: float) -> void:
	var direction := Vector3(impact_velocity.x, 0.0, impact_velocity.z).normalized()
	if direction == Vector3.ZERO:
		direction = Vector3.FORWARD
	var launch := clampf(impact_speed * 0.72, 4.0, 16.0)
	_hit_velocity = direction * launch + Vector3.UP * randf_range(4.5, 7.0)
	_hit_spin = Vector3(randf_range(-5.0, 5.0), randf_range(-2.0, 2.0), randf_range(-5.0, 5.0))
	_airborne = true
	_hit_cooldown = 1.0
	_pause = 0.0
	_next_action = ""
	var selected := "hit_%d" % randi_range(0, HIT_CLIPS.size() - 1)
	_play(selected)
	if OS.has_environment("CTT_PED_HIT_TEST"):
		print("[PED HIT] animation=%s launch=%s" % [selected, _hit_velocity])

func debug_simulate_vehicle_hit(impact_velocity: Vector3) -> void:
	_hit_by_vehicle(impact_velocity, Vector2(impact_velocity.x, impact_velocity.z).length())

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
	_hit_cooldown = maxf(0.0, _hit_cooldown - delta)
	if _airborne:
		_update_hit_flight(delta)
		return
	if _recover_time > 0.0:
		_recover_time -= delta
		_play("fallen")
		if _recover_time <= 0.0:
			rotation.x = 0.0
			rotation.z = 0.0
			_play("idle")
		return
	if _points.size() < 2:
		return
	if _pause > 0.0:
		_pause -= delta
		_play(_next_action if not _next_action.is_empty() else "idle")
		return
	var goal := _points[_i]
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var dist := to_goal.length()
	if dist < 0.25:
		var previous_dir := to_goal.normalized()
		_i = posmod(_i + _direction, _points.size())
		var next_dir := (_points[_i] - global_position).normalized()
		var turn_sign := previous_dir.cross(next_dir).y
		_next_action = "turn_left" if turn_sign > 0.05 else "turn_right"
		_pause = randf_range(0.25, 0.55)
		if _activity_points.has(_i):
			_next_action = "sit" if randf() < 0.55 else "gesture"
			_pause = randf_range(2.5, 5.5)
		elif randf() < 0.35:
			_next_action = "idle_alt" if randf() < 0.5 else "gesture"
			_pause = randf_range(0.8, 2.5)
		return
	_play("walk")
	_next_action = ""
	var dir := to_goal / dist
	if _path_blocked(dir):
		_direction *= -1
		_i = posmod(_i + _direction, _points.size())
		_next_action = "turn_left" if randf() < 0.5 else "turn_right"
		_pause = randf_range(0.45, 0.8)
		return
	global_position += dir * speed * delta
	# Smoothly face travel direction.
	var target_yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))
	_ground()

func _update_hit_flight(delta: float) -> void:
	_hit_velocity.y -= 14.0 * delta
	global_position += _hit_velocity * delta
	rotation += _hit_spin * delta
	var ground := _ground_point_below()
	if not ground.is_empty() and _hit_velocity.y <= 0.0 and global_position.y <= float(ground.position.y) + 0.08:
		var p := global_position
		p.y = float(ground.position.y)
		global_position = p
		_hit_velocity = Vector3.ZERO
		_hit_spin = Vector3.ZERO
		_airborne = false
		_recover_time = randf_range(1.0, 1.8)

func _ground_point_below() -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 3.0,
		global_position + Vector3.DOWN * 12.0)
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query)

## Lamp/signal colliders stay solid. A waist-high probe makes walkers turn back
## along their verified loop instead of ghosting through an unexpected fixture.
func _path_blocked(direction: Vector3) -> bool:
	var from := global_position + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 0.75)
	query.collision_mask = 1
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

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
