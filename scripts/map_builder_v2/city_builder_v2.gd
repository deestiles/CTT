extends Node3D
class_name CityBuilderV2
## Top-down grid editor for map-builder v2 cities.
##
## Places REAL Synty prefabs on the 5 m grid and authors the gameplay-metadata
## layers (spawns, sidewalk routes, recovery points, boundary). The live 3D
## preview is rebuilt with the SAME GeneratedCityLoader the runtime uses, so what
## you build is exactly what plays; primitives are used only for gizmos and the
## hover/selection highlight. Saves ctt_city_v2 JSON under maps_v2/ and can launch
## the generated-city runtime with the current map (Test Map).

const Catalog := preload("res://scripts/map_builder_v2/city_module_catalog.gd")
const Schema := preload("res://scripts/map_builder_v2/city_map_schema.gd")
const Validator := preload("res://scripts/map_builder_v2/city_map_validator.gd")
const Loader := preload("res://scripts/drive/generated_city_loader.gd")
const GeneratedCity := preload("res://scripts/drive/generated_city.gd")
const ImageImport := preload("res://scripts/map_builder_v2/city_image_import.gd")
const RandomGen := preload("res://scripts/map_builder_v2/city_random_generator.gd")

const TEST_SCENE := "res://scenes/drive/generated_city_test.tscn"
const GRID := 5.0
const PALETTE_W := 236
const THUMB_PX := 128
# The full Synty Demo city, loadable as a read-only reference backdrop so the
# owner can study how the professionally-placed assets are arranged. Its ground
# sits ~43 m up (nested Demo coords), so drop it to the builder grid plane.
const DEMO_SCENE := "res://Assets/Synty/PolygonCity/Scenes/Demo.tscn"
const DEMO_GROUND_Y := 43.08

var _map: Dictionary = {}
var _selected: Dictionary = {}
var _turns: int = 0
var _undo: Array = []
var _redo: Array = []
var _current_route: Array = []
var _hover_cell := Vector2i.ZERO
var _painting := false
var _paint_seen := {}

var _cam: Camera3D
var _geometry: Node3D
var _markers: Node3D
var _hover: MeshInstance3D
var _sel_box: MeshInstance3D
var _selected_placed := -1     # index into _map.items of the clicked placed item
var _sel_cell := Vector2i(2147483647, 2147483647)   # cell the current selection was clicked on
var _item_nodes: Array = []    # instanced node per _map["items"] entry (index-aligned)
var _select_mode := false      # when true (or Alt held), left-click selects instead of placing
var _grid: MeshInstance3D
var _status: Label
var _sel_label: Label
var _name_edit: LineEdit

var _cam_center := Vector3(0, 0, 0)
var _cam_size := 160.0
var _panning := false
var _ui: CanvasLayer
var _dialog: AcceptDialog
var _stack_menu: PanelContainer
var _stack_menu_box: VBoxContainer
var _mode_button: Button
var _underlay: MeshInstance3D
var _reference: Node3D
var _ref_label: Label
var _palette_list: VBoxContainer

# Capture-group-from-reference state.
var _capture_mode := false
var _captured: Array = []       # [{prefab, xform:Transform3D, node}]
var _capture_markers: Node3D
var _capture_panel: PanelContainer
var _capture_list: VBoxContainer
var _capture_name: LineEdit
var _marquee_active := false
var _marquee_start := Vector2.ZERO
var _marquee_rect: Panel
var _image_edit: LineEdit
var _cells_edit: LineEdit
var _bright_edit: LineEdit
var _rotate_edit: LineEdit

# Accordion palette + lazy 3D thumbnails.
var _sections: Array = []
var _open_section := -1
var _thumb_cache := {}          # module id -> ImageTexture
var _thumb_queue: Array = []    # [{module, button}]
var _thumb_vp: SubViewport
var _thumb_cam: Camera3D
var _thumb_holder: Node3D

# Editor camera orbit (tilt to inspect building height).
var _cam_pitch := -90.0
var _cam_yaw := 0.0



func _ready() -> void:
	_maximize_window()
	_map = Schema.new_empty("my_city")
	_build_camera()
	_build_grid()
	_geometry = Node3D.new()
	_geometry.name = "Geometry"
	add_child(_geometry)
	_markers = Node3D.new()
	_markers.name = "Markers"
	add_child(_markers)
	_capture_markers = Node3D.new()
	_capture_markers.name = "CaptureMarkers"
	add_child(_capture_markers)
	_build_hover()
	_build_ui()
	var mods: Array = Catalog.modules()
	if not mods.is_empty():
		_select_module(mods[0])
	_rebuild()
	_update_camera()
	call_deferred("_thumb_worker")   # lazily render palette thumbnails
	if OS.has_environment("CTT_BUILDER_TEST"):
		call_deferred("_run_builder_test")


# --- Window / camera / grid ----------------------------------------------

## The game project is a small portrait window; a map editor needs room. Open the
## builder maximized and resizable so the (expand-stretch) viewport shows far more
## of the city. No-op headless. Only affects the running builder, not the game.
func _maximize_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	if win:
		win.unresizable = false
		win.min_size = Vector2i(900, 600)
		# Resize the game window itself (works for a floating window and resizes an
		# embedded one within the editor's Game panel). Match the primary screen so
		# a maximise fills it.
		var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
		if screen.x > 0 and screen.y > 0:
			win.size = Vector2i(int(screen.x * 0.9), int(screen.y * 0.9))
		else:
			win.size = Vector2i(1600, 900)
		win.move_to_center()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "EditorCamera"
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = _cam_size
	_cam.far = 4000.0
	_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_cam.current = true
	add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, -35.0, 0.0)
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.19, 0.23)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.62)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)


func _update_camera() -> void:
	if _cam == null:
		return
	_cam.size = _cam_size
	if _cam_pitch <= -88.0:
		# True top-down: look_at is degenerate straight down, so set rotation.
		_cam.global_position = Vector3(_cam_center.x, 400.0, _cam_center.z)
		_cam.rotation_degrees = Vector3(-90.0, _cam_yaw, 0.0)
		return
	var pitch := deg_to_rad(clampf(_cam_pitch, -88.0, -15.0))
	var yaw := deg_to_rad(_cam_yaw)
	var offset := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * 400.0
	_cam.global_position = _cam_center + offset
	_cam.look_at(_cam_center, Vector3.UP)


func _cycle_tilt() -> void:
	_cam_pitch = -55.0 if _cam_pitch <= -88.0 else (-32.0 if _cam_pitch <= -50.0 else -90.0)
	_update_camera()
	_set_status("View tilt %.0f°  (V tilt · , . orbit)" % _cam_pitch)


func _build_grid() -> void:
	_grid = MeshInstance3D.new()
	_grid.name = "Grid"
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var half := 400
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for i in range(-half, half + 1):
		var c := Color(0.4, 0.45, 0.5, 0.28)
		if i == 0:
			c = Color(0.75, 0.8, 0.85, 0.7)
		elif i % 10 == 0:
			c = Color(0.55, 0.6, 0.66, 0.5)      # major line every 10 cells (50 m)
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(i * GRID, 0.02, -half * GRID))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(i * GRID, 0.02, half * GRID))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(-half * GRID, 0.02, i * GRID))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(half * GRID, 0.02, i * GRID))
	im.surface_end()
	_grid.mesh = im
	add_child(_grid)


func _build_hover() -> void:
	_hover = MeshInstance3D.new()
	_hover.name = "Hover"
	var box := BoxMesh.new()
	box.size = Vector3(GRID, 0.4, GRID)
	_hover.mesh = box
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.3, 0.8, 1.0, 0.28)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover.material_override = mat
	add_child(_hover)
	# Selection highlight (a placed item that was clicked) -- a warmer colour.
	_sel_box = MeshInstance3D.new()
	_sel_box.name = "Selection"
	var sbox := BoxMesh.new()
	sbox.size = Vector3(GRID, 0.6, GRID)
	_sel_box.mesh = sbox
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(1.0, 0.78, 0.2, 0.35)
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sel_box.material_override = smat
	_sel_box.visible = false
	add_child(_sel_box)


# --- Rebuild preview ------------------------------------------------------

## Full rebuild of all geometry. Only for bulk changes (undo/redo/load/import/
## generate/clear); per-edit ops touch single nodes incrementally instead, so a
## click no longer re-instances the whole city. _item_nodes stays index-aligned
## with _map["items"] so a single item can be updated/removed in place.
func _rebuild() -> void:
	if _geometry:
		_geometry.queue_free()
	_geometry = Node3D.new()
	_geometry.name = "Geometry"
	add_child(_geometry)
	_item_nodes.clear()
	for raw in _map.get("items", []):
		_item_nodes.append(_spawn_item_node(raw))
	_rebuild_markers()


## Instance one map item's prefab and add it under _geometry; returns the node
## (or null if the id/prefab is missing, e.g. a marker).
func _spawn_item_node(raw: Variant) -> Node3D:
	if not (raw is Dictionary) or _geometry == null:
		return null
	var module: Dictionary = Catalog.by_id(String(raw.get("id", "")))
	if module.is_empty() or not Loader.is_placeable(module):
		return null
	var node := Loader.instance_item(module, _cell(raw.get("cell", [0, 0])), int(raw.get("turns", 0)), 0.0)
	if node:
		_geometry.add_child(node)
	return node


func _rebuild_markers() -> void:
	for c in _markers.get_children():
		c.queue_free()
	var spawns: Dictionary = _map.get("spawns", {})
	if spawns.has("police"):
		_marker_gizmo(_cell(spawns["police"]["cell"]), Color("#28a9ff"), "POLICE")
	if spawns.has("thief"):
		_marker_gizmo(_cell(spawns["thief"]["cell"]), Color("#ff344d"), "THIEF")
	for rp in _map.get("recovery_points", []):
		if rp is Dictionary:
			_marker_gizmo(_cell(rp["cell"]), Color("#42f5a7"), "R")
	for post in _map.get("boundary", []):
		_marker_post(_cell(post), Color("#b061ff"))
	var route_index := 0
	for route in _map.get("sidewalk_routes", []):
		_route_gizmo(route, Color("#ffce54"), route_index)
		route_index += 1
	if not _current_route.is_empty():
		_route_gizmo(_current_route, Color("#fff27a"), -1)


func _marker_gizmo(cell: Vector2i, color: Color, label: String) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 4.0, 2.4)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Schema.cell_center(cell, 2.0)
	_markers.add_child(mi)
	var l := Label3D.new()
	l.text = label
	l.font_size = 96
	l.modulate = Color.WHITE
	l.outline_size = 24
	l.pixel_size = 0.02
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Schema.cell_center(cell, 5.0)
	_markers.add_child(l)


func _marker_post(cell: Vector2i, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 3.0
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Schema.cell_center(cell, 1.5)
	_markers.add_child(mi)


func _route_gizmo(route: Array, color: Color, _index: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for raw_cell in route:
		var mi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.8
		sph.height = 1.6
		mi.mesh = sph
		mi.material_override = mat
		mi.position = Schema.cell_center(_cell(raw_cell), 1.0)
		_markers.add_child(mi)
	if route.size() >= 2:
		var line := MeshInstance3D.new()
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		for raw_cell in route:
			im.surface_add_vertex(Schema.cell_center(_cell(raw_cell), 1.0))
		im.surface_end()
		line.mesh = im
		_markers.add_child(line)


# --- Input ----------------------------------------------------------------

func _process(_delta: float) -> void:
	_update_hover()
	_update_ref_hover()
	# WASD / arrow panning.
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.y += 1
	if pan != Vector2.ZERO and not _name_edit.has_focus():
		_cam_center += Vector3(pan.x, 0, pan.y) * (_cam_size * 0.015)
		_update_camera()


func _current_cell() -> Vector2i:
	return Schema.world_to_cell(_mouse_to_ground())


## While the reference city is shown, name the asset under the cursor (physics
## raycast) in a small floating label. Purely informative.
func _update_ref_hover() -> void:
	if _ref_label == null:
		return
	if _reference == null or not _reference.visible or _cam == null:
		_ref_label.visible = false
		return
	var mouse := get_viewport().get_mouse_position()
	var from := _cam.project_ray_origin(mouse)
	var to := from + _cam.project_ray_normal(mouse) * 6000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_ref_label.visible = false
		return
	_ref_label.text = _asset_name_from(hit.get("collider"))
	_ref_label.reset_size()
	var vp := get_viewport().get_visible_rect().size
	var pos := mouse + Vector2(18.0, 14.0)
	pos.x = min(pos.x, vp.x - _ref_label.size.x - 8.0)
	pos.y = min(pos.y, vp.y - _ref_label.size.y - 8.0)
	_ref_label.position = pos
	_ref_label.visible = true


## Nearest ancestor Synty asset name (SM_*) of a hit collider; else the collider's
## own name. Trailing "_x_y" cell suffixes added to placed items are stripped.
func _asset_name_from(collider: Variant) -> String:
	var n := collider as Node
	while n != null:
		var nm := String(n.name)
		if nm.begins_with("SM_"):
			var parts := nm.split("_")
			# Drop a trailing "_<cell>_<cell>" suffix from placed items.
			if parts.size() >= 3 and parts[parts.size() - 1].is_valid_int() and parts[parts.size() - 2].lstrip("-").is_valid_int():
				parts.remove_at(parts.size() - 1)
				parts.remove_at(parts.size() - 1)
				return "_".join(parts)
			return nm
		n = n.get_parent()
	return String((collider as Node).name) if collider is Node else "?"


func _is_surface_selected() -> bool:
	return not _selected.is_empty() and not bool(_selected.get("is_marker", false)) \
		and int(_selected.get("layer", -1)) == Catalog.Layer.SURFACE


## Real footprint (in cells) measured from the prefab's mesh extent, so a big
## building shows a big cursor. Cached; also written back onto the module so
## placement occupancy matches the cursor. Markers/empty prefabs stay 1x1.
func _real_footprint(module: Dictionary) -> Vector2i:
	# Delegate to the loader so the cursor uses the exact footprint the loader
	# places by; also write it back so occupancy (overlap/replace) matches.
	var fp := Loader.asset_footprint(module)
	module["footprint"] = fp
	return fp


func _update_hover() -> void:
	_hover_cell = _current_cell()
	var footprint := Vector2i.ONE
	if not _selected.is_empty():
		footprint = _real_footprint(_selected)
	var cells := Schema.covered_cells(_hover_cell, footprint, _turns)
	var min_c := _hover_cell
	var max_c := _hover_cell
	for c in cells:
		min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
		max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	var span := Vector2i(max_c.x - min_c.x + 1, max_c.y - min_c.y + 1)
	(_hover.mesh as BoxMesh).size = Vector3(span.x * GRID, 0.4, span.y * GRID)
	_hover.position = Vector3((min_c.x + span.x * 0.5) * GRID, 0.25, (min_c.y + span.y * 0.5) * GRID)


func _mouse_to_ground() -> Vector3:
	var mouse := get_viewport().get_mouse_position()
	if _cam == null:
		return Vector3.ZERO
	var from := _cam.project_ray_origin(mouse)
	var dir := _cam.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	var t := -from.y / dir.y
	return from + dir * t


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_size = clampf(_cam_size * 0.9, 10.0, 3000.0)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_size = clampf(_cam_size * 1.1, 10.0, 3000.0)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Capture from the reference city, or place/select on the grid.
				if _capture_mode:
					_capture_begin_marquee()
				else:
					_handle_left_click(_current_cell(), mb.alt_pressed)
			else:
				if _marquee_active:
					_capture_end_marquee()
				else:
					_painting = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_delete_at_hover()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			_cam_center -= Vector3(mm.relative.x, 0, mm.relative.y) * (_cam_size * 0.0016)
			_update_camera()
		elif _marquee_active:
			_capture_update_marquee()
		elif _painting:
			_paint_step()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if _name_edit and _name_edit.has_focus():
			return
		match k.keycode:
			KEY_R:
				if _selected_placed >= 0:
					_rotate_selected_placed()
				else:
					_turns = posmod(_turns + 1, 4)
					_set_status("Rotation: %d°" % (_turns * 90))
			KEY_Z:
				if k.ctrl_pressed:
					_do_undo()
			KEY_Y:
				if k.ctrl_pressed:
					_do_redo()
			KEY_S:
				if k.ctrl_pressed:
					_save()
			KEY_H:
				_toggle_panels()
			KEY_F:
				_focus_on_content()
			KEY_V:
				_cycle_tilt()
			KEY_COMMA:
				_cam_yaw -= 15.0
				_update_camera()
			KEY_PERIOD:
				_cam_yaw += 15.0
				_update_camera()


# --- Editing operations ---------------------------------------------------

func _begin_edit() -> void:
	_undo.append(_snapshot())
	if _undo.size() > 100:
		_undo.pop_front()
	_redo.clear()


func _snapshot() -> Dictionary:
	return _map.duplicate(true)


## Click-drag painting of surface tiles (roads/sidewalks) to draw long runs.
## One undo entry per stroke; fills only empty cells, and instances each tile
## incrementally (no full rebuild) so dragging stays responsive.
func _begin_paint() -> void:
	_painting = true
	_paint_seen = {}
	_begin_edit()
	_paint_step()


func _paint_step() -> void:
	if _selected.is_empty():
		return
	var cell := _current_cell()
	if _paint_seen.has(cell):
		return
	_paint_seen[cell] = true
	if _cell_has_layer(cell, [Catalog.Layer.SURFACE, Catalog.Layer.STRUCTURE]):
		return
	var item := {"id": _selected["id"], "cell": [cell.x, cell.y], "turns": _turns}
	_map["items"].append(item)
	_item_nodes.append(_spawn_item_node(item))    # incremental: one tile, no full rebuild
	_set_status("Painted %d tile(s)" % _paint_seen.size())


func _cell_has_layer(cell: Vector2i, layers: Array) -> bool:
	for raw in _map.get("items", []):
		if not (raw is Dictionary):
			continue
		var module: Dictionary = Catalog.by_id(String(raw.get("id", "")))
		if module.is_empty() or not (int(module.get("layer", -1)) in layers):
			continue
		var occ := Schema.covered_cells(_cell(raw.get("cell", [0, 0])), module.get("footprint", Vector2i.ONE), int(raw.get("turns", 0)))
		if cell in occ:
			return true
	return false


func _place_at_hover() -> void:
	if _selected.is_empty():
		return
	var kind := String(_selected.get("marker_kind", ""))
	if bool(_selected.get("is_marker", false)):
		_place_marker(kind)
		return
	_begin_edit()
	var layer: int = _selected.get("layer", Catalog.Layer.SURFACE)
	var footprint: Vector2i = _real_footprint(_selected)
	var cells := Schema.covered_cells(_hover_cell, footprint, _turns)
	# Surfaces and structures are exclusive per cell; remove anything overlapping.
	if layer == Catalog.Layer.SURFACE or layer == Catalog.Layer.STRUCTURE:
		_remove_items_on_cells(cells, [Catalog.Layer.SURFACE, Catalog.Layer.STRUCTURE])
	var item := {"id": _selected["id"], "cell": [_hover_cell.x, _hover_cell.y], "turns": _turns}
	_map["items"].append(item)
	_item_nodes.append(_spawn_item_node(item))    # incremental: one item, no full rebuild
	_set_status("Placed %s @ (%d,%d)" % [_selected["display_name"], _hover_cell.x, _hover_cell.y])


func _place_marker(kind: String) -> void:
	_begin_edit()
	match kind:
		"police_spawn":
			_map["spawns"]["police"] = {"cell": [_hover_cell.x, _hover_cell.y], "turns": _turns}
		"thief_spawn":
			_map["spawns"]["thief"] = {"cell": [_hover_cell.x, _hover_cell.y], "turns": _turns}
		"recovery":
			_map["recovery_points"].append({"cell": [_hover_cell.x, _hover_cell.y], "turns": _turns})
		"boundary":
			_map["boundary"].append([_hover_cell.x, _hover_cell.y])
		"sidewalk_route":
			_current_route.append([_hover_cell.x, _hover_cell.y])
	_rebuild_markers()
	_set_status("Marker %s @ (%d,%d)" % [kind, _hover_cell.x, _hover_cell.y])


# --- Select / rotate a placed item ---------------------------------------

## All placed item indices covering `cell`, topmost (last-placed) first.
func _items_at(cell: Vector2i) -> Array:
	var out: Array = []
	var items: Array = _map.get("items", [])
	for i in range(items.size() - 1, -1, -1):
		var raw = items[i]
		if not (raw is Dictionary):
			continue
		var module: Dictionary = Catalog.by_id(String(raw.get("id", "")))
		if module.is_empty():
			continue
		if cell in Schema.covered_cells(_cell(raw.get("cell", [0, 0])), Loader.asset_footprint(module), int(raw.get("turns", 0))):
			out.append(i)
	return out


## Topmost item covering `cell`, or -1.
func _item_index_at(cell: Vector2i) -> int:
	var stack := _items_at(cell)
	return stack[0] if not stack.is_empty() else -1


## Which item to select on a click: the topmost, unless we're clicking the same
## cell again and the current selection is in its stack -- then advance (cycle).
func _select_index_for(cell: Vector2i) -> int:
	var stack := _items_at(cell)
	if stack.is_empty():
		return -1
	var chosen: int = stack[0]
	if cell == _sel_cell and stack.has(_selected_placed):
		chosen = stack[(stack.find(_selected_placed) + 1) % stack.size()]
	_sel_cell = cell
	return chosen


func _select_placed(idx: int) -> void:
	_selected_placed = idx
	_update_sel_box()
	var raw = _map["items"][idx]
	var module: Dictionary = Catalog.by_id(String(raw.get("id", "")))
	var here := _items_at(_cell(raw.get("cell", [0, 0])))
	var extra := ""
	if here.size() > 1:
		var pos := here.find(idx)
		extra = "  ·  item %d/%d (click to cycle)" % [pos + 1 if pos >= 0 else 1, here.size()]
	_set_status("Selected: %s%s  ·  R rotate · right-click remove" % [module.get("display_name", "item"), extra], Color("#ffce54"))


func _deselect_placed() -> void:
	_selected_placed = -1
	_sel_cell = Vector2i(2147483647, 2147483647)
	if _sel_box:
		_sel_box.visible = false
	_hide_stack_menu()


## Default: left-click PLACES the palette asset (props layer on top, surfaces
## replace), so you can stack a lamp/prop onto an existing sidewalk. Selecting a
## placed item is explicit: Select mode on, or hold Alt -- then one item selects,
## several show a pick menu. A world click while the menu is open just closes it.
func _handle_left_click(cell: Vector2i, alt: bool) -> void:
	if _stack_menu != null and _stack_menu.visible:
		_hide_stack_menu()
		return
	if _select_mode or alt:
		var stack := _items_at(cell)
		if stack.size() > 1:
			_show_stack_menu(stack)
		elif stack.size() == 1:
			_select_placed(stack[0])
		else:
			_deselect_placed()
		return
	# Place mode (default).
	_deselect_placed()
	if _is_surface_selected():
		_begin_paint()
	else:
		_place_at_hover()


func _toggle_select_mode() -> void:
	_select_mode = not _select_mode
	if not _select_mode:
		_deselect_placed()
	_update_mode_button()
	_set_status("Select mode %s  ·  %s" % [
		"ON — click a placed item to edit it" if _select_mode else "OFF — click places assets",
		"Alt+click also selects"], Color("#ffce54") if _select_mode else Color.WHITE)


func _update_mode_button() -> void:
	if _mode_button:
		_mode_button.text = "Mode: SELECT" if _select_mode else "Mode: PLACE"
		_mode_button.add_theme_color_override("font_color", Color("#ffce54") if _select_mode else Color.WHITE)


func _show_stack_menu(indices: Array) -> void:
	for c in _stack_menu_box.get_children():
		c.queue_free()
	var header := Label.new()
	header.text = "This square (%d):" % indices.size()
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color("#ffce54"))
	_stack_menu_box.add_child(header)
	for idx in indices:
		var raw = _map["items"][idx]
		var module: Dictionary = Catalog.by_id(String(raw.get("id", "")))
		var b := Button.new()
		b.text = String(module.get("display_name", "item"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(180, 0)
		b.pressed.connect(_on_stack_pick.bind(idx))
		_stack_menu_box.add_child(b)
	_stack_menu.reset_size()
	var vp := get_viewport().get_visible_rect().size
	var pos := get_viewport().get_mouse_position() + Vector2(12, 12)
	pos.x = clampf(pos.x, 0.0, vp.x - _stack_menu.size.x)
	pos.y = clampf(pos.y, 0.0, vp.y - _stack_menu.size.y)
	_stack_menu.position = pos
	_stack_menu.visible = true


func _on_stack_pick(idx: int) -> void:
	_hide_stack_menu()
	if idx >= 0 and idx < (_map.get("items", []) as Array).size():
		_select_placed(idx)


func _hide_stack_menu() -> void:
	if _stack_menu:
		_stack_menu.visible = false


func _rotate_selected_placed() -> void:
	var items: Array = _map.get("items", [])
	if _selected_placed < 0 or _selected_placed >= items.size():
		_deselect_placed()
		return
	_begin_edit()
	var raw = items[_selected_placed]
	raw["turns"] = posmod(int(raw.get("turns", 0)) + 1, 4)
	# Re-instance only this item's node (no full rebuild).
	if _selected_placed < _item_nodes.size():
		var old = _item_nodes[_selected_placed]
		if is_instance_valid(old):
			old.queue_free()
		_item_nodes[_selected_placed] = _spawn_item_node(raw)
	_update_sel_box()
	_set_status("Rotated to %d°  (R again to keep turning)" % (int(raw["turns"]) * 90), Color("#ffce54"))


func _update_sel_box() -> void:
	if _sel_box == null:
		return
	var items: Array = _map.get("items", [])
	if _selected_placed < 0 or _selected_placed >= items.size():
		_sel_box.visible = false
		return
	var raw = items[_selected_placed]
	var module: Dictionary = Catalog.by_id(String(raw.get("id", "")))
	if module.is_empty():
		_sel_box.visible = false
		return
	var anchor := _cell(raw.get("cell", [0, 0]))
	var cells := Schema.covered_cells(anchor, Loader.asset_footprint(module), int(raw.get("turns", 0)))
	var min_c := cells[0] as Vector2i
	var max_c := cells[0] as Vector2i
	for c in cells:
		min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
		max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	var span := Vector2i(max_c.x - min_c.x + 1, max_c.y - min_c.y + 1)
	(_sel_box.mesh as BoxMesh).size = Vector3(span.x * GRID, 0.6, span.y * GRID)
	_sel_box.position = Vector3((min_c.x + span.x * 0.5) * GRID, 0.35, (min_c.y + span.y * 0.5) * GRID)
	_sel_box.visible = true


func _delete_at_hover() -> void:
	var items: Array = _map.get("items", [])
	# If a specific item is selected and it's under the cursor, remove THAT one
	# (so you can cycle-select a stacked item and delete exactly it).
	if _selected_placed >= 0 and _selected_placed < items.size():
		var sraw = items[_selected_placed]
		var sm: Dictionary = Catalog.by_id(String(sraw.get("id", "")))
		if not sm.is_empty() and _hover_cell in Schema.covered_cells(_cell(sraw.get("cell", [0, 0])), Loader.asset_footprint(sm), int(sraw.get("turns", 0))):
			var idx := _selected_placed
			_begin_edit()
			_deselect_placed()
			_remove_item_at(idx)
			_set_status("Deleted %s" % sm.get("display_name", "item"))
			return
	# Otherwise remove the topmost item covering the hovered cell, else a marker.
	for i in range(items.size() - 1, -1, -1):
		var raw = items[i]
		if not (raw is Dictionary):
			continue
		var module: Dictionary = Catalog.by_id(String(raw.get("id", "")))
		if module.is_empty():
			continue
		var cells := Schema.covered_cells(_cell(raw.get("cell", [0, 0])), Loader.asset_footprint(module), int(raw.get("turns", 0)))
		if _hover_cell in cells:
			_begin_edit()
			_deselect_placed()
			_remove_item_at(i)              # incremental: frees one node, no full rebuild
			_set_status("Deleted %s" % module.get("display_name", "item"))
			return
	# No geometry: try markers on the cell.
	if _delete_marker_at(_hover_cell):
		_rebuild_markers()


func _delete_marker_at(cell: Vector2i) -> bool:
	var changed := false
	var spawns: Dictionary = _map.get("spawns", {})
	for key in ["police", "thief"]:
		if spawns.has(key) and _cell(spawns[key]["cell"]) == cell:
			_begin_edit()
			spawns.erase(key)
			changed = true
	var boundary: Array = _map.get("boundary", [])
	for i in range(boundary.size() - 1, -1, -1):
		if _cell(boundary[i]) == cell:
			if not changed:
				_begin_edit()
			boundary.remove_at(i)
			changed = true
	var recovery: Array = _map.get("recovery_points", [])
	for i in range(recovery.size() - 1, -1, -1):
		if recovery[i] is Dictionary and _cell(recovery[i]["cell"]) == cell:
			if not changed:
				_begin_edit()
			recovery.remove_at(i)
			changed = true
	return changed


func _remove_items_on_cells(cells: Array, layers: Array) -> void:
	var items: Array = _map.get("items", [])
	for i in range(items.size() - 1, -1, -1):
		var raw = items[i]
		if not (raw is Dictionary):
			continue
		var module: Dictionary = Catalog.by_id(String(raw.get("id", "")))
		if module.is_empty() or not (int(module.get("layer", -1)) in layers):
			continue
		var occ := Schema.covered_cells(_cell(raw.get("cell", [0, 0])), Loader.asset_footprint(module), int(raw.get("turns", 0)))
		for c in occ:
			if c in cells:
				_remove_item_at(i)
				break


## Remove item i from the map AND its instanced node, keeping the arrays aligned.
func _remove_item_at(i: int) -> void:
	if i >= 0 and i < _item_nodes.size():
		var node = _item_nodes[i]
		if is_instance_valid(node):
			node.queue_free()
		_item_nodes.remove_at(i)
	(_map["items"] as Array).remove_at(i)


func _do_undo() -> void:
	if _undo.is_empty():
		_set_status("Nothing to undo")
		return
	_redo.append(_snapshot())
	_map = _undo.pop_back()
	_deselect_placed()
	_rebuild()
	_set_status("Undo")


func _do_redo() -> void:
	if _redo.is_empty():
		_set_status("Nothing to redo")
		return
	_undo.append(_snapshot())
	_map = _redo.pop_back()
	_deselect_placed()
	_rebuild()
	_set_status("Redo")


func _finish_route() -> void:
	if _current_route.size() < 2:
		_set_status("Route needs at least 2 nodes")
		return
	_begin_edit()
	_map["sidewalk_routes"].append(_current_route.duplicate())
	_current_route.clear()
	_rebuild_markers()
	_set_status("Route committed (%d total)" % (_map["sidewalk_routes"] as Array).size())


func _clear_map() -> void:
	_begin_edit()
	_map = Schema.new_empty(_current_name())
	_current_route.clear()
	_deselect_placed()
	_rebuild()
	_set_status("Cleared")


# --- Save / load / validate / test ---------------------------------------

func _current_name() -> String:
	var n := _name_edit.text.strip_edges() if _name_edit else ""
	return n if not n.is_empty() else "my_city"


func _save() -> void:
	_map["name"] = _current_name()
	var path := Schema.repo_path(_current_name())
	var err: int = Schema.save(path, _map)
	if err == OK:
		var full := ProjectSettings.globalize_path(path)
		var count: int = (_map.get("items", []) as Array).size()
		_set_status("Saved %s" % path, Color("#42f5a7"))
		_popup("Map Saved", "Saved \"%s\" (%d items)\n\n%s" % [_current_name(), count, full])
	else:
		_set_status("SAVE FAILED err=%d" % err, Color("#ff5a4d"))
		_popup("Save Failed", "Could not save (error %d).\nTried: %s" % [err, ProjectSettings.globalize_path(path)])


func _load() -> void:
	var path := Schema.repo_path(_current_name())
	var loaded: Dictionary = Schema.load_from(path)
	if loaded.is_empty():
		_set_status("LOAD FAILED — no %s" % path, Color("#ffb52e"))
		_popup("Load Failed", "No saved map named \"%s\".\nLooked in: %s" % [
			_current_name(), ProjectSettings.globalize_path(path)])
		return
	_begin_edit()
	_map = loaded
	_current_route.clear()
	_deselect_placed()
	_rebuild()
	var loaded_count: int = (_map.get("items", []) as Array).size()
	_set_status("Loaded %s (%d items)" % [path, loaded_count], Color("#42f5a7"))
	_popup("Map Loaded", "Loaded \"%s\" (%d items)." % [_current_name(), loaded_count])
	_focus_on_content()


func _validate() -> void:
	var r: Dictionary = Validator.validate_static(_map)
	var errors: Array = r["errors"]
	var warnings: Array = r["warnings"]
	var lines: Array = []
	if r["valid"] and warnings.is_empty():
		lines.append("VALID — ready to Test Map.")
		_set_status("VALID ✓", Color("#42f5a7"))
	elif r["valid"]:
		lines.append("VALID (with %d warning(s)):" % warnings.size())
		_set_status("VALID, %d warning(s)" % warnings.size(), Color("#ffce54"))
	else:
		lines.append("INVALID — fix these before Test Map:")
		_set_status("INVALID — %d error(s)" % errors.size(), Color("#ff5a4d"))
	for e in errors:
		lines.append("  ✗ %s" % e["message"])
	for w in warnings:
		lines.append("  ⚠ %s" % w["message"])
	lines.append("")
	lines.append("Stats: %s" % r["stats"])
	_popup("Validation", "\n".join(lines))


func _test_map() -> void:
	var r: Dictionary = Validator.validate_static(_map)
	if not r["valid"]:
		var lines: Array = ["Can't test yet — fix these first:"]
		for e in r["errors"]:
			lines.append("  ✗ %s" % e["message"])
		_set_status("TEST BLOCKED — %d error(s)" % (r["errors"] as Array).size(), Color("#ff5a4d"))
		_popup("Test Map Blocked", "\n".join(lines))
		return
	_map["name"] = _current_name()
	var path := Schema.repo_path(_current_name())
	if Schema.save(path, _map) != OK:
		_set_status("TEST BLOCKED — save failed", Color("#ff5a4d"))
		_popup("Test Map Blocked", "Could not save the map before testing.")
		return
	GeneratedCity.override_map_path = path
	get_tree().change_scene_to_file(TEST_SCENE)


# --- UI -------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	_ui = layer
	_dialog = AcceptDialog.new()
	_dialog.title = "City Builder"
	_dialog.dialog_hide_on_ok = true
	layer.add_child(_dialog)
	# Floating label naming the asset under the cursor in the reference city.
	_ref_label = Label.new()
	_ref_label.visible = false
	_ref_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ref_label.z_index = 30
	_ref_label.add_theme_color_override("font_color", Color.WHITE)
	_ref_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_ref_label.add_theme_constant_override("outline_size", 6)
	_ref_label.add_theme_font_size_override("font_size", 15)
	layer.add_child(_ref_label)
	# Pick menu shown when clicking a square that holds several assets.
	_stack_menu = PanelContainer.new()
	_stack_menu.visible = false
	_stack_menu.z_index = 40
	var menu_style := StyleBoxFlat.new()
	menu_style.bg_color = Color(0.05, 0.07, 0.11, 0.97)
	menu_style.border_color = Color("#ffce54")
	menu_style.set_border_width_all(2)
	menu_style.set_corner_radius_all(8)
	menu_style.set_content_margin_all(6)
	_stack_menu.add_theme_stylebox_override("panel", menu_style)
	_stack_menu_box = VBoxContainer.new()
	_stack_menu_box.add_theme_constant_override("separation", 2)
	_stack_menu.add_child(_stack_menu_box)
	layer.add_child(_stack_menu)
	# Capture-group panel (shown in capture mode).
	_capture_panel = PanelContainer.new()
	_capture_panel.visible = false
	_capture_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_capture_panel.offset_left = -270
	_capture_panel.offset_top = 92
	_capture_panel.offset_right = -12
	var cap_style := StyleBoxFlat.new()
	cap_style.bg_color = Color(0.05, 0.08, 0.12, 0.96)
	cap_style.border_color = Color("#8be0ff")
	cap_style.set_border_width_all(2)
	cap_style.set_corner_radius_all(8)
	cap_style.set_content_margin_all(8)
	_capture_panel.add_theme_stylebox_override("panel", cap_style)
	var cap_box := VBoxContainer.new()
	cap_box.add_theme_constant_override("separation", 4)
	_capture_panel.add_child(cap_box)
	var cap_title := Label.new()
	cap_title.text = "CAPTURE GROUP"
	cap_title.add_theme_color_override("font_color", Color("#8be0ff"))
	cap_box.add_child(cap_title)
	var cap_help := Label.new()
	cap_help.text = "Drag a box over the reference to select many assets, or click one (click again to remove)."
	cap_help.autowrap_mode = TextServer.AUTOWRAP_WORD
	cap_help.custom_minimum_size = Vector2(246, 0)
	cap_help.add_theme_font_size_override("font_size", 11)
	cap_box.add_child(cap_help)
	_capture_list = VBoxContainer.new()
	cap_box.add_child(_capture_list)
	_capture_name = LineEdit.new()
	_capture_name.placeholder_text = "group name"
	cap_box.add_child(_capture_name)
	var cap_buttons := HBoxContainer.new()
	cap_box.add_child(cap_buttons)
	_add_button(cap_buttons, "Save Group", _save_group)
	_add_button(cap_buttons, "Clear", _clear_capture)
	_add_button(cap_buttons, "Done", _toggle_capture_mode)
	layer.add_child(_capture_panel)
	# Rubber-band selection rectangle (capture mode).
	_marquee_rect = Panel.new()
	_marquee_rect.visible = false
	_marquee_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marquee_rect.z_index = 35
	var mq_style := StyleBoxFlat.new()
	mq_style.bg_color = Color(0.3, 0.9, 1.0, 0.15)
	mq_style.border_color = Color("#8be0ff")
	mq_style.set_border_width_all(1)
	_marquee_rect.add_theme_stylebox_override("panel", mq_style)
	layer.add_child(_marquee_rect)

	# Top toolbar.
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size = Vector2(0, 46)
	layer.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	top.add_child(bar)
	var title := Label.new()
	title.text = "CITY BUILDER V2"
	bar.add_child(title)
	_name_edit = LineEdit.new()
	_name_edit.text = "my_city"
	_name_edit.custom_minimum_size = Vector2(160, 0)
	bar.add_child(_name_edit)
	_add_button(bar, "Save (Ctrl+S)", _save)
	_add_button(bar, "Load", _load)
	_add_button(bar, "Validate", _validate)
	_add_button(bar, "Test Map", _test_map)
	_add_button(bar, "Undo", _do_undo)
	_add_button(bar, "Redo", _do_redo)
	_add_button(bar, "Finish Route", _finish_route)
	_add_button(bar, "Clear", _clear_map)
	_mode_button = Button.new()
	_mode_button.text = "Mode: PLACE"
	_mode_button.pressed.connect(_toggle_select_mode)
	bar.add_child(_mode_button)
	_add_button(bar, "Fit View (F)", _focus_on_content)
	_add_button(bar, "Tilt (V)", _cycle_tilt)
	_add_button(bar, "Reference City", _toggle_reference)
	_add_button(bar, "Capture Group", _toggle_capture_mode)
	_add_button(bar, "Hide Panels (H)", _toggle_panels)

	# Import toolbar (second row): trace/generate a city from a map image.
	var imp := PanelContainer.new()
	imp.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	imp.offset_top = 46
	imp.offset_bottom = 86
	layer.add_child(imp)
	var ibar := HBoxContainer.new()
	ibar.add_theme_constant_override("separation", 6)
	imp.add_child(ibar)
	var ilabel := Label.new()
	ilabel.text = "Map image:"
	ibar.add_child(ilabel)
	_image_edit = LineEdit.new()
	_image_edit.placeholder_text = "C:\\path\\to\\map.png  (or res://…)"
	_image_edit.custom_minimum_size = Vector2(320, 0)
	ibar.add_child(_image_edit)
	ibar.add_child(_mini_label("cells across"))
	_cells_edit = LineEdit.new()
	_cells_edit.text = "80"
	_cells_edit.custom_minimum_size = Vector2(52, 0)
	ibar.add_child(_cells_edit)
	ibar.add_child(_mini_label("road grey<"))
	_bright_edit = LineEdit.new()
	_bright_edit.text = "0.86"
	_bright_edit.tooltip_text = "Roads are grey lines darker than this; whiter background is land and lighter-grey blobs are buildings. Raise if streets are missed; lower if building footprints get taken as road."
	_bright_edit.custom_minimum_size = Vector2(56, 0)
	ibar.add_child(_bright_edit)
	ibar.add_child(_mini_label("rotate°"))
	_rotate_edit = LineEdit.new()
	_rotate_edit.placeholder_text = "auto"
	_rotate_edit.tooltip_text = "Leave blank to auto-straighten the map to the street grid, or type degrees to rotate manually (e.g. -16). Re-import to apply."
	_rotate_edit.custom_minimum_size = Vector2(52, 0)
	ibar.add_child(_rotate_edit)
	_add_button(ibar, "Import Image", _import_image)
	_add_button(ibar, "Toggle Underlay", _toggle_underlay)
	_add_button(ibar, "Generate City", _generate_city)

	# Left palette: collapsible (accordion) category sections with 3D thumbnails.
	var pstyle := PanelContainer.new()
	pstyle.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	pstyle.offset_top = 88
	pstyle.offset_bottom = -70
	pstyle.custom_minimum_size = Vector2(PALETTE_W, 0)
	layer.add_child(pstyle)
	var palette := ScrollContainer.new()
	palette.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	palette.offset_top = 88
	palette.offset_bottom = -70
	palette.custom_minimum_size = Vector2(PALETTE_W, 0)
	palette.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layer.add_child(palette)
	_palette_list = VBoxContainer.new()
	_palette_list.add_theme_constant_override("separation", 2)
	_palette_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette.add_child(_palette_list)
	_rebuild_palette()

	# Bottom status + selection.
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.custom_minimum_size = Vector2(0, 64)
	layer.add_child(bottom)
	var bbox := VBoxContainer.new()
	bottom.add_child(bbox)
	_sel_label = Label.new()
	_sel_label.text = "Selected: —"
	bbox.add_child(_sel_label)
	_status = Label.new()
	_status.text = "L-click places (props layer on top) · Alt+click or Mode:SELECT to edit a placed item · R rotate · R-click delete · drag paint roads · wheel zoom · MMB/WASD pan · F fit · V tilt"
	bbox.add_child(_status)


func _toggle_panels() -> void:
	if _ui:
		_ui.visible = not _ui.visible


## Frame the whole map: center the camera on all placed items/markers and zoom to
## fit, so a big city is viewable at a glance. F key or on demand.
func _focus_on_content() -> void:
	var cells: Array = []
	for raw in _map.get("items", []):
		if raw is Dictionary:
			cells.append(_cell(raw.get("cell", [0, 0])))
	var spawns: Dictionary = _map.get("spawns", {})
	for key in ["police", "thief"]:
		if spawns.has(key):
			cells.append(_cell(spawns[key]["cell"]))
	if cells.is_empty():
		_cam_center = Vector3.ZERO
		_cam_size = 160.0
		_update_camera()
		return
	var min_c := cells[0] as Vector2i
	var max_c := cells[0] as Vector2i
	for c in cells:
		min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
		max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	var center_cell := Vector3((min_c.x + max_c.x + 1) * 0.5 * GRID, 0, (min_c.y + max_c.y + 1) * 0.5 * GRID)
	_cam_center = center_cell
	var span := maxf((max_c.x - min_c.x + 2) * GRID, (max_c.y - min_c.y + 2) * GRID)
	_cam_size = clampf(span * 1.15, 20.0, 3000.0)
	_update_camera()
	_set_status("Framed map (%d cells)" % cells.size())


func _mini_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	return l


# --- Map-image import -----------------------------------------------------

func _import_image() -> void:
	var path := _image_edit.text.strip_edges() if _image_edit else ""
	if path.is_empty():
		_popup("Import Image", "Enter the path to a top-down map image (PNG/JPG) first.")
		return
	var img := _load_image(path)
	if img == null:
		_popup("Import Failed", "Could not load an image at:\n%s\n\nUse a full path (e.g. C:\\Users\\you\\map.png) or a res:// path." % path)
		return
	var cells := 80
	if _cells_edit and _cells_edit.text.is_valid_int():
		cells = clampi(_cells_edit.text.to_int(), 8, 400)
	var ceiling := 0.90
	if _bright_edit and _bright_edit.text.is_valid_float():
		ceiling = clampf(_bright_edit.text.to_float(), 0.3, 1.0)
	var import_opts := {"cells_across": cells, "road_ceiling": ceiling}
	if _rotate_edit and _rotate_edit.text.strip_edges().is_valid_float():
		import_opts["rotation_override"] = _rotate_edit.text.to_float()
	var result: Dictionary = ImageImport.build_map_from_image(img, import_opts)
	_begin_edit()
	_map = result["data"]
	_current_route.clear()
	_deselect_placed()
	_rebuild()
	_show_underlay(img, int(result["cells_across"]), int(result["cells_down"]))
	_focus_on_content()
	_set_status("Imported %d roads (%d major) / %d sidewalks / %d buildings  (deskew %.0f°)" % [result["roads"], result.get("major_roads", 0), result["sidewalks"], result["buildings"], result.get("rotation_deg", 0.0)], Color("#42f5a7"))
	_popup("Image Imported", "Placed from the image (replacing the current map):\n  roads: %d  (%d major two-lane)\n  sidewalks: %d\n  buildings: %d\n  map rotated %.0f° to align streets to the grid\n\nThe map was deskewed so the majority of streets run N/S/E/W; diagonal/curved roads that don't fit the box grid are dropped. Road tiles follow each street; thick roads use lane-line tiles, normal streets a centre line; corners/junctions use plain asphalt.\n\nThe image is shown underneath as a tracing guide (Toggle Underlay).\nNext: place a Police Spawn and Thief Spawn on road cells, Validate, and Test Map." % [result["roads"], result.get("major_roads", 0), result["sidewalks"], result["buildings"], result.get("rotation_deg", 0.0)])


func _load_image(path: String) -> Image:
	if path.begins_with("res://") or path.begins_with("user://"):
		var res := load(path)
		if res is Texture2D:
			return (res as Texture2D).get_image()
		if res is Image:
			return res as Image
		return null
	return Image.load_from_file(path)


func _show_underlay(img: Image, cols: int, rows: int) -> void:
	if _underlay:
		_underlay.queue_free()
	_underlay = MeshInstance3D.new()
	_underlay.name = "Underlay"
	var plane := PlaneMesh.new()
	plane.size = Vector2(cols * GRID, rows * GRID)
	_underlay.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.5)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_underlay.material_override = mat
	# Sit just below the grid/tiles so placed geometry renders on top.
	_underlay.position = Vector3(cols * GRID * 0.5, -0.12, rows * GRID * 0.5)
	add_child(_underlay)


## Load the full Synty Demo city as a read-only reference backdrop (dropped to the
## grid plane), or toggle it if already loaded. Great for studying how assets are
## placed, then rebuilding on the grid. It is purely visual -- placement still
## raycasts the math ground plane, not this scene.
func _toggle_reference() -> void:
	if _reference != null:
		_reference.visible = not _reference.visible
		_set_status("Reference city %s" % ("shown" if _reference.visible else "hidden"))
		return
	var scene: PackedScene = load(DEMO_SCENE)
	if scene == null:
		_popup("Reference City", "Could not load the Demo city:\n%s" % DEMO_SCENE)
		return
	_set_status("Loading reference city…")
	_reference = Node3D.new()
	_reference.name = "ReferenceCity"
	_reference.position = Vector3(0.0, -DEMO_GROUND_Y, 0.0)
	add_child(_reference)
	_reference.add_child(scene.instantiate())
	_deactivate_cameras(_reference)
	_set_status("Reference city loaded — tilt (V) / orbit (, .) to study it; button again to hide", Color("#42f5a7"))
	_popup("Reference City", "Loaded the full Synty city as a read-only backdrop, dropped to the grid.\n\nTilt (V) and orbit (, / .) to see how assets are placed, then build your grid over it. Click 'Reference City' again to hide it.")


func _deactivate_cameras(node: Node) -> void:
	if node is Camera3D:
		(node as Camera3D).current = false
	for c in node.get_children():
		_deactivate_cameras(c)


# --- Capture a group from the reference city ------------------------------

func _toggle_capture_mode() -> void:
	if not _capture_mode and (_reference == null or not _reference.visible):
		_popup("Capture Group", "Load the Reference City first (button), then Capture Group and click assets in it.")
		return
	_capture_mode = not _capture_mode
	_capture_panel.visible = _capture_mode
	if _capture_mode:
		_deselect_placed()
		_set_status("Capture ON — click assets in the reference city, then Save Group", Color("#8be0ff"))
	else:
		_clear_capture()
		_set_status("Capture off")


## Raycast the cursor into the reference and add/remove the hit prefab asset.
func _capture_pick() -> void:
	if _cam == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var from := _cam.project_ray_origin(mouse)
	var to := from + _cam.project_ray_normal(mouse) * 6000.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		return
	var asset := _prefab_instance_ancestor(hit.get("collider"))
	if asset == null or asset.scene_file_path == "":
		_set_status("That isn't a placeable prefab asset")
		return
	for k in _captured.size():
		if _captured[k]["node"] == asset:
			_captured.remove_at(k)
			_rebuild_capture_markers()
			_update_capture_panel()
			return
	_captured.append({"prefab": asset.scene_file_path, "xform": asset.global_transform, "node": asset})
	_add_capture_marker(asset)
	_update_capture_panel()
	_set_status("Captured %d asset(s)" % _captured.size(), Color("#8be0ff"))


func _capture_begin_marquee() -> void:
	_marquee_active = true
	_marquee_start = get_viewport().get_mouse_position()
	if _marquee_rect:
		_marquee_rect.position = _marquee_start
		_marquee_rect.size = Vector2.ZERO
		_marquee_rect.visible = true


func _capture_update_marquee() -> void:
	if _marquee_rect == null:
		return
	var r := Rect2(_marquee_start, Vector2.ZERO).expand(get_viewport().get_mouse_position())
	_marquee_rect.position = r.position
	_marquee_rect.size = r.size


## On release: a tiny drag is a single-click pick; a real box selects every
## reference asset whose on-screen position falls inside it (including ones
## hidden behind others, since this projects positions rather than raycasting).
func _capture_end_marquee() -> void:
	_marquee_active = false
	if _marquee_rect:
		_marquee_rect.visible = false
	var r := Rect2(_marquee_start, Vector2.ZERO).expand(get_viewport().get_mouse_position())
	if r.size.length() < 6.0:
		_capture_pick()
		return
	var candidates := _reference_prefab_nodes()
	var added := 0
	for asset in candidates:
		if _cam.is_position_behind(asset.global_transform.origin):
			continue
		if not r.has_point(_cam.unproject_position(asset.global_transform.origin)):
			continue
		if _is_captured(asset):
			continue
		_captured.append({"prefab": asset.scene_file_path, "xform": asset.global_transform, "node": asset})
		_add_capture_marker(asset)
		added += 1
	_update_capture_panel()
	_set_status("Box-selected %d of %d reference assets  ·  total %d" % [added, candidates.size(), _captured.size()], Color("#8be0ff"))


## Every prefab-instance node under the reference (its scene_file_path points into
## /Prefabs/). Skips the Demo scene root itself so we descend into its assets.
func _reference_prefab_nodes() -> Array:
	var out: Array = []
	if _reference == null:
		return out
	var stack: Array = [_reference]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and String((n as Node3D).scene_file_path).contains("/Prefabs/"):
			out.append(n)
			continue   # its children belong to this prefab instance
		for c in n.get_children():
			stack.append(c)
	return out


func _is_captured(asset: Node3D) -> bool:
	for c in _captured:
		if c["node"] == asset:
			return true
	return false


func _prefab_instance_ancestor(collider: Variant) -> Node3D:
	var n := collider as Node
	while n != null and n != _reference:
		if n is Node3D and String((n as Node3D).scene_file_path).contains("/Prefabs/"):
			return n as Node3D
		n = n.get_parent()
	return null


func _add_capture_marker(asset: Node3D) -> void:
	var aabb := _combined_aabb(asset)
	if aabb.size == Vector3.ZERO:
		aabb = AABB(asset.global_position - Vector3(1, 1, 1), Vector3(2, 2, 2))
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = aabb.size + Vector3(0.4, 0.4, 0.4)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.3, 0.9, 1.0, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	_capture_markers.add_child(mi)
	mi.global_position = aabb.get_center()


func _rebuild_capture_markers() -> void:
	for c in _capture_markers.get_children():
		c.queue_free()
	for c in _captured:
		if is_instance_valid(c["node"]):
			_add_capture_marker(c["node"])


func _update_capture_panel() -> void:
	if _capture_list == null:
		return
	for c in _capture_list.get_children():
		c.queue_free()
	var head := Label.new()
	head.text = "Captured (%d):" % _captured.size()
	head.add_theme_font_size_override("font_size", 12)
	_capture_list.add_child(head)
	for c in _captured:
		var l := Label.new()
		l.text = "  • " + String(c["prefab"]).get_file().trim_suffix(".tscn")
		l.add_theme_font_size_override("font_size", 11)
		_capture_list.add_child(l)


func _clear_capture() -> void:
	_captured.clear()
	_rebuild_capture_markers()
	_update_capture_panel()


func _save_group() -> void:
	if _captured.is_empty():
		_popup("Save Group", "Pick at least one asset from the reference city first.")
		return
	var name := _capture_name.text.strip_edges()
	if name.is_empty():
		name = "My Group"
	# Anchor: ground-projected centroid (x,z average; y at the lowest asset base).
	var sx := 0.0
	var sz := 0.0
	var min_y := INF
	for c in _captured:
		var o: Vector3 = c["xform"].origin
		sx += o.x
		sz += o.z
		var ab := _combined_aabb(c["node"])
		min_y = minf(min_y, ab.position.y)
	var n := _captured.size()
	var anchor := Vector3(sx / n, min_y if min_y != INF else 0.0, sz / n)
	var parts: Array = []
	var is_signal := false
	for c in _captured:
		var xf: Transform3D = c["xform"]
		var rel := xf.origin - anchor
		var yaw := rad_to_deg(xf.basis.get_euler().y)
		parts.append({"prefab": String(c["prefab"]), "pos": [rel.x, rel.y, rel.z], "rot_deg": yaw})
		var pl := String(c["prefab"])
		if pl.contains("LightPole_Lights") or pl.contains("LightPole_Arm"):
			is_signal = true
	var gid := "GRP_" + name.validate_filename()
	if gid == "GRP_":
		gid = "GRP_My_Group"
	var group := {"id": gid, "display_name": name, "is_signal": is_signal, "group_root": name.validate_filename() + "Group", "parts": parts}
	var err := Catalog.save_custom_group(group)
	if err != OK:
		_popup("Save Failed", "Could not write the groups file (error %d)." % err)
		return
	_rebuild_palette()
	_clear_capture()
	_capture_mode = false
	_capture_panel.visible = false
	_set_status("Saved group '%s' (%d parts) to My Groups" % [name, n], Color("#42f5a7"))
	_popup("Group Saved", "Saved \"%s\" (%d assets) to the palette under \"My Groups\".\nPlace it on any map like any other asset. Save again with the same name to update it." % [name, n])


## Procedurally generate a whole new city (replaces the current map, undoable).
## A fresh random layout each click.
func _generate_city() -> void:
	var result: Dictionary = RandomGen.generate({})
	_begin_edit()
	_map = result["data"]
	_current_route.clear()
	_deselect_placed()
	if _underlay:
		_underlay.visible = false
	_rebuild()
	_focus_on_content()
	_set_status("Generated city: %d roads (%d major), %d buildings, %d trees (seed %d)" % [
		result["roads"], result["major_roads"], result["buildings"], result["trees"], result["seed"]], Color("#42f5a7"))
	_popup("City Generated", "A new random city (seed %d):\n  roads: %d  (%d major)\n  sidewalks: %d\n  buildings: %d\n  trees: %d\n\nRoads follow the grid with lamps/props/signals grouped on the sidewalks and blocks of buildings, like the reference city. Police + thief spawns and a boundary are set.\n\nClick 'Generate City' again for a different layout. Validate + Test Map to drive it, or edit by hand. Save to keep it." % [
		result["seed"], result["roads"], result["major_roads"], result["sidewalks"], result["buildings"], result["trees"]])


func _toggle_underlay() -> void:
	if _underlay:
		_underlay.visible = not _underlay.visible
		_set_status("Underlay %s" % ("shown" if _underlay.visible else "hidden"))
	else:
		_set_status("No image imported yet")


func _add_button(parent: Node, text: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	parent.add_child(b)


func _select_module(module: Dictionary) -> void:
	_selected = module
	if _sel_label:
		var suffix := "  (marker)" if bool(module.get("is_marker", false)) else ""
		_sel_label.text = "Selected: %s%s" % [module["display_name"], suffix]


# --- Accordion palette ----------------------------------------------------

## (Re)build the category accordion from the current catalog (picks up newly
## saved custom groups). Fresh Catalog scan each time it is refreshed.
func _rebuild_palette() -> void:
	if _palette_list == null:
		return
	for c in _palette_list.get_children():
		c.queue_free()
	_sections.clear()
	_open_section = -1
	var by_cat := {}
	var cat_order: Array = []
	for module in Catalog.modules():
		var category := String(module["category"])
		if not by_cat.has(category):
			by_cat[category] = []
			cat_order.append(category)
		by_cat[category].append(module)
	for ci in cat_order.size():
		var category: String = cat_order[ci]
		var header := Button.new()
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.add_theme_font_size_override("font_size", 15)
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_palette_list.add_child(header)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.visible = false
		_palette_list.add_child(grid)
		_sections.append({"header": header, "grid": grid, "category": category, "modules": by_cat[category], "built": false})
		header.text = "▶ %s (%d)" % [category, (by_cat[category] as Array).size()]
		header.pressed.connect(_toggle_section.bind(ci))
	if not _sections.is_empty():
		_toggle_section(0)


func _toggle_section(idx: int) -> void:
	if idx < 0 or idx >= _sections.size():
		return
	if _open_section == idx:
		_set_section_open(idx, false)
		_open_section = -1
		return
	if _open_section >= 0:
		_set_section_open(_open_section, false)
	if not bool(_sections[idx]["built"]):
		_build_section_items(_sections[idx])
		_sections[idx]["built"] = true
	_set_section_open(idx, true)
	_open_section = idx


func _set_section_open(idx: int, open: bool) -> void:
	var sec: Dictionary = _sections[idx]
	(sec["grid"] as Control).visible = open
	var arrow := "▼" if open else "▶"
	(sec["header"] as Button).text = "%s %s (%d)" % [arrow, sec["category"], (sec["modules"] as Array).size()]


func _build_section_items(sec: Dictionary) -> void:
	var grid: GridContainer = sec["grid"]
	for module in sec["modules"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(104, 112)
		b.text = String(module["display_name"])
		b.clip_text = true
		b.tooltip_text = String(module["display_name"])
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_font_size_override("font_size", 10)
		b.pressed.connect(_select_module.bind(module))
		grid.add_child(b)
		_queue_thumb(module, b)


# --- Lazy 3D thumbnails ---------------------------------------------------

func _queue_thumb(module: Dictionary, button: Button) -> void:
	if not Loader.is_placeable(module):
		button.icon = _marker_icon(module.get("gizmo_color", Color(0.8, 0.8, 0.85)))
		return
	if _thumb_cache.has(module["id"]):
		button.icon = _thumb_cache[module["id"]]
		return
	_thumb_queue.append({"module": module, "button": button})


func _marker_icon(color: Color) -> ImageTexture:
	var img := Image.create(THUMB_PX, THUMB_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(color.r, color.g, color.b, 0.0))
	var m := 24
	for y in range(m, THUMB_PX - m):
		for x in range(m, THUMB_PX - m):
			img.set_pixel(x, y, Color(color.r, color.g, color.b, 0.95))
	return ImageTexture.create_from_image(img)


func _ensure_thumb_vp() -> void:
	if _thumb_vp != null:
		return
	_thumb_vp = SubViewport.new()
	_thumb_vp.size = Vector2i(THUMB_PX, THUMB_PX)
	_thumb_vp.own_world_3d = true
	_thumb_vp.transparent_bg = true
	_thumb_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_thumb_vp)
	_thumb_holder = Node3D.new()
	_thumb_vp.add_child(_thumb_holder)
	_thumb_cam = Camera3D.new()
	_thumb_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_thumb_cam.far = 5000.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.15, 0.19, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.68)
	env.ambient_light_energy = 1.3
	_thumb_cam.environment = env
	_thumb_vp.add_child(_thumb_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -40.0, 0.0)
	_thumb_vp.add_child(sun)


func _thumb_worker() -> void:
	_ensure_thumb_vp()
	while is_inside_tree():
		if _thumb_queue.is_empty():
			await get_tree().process_frame
			continue
		await _render_thumb(_thumb_queue.pop_front())


func _render_thumb(job: Dictionary) -> void:
	var module: Dictionary = job["module"]
	var button: Button = job["button"]
	if not is_instance_valid(button):
		return
	if _thumb_cache.has(module["id"]):
		button.icon = _thumb_cache[module["id"]]
		return
	for c in _thumb_holder.get_children():
		c.queue_free()
	var node := Loader.instance_item(module, Vector2i.ZERO, 0, 0.0)
	if node == null:
		return
	node.transform = Transform3D.IDENTITY
	_thumb_holder.add_child(node)
	await get_tree().process_frame
	var aabb := _combined_aabb(node)
	if aabb.size == Vector3.ZERO:
		aabb = AABB(Vector3(-2.5, 0.0, -2.5), Vector3(5.0, 3.0, 5.0))
	var target := aabb.get_center()
	var radius: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	_thumb_cam.size = radius * 1.35
	var dir := Vector3(0.75, 0.8, 0.75).normalized()
	_thumb_cam.global_position = target + dir * (radius * 2.0 + 6.0)
	_thumb_cam.look_at(target, Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _thumb_vp.get_texture().get_image()
	if img != null and not img.is_empty():
		var tex := ImageTexture.create_from_image(img)
		_thumb_cache[module["id"]] = tex
		if is_instance_valid(button):
			button.icon = tex


func _combined_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			var vi := n as VisualInstance3D
			var g := vi.global_transform * vi.get_aabb()
			if first:
				out = g
				first = false
			else:
				out = out.merge(g)
		for c in n.get_children():
			stack.append(c)
	return out


func _set_status(text: String, color := Color.WHITE) -> void:
	if _status:
		_status.text = text
		_status.add_theme_color_override("font_color", color)


## Visible confirmation dialog (the bottom status line is easy to miss, and can be
## off-screen in a small window). Used by save/load/validate/test.
func _popup(title: String, body: String) -> void:
	if _dialog:
		_dialog.title = title
		_dialog.dialog_text = body
		_dialog.reset_size()
		_dialog.popup_centered()


func _cell(raw: Variant) -> Vector2i:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	if raw is Vector2i:
		return raw
	return Vector2i.ZERO


# --- Headless self-test ---------------------------------------------------

func _run_builder_test() -> void:
	var road: Dictionary = Catalog.by_id("SM_Env_Road_Lines_01")
	for x in range(0, 5):
		_selected = road
		_hover_cell = Vector2i(x, 0)
		_turns = 0
		_place_at_hover()
	# Overlap replace: dropping a sidewalk on a road cell replaces the road.
	_selected = Catalog.by_id("SM_Env_Sidewalk_Straight_01")
	_hover_cell = Vector2i(2, 0)
	_place_at_hover()
	_selected = Catalog.by_id("spawn_police")
	_hover_cell = Vector2i(0, 0)
	_place_at_hover()
	_selected = Catalog.by_id("spawn_thief")
	_hover_cell = Vector2i(4, 0)
	_place_at_hover()
	var items_before: int = (_map["items"] as Array).size()
	var r: Dictionary = Validator.validate_static(_map)
	print("[BUILDER TEST] items=%d undo_depth=%d valid=%s errors=%d markers_police=%s thief=%s" % [
		items_before, _undo.size(), r["valid"], (r["errors"] as Array).size(),
		_map["spawns"].has("police"), _map["spawns"].has("thief")])
	_do_undo()
	print("[BUILDER TEST] after_undo items=%d (expect %d)" % [(_map["items"] as Array).size(), items_before])
	var save_path := "user://mapbuilder_v2_test.json"
	var err: int = Schema.save(save_path, _map)
	print("[BUILDER TEST] save_err=%d geometry_children=%d markers_children=%d" % [
		err, _geometry.get_child_count(), _markers.get_child_count()])
	# Select + rotate a placed item.
	if (_map["items"] as Array).size() > 0:
		_select_placed(0)
		var t0: int = int(_map["items"][0]["turns"])
		_rotate_selected_placed()
		print("[SELECT TEST] sel_idx=%d turns %d->%d sel_visible=%s" % [
			_selected_placed, t0, int(_map["items"][0]["turns"]), _sel_box.visible])
	# Stacked-cell menu: two items on one square -> click shows a pick menu.
	_map["items"].append({"id": "SM_Env_Sidewalk_Straight_01", "cell": [7, 7], "turns": 0})
	_item_nodes.append(_spawn_item_node(_map["items"].back()))
	_map["items"].append({"id": "SM_Prop_LightPole_Base_01", "cell": [7, 7], "turns": 0})
	_item_nodes.append(_spawn_item_node(_map["items"].back()))
	var st := _items_at(Vector2i(7, 7))
	_handle_left_click(Vector2i(7, 7), true)     # Alt+click -> select mode
	var menu_shown := _stack_menu.visible
	var entries := _stack_menu_box.get_child_count()   # header + one per item
	_on_stack_pick(st[1])
	print("[STACK TEST] stack=%d menu_shown=%s entries=%d picked_sel=%d menu_hidden=%s" % [
		st.size(), menu_shown, entries, _selected_placed, not _stack_menu.visible])
	# Place-over: with a sidewalk already down, place-mode click adds a lamp on top.
	_deselect_placed()
	_selected = Catalog.by_id("SM_Env_Sidewalk_Straight_01")
	_hover_cell = Vector2i(9, 9)
	_place_at_hover()
	_selected = Catalog.by_id("SM_Prop_LightPole_Base_01")
	_hover_cell = Vector2i(9, 9)
	_handle_left_click(Vector2i(9, 9), false)      # place mode: should layer, not select
	print("[LAYER TEST] items_on_cell=%d (expect 2) selected=%d" % [_items_at(Vector2i(9, 9)).size(), _selected_placed])
	print("[BUILDER TEST] DONE")
	get_tree().quit()
