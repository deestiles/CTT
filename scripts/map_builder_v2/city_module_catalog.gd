class_name CityModuleCatalog
extends RefCounted
## Palette of real Synty Polygon City prefabs for map-builder v2.
##
## The palette is built by SCANNING res://Assets/Synty/PolygonCity/Prefabs so
## every road/sidewalk/building/prop in the pack is available, not a curated
## handful. Entries keep the prefab's Synty node names, which is what the
## approved name-driven runtime (scripts/drive/drive_city.gd) decorates by, so a
## generated city works with no runtime edits. Gameplay markers (spawns, routes,
## boundary, recovery) are appended after the scanned prefabs.
##
## Calibration: environment tiles are 5 m x 5 m, near-corner pivot spanning
## +X / -Z (verified from SM_Env_Road_01's 5x5 collider). Prefabs default to a
## 1x1 footprint at native scale; buildings are NOT scaled up (a x2 scale
## overflows the footprint onto neighbouring cells).

const GRID_SIZE := 5.0
const PREFAB_ROOT := "res://Assets/Synty/PolygonCity/Prefabs"
## Custom groups the owner saves (captured from the reference city, or composed).
const GROUPS_FILE := "res://maps_v2/groups.json"

enum Layer { SURFACE, STRUCTURE, PROP, VEHICLE, MARKER }

# Reactive-prop name fragments (matched by the runtime knockable pass).
const _KNOCKABLE := ["trash", "cardboard", "mailbox", "cone", "barrier", "skip", "trashbin"]
# Environment names that are not useful on a city grid.
const _ENV_SKIP := ["cloud", "ocean", "water", "flower"]
const _CATEGORY_ORDER := ["Roads", "Sidewalks", "Buildings", "Street Fixtures", "Reactive Props", "Nature", "Ground & Decor", "Props", "Markers"]

static var _cache: Array = []


## Cached; scanning the pack is done once per process.
static func modules() -> Array:
	if _cache.is_empty():
		_cache = _scan()
	return _cache


## Drop the cache so a newly saved custom group is picked up on the next call.
static func refresh() -> void:
	_cache = []


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


# --- Scan -----------------------------------------------------------------

static func _scan() -> Array:
	var out: Array = []
	_scan_dir(PREFAB_ROOT, out)
	out.append_array(_composite_buildings())
	out.append_array(_group_modules())
	out.append_array(_load_custom_groups())
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := _CATEGORY_ORDER.find(String(a["category"]))
		var cb := _CATEGORY_ORDER.find(String(b["category"]))
		if ca != cb:
			return ca < cb
		return String(a["display_name"]) < String(b["display_name"]))
	out.append_array(_markers())
	return out


## Multi-level buildings assembled on the fly from Synty apartment kit pieces
## (ground Door + N Stack floors + Roof), the way the Demo builds tall apartments.
## Single-floor prefabs like SM_Bld_Apartment_01 look one-storey on their own.
static func _composite_buildings() -> Array:
	var bld := "%s/Buildings/" % PREFAB_ROOT
	var base := {
		"category": "Buildings", "footprint": Vector2i.ONE, "layer": Layer.STRUCTURE,
		"corner_pivot": true, "scale": Vector3.ONE, "offset": Vector3.ZERO,
		"is_signal": false, "is_marker": false, "marker_kind": "", "gizmo_color": Color("#cfd8e3"),
	}
	var out: Array = []
	for spec in [["CTT_Apartment_Tower_Low", "Apartment Tower (low)", 1], ["CTT_Apartment_Tower_High", "Apartment Tower (high)", 2]]:
		var m := base.duplicate()
		m["id"] = spec[0]
		m["display_name"] = spec[1]
		m["prefab"] = "%sSM_Bld_Apartment_Door_01.tscn" % bld
		m["stack"] = {
			"base_height": 3.0,
			"mid": "%sSM_Bld_Apartment_Stack_01.tscn" % bld,
			"mid_height": 9.0,
			"floors": int(spec[2]),
			"roof": "%sSM_Bld_Apartment_Roof_01.tscn" % bld,
		}
		out.append(m)
	return out


static func _scan_dir(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	# Vehicles and Characters are handled by spawns / pedestrian routes, not
	# placed as static geometry.
	if path.ends_with("/Vehicles") or path.ends_with("/Characters"):
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir("%s/%s" % [path, entry], out)
		elif entry.ends_with(".tscn"):
			var module := _classify("%s/%s" % [path, entry], entry.trim_suffix(".tscn"))
			if not module.is_empty():
				out.append(module)
		entry = dir.get_next()
	dir.list_dir_end()


static func _classify(full_path: String, base_name: String) -> Dictionary:
	var lower := base_name.to_lower()
	if "/Environments/" in full_path or "/Environments" in full_path.get_base_dir():
		for skip in _ENV_SKIP:
			if skip in lower:
				return {}
		if "road" in lower:
			return _mk(base_name, full_path, "Roads", Layer.SURFACE, true, false)
		if "sidewalk" in lower or "gutter" in lower or "curb" in lower:
			return _mk(base_name, full_path, "Sidewalks", Layer.SURFACE, true, false)
		if "tree" in lower:
			return _mk(base_name, full_path, "Nature", Layer.STRUCTURE, false, false)
		return _mk(base_name, full_path, "Ground & Decor", Layer.PROP, false, false)
	if "/Buildings/" in full_path or "/Buildings" in full_path.get_base_dir():
		return _mk(base_name, full_path, "Buildings", Layer.STRUCTURE, true, false)
	if "/Props/" in full_path or "/Props" in full_path.get_base_dir():
		if "lightpole_lights" in lower or "lightpole_arm" in lower or "trafficlight" in lower and ("lights" in lower or "arm" in lower):
			return _mk(base_name, full_path, "Street Fixtures", Layer.PROP, false, true)
		if "lightpole" in lower:
			return _mk(base_name, full_path, "Street Fixtures", Layer.PROP, false, false)
		for frag in _KNOCKABLE:
			if frag in lower:
				return _mk(base_name, full_path, "Reactive Props", Layer.PROP, false, false)
		return _mk(base_name, full_path, "Props", Layer.PROP, false, false)
	return {}


# --- Entry builders -------------------------------------------------------

static func _mk(base_name: String, prefab: String, category: String, layer: int, corner_pivot: bool, is_signal: bool) -> Dictionary:
	return {
		"id": base_name,                       # stable, unique (SM_ prefab name)
		"display_name": _pretty(base_name),
		"category": category,
		"prefab": prefab,
		"footprint": Vector2i.ONE,
		"layer": layer,
		"corner_pivot": corner_pivot,
		"scale": Vector3.ONE,
		"offset": Vector3.ZERO,
		"is_signal": is_signal,
		"is_marker": false,
		"marker_kind": "",
		"gizmo_color": Color("#cfd8e3"),
	}


static func _pretty(base_name: String) -> String:
	var text := base_name
	for prefix in ["SM_Env_", "SM_Bld_", "SM_Prop_", "SM_Veh_", "SM_"]:
		if text.begins_with(prefix):
			text = text.substr(prefix.length())
			break
	return text.replace("_", " ")


## Asset GROUPS: several sub-prefabs dropped together as one placeable (assembled
## by generated_city_loader from the "parts" list). Synty's kit pieces are modelled
## in place, so the parts sit at the same origin. Add more here to make new combos
## without a separate asset-builder UI.
static func _group_modules() -> Array:
	var props := "%s/Props/" % PREFAB_ROOT
	var base := {
		"category": "Street Fixtures", "footprint": Vector2i.ONE, "layer": Layer.PROP,
		"corner_pivot": false, "scale": Vector3.ONE, "offset": Vector3.ZERO,
		"is_marker": false, "marker_kind": "", "gizmo_color": Color("#cfd8e3"), "prefab": "",
	}
	var traffic := base.duplicate()
	traffic["id"] = "CTT_TrafficLight_Full"
	traffic["display_name"] = "Traffic Light (full)"
	traffic["is_signal"] = true
	traffic["group_root"] = "TrafficLightGroup"
	traffic["parts"] = [
		{"prefab": props + "SM_Prop_LightPole_Base_01.tscn", "pos": Vector3.ZERO, "turns": 0},
		{"prefab": props + "SM_Prop_LightPole_Arm_01.tscn", "pos": Vector3.ZERO, "turns": 0},
		{"prefab": props + "SM_Prop_LightPole_Lights_01.tscn", "pos": Vector3.ZERO, "turns": 0},
		{"prefab": props + "SM_Prop_LightPole_Box_01.tscn", "pos": Vector3.ZERO, "turns": 0},
	]
	var lamp := base.duplicate()
	lamp["id"] = "CTT_StreetLamp_Full"
	lamp["display_name"] = "Street Lamp (full)"
	lamp["is_signal"] = false
	lamp["group_root"] = "StreetLampGroup"
	lamp["parts"] = [
		{"prefab": props + "SM_Prop_LightPole_Base_01.tscn", "pos": Vector3.ZERO, "turns": 0},
		{"prefab": props + "SM_Prop_Light_Attachment_01.tscn", "pos": Vector3.ZERO, "turns": 0},
	]
	return [traffic, lamp]


## Load the owner's saved custom groups (a JSON array of group dicts) into palette
## modules under "My Groups". Missing/invalid file -> none.
static func _load_custom_groups() -> Array:
	if not FileAccess.file_exists(GROUPS_FILE):
		return []
	var file := FileAccess.open(GROUPS_FILE, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Array):
		return []
	var out: Array = []
	for g in parsed:
		if not (g is Dictionary) or not g.has("id") or not g.has("parts"):
			continue
		out.append({
			"id": String(g["id"]),
			"display_name": String(g.get("display_name", g["id"])),
			"category": "My Groups",
			"footprint": Vector2i.ONE,
			"layer": Layer.PROP,
			"corner_pivot": false,
			"scale": Vector3.ONE,
			"offset": Vector3.ZERO,
			"is_signal": bool(g.get("is_signal", false)),
			"is_marker": false,
			"marker_kind": "",
			"gizmo_color": Color("#8be0ff"),
			"prefab": "",
			"group_root": String(g.get("group_root", "CustomGroup")),
			"parts": g["parts"],
		})
	return out


## Append a group to the saved-groups file and refresh the palette cache. `group`
## is {id, display_name, is_signal?, parts:[{prefab, pos:[x,y,z], rot_deg}]}.
static func save_custom_group(group: Dictionary) -> int:
	var groups: Array = []
	if FileAccess.file_exists(GROUPS_FILE):
		var rf := FileAccess.open(GROUPS_FILE, FileAccess.READ)
		if rf:
			var parsed: Variant = JSON.parse_string(rf.get_as_text())
			if parsed is Array:
				groups = parsed
	# Replace an existing group with the same id, else append.
	var replaced := false
	for i in groups.size():
		if groups[i] is Dictionary and String(groups[i].get("id", "")) == String(group.get("id", "")):
			groups[i] = group
			replaced = true
			break
	if not replaced:
		groups.append(group)
	var dir := GROUPS_FILE.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var wf := FileAccess.open(GROUPS_FILE, FileAccess.WRITE)
	if wf == null:
		return FileAccess.get_open_error()
	wf.store_string(JSON.stringify(groups, "\t"))
	wf.close()
	refresh()
	return OK


static func _markers() -> Array:
	return [
		_marker("spawn_police", "Police Spawn", "police_spawn", Color("#28a9ff")),
		_marker("spawn_thief", "Thief Spawn", "thief_spawn", Color("#ff344d")),
		_marker("recovery_point", "Recovery Point", "recovery", Color("#42f5a7")),
		_marker("route_node", "Sidewalk Route Node", "sidewalk_route", Color("#ffce54")),
		_marker("boundary_post", "Map Boundary Post", "boundary", Color("#b061ff")),
	]


static func _marker(id: String, label: String, kind: String, color: Color) -> Dictionary:
	return {
		"id": id,
		"display_name": label,
		"category": "Markers",
		"prefab": "",
		"footprint": Vector2i.ONE,
		"layer": Layer.MARKER,
		"corner_pivot": false,
		"scale": Vector3.ONE,
		"offset": Vector3.ZERO,
		"is_signal": false,
		"is_marker": true,
		"marker_kind": kind,
		"gizmo_color": color,
	}
