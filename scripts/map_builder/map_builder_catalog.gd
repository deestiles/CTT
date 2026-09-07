class_name MapBuilderCatalog
extends RefCounted

const PlaceableDefinition = preload("res://scripts/map_builder/placeable_definition.gd")
const RoadModuleRules = preload("res://scripts/map_builder/road_module_rules.gd")


static func create_default() -> Array:
	var definitions := [
		PlaceableDefinition.create("one_way_street", "One-Way Street", "Roads", "res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Road_Bare_01.tscn", Vector2i.ONE, PackedStringArray(["N", "S"]), false, true, "surface", PackedStringArray(), Vector3.ONE, Vector3.ZERO, false, PackedStringArray(["N"])),
		PlaceableDefinition.create("two_way_street_1x1", "Two-Way: 1 Lane Each Direction", "Roads", "res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Road_Bare_01.tscn", Vector2i(2, 1), PackedStringArray(["N", "S"]), false, true, "surface", PackedStringArray(), Vector3.ONE, Vector3.ZERO, true, PackedStringArray(["N", "S"])),
		PlaceableDefinition.create("two_way_street_2x2", "Two-Way: 2 Lanes Each Direction", "Roads", "res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Road_Bare_01.tscn", Vector2i(4, 1), PackedStringArray(["N", "S"]), false, true, "surface", PackedStringArray(), Vector3.ONE, Vector3.ZERO, true, PackedStringArray(["N", "S"])),
		PlaceableDefinition.create("curve_one_way", "Curve: One-Way", "Roads", "res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Road_Bare_01.tscn", Vector2i.ONE, PackedStringArray(["S", "E"]), false, true, "surface", PackedStringArray(), Vector3.ONE, Vector3.ZERO, false, PackedStringArray(["S", "E"])),
		PlaceableDefinition.create("curve_two_way_1x1", "Curve: 1 Lane Each Direction", "Roads", "res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Road_Bare_01.tscn", Vector2i(2, 2), PackedStringArray(["S", "E"]), false, true, "surface", PackedStringArray(), Vector3.ONE, Vector3.ZERO, false, PackedStringArray(["S", "E"])),
		PlaceableDefinition.create("curve_two_way_2x2", "Curve: 2 Lanes Each Direction", "Roads", "res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Road_Bare_01.tscn", Vector2i(4, 4), PackedStringArray(["S", "E"]), false, true, "surface", PackedStringArray(), Vector3.ONE, Vector3.ZERO, false, PackedStringArray(["S", "E"])),
		PlaceableDefinition.create("one_way_intersection", "One-Way Intersection", "Roads", "res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Road_Bare_01.tscn", Vector2i.ONE, PackedStringArray(["N", "E", "S", "W"]), false, true, "surface", PackedStringArray(), Vector3.ONE, Vector3.ZERO, false, PackedStringArray(["N", "E", "S", "W"])),
		PlaceableDefinition.create("compact_t_intersection_1x2", "Intersection: 2 Squares (T)", "Roads", "res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Road_Bare_01.tscn", Vector2i(2, 1), PackedStringArray(["N", "E", "S"]), false, true, "surface", PackedStringArray(), Vector3.ONE, Vector3.ZERO, true, PackedStringArray(["N", "S"])),
		PlaceableDefinition.create("two_way_intersection_1x1", "Intersection: 1 Lane Each Way", "Roads", "res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Road_Bare_01.tscn", Vector2i(2, 2), PackedStringArray(["N", "E", "S", "W"]), false, true, "surface", PackedStringArray(), Vector3.ONE, Vector3.ZERO, true, PackedStringArray(["N", "E", "S", "W"])),
		PlaceableDefinition.create("two_way_intersection_2x2", "Intersection: 2 Lanes Each Way", "Roads", "res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Road_Bare_01.tscn", Vector2i(4, 4), PackedStringArray(["N", "E", "S", "W"]), false, true, "surface", PackedStringArray(), Vector3.ONE, Vector3.ZERO, true, PackedStringArray(["N", "E", "S", "W"])),
		PlaceableDefinition.create("sidewalk", "Sidewalk — Straight", "Sidewalks", "res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Sidewalk_Straight_01.tscn"),
		PlaceableDefinition.create("sidewalk_corner", "Sidewalk — Corner 01", "Sidewalks", "res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Sidewalk_Corner_01.tscn"),
		PlaceableDefinition.create("sidewalk_corner_02", "Sidewalk — Corner 02", "Sidewalks", "res://Assets/Synty/PolygonCity/Prefabs/Environments/SM_Env_Sidewalk_Corner_02.tscn"),
		PlaceableDefinition.create("shop", "Shop Building (2×2)", "Buildings", "res://Assets/Synty/PolygonCity/Prefabs/Buildings/SM_Bld_Shop_01.tscn", Vector2i(2, 2), PackedStringArray(), true, true, "structure", PackedStringArray(), Vector3(2, 2, 2)),
		PlaceableDefinition.create("apartment", "Apartment Building (2×2)", "Buildings", "res://Assets/Synty/PolygonCity/Prefabs/Buildings/SM_Bld_Apartment_01.tscn", Vector2i(2, 2), PackedStringArray(), true, true, "structure", PackedStringArray(), Vector3(2, 2, 2)),
		PlaceableDefinition.create("street_lamp", "Street Lamp", "Street Fixtures", "res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_LightPole_Base_01.tscn", Vector2i.ONE, PackedStringArray(), false, false, "prop", PackedStringArray(["Sidewalks"]), Vector3.ONE, Vector3(-2.1, 0, 0)),
		PlaceableDefinition.create("traffic_light", "Traffic Light", "Street Fixtures", "res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_TrafficLight_01.tscn", Vector2i.ONE, PackedStringArray(), false, false, "prop", PackedStringArray(["Sidewalks"]), Vector3.ONE, Vector3(-2.0, 3.2, 0)),
		PlaceableDefinition.create("police_car", "Police Car", "Vehicles", "res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Police_01.tscn", Vector2i.ONE, PackedStringArray(), false, false, "vehicle", PackedStringArray(["Roads"])),
		PlaceableDefinition.create("sedan", "Civilian Sedan", "Vehicles", "res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Sedan_01.tscn", Vector2i.ONE, PackedStringArray(), false, false, "vehicle", PackedStringArray(["Roads"])),
		PlaceableDefinition.create("pedestrian", "Pedestrian", "Pedestrians", "res://Assets/Synty/PolygonCity/Prefabs/Characters/Character_BusinessMan_Shirt.tscn", Vector2i.ONE, PackedStringArray(), false, false, "character", PackedStringArray(["Sidewalks"])),
	]
	for definition in definitions:
		if definition.category == "Roads":
			definition.module_rules = RoadModuleRules.for_id(definition.id)
	return definitions
