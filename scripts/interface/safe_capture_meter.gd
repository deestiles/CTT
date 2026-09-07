extends Control

var cursor_value := 0.0
var target_min := 38.0
var target_max := 64.0


func _ready() -> void:
	custom_minimum_size = Vector2(460.0, 74.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func configure_window(minimum: float, maximum: float) -> void:
	target_min = clampf(minimum, 0.0, 100.0)
	target_max = clampf(maximum, target_min, 100.0)
	queue_redraw()


func set_cursor(value: float) -> void:
	cursor_value = clampf(value, 0.0, 100.0)
	queue_redraw()


func _draw() -> void:
	var track := Rect2(8.0, 15.0, size.x - 16.0, 42.0)
	draw_rect(track, Color("#07131f"), true)
	draw_rect(track, Color("#31536a"), false, 2.0)

	var zone_x := track.position.x + track.size.x * target_min / 100.0
	var zone_width := track.size.x * (target_max - target_min) / 100.0
	var target_rect := Rect2(zone_x, track.position.y + 2.0, zone_width, track.size.y - 4.0)
	draw_rect(target_rect, Color(0.18, 0.88, 0.58, 0.42), true)
	draw_line(Vector2(zone_x, track.position.y - 6.0), Vector2(zone_x, track.end.y + 6.0), Color("#2fe0a0"), 4.0)
	draw_line(Vector2(zone_x + zone_width, track.position.y - 6.0), Vector2(zone_x + zone_width, track.end.y + 6.0), Color("#2fe0a0"), 4.0)

	for tick in range(0, 101, 10):
		var tick_x := track.position.x + track.size.x * float(tick) / 100.0
		var tick_height := 9.0 if tick % 20 == 0 else 5.0
		draw_line(Vector2(tick_x, track.end.y - tick_height), Vector2(tick_x, track.end.y), Color("#7893a5"), 1.0)

	var marker_x := track.position.x + track.size.x * cursor_value / 100.0
	var marker_color := Color("#ffffff") if cursor_value < target_min or cursor_value > target_max else Color("#ffca55")
	draw_line(Vector2(marker_x, track.position.y - 10.0), Vector2(marker_x, track.end.y + 10.0), marker_color, 5.0)
	var arrow := PackedVector2Array([
		Vector2(marker_x - 8.0, track.position.y - 11.0),
		Vector2(marker_x + 8.0, track.position.y - 11.0),
		Vector2(marker_x, track.position.y - 2.0)
	])
	draw_colored_polygon(arrow, marker_color)
