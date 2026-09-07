class_name ResidentialHouseBuilder
extends Node3D

const TinyTreatsHouse = preload("res://addons/tiny_treats_homely_house_set/Assets/gltf/house.gltf")
const TinyTreatsFoliageA = preload("res://addons/tiny_treats_homely_house_set/Assets/gltf/foliage_A.gltf")
const TinyTreatsFoliageB = preload("res://addons/tiny_treats_homely_house_set/Assets/gltf/foliage_B.gltf")
const TinyTreatsTree = preload("res://addons/tiny_treats_homely_house_set/Assets/gltf/tree.gltf")
const TinyTreatsTreeLarge = preload("res://addons/tiny_treats_homely_house_set/Assets/gltf/tree_large.gltf")
const WALL_COLORS := [
	Color("#d98f70"), Color("#e2bd78"), Color("#86a8b8"), Color("#a795bd"),
	Color("#8fb28f"), Color("#d7a0a0"), Color("#c6a57c"), Color("#83a3a0")
]
const ROOF_COLORS := [Color("#59494a"), Color("#73514a"), Color("#46535e"), Color("#66526d")]
const TRIM := Color("#f1eadb")
const GLASS := Color("#79b7cc")

var walking_people: Array[Node3D] = []
var walking_origins: Array[Vector3] = []
var walking_axes: Array[Vector3] = []
var walking_phases: Array[float] = []


func setup() -> void:
	name = "ResidentialHouses"
	add_grid_sidewalks()
	add_grid_street_lamps()
	# Two homes per block, well inside the scenery area and at least 20 m
	# from an intersection center. Roads run on x/z = -92, 0, and 92.
	var placements := [
		[Vector3(-64, 0, -27), Vector3(0, 0, 1)],
		[Vector3(-28, 0, -65), Vector3(0, 0, -1)],
		[Vector3(28, 0, -27), Vector3(0, 0, 1)],
		[Vector3(65, 0, -64), Vector3(1, 0, 0)],
		[Vector3(-65, 0, 28), Vector3(-1, 0, 0)],
		[Vector3(-28, 0, 65), Vector3(0, 0, 1)],
		[Vector3(28, 0, 65), Vector3(0, 0, 1)],
		[Vector3(65, 0, 28), Vector3(1, 0, 0)],
	]
	for index in placements.size():
		if index < 3:
			add_tiny_treats_house(placements[index][0], placements[index][1], index)
		else:
			add_house(placements[index][0], placements[index][1], index)
	add_property_landscaping(placements)
	add_sidewalk_pedestrians()


func _process(_delta: float) -> void:
	var elapsed := float(Time.get_ticks_msec()) / 1000.0
	for index in walking_people.size():
		var person := walking_people[index]
		var phase := elapsed * (0.11 + float(index) * 0.012) + walking_phases[index]
		var offset := sin(phase) * 7.0
		person.global_position = walking_origins[index] + walking_axes[index] * offset
		var travel_sign := 1.0 if cos(phase) >= 0.0 else -1.0
		person.look_at(person.global_position + walking_axes[index] * travel_sign, Vector3.UP)
		var visual := person.get_node("Visual") as Node3D
		visual.position.y = absf(sin(phase * 7.0)) * 0.035
		var swing := sin(phase * 7.0) * 18.0
		var left_leg := visual.get_node("LegLeft") as Node3D
		var right_leg := visual.get_node("LegRight") as Node3D
		left_leg.rotation_degrees.x = swing
		right_leg.rotation_degrees.x = -swing


func add_sidewalk_pedestrians() -> void:
	var pedestrian_root := Node3D.new()
	pedestrian_root.name = "SidewalkPedestrians"
	add_child(pedestrian_root)
	var pedestrian_data := [
		[Vector3(-50, 0.3, -12), Vector3.RIGHT, true],
		[Vector3(42, 0.3, -80), Vector3.RIGHT, true],
		[Vector3(-12, 0.3, 40), Vector3.FORWARD, true],
		[Vector3(80, 0.3, 50), Vector3.FORWARD, true],
		[Vector3(-40, 0.3, 80), Vector3.RIGHT, false],
		[Vector3(50, 0.3, 12), Vector3.LEFT, false],
	]
	for index in pedestrian_data.size():
		var person := create_person(index)
		pedestrian_root.add_child(person)
		person.global_position = pedestrian_data[index][0]
		person.look_at(person.global_position + Vector3(pedestrian_data[index][1]), Vector3.UP)
		if bool(pedestrian_data[index][2]):
			walking_people.append(person)
			walking_origins.append(person.global_position)
			walking_axes.append(Vector3(pedestrian_data[index][1]).normalized())
			walking_phases.append(float(index) * 1.37)


func create_person(index: int) -> Node3D:
	var person := Node3D.new()
	person.name = "Pedestrian_%02d" % (index + 1)
	var visual := Node3D.new()
	visual.name = "Visual"
	person.add_child(visual)
	var shirt_colors := [Color("#4e9fc1"), Color("#cf665f"), Color("#d7aa4d"), Color("#8067a2"), Color("#4f8d68"), Color("#cc7fa0")]
	var skin_colors := [Color("#e0ae87"), Color("#9c674e"), Color("#c98c68"), Color("#754b3b")]
	add_capsule(visual, 0.27, 0.92, shirt_colors[index % shirt_colors.size()], Vector3.UP * 1.08, "Torso")
	add_sphere(visual, 0.28, skin_colors[index % skin_colors.size()], Vector3.UP * 1.75, "Head")
	add_cylinder(visual, 0.085, 0.68, Color("#28384b"), Vector3(-0.13, 0.48, 0)).name = "LegLeft"
	add_cylinder(visual, 0.085, 0.68, Color("#28384b"), Vector3(0.13, 0.48, 0)).name = "LegRight"
	return person


func add_property_landscaping(placements: Array) -> void:
	var landscape_root := Node3D.new()
	landscape_root.name = "PropertyLandscaping"
	add_child(landscape_root)
	for index in placements.size():
		var house_position: Vector3 = placements[index][0]
		var street_direction: Vector3 = placements[index][1]
		var side := Vector3(-street_direction.z, 0, street_direction.x)
		# Bushes frame the front yard but remain behind the sidewalk boundary.
		for side_sign in [-1.0, 1.0]:
			var foliage_scene: PackedScene = TinyTreatsFoliageA if (index + int(side_sign)) % 2 == 0 else TinyTreatsFoliageB
			var bush := foliage_scene.instantiate() as Node3D
			bush.name = "Bush_%02d_%s" % [index + 1, "L" if side_sign < 0 else "R"]
			landscape_root.add_child(bush)
			bush.global_position = house_position + street_direction * 7.0 + side * side_sign * 3.2 + Vector3.UP * 0.16
			bush.rotation.y = deg_to_rad(float((index * 47 + int(side_sign) * 19) % 360))
			bush.scale = Vector3.ONE * 2.35
		# Four trees are set behind alternating houses, comfortably inside lots.
		if index % 2 == 0:
			var tree_scene: PackedScene = TinyTreatsTreeLarge if index % 4 == 0 else TinyTreatsTree
			var tree := tree_scene.instantiate() as Node3D
			tree.name = "PropertyTree_%02d" % (index + 1)
			landscape_root.add_child(tree)
			tree.global_position = house_position - street_direction * 8.0 + side * (4.5 if index % 4 == 0 else -4.5) + Vector3.UP * 0.45
			tree.rotation.y = deg_to_rad(float((index * 61) % 360))
			tree.scale = Vector3.ONE * (1.5 if index % 4 == 0 else 1.65)


func add_grid_sidewalks() -> void:
	var sidewalk_root := Node3D.new()
	sidewalk_root.name = "ResidentialSidewalks"
	add_child(sidewalk_root)
	var concrete := Color("#aeb5b6")
	var curb_color := Color("#c5cbca")
	# Four 4 m lanes plus two 2 m shoulders make the road 20 m wide. Sidewalks
	# therefore begin exactly 10 m from each road centerline. Their 68 m spans
	# meet at the corners without entering the intersection road surface.
	for block_x in [-46.0, 46.0]:
		for block_z in [-46.0, 46.0]:
			for z_side in [-1.0, 1.0]:
				var sidewalk_z: float = float(block_z) + float(z_side) * 34.0
				add_box(sidewalk_root, Vector3(64.0, 0.28, 4.0), concrete, Vector3(block_x, 0.14, sidewalk_z))
				var curb_z: float = sidewalk_z + float(z_side) * 2.12
				add_box(sidewalk_root, Vector3(68.0, 0.42, 0.28), curb_color, Vector3(block_x, 0.21, curb_z))
			for x_side in [-1.0, 1.0]:
				var sidewalk_x: float = float(block_x) + float(x_side) * 34.0
				add_box(sidewalk_root, Vector3(4.0, 0.28, 64.0), concrete, Vector3(sidewalk_x, 0.14, block_z))
				var curb_x: float = sidewalk_x + float(x_side) * 2.12
				add_box(sidewalk_root, Vector3(0.28, 0.42, 68.0), curb_color, Vector3(curb_x, 0.21, block_z))
			# Dedicated tiles fill each corner exactly once, avoiding coplanar
			# overlapping meshes and the diagonal flicker/seam they produced.
			for corner_x in [-1.0, 1.0]:
				for corner_z in [-1.0, 1.0]:
					add_box(
						sidewalk_root,
						Vector3(4.0, 0.28, 4.0),
						concrete,
						Vector3(float(block_x) + float(corner_x) * 34.0, 0.14, float(block_z) + float(corner_z) * 34.0)
					)


func add_grid_street_lamps() -> void:
	var lamp_root := Node3D.new()
	lamp_root.name = "ResidentialStreetLamps"
	add_child(lamp_root)
	for block_x in [-46.0, 46.0]:
		for block_z in [-46.0, 46.0]:
			# Two lamps per horizontal block edge, on grass behind the sidewalk.
			for z_side in [-1.0, 1.0]:
				var outward := Vector3(0, 0, float(z_side))
				for along in [-18.0, 18.0]:
					add_street_lamp(lamp_root, Vector3(float(block_x) + along, 0, float(block_z) + float(z_side) * 31.0), outward)
			# Two lamps per vertical block edge, also safely away from corners.
			for x_side in [-1.0, 1.0]:
				var outward := Vector3(float(x_side), 0, 0)
				for along in [-18.0, 18.0]:
					add_street_lamp(lamp_root, Vector3(float(block_x) + float(x_side) * 31.0, 0, float(block_z) + along), outward)


func add_street_lamp(parent: Node3D, position: Vector3, outward: Vector3) -> void:
	var lamp := Node3D.new()
	lamp.name = "StreetLamp_%03d" % parent.get_child_count()
	parent.add_child(lamp)
	lamp.global_position = position
	var dark_metal := Color("#202d34")
	add_cylinder(lamp, 0.18, 9.2, dark_metal, Vector3.UP * 4.6)
	# The arm reaches from the grass over the sidewalk toward the street.
	var arm := add_box(lamp, Vector3(0.24, 0.24, 3.0), dark_metal, Vector3.UP * 9.08 + outward * 1.45)
	arm.look_at(arm.global_position + outward, Vector3.UP)
	var fixture := add_box(lamp, Vector3(0.9, 0.3, 0.58), Color("#35444a"), Vector3.UP * 8.9 + outward * 2.9)
	fixture.look_at(fixture.global_position + outward, Vector3.UP)
	var lens := add_box(lamp, Vector3(0.68, 0.1, 0.4), Color("#ffe7a8"), Vector3.UP * 8.72 + outward * 2.9)
	lens.name = "StreetLampLens"
	lens.material_override = make_glow_material(Color("#ffe7a8"), 2.2)
	var light := SpotLight3D.new()
	light.name = "SidewalkStreetLight"
	lamp.add_child(light)
	light.position = Vector3.UP * 8.68 + outward * 2.85
	light.light_color = Color("#ffe2a0")
	light.light_energy = 3.2
	light.spot_range = 24.0
	light.spot_angle = 52.0
	light.shadow_enabled = false
	light.look_at(lamp.global_position + outward * 5.0 + Vector3.UP * 0.1, Vector3.UP)


func add_tiny_treats_house(position: Vector3, street_direction: Vector3, index: int) -> void:
	var house := TinyTreatsHouse.instantiate() as Node3D
	house.name = "TinyTreatsHouse_%02d" % (index + 1)
	add_child(house)
	house.global_position = position
	# Tiny Treats authors the front door on local +Z; Godot look_at points -Z.
	house.look_at(position - street_direction, Vector3.UP)
	house.scale = Vector3.ONE * 1.70


func add_house(position: Vector3, street_direction: Vector3, index: int) -> void:
	var house := Node3D.new()
	house.name = "House_%02d" % (index + 1)
	add_child(house)
	house.global_position = position
	# The model's facade is local -Z.
	house.look_at(position + street_direction, Vector3.UP)
	var width := 8.5 + float(index % 3) * 0.7
	var depth := 8.0 + float((index + 1) % 2) * 0.8
	var wall_color: Color = WALL_COLORS[index % WALL_COLORS.size()]
	add_box(house, Vector3(width, 4.5, depth), wall_color, Vector3.UP * 2.25)
	# Two broad roof slabs make a readable gable without detailed textures.
	add_roof_slab(house, Vector3(width * 0.58, 0.48, depth + 0.8), ROOF_COLORS[index % ROOF_COLORS.size()], Vector3(-width * 0.22, 5.32, 0), -25.0)
	add_roof_slab(house, Vector3(width * 0.58, 0.48, depth + 0.8), ROOF_COLORS[index % ROOF_COLORS.size()], Vector3(width * 0.22, 5.32, 0), 25.0)
	add_box(house, Vector3(1.25, 2.35, 0.16), Color("#76513d"), Vector3(0, 1.18, -depth * 0.51))
	add_box(house, Vector3(0.18, 0.18, 0.08), Color("#e9bf55"), Vector3(0.42, 1.2, -depth * 0.61))
	for side in [-1.0, 1.0]:
		add_box(house, Vector3(1.45, 1.15, 0.14), TRIM, Vector3(side * width * 0.28, 2.35, -depth * 0.515))
		add_box(house, Vector3(1.15, 0.86, 0.08), GLASS, Vector3(side * width * 0.28, 2.35, -depth * 0.60))
	# Small foundations keep the houses visually grounded without collision.
	add_box(house, Vector3(width + 0.6, 0.28, depth + 0.6), wall_color.darkened(0.22), Vector3.UP * 0.14)


func add_roof_slab(parent: Node3D, size: Vector3, color: Color, position: Vector3, angle: float) -> void:
	var roof := add_box(parent, size, color, position)
	roof.rotation_degrees.z = angle


func add_box(parent: Node3D, size: Vector3, color: Color, position: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = make_material(color)
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
	return instance


func add_cylinder(parent: Node3D, radius: float, height: float, color: Color, position: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.18
	mesh.height = height
	mesh.radial_segments = 10
	mesh.material = make_material(color)
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
	return instance


func add_capsule(parent: Node3D, radius: float, height: float, color: Color, position: Vector3, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = make_material(color)
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
	return instance


func add_sphere(parent: Node3D, radius: float, color: Color, position: Vector3, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = make_material(color)
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
	return instance


func make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	return material


func make_glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := make_material(color)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
