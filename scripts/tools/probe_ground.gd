extends Node3D
## Throwaway: instance the Demo city, let physics settle, then raycast straight down
## across a Z sweep at fixed X values to discover which surface (road vs sidewalk vs
## nothing) is where — so pedestrian loops can be laid on real sidewalk in world space.
## Run: godot --headless --path . scenes/tools/probe_ground.tscn

var _done := false

func _ready() -> void:
	var demo := (load("res://Assets/Synty/PolygonCity/Scenes/Demo.tscn") as PackedScene).instantiate()
	add_child(demo)

func _physics_process(_delta: float) -> void:
	if _done:
		return
	_done = true
	# Wait a couple of physics frames for colliders to register, then probe.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	# Sweep along X on the two sidewalk strips found at X=-30 (north z=-13, south z=2.5)
	# to confirm they run continuously (a strip we can lay a stroll loop on).
	for z in [-13.0, 2.5]:
		print("=== Z = %.1f  (x sweep, sidewalk strip check) ===" % z)
		for xi in range(-10, -61, -2):
			var x := float(xi)
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 40.0, z), Vector3(x, -20.0, z))
			var hit := space.intersect_ray(q)
			var nm := "(none)"
			var yy := 0.0
			if hit:
				yy = float(hit.position.y)
				if hit.collider is Node:
					nm = _surface_name(hit.collider as Node)
			print("  x=%5.0f  y=%6.2f  %s" % [x, yy, nm])
	get_tree().quit()

## Climb to a meaningfully named ancestor (the tile), skipping StaticBody wrappers.
func _surface_name(n: Node) -> String:
	var cur := n
	for _i in 6:
		var nm := cur.name
		if nm.begins_with("SM_Env") or nm.begins_with("SM_Prop"):
			return nm
		if cur.get_parent() == null:
			break
		cur = cur.get_parent()
	return n.name
