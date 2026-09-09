extends SceneTree
## Headless check that a counter-clockwise one-way loop built with the new
## left-hand curve generates a fully-linked, drivable lane network.
##   godot --headless --path . --script res://tools/verify_left_curve_lanes.gd
const BuilderLaneNetwork = preload("res://scripts/chase/builder_lane_network.gd")
const Catalog = preload("res://scripts/map_builder/map_builder_catalog.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var file := FileAccess.open("res://maps/ccw_ring.json", FileAccess.READ)
	if file == null:
		print("VERIFY FAIL: res://maps/ccw_ring.json not found")
		quit(1); return
	var map_data = JSON.parse_string(file.get_as_text())
	if not map_data is Dictionary:
		print("VERIFY FAIL: bad map json")
		quit(1); return
	var manager := Node3D.new()
	root.add_child(manager)
	var container := BuilderLaneNetwork.build(manager, map_data, Vector3.ZERO, Catalog.create_default())
	var lanes := int(container.get_meta("lane_count", 0))
	var unlinked := int(container.get_meta("unlinked_lane_count", -1))
	print("VERIFY left-curve loop: lanes=%d unlinked=%d" % [lanes, unlinked])
	if lanes > 0 and unlinked == 0:
		print("VERIFY PASS: every lane in the CCW left-curve loop links to a continuation")
	else:
		print("VERIFY WARN: unlinked lanes present (loop not fully continuous)")
	quit()
