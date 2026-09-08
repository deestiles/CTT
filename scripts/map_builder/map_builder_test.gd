extends Node3D

const PlaceableDefinition = preload("res://scripts/map_builder/placeable_definition.gd")
const BuilderCatalog = preload("res://scripts/map_builder/map_builder_catalog.gd")
const RoadModuleRules = preload("res://scripts/map_builder/road_module_rules.gd")
const AssetPaletteButton = preload("res://scripts/map_builder/asset_palette_button.gd")

const GRID_SIZE := 5.0
const MIN_CAMERA_SIZE := 18.0
const MAX_CAMERA_SIZE := 260.0
const ZOOM_STEP := 0.12
const KEYBOARD_PAN_SPEED := 0.72
const MAP_SAVE_DIRECTORY := "user://maps"
const DIRECTIONS := {
	"N": Vector2i(0, -1),
	"E": Vector2i(1, 0),
	"S": Vector2i(0, 1),
	"W": Vector2i(-1, 0),
}
const OPPOSITE := {"N": "S", "E": "W", "S": "N", "W": "E"}

@onready var camera: Camera3D = $Camera3D
@onready var inventory: VBoxContainer = $UI/Inventory/Scroll/Items
@onready var selection_label: Label = $UI/Selection
@onready var status_label: Label = $UI/Status
@onready var preview: MeshInstance3D = $Preview
@onready var direction_arrow: Node3D = $DirectionArrow
@onready var map_name: LineEdit = $UI/SavePanel/MapName
@onready var save_button: Button = $UI/SavePanel/Actions/Save
@onready var load_button: Button = $UI/SavePanel/Actions/Load
@onready var test_button: Button = $UI/SavePanel/Test
@onready var save_confirmation: ConfirmationDialog = $UI/SaveConfirmation

var catalog: Array = []
var selected: Resource
var quarter_turns := 0
var hovered_cell := Vector2i.ZERO
var occupancy := {}
var placed := {}
var road_drag_active := false
var road_drag_anchor := Vector2i.ZERO
var road_drag_last_cell := Vector2i.ZERO
var palette_drag_active := false
var thumbnail_viewports: Array[SubViewport] = []
var asset_thumbnails := {}
var drag_icon: TextureRect
var validation_result := {"valid": false, "issues": 0}
var validation_marked_cells := {}


func _ready() -> void:
	catalog = BuilderCatalog.create_default()
	_build_inventory()
	_select_definition(catalog[0])
	_update_validation()
	save_button.pressed.connect(_request_save)
	load_button.pressed.connect(_load_map)
	test_button.pressed.connect(_test_map)
	save_confirmation.confirmed.connect(_save_map)


func _process(delta: float) -> void:
	var movement := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if movement == Vector2.ZERO:
		return
	var pan_speed := camera.size * KEYBOARD_PAN_SPEED
	camera.position += Vector3(movement.x, 0.0, movement.y) * pan_speed * delta


func _build_inventory() -> void:
	var last_category := ""
	for definition in catalog:
		if definition.category == "Hidden Compatibility":
			continue
		if definition.category != last_category:
			var heading := Label.new()
			heading.text = definition.category.to_upper()
			heading.add_theme_font_size_override("font_size", 14)
			inventory.add_child(heading)
			last_category = definition.category
		var button := AssetPaletteButton.new()
		var thumbnail := _create_asset_thumbnail(definition)
		asset_thumbnails[definition.id] = thumbnail
		button.configure(definition, self, thumbnail)
		button.pressed.connect(_select_definition.bind(definition))
		inventory.add_child(button)


func _create_asset_thumbnail(definition: Resource) -> Texture2D:
	var viewport := SubViewport.new()
	viewport.name = "Thumbnail_%s" % definition.id
	viewport.size = Vector2i(112, 72)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	thumbnail_viewports.append(viewport)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.08, 0.11, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b9c8d5")
	environment.ambient_light_energy = 1.15
	environment_node.environment = environment
	viewport.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.3
	viewport.add_child(sun)
	var packed := load(definition.scene_path) as PackedScene
	var instance := packed.instantiate() as Node3D
	viewport.add_child(instance)
	instance.scale = definition.visual_scale
	if definition.id == "traffic_light":
		_add_traffic_light_support(instance)
	var bounds := _visual_bounds(instance)
	var center := bounds.get_center()
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var camera_node := Camera3D.new()
	camera_node.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_node.size = maxf(2.8, extent * 1.45)
	camera_node.position = center + Vector3(extent * 1.15, extent * 0.9, extent * 1.35)
	viewport.add_child(camera_node)
	camera_node.look_at(center, Vector3.UP)
	camera_node.current = true
	return viewport.get_texture()


func _visual_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	var inverse_root := root.global_transform.affine_inverse()
	var meshes: Array[Node] = []
	if root is MeshInstance3D:
		meshes.append(root)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var transformed: AABB = (inverse_root * mesh_instance.global_transform) * mesh_instance.get_aabb()
		result = transformed if not found else result.merge(transformed)
		found = true
	return result if found else AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))


func begin_palette_drag(definition: Resource) -> void:
	palette_drag_active = true
	_select_definition(definition)
	status_label.text = "DRAGGING — release over the map to place"
	status_label.modulate = Color(0.25, 0.9, 1.0)
	drag_icon = TextureRect.new()
	drag_icon.texture = asset_thumbnails.get(definition.id)
	drag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drag_icon.custom_minimum_size = Vector2(96, 64)
	drag_icon.size = Vector2(96, 64)
	drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_icon.modulate.a = 0.86
	$UI.add_child(drag_icon)
	move_palette_drag(get_viewport().get_mouse_position())


func move_palette_drag(screen_position: Vector2) -> void:
	if not palette_drag_active:
		return
	hovered_cell = _screen_to_cell(screen_position)
	_update_preview()
	if is_instance_valid(drag_icon):
		drag_icon.position = screen_position + Vector2(14, 10)


func drop_palette_asset(screen_position: Vector2) -> void:
	if not palette_drag_active:
		return
	palette_drag_active = false
	if is_instance_valid(drag_icon):
		drag_icon.queue_free()
	# UI panels are not valid world drop targets.
	if $UI/Inventory.get_global_rect().has_point(screen_position) or $UI/SavePanel.get_global_rect().has_point(screen_position):
		_update_validation()
		return
	hovered_cell = _screen_to_cell(screen_position)
	_place_selected()


func _select_definition(definition: Resource) -> void:
	selected = definition
	_update_selection_label()
	_update_preview()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		quarter_turns = (quarter_turns + 1) % 4
		_update_selection_label()
		_update_preview()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		_pan_camera(event.relative)
	elif event is InputEventMouseMotion:
		hovered_cell = _screen_to_cell(event.position)
		if road_drag_active and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_extend_road_drag(hovered_cell)
		_update_preview()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			road_drag_active = false
			return
		if not event.pressed:
			return
		if get_viewport().gui_get_hovered_control() != null:
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(-1, event.position)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(1, event.position)
			return
		hovered_cell = _screen_to_cell(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place_selected()
			if _selected_supports_road_drag():
				road_drag_active = true
				road_drag_anchor = hovered_cell
				road_drag_last_cell = hovered_cell
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_erase_at(hovered_cell)


func _selected_supports_road_drag() -> bool:
	return selected != null and selected.module_rules.get("kind", "") == "straight"


func _extend_road_drag(cursor_cell: Vector2i) -> void:
	# A straight road's unrotated segment runs north/south. Lock the lateral
	# anchor during a drag so a slightly diagonal pointer motion cannot stagger
	# a wide carriageway or create overlaps between consecutive pieces.
	var target := cursor_cell
	if quarter_turns % 2 == 0:
		target.x = road_drag_anchor.x
	else:
		target.y = road_drag_anchor.y
	if target == road_drag_last_cell:
		return
	var step := Vector2i(0, signi(target.y - road_drag_last_cell.y)) if quarter_turns % 2 == 0 else Vector2i(signi(target.x - road_drag_last_cell.x), 0)
	if step == Vector2i.ZERO:
		return
	var next_cell := road_drag_last_cell + step
	while true:
		hovered_cell = next_cell
		if _can_place(hovered_cell):
			_place_selected()
		if next_cell == target:
			break
		next_cell += step
	road_drag_last_cell = target


func _pan_camera(relative: Vector2) -> void:
	var viewport_height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var world_per_pixel := camera.size / viewport_height
	camera.position += Vector3(-relative.x, 0.0, -relative.y) * world_per_pixel


func _zoom_camera(direction: int, mouse_position: Vector2) -> void:
	# Preserve the world point below the cursor so zooming remains useful while
	# working far away from the map origin.
	var before := _screen_to_ground(mouse_position)
	var factor := 1.0 + ZOOM_STEP if direction > 0 else 1.0 / (1.0 + ZOOM_STEP)
	camera.size = clampf(camera.size * factor, MIN_CAMERA_SIZE, MAX_CAMERA_SIZE)
	var after := _screen_to_ground(mouse_position)
	camera.position += before - after
	hovered_cell = _screen_to_cell(mouse_position)
	_update_preview()


func _screen_to_ground(screen_position: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.001:
		return Vector3(hovered_cell.x * GRID_SIZE, 0.0, hovered_cell.y * GRID_SIZE)
	return origin + direction * (-origin.y / direction.y)


func _screen_to_cell(screen_position: Vector2) -> Vector2i:
	var point := _screen_to_ground(screen_position)
	return Vector2i(floori(point.x / GRID_SIZE), floori(point.z / GRID_SIZE))


func _update_preview() -> void:
	if selected == null:
		return
	var footprint := _rotated_footprint(selected)
	var center := Vector3((hovered_cell.x + footprint.x * 0.5) * GRID_SIZE, 0.16, (hovered_cell.y + footprint.y * 0.5) * GRID_SIZE)
	preview.position = center
	preview.rotation.y = 0.0
	(preview.mesh as BoxMesh).size = Vector3(footprint.x * GRID_SIZE - 0.2, 0.25, footprint.y * GRID_SIZE - 0.2)
	direction_arrow.position = center + Vector3(0, 0.34, 0)
	direction_arrow.rotation.y = quarter_turns * PI * 0.5
	direction_arrow.visible = not selected.traffic_directions.is_empty()
	$DirectionArrow/Reverse.visible = selected.traffic_directions.size() > 1
	var material := preview.material_override as StandardMaterial3D
	material.albedo_color = Color(0.15, 0.85, 1.0, 0.42) if _can_place(hovered_cell) else Color(1.0, 0.15, 0.12, 0.48)


func _can_place(cell: Vector2i) -> bool:
	for covered_cell in _covered_cells(cell, selected):
		var existing_definitions: Array = placed.get(covered_cell, [])
		if selected.placement_layer in ["surface", "structure"]:
			for existing in existing_definitions:
				# Sidewalk is a ground layer and may continue beneath a building's
				# frontage. Roads and objects on the same layer remain exclusive.
				var building_sidewalk_pair: bool = (
					(selected.category == "Buildings" and existing.category == "Sidewalks")
					or (selected.category == "Sidewalks" and existing.category == "Buildings")
				)
				if not building_sidewalk_pair:
					return false
			continue
		var has_allowed_base: bool = selected.allowed_base_categories.is_empty()
		for existing in existing_definitions:
			if selected.allowed_base_categories.has(existing.category):
				has_allowed_base = true
			if existing.placement_layer == selected.placement_layer:
				return false
		if not has_allowed_base:
			return false
	if selected.requires_road_edge and not (
		_footprint_touches_category(cell, selected, "Roads")
		or _footprint_touches_category(cell, selected, "Sidewalks")
	):
		return false
	return true


func _footprint_touches_category(anchor: Vector2i, definition: Resource, category: String) -> bool:
	var covered := _covered_cells(anchor, definition)
	for covered_cell in covered:
		for direction in DIRECTIONS.values():
			var neighbor: Vector2i = covered_cell + direction
			if covered.has(neighbor):
				continue
			for existing in placed.get(neighbor, []):
				if existing.category == category:
					return true
	return false


func _place_selected() -> void:
	if selected == null or not _can_place(hovered_cell):
		status_label.text = "Cannot place: that grid cell is occupied."
		return
	var packed := load(selected.scene_path) as PackedScene
	if packed == null:
		status_label.text = "Missing asset: " + selected.scene_path
		return
	var owner := Node3D.new()
	owner.name = selected.id
	$PlacedItems.add_child(owner)
	var covered_cells := _covered_cells(hovered_cell, selected)
	if selected.id.begins_with("curve_"):
		_add_curved_road(owner, hovered_cell, selected, quarter_turns)
	elif selected.fill_footprint_with_tiles:
		for covered_cell in covered_cells:
			var tile := packed.instantiate() as Node3D
			owner.add_child(tile)
			var tile_turns := _tile_rotation_for(selected, covered_cell, hovered_cell, quarter_turns)
			tile.position = _placement_position(selected, covered_cell, tile_turns)
			tile.rotation.y = tile_turns * PI * 0.5
	else:
		var instance := packed.instantiate() as Node3D
		owner.add_child(instance)
		instance.position = _placement_position(selected, hovered_cell, quarter_turns)
		instance.rotation.y = quarter_turns * PI * 0.5
		instance.scale = selected.visual_scale
		if selected.id == "traffic_light":
			_add_traffic_light_support(instance)
	if selected.id.begins_with("two_way_street"):
		_add_two_way_markings(owner, hovered_cell, selected, quarter_turns)
	owner.set_meta("definition_id", selected.id)
	owner.set_meta("quarter_turns", quarter_turns)
	owner.set_meta("cell", hovered_cell)
	owner.set_meta("covered_cells", covered_cells)
	for covered_cell in covered_cells:
		var cell_nodes: Array = occupancy.get(covered_cell, [])
		cell_nodes.append(owner)
		occupancy[covered_cell] = cell_nodes
		var cell_definitions: Array = placed.get(covered_cell, [])
		cell_definitions.append(selected)
		placed[covered_cell] = cell_definitions
	_update_validation()
	_update_preview()


func _add_traffic_light_support(signal_head: Node3D) -> void:
	if signal_head.has_node("TrafficSignalSupport"):
		return
	var pole := MeshInstance3D.new()
	pole.name = "TrafficSignalSupport"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.105
	mesh.bottom_radius = 0.145
	mesh.height = 2.46
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#26343b")
	material.metallic = 0.28
	material.roughness = 0.52
	mesh.material = material
	pole.mesh = mesh
	# The Polygon signal-head origin is at its top; its housing ends at -0.9 m.
	# This reaches from that housing down to sidewalk level after placement.
	pole.position.y = -2.13
	signal_head.add_child(pole)


func _add_curved_road(owner: Node3D, anchor: Vector2i, definition: Resource, turns: int) -> void:
	var road_width := GRID_SIZE
	if definition.id == "curve_two_way_1x1":
		road_width = GRID_SIZE * 2.0
	elif definition.id == "curve_two_way_2x2":
		road_width = GRID_SIZE * 4.0
	var outer_radius: float = definition.footprint.x * GRID_SIZE
	var inner_radius := outer_radius - road_width
	var center := Vector3((anchor.x + definition.footprint.x) * GRID_SIZE, 0.09, (anchor.y + definition.footprint.y) * GRID_SIZE)
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color("#b8a6a3")
	asphalt.roughness = 0.92
	# Procedural ArrayMesh winding can be culled differently by renderer/backend.
	# Curves are flat modular surfaces, so render both faces just like road tiles.
	asphalt.cull_mode = BaseMaterial3D.CULL_DISABLED
	asphalt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var road := MeshInstance3D.new()
	road.mesh = _make_arc_strip(center, inner_radius, outer_radius, PI, PI * 1.5, 32, 0.0, asphalt)
	owner.add_child(road)
	var pivot := Vector3((anchor.x + definition.footprint.x * 0.5) * GRID_SIZE, 0.0, (anchor.y + definition.footprint.y * 0.5) * GRID_SIZE)
	owner.set_meta("curve_pivot", pivot)
	for child in owner.get_children():
		_rotate_node_around(child as Node3D, pivot, turns * PI * 0.5)
	if definition.id.begins_with("curve_two_way"):
		var center_radius := outer_radius - road_width * 0.5
		_add_curved_marking(owner, center, center_radius, turns, pivot, true)
		if definition.id == "curve_two_way_2x2":
			_add_curved_marking(owner, center, center_radius - GRID_SIZE, turns, pivot, false)
			_add_curved_marking(owner, center, center_radius + GRID_SIZE, turns, pivot, false)


func _add_curved_marking(owner: Node3D, center: Vector3, radius: float, turns: int, pivot: Vector3, solid: bool) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.93, 0.72, 0.08) if solid else Color(0.91, 0.91, 0.86)
	material.roughness = 0.78
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dash_count := 1 if solid else 6
	for dash in range(dash_count):
		var start_angle := PI
		var end_angle := PI * 1.5
		if not solid:
			var slice := (PI * 0.5) / dash_count
			start_angle += dash * slice + slice * 0.18
			end_angle = PI + (dash + 1) * slice - slice * 0.28
		var line := MeshInstance3D.new()
		line.mesh = _make_arc_strip(center, radius - 0.065, radius + 0.065, start_angle, end_angle, 5 if not solid else 32, 0.035, material)
		owner.add_child(line)
		_rotate_node_around(line, pivot, turns * PI * 0.5)


func _make_arc_strip(center: Vector3, inner_radius: float, outer_radius: float, start_angle: float, end_angle: float, segments: int, height: float, material: Material) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for index in range(segments + 1):
		var angle := lerpf(start_angle, end_angle, float(index) / segments)
		for radius in [inner_radius, outer_radius]:
			var vertex := center + Vector3(cos(angle) * radius, height, sin(angle) * radius)
			vertices.append(vertex)
			normals.append(Vector3.UP)
			uvs.append(Vector2(vertex.x, vertex.z) / GRID_SIZE)
	for index in range(segments):
		var base := index * 2
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _rotate_node_around(node: Node3D, pivot: Vector3, angle: float) -> void:
	if is_zero_approx(angle):
		return
	var offset := node.position - pivot
	node.position = pivot + Basis(Vector3.UP, angle) * offset
	node.rotation.y += angle


func _request_save() -> void:
	var map_label := _safe_map_name()
	var action := "overwrite" if FileAccess.file_exists(_map_save_path()) else "create"
	save_confirmation.dialog_text = "Are you sure you want to %s ‘%s’?" % [action, map_label]
	save_confirmation.popup_centered(Vector2i(390, 150))


func _save_map() -> bool:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAP_SAVE_DIRECTORY))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		status_label.text = "SAVE FAILED — could not create the maps folder"
		status_label.modulate = Color(1.0, 0.3, 0.25)
		return false
	var item_data: Array = []
	for owner in $PlacedItems.get_children():
		var cell: Vector2i = owner.get_meta("cell", Vector2i.ZERO)
		item_data.append({
			"id": String(owner.get_meta("definition_id", "")),
			"cell": [cell.x, cell.y],
			"turns": int(owner.get_meta("quarter_turns", 0)),
		})
	var payload := {
		"version": RoadModuleRules.SCHEMA_VERSION,
		"grid_size": RoadModuleRules.GRID_SIZE,
		"lane_width": RoadModuleRules.LANE_WIDTH,
		"items": item_data,
		"camera": {"x": camera.position.x, "z": camera.position.z, "size": camera.size},
		"spawn_candidates": _collect_spawn_candidates(),
		"validation": validation_result.duplicate(true),
	}
	var path := _map_save_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		status_label.text = "SAVE FAILED — error %d" % FileAccess.get_open_error()
		status_label.modulate = Color(1.0, 0.3, 0.25)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	status_label.text = "MAP SAVED — %s (%d objects)" % [_safe_map_name(), item_data.size()]
	status_label.modulate = Color(0.45, 1.0, 0.62)
	return true


func _test_map() -> void:
	_update_validation()
	if not bool(validation_result.get("valid", false)):
		status_label.text = "TEST BLOCKED — fix the map validation warning first"
		status_label.modulate = Color(1.0, 0.3, 0.25)
		return
	if not _save_map():
		return
	GameState.builder_map_name = _safe_map_name()
	get_tree().change_scene_to_file("res://scenes/chase/grid_streets_test.tscn")


func _collect_spawn_candidates() -> Dictionary:
	var vehicles: Array = []
	var pedestrians: Array = []
	for owner in $PlacedItems.get_children():
		var definition := _definition_by_id(String(owner.get_meta("definition_id", "")))
		if definition == null:
			continue
		var anchor: Vector2i = owner.get_meta("cell", Vector2i.ZERO)
		var turns := int(owner.get_meta("quarter_turns", 0))
		if not definition.module_rules.is_empty() and String(definition.module_rules.get("kind", "")) == "straight":
			vehicles.append({"cell": [anchor.x, anchor.y], "turns": turns, "road_id": definition.id})
		elif definition.id.begins_with("sidewalk"):
			var blocked := false
			for cell in _covered_cells_for_turns(anchor, definition, turns):
				for occupant in occupancy.get(cell, []):
					var occupant_definition := _definition_by_id(String(occupant.get_meta("definition_id", "")))
					if occupant_definition != null and occupant_definition.placement_layer in ["prop", "character", "structure"]:
						blocked = true
			if not blocked:
				pedestrians.append({"cell": [anchor.x, anchor.y], "turns": turns})
	return {"vehicles": vehicles, "pedestrians": pedestrians}


func _load_map() -> void:
	var path := _map_save_path()
	if not FileAccess.file_exists(path):
		status_label.text = "LOAD FAILED — no saved map named %s" % _safe_map_name()
		status_label.modulate = Color(1.0, 0.72, 0.28)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.has("items"):
		status_label.text = "LOAD FAILED — invalid map file"
		status_label.modulate = Color(1.0, 0.3, 0.25)
		return
	_clear_map()
	var previous_selected := selected
	var previous_turns := quarter_turns
	var loaded_count := 0
	for item in parsed["items"]:
		if not item is Dictionary or not item.has("id") or not item.has("cell"):
			continue
		var definition := _definition_by_id(String(item["id"]))
		if definition == null:
			continue
		var coordinates: Array = item["cell"]
		if coordinates.size() < 2:
			continue
		selected = definition
		hovered_cell = Vector2i(int(coordinates[0]), int(coordinates[1]))
		quarter_turns = posmod(int(item.get("turns", 0)), 4)
		if _can_place(hovered_cell):
			_place_selected()
			loaded_count += 1
	selected = previous_selected
	quarter_turns = previous_turns
	var camera_data = parsed.get("camera", {})
	if camera_data is Dictionary:
		camera.position.x = float(camera_data.get("x", camera.position.x))
		camera.position.z = float(camera_data.get("z", camera.position.z))
		camera.size = clampf(float(camera_data.get("size", camera.size)), MIN_CAMERA_SIZE, MAX_CAMERA_SIZE)
	_update_selection_label()
	_update_preview()
	status_label.text = "MAP LOADED — %s (%d objects)" % [_safe_map_name(), loaded_count]
	status_label.modulate = Color(0.45, 1.0, 0.62)


func _clear_map() -> void:
	for child in $PlacedItems.get_children():
		child.free()
	occupancy.clear()
	placed.clear()


func _definition_by_id(definition_id: String) -> Resource:
	for definition in catalog:
		if definition.id == definition_id:
			return definition
	return null


func _safe_map_name() -> String:
	var value := map_name.text.strip_edges().validate_filename()
	return value if not value.is_empty() else "city_map"


func _map_save_path() -> String:
	return "%s/%s.json" % [MAP_SAVE_DIRECTORY, _safe_map_name()]


func _placement_position(definition: Resource, cell: Vector2i, rotation_index: int) -> Vector3:
	var rotated_offset: Vector3 = Basis(Vector3.UP, rotation_index * PI * 0.5) * definition.placement_offset
	if not definition.corner_pivot:
		return Vector3((cell.x + 0.5) * GRID_SIZE, 0.12, (cell.y + 0.5) * GRID_SIZE) + rotated_offset
	var offsets := [Vector2(0, 5), Vector2(5, 5), Vector2(5, 0), Vector2(0, 0)]
	var offset: Vector2 = offsets[posmod(rotation_index, 4)]
	return Vector3(cell.x * GRID_SIZE + offset.x, 0.08, cell.y * GRID_SIZE + offset.y) + rotated_offset


func _tile_rotation_for(definition: Resource, cell: Vector2i, anchor: Vector2i, base_turns: int) -> int:
	if not definition.id.begins_with("two_way_street"):
		return base_turns
	var footprint := _rotated_footprint(definition)
	var lateral_index := cell.x - anchor.x if base_turns % 2 == 0 else cell.y - anchor.y
	var lateral_width := footprint.x if base_turns % 2 == 0 else footprint.y
	# The far half is rotated 180 degrees so the two inner road edges meet as a
	# centerline instead of repeating an outside lane line down the middle.
	return base_turns + 2 if lateral_index >= lateral_width / 2 else base_turns


func _add_two_way_markings(owner: Node3D, anchor: Vector2i, definition: Resource, turns: int) -> void:
	var lane_count_each_way: int = definition.footprint.x / 2
	var road_width: float = definition.footprint.x * GRID_SIZE
	var along_center := Vector3((anchor.x + 0.5) * GRID_SIZE, 0.105, (anchor.y + 0.5) * GRID_SIZE)
	if turns % 2 == 0:
		along_center.x = anchor.x * GRID_SIZE + road_width * 0.5
	else:
		along_center.z = anchor.y * GRID_SIZE + road_width * 0.5
	_add_lane_line(owner, along_center, turns, true)
	if lane_count_each_way < 2:
		return
	# One dotted divider per carriageway. Neither divider is placed on an outside
	# edge, and the solid centerline remains the only opposing-flow boundary.
	for side in [-1.0, 1.0]:
		var divider := along_center
		var lateral_offset: float = side * GRID_SIZE
		if turns % 2 == 0:
			divider.x += lateral_offset
		else:
			divider.z += lateral_offset
		_add_lane_line(owner, divider, turns, false)


func _add_lane_line(owner: Node3D, at: Vector3, turns: int, solid: bool) -> void:
	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var line_length := GRID_SIZE if solid else GRID_SIZE * 0.52
	mesh.size = Vector3(0.11, 0.025, line_length) if turns % 2 == 0 else Vector3(line_length, 0.025, 0.11)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.93, 0.72, 0.08) if solid else Color(0.91, 0.91, 0.86)
	material.roughness = 0.78
	mesh.material = material
	line.mesh = mesh
	line.position = at
	owner.add_child(line)


func _erase_at(cell: Vector2i) -> void:
	if not occupancy.has(cell):
		return
	var selected_owner := (occupancy[cell] as Array).back() as Node3D
	var covered_cells: Array = selected_owner.get_meta("covered_cells", [cell])
	for covered_cell in covered_cells:
		var cell_nodes: Array = occupancy[covered_cell]
		var item_index := cell_nodes.find(selected_owner)
		if item_index >= 0:
			cell_nodes.remove_at(item_index)
			var cell_definitions: Array = placed[covered_cell]
			cell_definitions.remove_at(item_index)
			if cell_nodes.is_empty():
				occupancy.erase(covered_cell)
				placed.erase(covered_cell)
			else:
				occupancy[covered_cell] = cell_nodes
				placed[covered_cell] = cell_definitions
	selected_owner.queue_free()
	_update_validation()
	_update_preview()


func _rotated_connectors(definition: Resource, turns: int) -> PackedStringArray:
	var order := ["N", "E", "S", "W"]
	var result := PackedStringArray()
	for connector in definition.connectors:
		result.append(order[posmod(order.find(connector) - turns, 4)])
	return result


func _rotated_footprint(definition: Resource) -> Vector2i:
	return Vector2i(definition.footprint.y, definition.footprint.x) if quarter_turns % 2 == 1 else definition.footprint


func _covered_cells(anchor: Vector2i, definition: Resource) -> Array[Vector2i]:
	return _covered_cells_for_turns(anchor, definition, quarter_turns)


func _covered_cells_for_turns(anchor: Vector2i, definition: Resource, turns: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var footprint: Vector2i = definition.footprint
	if turns % 2 == 1:
		footprint = Vector2i(footprint.y, footprint.x)
	for x in range(footprint.x):
		for y in range(footprint.y):
			result.append(anchor + Vector2i(x, y))
	return result


func _update_selection_label() -> void:
	var footprint := _rotated_footprint(selected)
	var flow := ""
	if not selected.traffic_directions.is_empty():
		flow = "   TRAFFIC: " + "/".join(_rotated_connectors_for(selected.traffic_directions, quarter_turns))
	var base_rule := ""
	if not selected.allowed_base_categories.is_empty():
		base_rule = "   ON: " + "/".join(selected.allowed_base_categories)
	elif selected.requires_road_edge:
		base_rule = "   EDGE: ROAD/SIDEWALK"
	selection_label.text = "SELECTED: %s   SIZE: %d×%d   ROTATION: %d°   LAYER: %s%s%s" % [selected.display_name, footprint.x, footprint.y, quarter_turns * 90, selected.placement_layer.to_upper(), base_rule, flow]


func _rotated_connectors_for(values: PackedStringArray, turns: int) -> PackedStringArray:
	var order := ["N", "E", "S", "W"]
	var result := PackedStringArray()
	for value in values:
		result.append(order[posmod(order.find(value) - turns, 4)])
	return result


func _update_validation() -> void:
	_clear_validation_markers()
	var dangling := 0
	var incompatible := 0
	var direction_conflicts := 0
	var fixture_orientation_errors := 0
	var road_owners: Array[Node] = []
	for owner in $PlacedItems.get_children():
		var definition := _definition_by_id(String(owner.get_meta("definition_id", "")))
		if definition == null:
			continue
		if definition.id in ["street_lamp", "traffic_light"] and not _fixture_faces_road(owner):
			fixture_orientation_errors += 1
			_mark_validation_cell(owner.get_meta("cell", Vector2i.ZERO), "ROTATE TOWARD ROAD", false)
		if definition.module_rules.is_empty():
			continue
		road_owners.append(owner)
		var turns := int(owner.get_meta("quarter_turns", 0))
		for connector in RoadModuleRules.rotated_ports(definition.module_rules, turns):
			var port_connected := true
			for edge_cell in _port_boundary_cells(owner, connector):
				var connection_state := _connection_state(edge_cell + DIRECTIONS[connector], OPPOSITE[connector], definition.module_rules, definition, connector, turns)
				if connection_state == 0:
					port_connected = false
					_mark_validation_cell(edge_cell, "OPEN ROAD END", true)
				elif connection_state == 2:
					incompatible += 1
					port_connected = false
					_mark_validation_cell(edge_cell, "LANE MISMATCH", true)
				elif connection_state == 3:
					direction_conflicts += 1
					port_connected = false
					_mark_validation_cell(edge_cell, "WRONG DIRECTION", true)
			if not port_connected:
				dangling += 1
	var disconnected := _count_disconnected_roads(road_owners)
	_mark_disconnected_roads(road_owners)
	var spawns := _collect_spawn_candidates()
	var vehicle_spawn_count := (spawns.get("vehicles", []) as Array).size()
	var pedestrian_spawn_count := (spawns.get("pedestrians", []) as Array).size()
	var spawn_errors := int(vehicle_spawn_count < 2)
	var total_issues := dangling + incompatible + direction_conflicts + disconnected + fixture_orientation_errors + spawn_errors
	validation_result = {
		"valid": total_issues == 0,
		"issues": total_issues,
		"dangling_ports": dangling,
		"lane_mismatches": incompatible,
		"direction_conflicts": direction_conflicts,
		"disconnected_roads": disconnected,
		"misoriented_fixtures": fixture_orientation_errors,
		"vehicle_spawn_candidates": vehicle_spawn_count,
		"pedestrian_spawn_candidates": pedestrian_spawn_count,
	}
	if total_issues == 0:
		status_label.text = "VALID MAP — connected roads · %d vehicle spawns · %d pedestrian spawns" % [vehicle_spawn_count, pedestrian_spawn_count]
		status_label.modulate = Color(0.45, 1.0, 0.62)
	elif direction_conflicts > 0:
		status_label.text = "ONE-WAY CONFLICT — rotate %d road edge%s so arrows continue" % [direction_conflicts, "" if direction_conflicts == 1 else "s"]
		status_label.modulate = Color(1.0, 0.3, 0.25)
	elif incompatible > 0:
		status_label.text = "LANE MISMATCH — %d incompatible road edge%s" % [incompatible, "" if incompatible == 1 else "s"]
		status_label.modulate = Color(1.0, 0.3, 0.25)
	elif disconnected > 0:
		status_label.text = "DISCONNECTED MAP — %d road piece%s cannot be reached" % [disconnected, "" if disconnected == 1 else "s"]
		status_label.modulate = Color(1.0, 0.3, 0.25)
	elif fixture_orientation_errors > 0:
		status_label.text = "FIXTURE WARNING — rotate %d lamp/traffic light%s toward an adjacent road" % [fixture_orientation_errors, "" if fixture_orientation_errors == 1 else "s"]
		status_label.modulate = Color(1.0, 0.72, 0.28)
	elif spawn_errors > 0:
		status_label.text = "SPAWN WARNING — add at least two connected straight-road pieces"
		status_label.modulate = Color(1.0, 0.72, 0.28)
	else:
		status_label.text = "DESIGN WARNING — %d unconnected road end%s" % [dangling, "" if dangling == 1 else "s"]
		status_label.modulate = Color(1.0, 0.72, 0.28)


func _clear_validation_markers() -> void:
	validation_marked_cells.clear()
	for child in $ValidationMarkers.get_children():
		child.free()


func _mark_validation_cell(cell: Vector2i, reason: String, severe: bool) -> void:
	# Keep one concise marker per cell; red errors take precedence over amber.
	if validation_marked_cells.has(cell):
		var existing: Dictionary = validation_marked_cells[cell]
		if bool(existing.get("severe", false)) or not severe:
			return
		(existing.get("node") as Node).free()
	var marker := Node3D.new()
	marker.name = "Issue_%d_%d" % [cell.x, cell.y]
	marker.position = Vector3((cell.x + 0.5) * GRID_SIZE, 0.34, (cell.y + 0.5) * GRID_SIZE)
	$ValidationMarkers.add_child(marker)
	var tile := MeshInstance3D.new()
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(GRID_SIZE - 0.22, 0.09, GRID_SIZE - 0.22)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.08, 0.06, 0.43) if severe else Color(1.0, 0.62, 0.05, 0.40)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.04, 0.02) if severe else Color(1.0, 0.48, 0.02)
	material.emission_energy_multiplier = 1.3
	tile_mesh.material = material
	tile.mesh = tile_mesh
	marker.add_child(tile)
	var label := Label3D.new()
	label.text = reason
	label.position.y = 0.72
	label.font_size = 34
	label.outline_size = 8
	label.modulate = Color("#ff6259") if severe else Color("#ffc247")
	label.outline_modulate = Color(0.03, 0.04, 0.06, 0.94)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	marker.add_child(label)
	validation_marked_cells[cell] = {"node": marker, "severe": severe}


func _mark_disconnected_roads(road_owners: Array[Node]) -> void:
	if road_owners.is_empty():
		return
	var visited := _largest_road_component(road_owners)
	for owner in road_owners:
		if visited.has(owner):
			continue
		var definition := _definition_by_id(String(owner.get_meta("definition_id", "")))
		var anchor: Vector2i = owner.get_meta("cell", Vector2i.ZERO)
		# Connectivity is a summary consequence. Keep exact bad port cells red and
		# mark only the island anchor amber so a whole valid-looking road is not red.
		_mark_validation_cell(anchor, "DISCONNECTED ISLAND", false)
func _fixture_faces_road(owner: Node3D) -> bool:
	var cell: Vector2i = owner.get_meta("cell", Vector2i.ZERO)
	# Placement already keeps the pole on the sidewalk edge. Accept whichever
	# adjacent edge contains road; the Polygon meshes' authored local forward is
	# not consistent between the lamp and signal head.
	for direction in DIRECTIONS.values():
		for neighbor in occupancy.get(cell + direction, []):
			var definition := _definition_by_id(String(neighbor.get_meta("definition_id", "")))
			if definition != null and definition.category == "Roads":
				return true
	return false


func _count_disconnected_roads(road_owners: Array[Node]) -> int:
	if road_owners.is_empty():
		return 0
	return road_owners.size() - _largest_road_component(road_owners).size()


func _largest_road_component(road_owners: Array[Node]) -> Dictionary:
	var globally_seen := {}
	var largest := {}
	for seed in road_owners:
		if globally_seen.has(seed):
			continue
		var component := {seed: true}
		var queue: Array[Node] = [seed]
		globally_seen[seed] = true
		while not queue.is_empty():
			var owner: Node = queue.pop_front() as Node
			for neighbor in _connected_road_owners(owner):
				if not component.has(neighbor):
					component[neighbor] = true
					globally_seen[neighbor] = true
					queue.append(neighbor)
		if component.size() > largest.size():
			largest = component
	return largest


func _connected_road_owners(owner: Node3D) -> Array[Node]:
	var result: Array[Node] = []
	var definition := _definition_by_id(String(owner.get_meta("definition_id", "")))
	if definition == null or definition.module_rules.is_empty():
		return result
	var turns := int(owner.get_meta("quarter_turns", 0))
	for port in RoadModuleRules.rotated_ports(definition.module_rules, turns):
		for edge_cell in _port_boundary_cells(owner, port):
			for candidate in occupancy.get(edge_cell + DIRECTIONS[port], []):
				var candidate_definition := _definition_by_id(String(candidate.get_meta("definition_id", "")))
				if candidate_definition == null or candidate_definition.module_rules.is_empty():
					continue
				var candidate_ports := RoadModuleRules.rotated_ports(candidate_definition.module_rules, int(candidate.get_meta("quarter_turns", 0)))
				var candidate_turns := int(candidate.get_meta("quarter_turns", 0))
				if candidate_ports.has(OPPOSITE[port]) and _road_ports_compatible(definition.module_rules, port, turns, candidate_definition.module_rules, OPPOSITE[port], candidate_turns) and not result.has(candidate):
					result.append(candidate)
	return result


func _port_boundary_cells(owner: Node3D, direction: String) -> Array[Vector2i]:
	var anchor: Vector2i = owner.get_meta("cell", Vector2i.ZERO)
	var definition := _definition_by_id(String(owner.get_meta("definition_id", "")))
	var footprint: Vector2i = definition.footprint
	if int(owner.get_meta("quarter_turns", 0)) % 2 == 1:
		footprint = Vector2i(footprint.y, footprint.x)
	var cells: Array[Vector2i] = []
	if direction in ["N", "S"]:
		var y := anchor.y if direction == "N" else anchor.y + footprint.y - 1
		for x in range(anchor.x, anchor.x + footprint.x):
			cells.append(Vector2i(x, y))
	else:
		var x := anchor.x if direction == "W" else anchor.x + footprint.x - 1
		for y in range(anchor.y, anchor.y + footprint.y):
			cells.append(Vector2i(x, y))
	var turns := int(owner.get_meta("quarter_turns", 0))
	var profile := RoadModuleRules.rotated_port_profile(definition.module_rules, direction, turns)
	var span := clampi(int(profile.get("span", cells.size())), 1, cells.size())
	if span >= cells.size():
		return cells
	var configured_offset := int(profile.get("offset", -1))
	var start := configured_offset if configured_offset >= 0 else int((cells.size() - span) / 2)
	start = clampi(start, 0, cells.size() - span)
	return cells.slice(start, start + span)


func _connection_state(cell: Vector2i, required_port: String, source_rules: Dictionary, source_definition: Resource, source_port: String, source_turns: int) -> int:
	# 0: absent, 1: compatible, 2: lane mismatch, 3: one-way arrows collide/diverge.
	if not occupancy.has(cell):
		return 0
	var found_port := false
	for neighbor in occupancy[cell]:
		var definition := _definition_by_id(String(neighbor.get_meta("definition_id", "")))
		if definition == null or definition.module_rules.is_empty():
			continue
		var ports := RoadModuleRules.rotated_ports(definition.module_rules, int(neighbor.get_meta("quarter_turns", 0)))
		if not ports.has(required_port):
			continue
		found_port = true
		var neighbor_turns := int(neighbor.get_meta("quarter_turns", 0))
		if _road_ports_compatible(source_rules, source_port, source_turns, definition.module_rules, required_port, neighbor_turns):
			return 1
		# A junction routes internally, so a road may enter or leave it on any arm;
		# it never has a "wrong direction". Any leftover mismatch there is a
		# lane-count problem, reported as state 2 below. Direction conflicts apply
		# only to road-to-road (straight/curve/transition) connections.
		if not (_is_junction_rules(source_rules) or _is_junction_rules(definition.module_rules)):
			var source_profile := RoadModuleRules.rotated_port_profile(source_rules, source_port, source_turns)
			var neighbor_profile := RoadModuleRules.rotated_port_profile(definition.module_rules, required_port, neighbor_turns)
			var source_total := int(source_profile.get("incoming", 0)) + int(source_profile.get("outgoing", 0))
			var neighbor_total := int(neighbor_profile.get("incoming", 0)) + int(neighbor_profile.get("outgoing", 0))
			if source_total == neighbor_total and int(source_profile.get("span", 0)) == int(neighbor_profile.get("span", 0)):
				return 3
	return 2 if found_port else 0


func _is_junction_rules(rules: Dictionary) -> bool:
	return String(rules.get("kind", "")) in ["intersection_4", "intersection_t"]


func _road_ports_compatible(a: Dictionary, a_port: String, a_turns: int, b: Dictionary, b_port: String, b_turns: int) -> bool:
	if not is_equal_approx(float(a.get("lane_width", 0.0)), float(b.get("lane_width", 0.0))):
		return false
	var a_profile := RoadModuleRules.rotated_port_profile(a, a_port, a_turns)
	var b_profile := RoadModuleRules.rotated_port_profile(b, b_port, b_turns)
	if int(a_profile.get("span", 0)) != int(b_profile.get("span", 0)):
		return false
	# Junctions match on lane count only; road-to-road keeps the strict directional
	# handshake so opposing one-way roads are still flagged head-on.
	if _is_junction_rules(a) or _is_junction_rules(b):
		return true
	return (
		int(a_profile.get("outgoing", 0)) == int(b_profile.get("incoming", 0))
		and int(a_profile.get("incoming", 0)) == int(b_profile.get("outgoing", 0))
	)
