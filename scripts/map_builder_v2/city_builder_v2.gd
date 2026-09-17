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

const TEST_SCENE := "res://scenes/drive/generated_city_test.tscn"
const GRID := 5.0

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
var _grid: MeshInstance3D
var _status: Label
var _sel_label: Label
var _name_edit: LineEdit

var _cam_center := Vector3(0, 0, 0)
var _cam_size := 160.0
var _panning := false
var _ui: CanvasLayer
var _dialog: AcceptDialog


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
	_build_hover()
	_build_ui()
	var mods: Array = Catalog.modules()
	if not mods.is_empty():
		_select_module(mods[0])
	_rebuild()
	_update_camera()
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
	_cam.global_position = Vector3(_cam_center.x, 300.0, _cam_center.z)


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


# --- Rebuild preview ------------------------------------------------------

func _rebuild() -> void:
	if _geometry:
		_geometry.queue_free()
	var built: Dictionary = Loader.build_city(_map)
	_geometry = built["city"]
	_geometry.name = "Geometry"
	add_child(_geometry)
	_rebuild_markers()


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


func _is_surface_selected() -> bool:
	return not _selected.is_empty() and not bool(_selected.get("is_marker", false)) \
		and int(_selected.get("layer", -1)) == Catalog.Layer.SURFACE


func _update_hover() -> void:
	_hover_cell = _current_cell()
	var footprint := Vector2i.ONE
	if not _selected.is_empty():
		footprint = _selected.get("footprint", Vector2i.ONE)
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
				if _is_surface_selected():
					_begin_paint()
				else:
					_place_at_hover()
			else:
				_painting = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_delete_at_hover()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			_cam_center -= Vector3(mm.relative.x, 0, mm.relative.y) * (_cam_size * 0.0016)
			_update_camera()
		elif _painting:
			_paint_step()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if _name_edit and _name_edit.has_focus():
			return
		match k.keycode:
			KEY_R:
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
	_map["items"].append({"id": _selected["id"], "cell": [cell.x, cell.y], "turns": _turns})
	_add_item_visual(_selected, cell, _turns)
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


func _add_item_visual(module: Dictionary, cell: Vector2i, turns: int) -> void:
	if _geometry == null or String(module.get("prefab", "")) == "":
		return
	var node := Loader.instance_item(module, cell, turns, 0.0)
	if node:
		_geometry.add_child(node)


func _place_at_hover() -> void:
	if _selected.is_empty():
		return
	var kind := String(_selected.get("marker_kind", ""))
	if bool(_selected.get("is_marker", false)):
		_place_marker(kind)
		return
	_begin_edit()
	var layer: int = _selected.get("layer", Catalog.Layer.SURFACE)
	var footprint: Vector2i = _selected.get("footprint", Vector2i.ONE)
	var cells := Schema.covered_cells(_hover_cell, footprint, _turns)
	# Surfaces and structures are exclusive per cell; remove anything overlapping.
	if layer == Catalog.Layer.SURFACE or layer == Catalog.Layer.STRUCTURE:
		_remove_items_on_cells(cells, [Catalog.Layer.SURFACE, Catalog.Layer.STRUCTURE])
	_map["items"].append({"id": _selected["id"], "cell": [_hover_cell.x, _hover_cell.y], "turns": _turns})
	_rebuild()
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


func _delete_at_hover() -> void:
	# Remove the last item covering the hovered cell, else a marker on it.
	var items: Array = _map.get("items", [])
	for i in range(items.size() - 1, -1, -1):
		var raw = items[i]
		if not (raw is Dictionary):
			continue
		var module: Dictionary = Catalog.by_id(String(raw.get("id", "")))
		if module.is_empty():
			continue
		var cells := Schema.covered_cells(_cell(raw.get("cell", [0, 0])), module.get("footprint", Vector2i.ONE), int(raw.get("turns", 0)))
		if _hover_cell in cells:
			_begin_edit()
			items.remove_at(i)
			_rebuild()
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
		var occ := Schema.covered_cells(_cell(raw.get("cell", [0, 0])), module.get("footprint", Vector2i.ONE), int(raw.get("turns", 0)))
		for c in occ:
			if c in cells:
				items.remove_at(i)
				break


func _do_undo() -> void:
	if _undo.is_empty():
		_set_status("Nothing to undo")
		return
	_redo.append(_snapshot())
	_map = _undo.pop_back()
	_rebuild()
	_set_status("Undo")


func _do_redo() -> void:
	if _redo.is_empty():
		_set_status("Nothing to redo")
		return
	_undo.append(_snapshot())
	_map = _redo.pop_back()
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
	_add_button(bar, "Fit View (F)", _focus_on_content)
	_add_button(bar, "Hide Panels (H)", _toggle_panels)

	# Left palette.
	var palette := ScrollContainer.new()
	palette.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	palette.offset_top = 46
	palette.offset_bottom = -70
	palette.custom_minimum_size = Vector2(210, 0)
	var pstyle := PanelContainer.new()
	pstyle.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	pstyle.offset_top = 46
	pstyle.offset_bottom = -70
	pstyle.custom_minimum_size = Vector2(210, 0)
	layer.add_child(pstyle)
	layer.add_child(palette)
	var plist := VBoxContainer.new()
	plist.add_theme_constant_override("separation", 2)
	palette.add_child(plist)
	var last_category := ""
	for module in Catalog.modules():
		var category := String(module["category"])
		if category != last_category:
			last_category = category
			var header := Label.new()
			header.text = "— %s —" % category
			header.add_theme_color_override("font_color", Color("#9fd0ff"))
			plist.add_child(header)
		var btn := Button.new()
		btn.text = String(module["display_name"])
		btn.tooltip_text = String(module.get("prefab", ""))
		btn.pressed.connect(_select_module.bind(module))
		plist.add_child(btn)

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
	_status.text = "L-click/drag place · R-click delete · R rotate · wheel zoom (far out) · MMB/WASD pan · F fit · H hide panels"
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
	print("[BUILDER TEST] DONE")
	get_tree().quit()
