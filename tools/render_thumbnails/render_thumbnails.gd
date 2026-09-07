extends SceneTree
##
## Renders top-down PNG thumbnails of the Polygon City prefabs used by the web
## map builder, so edged/mesh assets (sidewalk corners, buildings, lamps,
## signals, vehicles, pedestrians) show their real appearance and rotation.
##
## Roads are intentionally skipped: every road id uses the same bare-road prefab
## and its look (lane arrows, dividers, curves) is procedural, so the builder's
## schematic is clearer than an identical bare-road photo.
##
## Run with a REAL renderer (NOT --headless; headless can't capture pixels):
##
##   & 'C:\Users\deest\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' \
##       --path . --script res://tools/render_thumbnails/render_thumbnails.gd
##
## Output: tools/web_map_builder/thumbs/<id>.png  (transparent background)
##
const Catalog = preload("res://scripts/map_builder/map_builder_catalog.gd")
const OUT_DIR := "res://tools/web_map_builder/thumbs"
const IMG_SIZE := 256

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var abs_out := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_out)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(IMG_SIZE, IMG_SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	# Neutral lighting so the flat-shaded meshes read clearly from above.
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.ambient_light_energy = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-65, -35, 0)
	key.light_energy = 1.1
	viewport.add_child(key)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0, 60, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0) # look straight down; image top = -Z (North)
	camera.far = 200.0
	viewport.add_child(camera)

	var holder := Node3D.new()
	viewport.add_child(holder)

	var rendered := 0
	for def in Catalog.create_default():
		if def.category == "Roads":
			continue
		var packed := load(def.scene_path) as PackedScene
		if packed == null:
			push_warning("skip %s: cannot load %s" % [def.id, def.scene_path])
			continue
		var instance := packed.instantiate() as Node3D
		instance.scale = def.visual_scale
		holder.position = Vector3.ZERO
		holder.add_child(instance)
		await process_frame # let global transforms settle before measuring

		# Auto-frame by the real mesh bounds so corner-pivoted prefabs (sidewalks,
		# lamps) are centered and every asset is sized to fit, regardless of pivot.
		var bounds := _world_aabb(instance)
		if def.corner_pivot and bounds.size != Vector3.ZERO:
			# Corner-pivoted ground pieces (sidewalks, buildings): center on their
			# real mesh bounds so the footprint sits square in the frame.
			var center := bounds.position + bounds.size * 0.5
			holder.position = Vector3(-center.x, 0.0, -center.z)
			camera.size = maxf(maxf(bounds.size.x, bounds.size.z) * 1.08, 2.0)
		else:
			# Cell-centered props/vehicles/pedestrians: frame on origin by footprint
			# so a stray sub-mesh can't throw the subject off-center.
			holder.position = Vector3.ZERO
			camera.size = maxf(float(maxi(def.footprint.x, def.footprint.y)) * 5.0 + 1.0, 5.0)

		# Let the viewport draw a few frames before capturing.
		for _i in 4:
			await process_frame
		RenderingServer.force_draw()
		var image := viewport.get_texture().get_image()
		var path := "%s/%s.png" % [abs_out, def.id]
		var err := image.save_png(path)
		if err == OK:
			rendered += 1
			print("  rendered %s -> %s.png" % [def.id, def.id])
		else:
			push_warning("save failed for %s (err %d)" % [def.id, err])
		instance.queue_free()
		await process_frame

	print("THUMBNAILS: wrote %d images to %s" % [rendered, abs_out])
	quit()


func _world_aabb(node: Node) -> AABB:
	var result := AABB()
	var has_any := false
	var nodes := node.find_children("*", "VisualInstance3D", true, false)
	if node is VisualInstance3D:
		nodes.append(node) # many single-mesh prefabs have the MeshInstance as their root
	for child in nodes:
		var vi := child as VisualInstance3D
		if vi == null:
			continue
		var local := vi.get_aabb()
		var world := vi.global_transform * local
		if not has_any:
			result = world
			has_any = true
		else:
			result = result.merge(world)
	return result

