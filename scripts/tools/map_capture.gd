extends Node3D
## Temporary diagnostic: build a saved map and capture a top-down PNG with the
## real renderer so rendered placement/rotation can be compared to the layout.
## Run WITH a real renderer (not --headless):
##   godot --path . --scene res://scenes/tools/map_capture.tscn
@export var map_name := "city_map"
@export var ortho_size := 230.0
@export var out_path := "user://map_capture.png"

func _ready() -> void:
	GameState.builder_map_name = map_name
	var district = preload("res://scripts/chase/downtown_grid_district.gd").new()
	district.name = "District"
	add_child(district)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.21)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.85, 0.9)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-70, -35, 0)
	key.light_energy = 1.2
	add_child(key)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.position = Vector3(0, 120, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0) # look straight down; image top = +Z (south)
	cam.size = ortho_size
	cam.far = 400.0
	add_child(cam)
	cam.make_current()

	for _i in 8:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out_path)
	img.save_png(abs_path)
	print("MAP_CAPTURE wrote ", abs_path)
	get_tree().quit()
