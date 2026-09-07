extends Control

signal vector_changed(value: Vector2)

var value := Vector2.ZERO
var dragging := false
var touch_index := -1


func _ready() -> void:
	custom_minimum_size = Vector2(270.0, 270.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.42
	draw_circle(center, radius, Color(0.02, 0.08, 0.13, 0.72))
	draw_arc(center, radius, 0.0, TAU, 64, Color("#27bfff"), 4.0)
	draw_line(center + Vector2(0.0, -radius * 0.82), center + Vector2(0.0, radius * 0.82), Color(0.55, 0.75, 0.84, 0.35), 2.0)
	draw_line(center + Vector2(-radius * 0.82, 0.0), center + Vector2(radius * 0.82, 0.0), Color(0.55, 0.75, 0.84, 0.35), 2.0)
	var knob_position := center + value * radius
	draw_circle(knob_position, radius * 0.34, Color("#123b63"))
	draw_arc(knob_position, radius * 0.34, 0.0, TAU, 48, Color("#f4fbff"), 3.0)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not dragging:
			dragging = true
			touch_index = event.index
			set_from_position(event.position)
		elif not event.pressed and event.index == touch_index:
			release_joystick()
	elif event is InputEventScreenDrag and event.index == touch_index:
		set_from_position(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if dragging:
			set_from_position(event.position)
		else:
			release_joystick()
	elif event is InputEventMouseMotion and dragging:
		set_from_position(event.position)


func set_from_position(local_position: Vector2) -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.42
	value = ((local_position - center) / radius).limit_length(1.0)
	if value.length() < 0.12:
		value = Vector2.ZERO
	vector_changed.emit(value)
	queue_redraw()


func release_joystick() -> void:
	dragging = false
	touch_index = -1
	value = Vector2.ZERO
	vector_changed.emit(value)
	queue_redraw()

