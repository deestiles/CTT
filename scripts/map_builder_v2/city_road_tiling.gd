class_name CityRoadTiling
extends RefCounted
## Neighbour-aware tile + rotation selection for a set of road cells (and their
## sidewalks). The Synty road kit has no corner/T pieces -- roads are 5 m squares
## with markings baked in -- so:
##   * straight runs get a marked tile rotated to run ALONG the street
##     (center-line for a normal two-way street, lane-lines for a major road),
##   * corners and 3-/4-way junctions get plain asphalt (no misaligned paint).
##
## ROTATION CONVENTION (verify visually; flip the two consts if paint runs across
## the road instead of along it): a tile at NS_TURNS has its lines running
## north-south (along +Z); EW_TURNS runs them east-west (along +X).
const NS_TURNS := 0
const EW_TURNS := 1

const ROAD_PLAIN := "SM_Env_Road_01"
const ROAD_MINOR := "SM_Env_Road_YellowLines_01"   # two-way, one lane each way
const ROAD_MAJOR := "SM_Env_Road_Lines_01"         # bigger road, lane lines
const ROAD_JUNCTION := "SM_Env_Road_01"            # plain asphalt at 3-/4-way
const SIDEWALK_STRAIGHT := "SM_Env_Sidewalk_Straight_01"
const SIDEWALK_CORNER := "SM_Env_Sidewalk_Corner_01"

const _N := Vector2i(0, -1)
const _S := Vector2i(0, 1)
const _E := Vector2i(1, 0)
const _W := Vector2i(-1, 0)


## Returns {id, turns} for a road cell given the road set and the major-road set.
static func road_tile(cell: Vector2i, roads: Dictionary, majors: Dictionary) -> Dictionary:
	var n := roads.has(cell + _N)
	var s := roads.has(cell + _S)
	var e := roads.has(cell + _E)
	var w := roads.has(cell + _W)
	var count := int(n) + int(s) + int(e) + int(w)
	var is_major := majors.has(cell)
	if count >= 3:
		return {"id": ROAD_JUNCTION, "turns": 0}
	if count == 2 and ((n and s) or (e and w)):
		var vertical := n and s
		return _straight(is_major, vertical)
	if count == 1:
		var vertical := n or s
		return _straight(is_major, vertical)
	# Corner (two adjacent neighbours) or isolated: plain asphalt, no paint to
	# misalign (the kit has no road corner piece).
	return {"id": ROAD_PLAIN, "turns": 0}


static func _straight(is_major: bool, vertical: bool) -> Dictionary:
	var id := ROAD_MAJOR if is_major else ROAD_MINOR
	return {"id": id, "turns": NS_TURNS if vertical else EW_TURNS}


## Returns {id, turns} for a sidewalk cell so it runs parallel to the road it
## borders, using a corner tile where it wraps a road corner.
static func sidewalk_tile(cell: Vector2i, roads: Dictionary) -> Dictionary:
	var rn := roads.has(cell + _N)
	var rs := roads.has(cell + _S)
	var re := roads.has(cell + _E)
	var rw := roads.has(cell + _W)
	var vertical_border := re or rw     # road to the side => sidewalk runs N-S
	var horizontal_border := rn or rs   # road above/below => sidewalk runs E-W
	if vertical_border and horizontal_border:
		return {"id": SIDEWALK_CORNER, "turns": _corner_turns(rn, re, rs, rw)}
	if horizontal_border:
		return {"id": SIDEWALK_STRAIGHT, "turns": EW_TURNS}
	if vertical_border:
		return {"id": SIDEWALK_STRAIGHT, "turns": NS_TURNS}
	return {"id": SIDEWALK_STRAIGHT, "turns": NS_TURNS}


## Pick a corner rotation from which perpendicular sides face a road. Convention;
## flip/rotate if corners point the wrong way in a visual check.
static func _corner_turns(rn: bool, re: bool, rs: bool, rw: bool) -> int:
	if rn and re:
		return 0
	if re and rs:
		return 1
	if rs and rw:
		return 2
	if rw and rn:
		return 3
	return 0
