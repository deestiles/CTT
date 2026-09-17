class_name CityModuleCatalog
extends RefCounted
## Palette of real Synty Polygon City prefabs for map-builder v2.
##
## This catalog is deliberately SEPARATE from the old lane-graph builder's
## `scripts/map_builder/map_builder_catalog.gd`. It exists to assemble a city
## whose runtime `City` node tree keeps the Synty node-naming conventions that
## `scripts/drive/drive_city.gd` decorates by (roads=*Road*, sidewalks=*Sidewalk*,
## lamps=*LightPole_Base*, signals=*LightPole_Arm*/*LightPole_Lights*,
## windows=*Prop_Window_*, knockables=*Trash*/*Cardboard*/*Mailbox*/*Cone*/
## *Barrier*/*Skip*). Because the approved runtime is name-driven and
## layout-agnostic, a generated city built from these prefabs runs on the same
## navigation/lighting/knockable passes with no runtime edits.
##
## Calibration (verified 2026-09-17 against the prefab colliders):
##   SM_Env_Road_01 BoxShape3D size = (5, 0.16, 5), collider origin (+2.5,0,-2.5)
##   => environment tiles are 5 m x 5 m, near-corner pivot spanning +X / -Z.
## The 5 m grid and corner-pivot placement math match the old builder's proven
## `_placement_position` convention.

const GRID_SIZE := 5.0

## Placement layers. "marker" modules carry authored gameplay metadata and are
## NOT instanced as gameplay geometry at runtime (they drive spawns / routes /
## boundaries); the editor draws a primitive gizmo for them.
enum Layer { SURFACE, STRUCTURE, PROP, VEHICLE, MARKER }

const _ROOT := "res://Assets/Synty/PolygonCity/Prefabs/"


## Returns an Array[Dictionary]; each entry is one placeable module. Kept as
## plain dictionaries (not .tres Resources) so the catalog is code-only and
## diff-friendly, and never collides with the old builder's Resource palette.
static func modules() -> Array:
	return [
		# --- Roads (name contains "Road" -> baked into the road-only NavMesh) ---
		_road("road_plain", "Road — Plain", "SM_Env_Road_01"),
		_road("road_lines", "Road — Lane Lines", "SM_Env_Road_Lines_01"),
		_road("road_yellow", "Road — Center Line", "SM_Env_Road_YellowLines_01"),
		_road("road_crossing", "Road — Crosswalk", "SM_Env_Road_Crossing_01"),
		_road("road_median", "Road — Median", "SM_Env_Road_Median_01"),
		_road("road_bare", "Road — Bare", "SM_Env_Road_Bare_01"),

		# --- Sidewalks (name contains "Sidewalk"; raycast-verified ped surface) ---
		_sidewalk("sidewalk_straight", "Sidewalk — Straight", "SM_Env_Sidewalk_Straight_01"),
		_sidewalk("sidewalk_plain", "Sidewalk — Panel", "SM_Env_Sidewalk_01"),
		_sidewalk("sidewalk_corner_01", "Sidewalk — Corner A", "SM_Env_Sidewalk_Corner_01"),
		_sidewalk("sidewalk_corner_02", "Sidewalk — Corner B", "SM_Env_Sidewalk_Corner_02"),

		# --- Buildings (structure; scaled x2 like the old catalog, 2x2 cells) ---
		_building("bld_shop", "Building — Shop", "Buildings/SM_Bld_Shop_01"),
		_building("bld_apartment", "Building — Apartment", "Buildings/SM_Bld_Apartment_01"),

		# --- Trees (solid; fed into the road NavMesh so cars route around them) ---
		_prop("tree_01", "Tree", "Environments/SM_Env_Tree_01", Layer.STRUCTURE),

		# --- Street fixtures ---
		# Lamp: runtime adds a downward SpotLight to any *LightPole_Base* mesh.
		_prop("street_lamp", "Street Lamp", "Props/SM_Prop_LightPole_Base_01", Layer.PROP),
		# Signal: MUST instance a *LightPole_Lights* / *LightPole_Arm* prefab so the
		# runtime signal-phase pass finds and emits on it. SM_Prop_TrafficLight_*
		# does NOT match those patterns and would stay dark.
		_signal("traffic_signal", "Traffic Signal (head)", "Props/SM_Prop_LightPole_Lights_01"),
		_signal("traffic_signal_arm", "Traffic Signal (gantry arm)", "Props/SM_Prop_LightPole_Arm_01"),

		# --- Reactive props (name-matched by the knockable pass) ---
		_prop("prop_trashcan", "Trash Can (light)", "Props/SM_Prop_TrashCan_01", Layer.PROP),
		_prop("prop_trashbin", "Trash Bin (heavy slide)", "Props/SM_Prop_Trashbin_01", Layer.PROP),
		_prop("prop_dumpster", "Commercial Dumpster (solid slide)", "Props/SM_Prop_Skip_01", Layer.PROP),
		_prop("prop_cone", "Traffic Cone (light)", "Props/SM_Prop_Cone_01", Layer.PROP),
		_prop("prop_mailbox", "Mailbox (light)", "Props/SM_Prop_Mailbox_01", Layer.PROP),
		_prop("prop_barrier", "Barrier (light)", "Props/SM_Prop_Barrier_01", Layer.PROP),

		# --- Gameplay markers (authored metadata, not gameplay geometry) ---
		_marker("spawn_police", "Police Spawn", "police_spawn", Color("#28a9ff")),
		_marker("spawn_thief", "Thief Spawn", "thief_spawn", Color("#ff344d")),
		_marker("recovery_point", "Recovery Point", "recovery", Color("#42f5a7")),
		_marker("route_node", "Sidewalk Route Node", "sidewalk_route", Color("#ffce54")),
		_marker("boundary_post", "Map Boundary Post", "boundary", Color("#b061ff")),
	]


static func by_id(module_id: String) -> Dictionary:
	for module in modules():
		if String(module.get("id", "")) == module_id:
			return module
	return {}


static func categories() -> Array:
	var seen := {}
	var ordered: Array = []
	for module in modules():
		var category := String(module.get("category", ""))
		if not seen.has(category):
			seen[category] = true
			ordered.append(category)
	return ordered


# --- Builders --------------------------------------------------------------

static func _road(id: String, label: String, prefab: String) -> Dictionary:
	return _entry(id, label, "Roads", "Environments/%s" % prefab, Vector2i.ONE, Layer.SURFACE, true)


static func _sidewalk(id: String, label: String, prefab: String) -> Dictionary:
	return _entry(id, label, "Sidewalks", "Environments/%s" % prefab, Vector2i.ONE, Layer.SURFACE, true)


static func _building(id: String, label: String, prefab: String) -> Dictionary:
	# SM_Bld_Shop_01 / Apartment_01 colliders are ~5 x 5.5 m at native scale, i.e.
	# a single 5 m cell. Do NOT scale them up: a x2 scale overflows the declared
	# footprint and spills the collider onto adjacent road/sidewalk cells.
	return _entry(id, label, "Buildings", prefab, Vector2i.ONE, Layer.STRUCTURE, true)


static func _signal(id: String, label: String, prefab: String) -> Dictionary:
	var entry := _entry(id, label, "Street Fixtures", prefab, Vector2i.ONE, Layer.PROP, false)
	entry["is_signal"] = true
	entry["base_categories"] = PackedStringArray(["Sidewalks", "Roads"])
	return entry


static func _prop(id: String, label: String, prefab: String, layer: int) -> Dictionary:
	var category := "Props"
	if layer == Layer.STRUCTURE:
		category = "Trees" if id.begins_with("tree") else "Structures"
	var base := PackedStringArray(["Sidewalks"]) if layer == Layer.PROP else PackedStringArray()
	var entry := _entry(id, label, category, prefab, Vector2i.ONE, layer, layer == Layer.STRUCTURE)
	entry["base_categories"] = base
	return entry


static func _marker(id: String, label: String, kind: String, color: Color) -> Dictionary:
	var entry := _entry(id, label, "Markers", "", Vector2i.ONE, Layer.MARKER, false)
	entry["marker_kind"] = kind
	entry["gizmo_color"] = color
	return entry


static func _entry(id: String, label: String, category: String, prefab: String,
		footprint: Vector2i, layer: int, corner_pivot: bool) -> Dictionary:
	return {
		"id": id,
		"display_name": label,
		"category": category,
		"prefab": ("%s%s.tscn" % [_ROOT, prefab]) if prefab != "" else "",
		"footprint": footprint,
		"layer": layer,
		"corner_pivot": corner_pivot,
		"scale": Vector3.ONE,
		"offset": Vector3.ZERO,
		"is_signal": false,
		"is_marker": layer == Layer.MARKER,
		"marker_kind": "",
		"base_categories": PackedStringArray(),
		"gizmo_color": Color("#cfd8e3"),
	}
