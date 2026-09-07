class_name MapPlaceableDefinition
extends Resource

@export var id := ""
@export var display_name := ""
@export var category := ""
@export_file("*.tscn") var scene_path := ""
@export var footprint := Vector2i.ONE
@export var connectors := PackedStringArray()
@export var requires_road_edge := false
@export var corner_pivot := true
@export var placement_layer := "surface"
@export var allowed_base_categories := PackedStringArray()
@export var visual_scale := Vector3.ONE
@export var placement_offset := Vector3.ZERO
@export var fill_footprint_with_tiles := false
@export var traffic_directions := PackedStringArray()
@export var module_rules: Dictionary = {}


static func create(
	item_id: String,
	label: String,
	item_category: String,
	path: String,
	item_footprint := Vector2i.ONE,
	item_connectors := PackedStringArray(),
	road_edge_required := false,
	uses_corner_pivot := true,
	item_layer := "surface",
	base_categories := PackedStringArray(),
	item_scale := Vector3.ONE,
	item_offset := Vector3.ZERO,
	tile_fill := false,
	item_traffic_directions := PackedStringArray()
) -> Resource:
	var definition := new()
	definition.id = item_id
	definition.display_name = label
	definition.category = item_category
	definition.scene_path = path
	definition.footprint = item_footprint
	definition.connectors = item_connectors
	definition.requires_road_edge = road_edge_required
	definition.corner_pivot = uses_corner_pivot
	definition.placement_layer = item_layer
	definition.allowed_base_categories = base_categories
	definition.visual_scale = item_scale
	definition.placement_offset = item_offset
	definition.fill_footprint_with_tiles = tile_fill
	definition.traffic_directions = item_traffic_directions
	return definition
