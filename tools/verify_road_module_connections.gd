extends SceneTree

const BuilderCatalog = preload("res://scripts/map_builder/map_builder_catalog.gd")
const BuilderLaneNetwork = preload("res://scripts/chase/builder_lane_network.gd")


func _init() -> void:
	var manager := Node3D.new()
	root.add_child(manager)
	await process_frame
	var one_way_map := {
		"items": [
			{"id": "one_way_street_2_lane", "cell": [0, -1], "turns": 0},
			{"id": "transition_one_way_1_to_2", "cell": [0, 0], "turns": 0},
			{"id": "one_way_street", "cell": [0, 3], "turns": 0},
		]
	}
	var network := BuilderLaneNetwork.build(manager, one_way_map, Vector3.ZERO, BuilderCatalog.create_default())
	_assert_equal(int(network.get_meta("lane_count", -1)), 5, "one-way transition lane count")
	_assert_equal(int(network.get_meta("unlinked_lane_count", -1)), 2, "one-way transition only has its two intentional outer exits")

	manager.queue_free()
	print("ROAD_MODULE_CONNECTION_TESTS: PASS")
	quit(0)


func _assert_equal(actual: int, expected: int, label: String) -> void:
	if actual == expected:
		return
	push_error("%s: expected %d, got %d" % [label, expected, actual])
	quit(1)
