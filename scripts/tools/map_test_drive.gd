extends Control
## Map test-drive launcher. Lists every saved map (user://maps) as a button;
## clicking one loads it into the free-drive scene so you can drive the police
## car around it and check the roads render and connect. This does not alter the
## map builder or the reference grid_streets_test scene — it just selects a map.

const FREE_DRIVE_SCENE := "res://scenes/chase/grid_streets_test.tscn"

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.11, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.position = Vector2(48, 48)
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var title := Label.new()
	title.text = "MAP TEST DRIVE"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Pick a map to drive the police car around it.\nFORWARD: drive  ·  BACK: brake  ·  LEFT/RIGHT: route"
	hint.add_theme_color_override("font_color", Color(0.6, 0.68, 0.78))
	box.add_child(hint)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	box.add_child(spacer)

	var dir := DirAccess.open("user://maps")
	if dir == null:
		var none := Label.new()
		none.text = "No maps found in user://maps. Save one in the builder first."
		none.add_theme_color_override("font_color", Color(1.0, 0.72, 0.28))
		box.add_child(none)
		return

	var names := []
	for fn in dir.get_files():
		if fn.ends_with(".json"):
			names.append(fn.get_basename())
	names.sort()
	if names.is_empty():
		var none := Label.new()
		none.text = "No .json maps in user://maps yet."
		box.add_child(none)
		return

	for map_name in names:
		var row := Button.new()
		row.text = "▶  %s%s" % [map_name, _valid_suffix(map_name)]
		row.custom_minimum_size = Vector2(0, 40)
		row.pressed.connect(_drive.bind(map_name))
		box.add_child(row)


func _valid_suffix(map_name: String) -> String:
	var file := FileAccess.open("user://maps/%s.json" % map_name, FileAccess.READ)
	if file == null:
		return ""
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary and data.has("validation"):
		var v = data["validation"]
		if v is Dictionary and v.has("valid"):
			return "   (valid)" if bool(v["valid"]) else "   (invalid — may not drive)"
	return ""


func _drive(map_name: String) -> void:
	GameState.builder_map_name = map_name
	get_tree().change_scene_to_file(FREE_DRIVE_SCENE)
