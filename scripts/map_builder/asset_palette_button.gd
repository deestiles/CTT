class_name MapBuilderAssetButton
extends Button

var definition: Resource
var builder: Node
var press_origin := Vector2.ZERO
var dragging := false


func configure(item: Resource, owner_builder: Node, thumbnail: Texture2D) -> void:
	definition = item
	builder = owner_builder
	text = item.display_name
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	icon = thumbnail
	expand_icon = true
	add_theme_constant_override("icon_max_width", 76)
	custom_minimum_size.y = 68.0
	tooltip_text = "%s\nDrag onto the map • R rotates before placement" % item.scene_path.get_file()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_origin = event.global_position
			dragging = false
		else:
			if dragging:
				builder.drop_palette_asset(event.global_position)
			dragging = false
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if not dragging and event.global_position.distance_to(press_origin) >= 7.0:
			dragging = true
			builder.begin_palette_drag(definition)
		if dragging:
			builder.move_palette_drag(event.global_position)
