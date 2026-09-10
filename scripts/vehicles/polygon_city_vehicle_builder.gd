class_name PolygonCityVehicleBuilder
extends RefCounted

const POLICE_SCENE := preload("res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Police_01.tscn")
const SEDAN_SCENE := preload("res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Sedan_01.tscn")
const LIGHT_SHADER := preload("res://Assets/Synty/PolygonCity/Materials/Misc/Vehicle_Runtime_Lights.gdshader")
const VEHICLE_TEXTURE := preload("res://Assets/Synty/PolygonCity/Textures/PolygonCity_01_A.png")


static func build_police(actor: Node3D) -> void:
	for old_name in ["base_body", "cabin", "wheels_back", "wheels_front", "ToyTrim", "PoliceLightbar", "PushBumper", "StylizedVehicle", "PolygonCityVehicle"]:
		var old := actor.get_node_or_null(old_name)
		if old == null:
			continue
		if old_name in ["base_body", "cabin", "wheels_back", "wheels_front"]:
			old.visible = false
		else:
			old.queue_free()
	var root := POLICE_SCENE.instantiate() as Node3D
	root.name = "PolygonCityVehicle"
	# Synty models face local +Z; RoadActor gameplay forward is local -Z.
	root.rotation.y = PI
	# The sedan mesh origin sits 0.106 m above its wheels, but the police mesh
	# origin is at its wheels. Match the sedan so both cars rest on the road at
	# the same spawn height instead of the police floating ~0.1 m.
	root.position.y = -0.1062
	actor.add_child(root)
	_apply_native_lamp_material(root.get_node("Body") as MeshInstance3D)
	_add_native_light_sources(root)


static func build_civilian(actor: Node3D) -> void:
	_hide_old_visual(actor)
	var root := SEDAN_SCENE.instantiate() as Node3D
	for collider in root.find_children("*", "StaticBody3D", true, false):
		collider.free()
	var body := root as MeshInstance3D
	root.name = "PolygonCityVehicle"
	root.rotation.y = PI
	actor.add_child(root)
	_apply_native_lamp_material(body)


static func _hide_old_visual(actor: Node3D) -> void:
	for old_name in ["base_body", "cabin", "wheels_back", "wheels_front", "ToyTrim", "PoliceLightbar", "PushBumper", "StylizedVehicle", "PolygonCityVehicle"]:
		var old := actor.get_node_or_null(old_name)
		if old == null:
			continue
		if old_name in ["base_body", "cabin", "wheels_back", "wheels_front"]:
			old.visible = false
		else:
			old.queue_free()


static func _apply_native_lamp_material(body: MeshInstance3D) -> void:
	if body == null:
		return
	var material := ShaderMaterial.new()
	material.shader = LIGHT_SHADER
	material.set_shader_parameter("albedo_texture", VEHICLE_TEXTURE)
	body.set_surface_override_material(0, material)


static func _add_native_light_sources(root: Node3D) -> void:
	# These illuminate from the locations of the headlights and modeled roof bar;
	# the visible lenses remain the original Polygon City meshes/materials.
	for index in 2:
		var x := -0.76 if index == 0 else 0.76
		var headlight := SpotLight3D.new()
		headlight.name = "NativeHeadlightLeft" if index == 0 else "NativeHeadlightRight"
		# Align each source with its modeled front lamp. A narrower cone makes
		# both lamps read separately instead of merging into one off-centre beam.
		headlight.position = Vector3(x, 0.74, 2.58)
		headlight.rotation_degrees.y = 180.0
		headlight.light_color = Color("#fff3cf")
		headlight.light_energy = 18.0
		headlight.spot_range = 55.0
		headlight.spot_angle = 25.0
		headlight.shadow_enabled = true
		headlight.visible = false
		root.add_child(headlight)
	var blue := OmniLight3D.new()
	blue.name = "NativeSirenBlue"
	blue.position = Vector3(0.42, 1.72, 0.05)
	blue.light_color = Color("#2685ff")
	blue.light_energy = 4.5
	blue.omni_range = 8.0
	root.add_child(blue)
	var red := OmniLight3D.new()
	red.name = "NativeSirenRed"
	red.position = Vector3(-0.42, 1.72, 0.05)
	red.light_color = Color("#ff3048")
	red.light_energy = 4.5
	red.omni_range = 8.0
	root.add_child(red)


static func update_police_lights(actor: Node3D, night: bool) -> void:
	update_lights(actor, false, false, night)


static func update_lights(actor: Node3D, reversing: bool, braking: bool, night: bool) -> void:
	var root := actor.get_node_or_null("PolygonCityVehicle")
	if root == null:
		return
	var body: MeshInstance3D = root.get_node_or_null("Body") as MeshInstance3D
	if body == null and root is MeshInstance3D:
		body = root as MeshInstance3D
	if body:
		var material := body.get_surface_override_material(0) as ShaderMaterial
		if material:
			material.set_shader_parameter("tail_energy", 0.72 if night else 0.0)
			material.set_shader_parameter("brake_energy", 5.8 if braking else 0.0)
			material.set_shader_parameter("reverse_energy", 3.2 if reversing else 0.0)
	for light in root.find_children("NativeHeadlight*", "SpotLight3D", true, false):
		(light as SpotLight3D).visible = night
	var alternate := int(Time.get_ticks_msec() / 180) % 2 == 0
	var blue := root.get_node_or_null("NativeSirenBlue") as OmniLight3D
	var red := root.get_node_or_null("NativeSirenRed") as OmniLight3D
	if blue:
		blue.visible = alternate
	if red:
		red.visible = not alternate
