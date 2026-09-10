class_name RoadModuleRules
extends RefCounted

const SCHEMA_VERSION := 3
const GRID_SIZE := 5.0
const LANE_WIDTH := 5.0


static func for_id(module_id: String) -> Dictionary:
	match module_id:
		"one_way_street":
			return _rules("straight", 1, 0, Vector2i(1, 1), ["N", "S"], ["continue", "lane_change"], {"N": _port(0, 1, 1), "S": _port(1, 0, 1)})
		"one_way_street_2_lane":
			return _rules("straight", 2, 0, Vector2i(2, 1), ["N", "S"], ["continue", "lane_change"], {"N": _port(0, 2, 2), "S": _port(2, 0, 2)})
		"two_way_street_1x1":
			return _rules("straight", 1, 1, Vector2i(2, 1), ["N", "S"], ["continue"], {"N": _port(1, 1, 2), "S": _port(1, 1, 2)})
		"two_way_street_2x2":
			return _rules("straight", 2, 2, Vector2i(4, 1), ["N", "S"], ["continue", "lane_change"], {"N": _port(2, 2, 4), "S": _port(2, 2, 4)})
		"transition_one_way_1_to_2":
			# A one-cell road cannot be centered on a two-cell carriageway. Keep the
			# narrow end on the left-hand footprint cell and widen on its right.
			return _rules("transition", 2, 0, Vector2i(2, 3), ["N", "S"], ["continue", "split", "merge"], {"N": _port(0, 2, 2), "S": _port(1, 0, 1, 0)})
		"transition_one_way_2_to_1":
			# Mirror of the split: same taper, opposite flow (wide N intake ->
			# narrow S output) so a one-way road can merge 2 lanes back to 1.
			var m := _rules("transition", 2, 0, Vector2i(2, 3), ["N", "S"], ["continue", "split", "merge"], {"N": _port(2, 0, 2), "S": _port(0, 1, 1, 0)})
			m["reverse_flow"] = true
			return m
		"transition_two_way_1_to_2":
			return _rules("transition", 2, 2, Vector2i(4, 3), ["N", "S"], ["continue", "split", "merge"], {"N": _port(2, 2, 4), "S": _port(1, 1, 2)})
		"curve_one_way":
			return _rules("curve_90", 1, 0, Vector2i(1, 1), ["S", "E"], ["turn_right"], {"S": _port(1, 0, 1), "E": _port(0, 1, 1)})
		"curve_one_way_2_lane":
			return _rules("curve_90", 2, 0, Vector2i(2, 2), ["S", "E"], ["turn_right", "lane_change"], {"S": _port(2, 0, 2), "E": _port(0, 2, 2)})
		"curve_one_way_left":
			# Mirror of curve_one_way: same arc, opposite flow (E->S), so a one-way
			# loop can run the other way around. reverse_flow flips lane generation.
			var lr := _rules("curve_90", 1, 0, Vector2i(1, 1), ["S", "E"], ["turn_left"], {"S": _port(0, 1, 1), "E": _port(1, 0, 1)})
			lr["reverse_flow"] = true
			return lr
		"curve_one_way_2_lane_left":
			var lr2 := _rules("curve_90", 2, 0, Vector2i(2, 2), ["S", "E"], ["turn_left", "lane_change"], {"S": _port(0, 2, 2), "E": _port(2, 0, 2)})
			lr2["reverse_flow"] = true
			return lr2
		"curve_two_way_1x1":
			return _rules("curve_90", 1, 1, Vector2i(2, 2), ["S", "E"], ["turn_left", "turn_right"], {"S": _port(1, 1, 2), "E": _port(1, 1, 2)})
		"curve_two_way_2x2":
			return _rules("curve_90", 2, 2, Vector2i(4, 4), ["S", "E"], ["turn_left", "turn_right", "lane_change"], {"S": _port(2, 2, 4), "E": _port(2, 2, 4)})
		"one_way_intersection":
			return _rules("intersection_4", 1, 0, Vector2i(1, 1), ["N", "E", "S", "W"], ["continue", "turn_left", "turn_right"])
		"compact_t_intersection_1x2":
			# A two-cell-wide, one-cell-deep T. N/S are the two-way through road;
			# E is the side-street opening and follows the module when rotated.
			return _rules("intersection_t", 1, 1, Vector2i(2, 1), ["N", "E", "S"], ["continue", "turn_left", "turn_right"], {"N": _port(1, 1, 2), "S": _port(1, 1, 2), "E": _port(1, 0, 1)})
		"t_main_4_side_1":
			return _rules("intersection_t", 2, 2, Vector2i(4, 2), ["N", "E", "S"], ["continue", "turn_left", "turn_right"], {"N": _port(2, 2, 4), "S": _port(2, 2, 4), "E": _port(1, 0, 1)})
		"t_main_4_side_2":
			return _rules("intersection_t", 2, 2, Vector2i(4, 2), ["N", "E", "S"], ["continue", "turn_left", "turn_right"], {"N": _port(2, 2, 4), "S": _port(2, 2, 4), "E": _port(1, 1, 2)})
		"two_way_intersection_1x1":
			return _rules("intersection_4", 1, 1, Vector2i(2, 2), ["N", "E", "S", "W"], ["continue", "turn_left", "turn_right"], {"N": _port(1, 1, 2), "E": _port(1, 1, 2), "S": _port(1, 1, 2), "W": _port(1, 1, 2)})
		"two_way_intersection_2x2":
			return _rules("intersection_4", 2, 2, Vector2i(4, 4), ["N", "E", "S", "W"], ["continue", "turn_left", "turn_right", "lane_change"], {"N": _port(2, 2, 4), "E": _port(2, 2, 4), "S": _port(2, 2, 4), "W": _port(2, 2, 4)})
	return {}


static func _rules(kind: String, forward_lanes: int, reverse_lanes: int, footprint: Vector2i, ports: Array, actions: Array, port_profiles := {}) -> Dictionary:
	var total_lanes := forward_lanes + reverse_lanes
	return {
		"schema_version": SCHEMA_VERSION,
		"kind": kind,
		"grid_size": GRID_SIZE,
		"lane_width": LANE_WIDTH,
		"lanes_forward": forward_lanes,
		"lanes_reverse": reverse_lanes,
		"total_lanes": total_lanes,
		"road_width": total_lanes * LANE_WIDTH,
		"footprint": [footprint.x, footprint.y],
		"ports": ports,
		"port_profiles": port_profiles,
		"allowed_actions": actions,
		"requires_matching_lane_count": true,
		"allows_dead_end": false,
		"supports_vehicle_spawn": kind == "straight",
		"supports_signal_socket": kind.begins_with("intersection"),
		"surface_layer": "road",
	}


static func _port(incoming: int, outgoing: int, span: int, offset := -1) -> Dictionary:
	return {"incoming": incoming, "outgoing": outgoing, "span": span, "offset": offset}


static func rotated_port_profile(rules: Dictionary, rotated_port: String, turns: int) -> Dictionary:
	var profiles: Dictionary = rules.get("port_profiles", {})
	for base_port in profiles:
		if rotated_ports({"ports": [base_port]}, turns)[0] == rotated_port:
			return profiles[base_port]
	var total := int(rules.get("total_lanes", 0))
	return {"incoming": total, "outgoing": total, "span": total, "offset": -1}


static func rotated_ports(rules: Dictionary, turns: int) -> Array[String]:
	var directions := ["N", "E", "S", "W"]
	var result: Array[String] = []
	for port in rules.get("ports", []):
		result.append(directions[posmod(directions.find(String(port)) - turns, 4)])
	return result


static func compatible(a: Dictionary, b: Dictionary) -> bool:
	return (
		int(a.get("total_lanes", 0)) == int(b.get("total_lanes", 0))
		and is_equal_approx(float(a.get("lane_width", 0.0)), float(b.get("lane_width", 0.0)))
	)
