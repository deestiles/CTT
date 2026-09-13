extends SceneTree
## Throwaway diagnostic: seat heights. Instances prefabs into a live tree so
## mesh AABBs are valid, then reports the road's visual top surface and the
## car's lowest visual point (to explain any float).
func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	for p in [
		"res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Road_01.tscn",
		"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Sedan_01.tscn",
		"res://Assets/Synty/PolygonCity/Prefabs/Characters/Character_Male_Jacket.tscn",
	]:
		var ps: PackedScene = load(p)
		var inst: Node3D = ps.instantiate()
		root.add_child(inst)
		var minv := 1e9
		var maxv := -1e9
		for mi in _all_mesh(inst):
			var ab: AABB = mi.get_aabb()
			var xf: Transform3D = mi.global_transform
			for i in 8:
				var corner: Vector3 = xf * (ab.position + Vector3(
					ab.size.x * (i & 1), ab.size.y * ((i >> 1) & 1), ab.size.z * ((i >> 2) & 1)))
				minv = min(minv, corner.y)
				maxv = max(maxv, corner.y)
		print("%s -> visual min.y=%.3f max.y=%.3f" % [p.get_file(), minv, maxv])
		inst.free()
	quit()

func _all_mesh(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_mesh(c))
	return out
