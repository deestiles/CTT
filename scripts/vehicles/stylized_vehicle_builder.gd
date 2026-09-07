class_name StylizedVehicleBuilder
extends RefCounted

const POLICE_BLUE := Color("#3b82ff")
const SIREN_RED := Color("#ff3b4e")
const GLASS := Color("#13293a")
const RUBBER := Color("#090c11")
const METAL := Color("#c8d1d8")


static func build(actor: Node3D, profile: String, primary: Color, police: bool, upgrades: Dictionary = {}) -> void:
	for legacy_name in ["base_body", "cabin", "wheels_back", "wheels_front", "ToyTrim", "PoliceLightbar", "PushBumper", "StylizedVehicle"]:
		var legacy := actor.get_node_or_null(legacy_name)
		if legacy:
			if legacy_name in ["base_body", "cabin", "wheels_back", "wheels_front"]:
				legacy.visible = false
			else:
				legacy.queue_free()

	var root := Node3D.new()
	root.name = "StylizedVehicle"
	actor.add_child(root)
	var spec := profile_spec(profile)
	var width: float = spec.width
	var length: float = spec.length
	var body_height: float = spec.body_height
	var cabin_length: float = spec.cabin_length
	var cabin_offset: float = spec.cabin_offset
	var ride_height: float = spec.ride_height
	var secondary := primary.lightened(0.16)

	# Layered blocks create a chunky painted-toy silhouette while the original
	# RoadActor collision and lane agent remain untouched.
	box(root, Vector3(width, body_height, length), primary, Vector3(0.0, ride_height + body_height * 0.5, 0.0), 0.34)
	box(root, Vector3(width * 0.93, 0.2, length * 0.9), secondary, Vector3(0.0, ride_height + body_height + 0.02, 0.0), 0.3)
	box(root, Vector3(width * 0.76, spec.cabin_height, cabin_length), GLASS, Vector3(0.0, ride_height + body_height + spec.cabin_height * 0.5, cabin_offset), 0.2)
	box(root, Vector3(width * 0.68, 0.12, cabin_length * 0.86), secondary, Vector3(0.0, ride_height + body_height + spec.cabin_height + 0.03, cabin_offset), 0.28)
	box(root, Vector3(width * 0.9, 0.18, length * 0.2), primary.darkened(0.08), Vector3(0.0, ride_height + body_height * 0.66, -length * 0.42), 0.34)
	box(root, Vector3(width * 0.92, 0.16, length * 0.18), primary.darkened(0.14), Vector3(0.0, ride_height + body_height * 0.58, length * 0.43), 0.4)

	if police:
		box(root, Vector3(width + 0.03, 0.11, length * 0.18), Color("#eef5f7"), Vector3(0.0, ride_height + body_height * 0.62, 0.05), 0.35)
		lightbar(root, Vector3(0.0, ride_height + body_height + spec.cabin_height + 0.18, cabin_offset))

	var wheel_radius: float = spec.wheel_radius + float(upgrades.get("handling", 0)) * 0.025
	var wheel_width := 0.28 + float(upgrades.get("handling", 0)) * 0.035
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			wheel(root, Vector3(x_sign * (width * 0.52), ride_height + wheel_radius, z_sign * length * 0.31), wheel_radius, wheel_width)

	for x_sign in [-1.0, 1.0]:
		var front_light := glow_box(root, Vector3(0.42, 0.16, 0.08), Color("#fff1b8"), Vector3(x_sign * width * 0.28, ride_height + body_height * 0.62, -length * 0.505))
		front_light.name = "HeadlightLens"
		var tail_light := glow_box(root, Vector3(0.5, 0.2, 0.12), SIREN_RED, Vector3(x_sign * width * 0.3, ride_height + body_height * 0.64, length * 0.515))
		tail_light.name = "TailLight"
		var reverse_light := glow_box(root, Vector3(0.25, 0.16, 0.12), Color("#dce8ef"), Vector3(x_sign * width * 0.11, ride_height + body_height * 0.64, length * 0.518))
		reverse_light.name = "ReverseLight"
		var reverse_material := reverse_light.mesh.material as StandardMaterial3D
		reverse_material.emission_energy_multiplier = 0.08

	add_profile_parts(root, profile, spec, primary, ride_height, body_height)
	add_upgrade_parts(root, spec, primary, police, upgrades, ride_height, body_height)
	if bool(upgrades.get("headlights", false)):
		add_headlights(root, spec, ride_height, body_height)


static func profile_spec(profile: String) -> Dictionary:
	match profile:
		"interceptor":
			return {"width": 2.02, "length": 4.65, "body_height": 0.58, "cabin_length": 1.82, "cabin_height": 0.58, "cabin_offset": 0.18, "ride_height": 0.28, "wheel_radius": 0.34}
		"muscle":
			return {"width": 2.12, "length": 4.78, "body_height": 0.66, "cabin_length": 1.72, "cabin_height": 0.56, "cabin_offset": 0.38, "ride_height": 0.3, "wheel_radius": 0.37}
		"van":
			return {"width": 2.16, "length": 4.92, "body_height": 0.82, "cabin_length": 2.72, "cabin_height": 0.92, "cabin_offset": 0.28, "ride_height": 0.34, "wheel_radius": 0.38}
		"compact":
			return {"width": 1.82, "length": 3.82, "body_height": 0.62, "cabin_length": 1.92, "cabin_height": 0.68, "cabin_offset": 0.08, "ride_height": 0.28, "wheel_radius": 0.32}
		_:
			return {"width": 2.02, "length": 4.5, "body_height": 0.64, "cabin_length": 2.08, "cabin_height": 0.66, "cabin_offset": 0.2, "ride_height": 0.3, "wheel_radius": 0.35}


static func add_profile_parts(root: Node3D, profile: String, spec: Dictionary, primary: Color, ride_height: float, body_height: float) -> void:
	var width: float = spec.width
	var length: float = spec.length
	match profile:
		"interceptor":
			box(root, Vector3(width * 0.78, 0.1, 0.42), primary.darkened(0.2), Vector3(0.0, ride_height + body_height + 0.22, length * 0.44), 0.28)
		"muscle":
			box(root, Vector3(width * 0.48, 0.12, length * 0.42), primary.lightened(0.12), Vector3(0.0, ride_height + body_height + 0.18, -length * 0.23), 0.25)
			box(root, Vector3(width * 0.84, 0.12, 0.28), primary.darkened(0.25), Vector3(0.0, ride_height + body_height + 0.28, length * 0.43), 0.3)
		"van":
			box(root, Vector3(width * 0.72, 0.1, 0.7), primary.lightened(0.2), Vector3(0.0, ride_height + body_height + spec.cabin_height + 0.12, 0.7), 0.35)
		"compact":
			box(root, Vector3(width * 0.72, 0.1, 0.24), primary.darkened(0.18), Vector3(0.0, ride_height + body_height + 0.18, length * 0.43), 0.32)


static func add_upgrade_parts(root: Node3D, spec: Dictionary, primary: Color, police: bool, upgrades: Dictionary, ride_height: float, body_height: float) -> void:
	var width: float = spec.width
	var length: float = spec.length
	var armor := int(upgrades.get("armor", 0))
	var engine := int(upgrades.get("engine", 0))
	var nitro := int(upgrades.get("nitro", 0))
	var electronics := int(upgrades.get("electronics", 0))
	if police or armor > 0:
		var bumper_scale := 1.0 + armor * 0.08
		box(root, Vector3(width * bumper_scale, 0.16, 0.16), Color("#101820"), Vector3(0.0, ride_height + 0.42, -length * 0.53), 0.22, 0.72)
		box(root, Vector3(0.14, 0.58, 0.14), Color("#101820"), Vector3(-width * 0.34, ride_height + 0.68, -length * 0.52), 0.22, 0.72)
		box(root, Vector3(0.14, 0.58, 0.14), Color("#101820"), Vector3(width * 0.34, ride_height + 0.68, -length * 0.52), 0.22, 0.72)
	if engine > 0:
		box(root, Vector3(width * 0.34, 0.1 + engine * 0.025, length * 0.22), primary.lightened(0.22), Vector3(0.0, ride_height + body_height + 0.22, -length * 0.28), 0.25)
	if nitro > 0:
		for x_sign in [-1.0, 1.0]:
			glow_box(root, Vector3(0.15, 0.15, 0.28), POLICE_BLUE, Vector3(x_sign * width * 0.22, ride_height + 0.32, length * 0.54))
	if electronics > 0:
		box(root, Vector3(0.05, 0.52 + electronics * 0.08, 0.05), METAL, Vector3(width * 0.26, ride_height + body_height + spec.cabin_height + 0.34, spec.cabin_offset + 0.45), 0.3, 0.75)


static func lightbar(root: Node3D, position: Vector3) -> void:
	box(root, Vector3(1.55, 0.08, 0.2), Color("#121923"), position, 0.3)
	glow_box(root, Vector3(0.68, 0.14, 0.22), POLICE_BLUE, position + Vector3(-0.4, 0.08, 0.0))
	glow_box(root, Vector3(0.68, 0.14, 0.22), SIREN_RED, position + Vector3(0.4, 0.08, 0.0))


static func add_headlights(root: Node3D, spec: Dictionary, ride_height: float, body_height: float) -> void:
	for x_sign in [-1.0, 1.0]:
		var light := SpotLight3D.new()
		light.name = "Headlight"
		light.position = Vector3(x_sign * float(spec.width) * 0.28, ride_height + body_height * 0.62, -float(spec.length) * 0.49)
		light.rotation_degrees.x = -6.0
		light.light_color = Color("#fff3cf")
		light.light_energy = 22.0
		light.spot_range = 65.0
		light.spot_angle = 42.0
		light.spot_attenuation = 0.82
		light.shadow_enabled = false
		# Time-of-day code explicitly enables these at dusk/night.
		light.visible = false
		root.add_child(light)


static func update_lights(actor: Node3D, reversing: bool, braking: bool, night: bool) -> void:
	var visual := actor.get_node_or_null("StylizedVehicle")
	if not visual:
		return
	for node in visual.find_children("ReverseLight*", "MeshInstance3D", true, false):
		var reverse_light := node as MeshInstance3D
		var reverse_material := reverse_light.mesh.material as StandardMaterial3D
		if reverse_material:
			reverse_material.emission = Color("#f5fbff") if reversing else Color("#8c9aa4")
			reverse_material.emission_energy_multiplier = 5.0 if reversing else 0.08
	for node in visual.find_children("TailLight*", "MeshInstance3D", true, false):
		var tail := node as MeshInstance3D
		var tail_material := tail.mesh.material as StandardMaterial3D
		if tail_material:
			tail_material.emission_energy_multiplier = 4.2 if braking else (2.2 if night else 1.2)
	for node in visual.find_children("Headlight*", "SpotLight3D", true, false):
		var headlight := node as SpotLight3D
		headlight.visible = night
	for node in visual.find_children("HeadlightLens*", "MeshInstance3D", true, false):
		var lens := node as MeshInstance3D
		var lens_material := lens.mesh.material as StandardMaterial3D
		if lens_material:
			lens_material.emission_energy_multiplier = 2.8 if night else 0.0


static func wheel(root: Node3D, position: Vector3, radius: float, width: float) -> void:
	var tire := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.material = material(RUBBER, 0.84)
	tire.mesh = mesh
	tire.position = position
	tire.rotation_degrees.z = 90.0
	root.add_child(tire)
	var rim := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = radius * 0.56
	rim_mesh.bottom_radius = radius * 0.56
	rim_mesh.height = width + 0.02
	rim_mesh.radial_segments = 12
	rim_mesh.material = material(METAL, 0.3, 0.7)
	rim.mesh = rim_mesh
	rim.position = position
	rim.rotation_degrees.z = 90.0
	root.add_child(rim)


static func box(root: Node3D, size: Vector3, color: Color, position: Vector3, roughness: float, metallic: float = 0.06) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material(color, roughness, metallic)
	part.mesh = mesh
	part.position = position
	root.add_child(part)
	return part


static func glow_box(root: Node3D, size: Vector3, color: Color, position: Vector3) -> MeshInstance3D:
	var part := box(root, size, color, position, 0.2)
	var glow_material := part.mesh.material as StandardMaterial3D
	glow_material.emission_enabled = true
	glow_material.emission = color
	glow_material.emission_energy_multiplier = 2.0
	return part


static func material(color: Color, roughness: float, metallic: float = 0.06) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	# Keep black paint visibly above the asphalt floor and give every toy car a
	# soft moon/street-light edge highlight without changing its chosen color.
	result.albedo_color = Color(maxf(color.r, 0.045), maxf(color.g, 0.05), maxf(color.b, 0.06), color.a)
	result.roughness = roughness
	result.metallic = metallic
	result.rim_enabled = true
	result.rim = 0.34
	result.rim_tint = 0.22
	return result
