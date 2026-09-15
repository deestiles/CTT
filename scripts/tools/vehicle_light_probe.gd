extends Node
## Mesh/atlas diagnostic for per-vehicle lamp calibration.

const VEHICLES: Array[String] = [
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Police_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Sedan_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Taxi_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Small_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Van_01.tscn",
	"res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Muscle_01.tscn",
]
const ATLAS := preload("res://Assets/Synty/PolygonCity/Textures/PolygonCity_01_A.png")

func _ready() -> void:
	var image := ATLAS.get_image()
	if image.is_compressed():
		image.decompress()
	for path in VEHICLES:
		var root := (load(path) as PackedScene).instantiate()
		var body := root as MeshInstance3D
		if body == null or body.mesh == null:
			print("[VEHICLE LAMP PROBE] missing body: ", path)
			root.free()
			continue
		var bounds := body.get_aabb()
		var front: Array[Vector3] = []
		var rear: Array[Vector3] = []
		var rear_white: Array[Vector3] = []
		for surface in body.mesh.get_surface_count():
			var arrays := body.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for i in mini(vertices.size(), uvs.size()):
				var p := vertices[i]
				var uv := uvs[i]
				var px := clampi(int(uv.x * float(image.get_width() - 1)), 0, image.get_width() - 1)
				var py := clampi(int(uv.y * float(image.get_height() - 1)), 0, image.get_height() - 1)
				var color := image.get_pixel(px, py).srgb_to_linear()
				var front_zone := p.z > bounds.position.z + bounds.size.z * 0.68
				var rear_zone := p.z < bounds.position.z + bounds.size.z * 0.30
				var pale := color.r > 0.34 and color.g > 0.30 and color.b > 0.22
				var red := color.r > 0.12 and color.r > color.g * 1.8 and color.r > color.b * 1.5
				if front_zone and pale and p.y > 0.35:
					front.append(p)
				if rear_zone and red and p.y > 0.35:
					rear.append(p)
				if rear_zone and pale and p.y > 0.35:
					rear_white.append(p)
		print("[VEHICLE LAMP PROBE] %s bounds=%s front=%s rear=%s" % [body.name, bounds, _range(front), _range(rear)])
		print("  front bins: ", _top_bins(front))
		print("  rear bins:  ", _top_bins(rear))
		print("  reverse candidates: ", _range(rear_white))
		print("  reverse bins: ", _top_bins(rear_white))
		root.free()
	get_tree().quit()

func _range(points: Array[Vector3]) -> String:
	if points.is_empty():
		return "none"
	var low := points[0]
	var high := points[0]
	for p in points:
		low = low.min(p)
		high = high.max(p)
	return "n=%d min=%s max=%s" % [points.size(), low, high]

func _top_bins(points: Array[Vector3]) -> String:
	var counts := {}
	for p in points:
		var key := Vector3(round(p.x * 5.0) / 5.0, round(p.y * 5.0) / 5.0, round(p.z * 5.0) / 5.0)
		counts[key] = int(counts.get(key, 0)) + 1
	var entries: Array = []
	for key in counts:
		entries.append([key, counts[key]])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	var result: Array[String] = []
	for i in mini(12, entries.size()):
		result.append("%s:%d" % [entries[i][0], entries[i][1]])
	return ", ".join(result)
