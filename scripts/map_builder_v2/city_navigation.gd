class_name CityNavigation
extends RefCounted
## Shared road-only navigation helper for map-builder v2.
##
## Bakes a NavigationMesh from a generated `City` tree with the SAME parameters
## the approved runtime uses (scripts/drive/drive_city.gd._setup_navigation), so
## the validator, the orchestrator, and the production runtime all agree on what
## "drivable road" means. Also wraps the post-bake map sync that path queries
## require (verified necessary during loader de-risking).

const ROAD_GROUP := "nav_road"


static func make_road_navmesh() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 1.4
	nm.agent_height = 1.5
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 30.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = ROAD_GROUP
	return nm


## Group every road (and tree, so trunks carve holes) mesh so the bake sees them.
static func tag_road_geometry(city: Node) -> int:
	var count := 0
	for r in city.find_children("*Road*", "MeshInstance3D", true, false):
		(r as Node).add_to_group(ROAD_GROUP)
		count += 1
	for t in city.find_children("*Tree*", "MeshInstance3D", true, false):
		(t as Node).add_to_group(ROAD_GROUP)
	return count


## Create and synchronously bake a NavigationRegion3D under `parent` from `city`.
## Returns the region (already added to the tree). Caller should await a few
## physics frames + sync_map() before querying paths.
static func bake_region(parent: Node, city: Node) -> NavigationRegion3D:
	tag_road_geometry(city)
	var region := NavigationRegion3D.new()
	region.name = "NavRegion"
	region.navigation_mesh = make_road_navmesh()
	parent.add_child(region)
	region.bake_navigation_mesh(false)
	# Re-assign to force the region to upload the freshly baked polygons.
	region.navigation_mesh = region.navigation_mesh
	return region


static func sync_map(map: RID) -> void:
	NavigationServer3D.map_force_update(map)


## Straight NavigationServer path between two world points on `map`.
static func path_between(map: RID, from: Vector3, to: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(map, from, to, true)


static func path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	return total


## Closest point on the navmesh to `world` (INF-guarded). Useful to test whether
## a spawn actually lands on drivable road.
static func closest_point(map: RID, world: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(map, world)
