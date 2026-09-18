class_name CityRandomGenerator
extends RefCounted
## Procedurally lay out a new city on the 5 m grid using the same Synty assets
## and the same grouping patterns seen in the reference city: a connected road
## grid (direction-correct marking tiles, thicker "major" avenues), sidewalks
## flanking the roads, blocks filled with buildings (residential towers, shops,
## the occasional office tower and park), plus street furniture grouped ONTO the
## sidewalk squares -- lamps at intervals, occasional bins/mailboxes, trees, and
## traffic signals at the big intersections (multiple assets sharing one square).
##
## It produces a ctt_city_v2 map (see city_map_schema.gd) with spawns and a
## boundary, ready to Load / Validate / Test / edit.

const Schema := preload("res://scripts/map_builder_v2/city_map_schema.gd")
const Tiling := preload("res://scripts/map_builder_v2/city_road_tiling.gd")

const SHOPS := ["SM_Bld_Shop_01", "SM_Bld_Shop_02", "SM_Bld_Shop_03", "SM_Bld_Shop_04"]
const TOWERS := ["CTT_Apartment_Tower_Low", "CTT_Apartment_Tower_High"]
const OFFICE := "SM_Bld_OfficeSquare_01"          # 3x3 downtown tower
const LAMP := "SM_Prop_LightPole_Base_01"
const SIGNAL := "SM_Prop_LightPole_Lights_01"
const TREE := "SM_Env_Tree_01"
const SIDEWALK_PROPS := ["SM_Prop_TrashCan_01", "SM_Prop_Mailbox_01", "SM_Prop_ParkBench_01", "SM_Prop_Cone_01"]

const _N := Vector2i(0, -1)
const _S := Vector2i(0, 1)
const _E := Vector2i(1, 0)
const _W := Vector2i(-1, 0)


static func default_options() -> Dictionary:
	return {
		"width": 64,
		"height": 44,
		"seed": 0,            # 0 => randomize
		"block_min": 4,
		"block_max": 8,
		"major_every": 3,     # every Nth avenue is a major (lane-line) road
		"park_chance": 0.12,
		"lamp_spacing": 4,
		"tree_chance": 0.10,
		"prop_chance": 0.10,
	}


static func generate(options: Dictionary = {}) -> Dictionary:
	var o := default_options()
	for k in options.keys():
		o[k] = options[k]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(o["seed"]) if int(o["seed"]) != 0 else randi()

	var width := int(o["width"])
	var height := int(o["height"])

	# 1) Road lines -> connected grid.
	var col_x := _road_lines(width, int(o["block_min"]), int(o["block_max"]), rng)
	var row_z := _road_lines(height, int(o["block_min"]), int(o["block_max"]), rng)
	var road := {}
	var majors := {}
	for i in col_x.size():
		var x: int = col_x[i]
		var major: bool = (i % int(o["major_every"])) == 0
		for z in range(0, height):
			road[Vector2i(x, z)] = true
			if major:
				majors[Vector2i(x, z)] = true
	for j in row_z.size():
		var z: int = row_z[j]
		var major: bool = (j % int(o["major_every"])) == 0
		for x in range(0, width):
			road[Vector2i(x, z)] = true
			if major:
				majors[Vector2i(x, z)] = true

	# 2) Sidewalks: non-road cells 4-adjacent to a road, inside bounds.
	var sidewalk := {}
	for cell in road:
		for step in [_N, _S, _E, _W]:
			var n: Vector2i = cell + step
			if not road.has(n) and _in_bounds(n, width, height):
				sidewalk[n] = true

	# 3) Blocks: interior land cells grouped into lots; fill per-block theme.
	var interior := {}
	for x in range(0, width):
		for z in range(0, height):
			var c := Vector2i(x, z)
			if not road.has(c) and not sidewalk.has(c):
				interior[c] = true
	var buildings := {}      # cell -> building id
	var trees := {}          # cell -> true
	for block in _components(interior):
		_fill_block(block, rng, o, buildings, trees)

	# 4) Emit items. Roads/sidewalks are single tiles; furniture is layered ONTO
	# the sidewalk squares (multiple assets per cell), like the reference city.
	var items: Array = []
	var major_count := 0
	for cell in road:
		var t: Dictionary = Tiling.road_tile(cell, road, majors)
		items.append(_item(t["id"], cell, int(t["turns"])))
		if majors.has(cell):
			major_count += 1
	var sidewalk_list: Array = sidewalk.keys()
	sidewalk_list.sort_custom(func(a, b): return (a.x * 1000 + a.y) < (b.x * 1000 + b.y))
	var lamp_i := 0
	for cell in sidewalk_list:
		var st: Dictionary = Tiling.sidewalk_tile(cell, road)
		items.append(_item(st["id"], cell, int(st["turns"])))
		# Lamp every Nth sidewalk cell (grouped on the same square).
		lamp_i += 1
		if lamp_i % int(o["lamp_spacing"]) == 0:
			items.append(_item(LAMP, cell, 0))
		elif rng.randf() < float(o["prop_chance"]):
			items.append(_item(SIDEWALK_PROPS[rng.randi() % SIDEWALK_PROPS.size()], cell, rng.randi() % 4))
		elif rng.randf() < float(o["tree_chance"]):
			items.append(_item(TREE, cell, 0))
	# Traffic signals at 4-way intersections (on the diagonal sidewalk corners),
	# alternating axis so perpendicular approaches oppose.
	for cell in road:
		if _is_four_way(cell, road):
			_place_signals(cell, sidewalk, items)
	for cell in buildings:
		items.append(_item(buildings[cell], cell, rng.randi() % 4))
	for cell in trees:
		items.append(_item(TREE, cell, 0))

	# 5) Spawns (far apart on the road) + boundary ring.
	var data: Dictionary = Schema.new_empty("random_city")
	data["items"] = items
	var road_list: Array = road.keys()
	road_list.sort_custom(func(a, b): return a.x < b.x)
	if road_list.size() >= 2:
		var west: Vector2i = road_list[0]
		var east: Vector2i = road_list[road_list.size() - 1]
		data["spawns"] = {
			"police": {"cell": [west.x, west.y], "turns": 0},
			"thief": {"cell": [east.x, east.y], "turns": 0}}
	data["boundary"] = [[0, 0], [width, 0], [width, height], [0, height]]
	data["time_of_day"] = ["DAY", "DUSK", "NIGHT"][rng.randi() % 3]

	return {
		"data": data,
		"seed": rng.seed,
		"roads": road.size(),
		"major_roads": major_count,
		"sidewalks": sidewalk.size(),
		"buildings": buildings.size(),
		"trees": trees.size(),
	}


# --- Layout helpers -------------------------------------------------------

static func _road_lines(extent: int, block_min: int, block_max: int, rng: RandomNumberGenerator) -> Array:
	var lines: Array = []
	var pos := 0
	while pos < extent:
		lines.append(pos)
		pos += rng.randi_range(block_min, block_max) + 1
	if lines.is_empty() or int(lines[lines.size() - 1]) < extent - 1:
		lines.append(extent - 1)
	return lines


static func _fill_block(block: Array, rng: RandomNumberGenerator, o: Dictionary, buildings: Dictionary, trees: Dictionary) -> void:
	if block.is_empty():
		return
	if rng.randf() < float(o["park_chance"]):
		# Park: mostly open with scattered trees.
		for cell in block:
			if rng.randf() < 0.25:
				trees[cell] = true
		return
	# Try one downtown office tower (3x3) inside a big-enough block.
	var used := {}
	if block.size() >= 9 and rng.randf() < 0.35:
		var anchor = _fit_square(block, 3)
		if anchor != null:
			for dx in range(3):
				for dz in range(3):
					used[anchor + Vector2i(dx, dz)] = true
			buildings[anchor] = OFFICE   # placed once at its anchor (3x3 footprint)
	# Residential mix on the remaining cells (weighted toward towers).
	for cell in block:
		if used.has(cell):
			continue
		var roll := rng.randf()
		if roll < 0.55:
			buildings[cell] = TOWERS[rng.randi() % TOWERS.size()]
		elif roll < 0.85:
			buildings[cell] = SHOPS[rng.randi() % SHOPS.size()]
		else:
			trees[cell] = true   # a gap / yard


static func _fit_square(block: Array, size: int):
	var set := {}
	for c in block:
		set[c] = true
	for c in block:
		var ok := true
		for dx in range(size):
			for dz in range(size):
				if not set.has(c + Vector2i(dx, dz)):
					ok = false
					break
			if not ok:
				break
		if ok:
			return c
	return null


static func _place_signals(cell: Vector2i, sidewalk: Dictionary, items: Array) -> void:
	# Put a signal head on the NE and SW sidewalk corners, opposing axes.
	var ne: Vector2i = cell + _N + _E
	var sw: Vector2i = cell + _S + _W
	if sidewalk.has(ne):
		items.append(_item(SIGNAL, ne, 0))
	if sidewalk.has(sw):
		items.append(_item(SIGNAL, sw, 1))


static func _is_four_way(cell: Vector2i, road: Dictionary) -> bool:
	return road.has(cell + _N) and road.has(cell + _S) and road.has(cell + _E) and road.has(cell + _W)


static func _in_bounds(c: Vector2i, width: int, height: int) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


static func _components(cells: Dictionary) -> Array:
	var remaining := cells.duplicate()
	var out: Array = []
	var neighbors := [_N, _S, _E, _W]
	while not remaining.is_empty():
		var start: Vector2i = remaining.keys()[0]
		var comp: Array = [start]
		remaining.erase(start)
		var queue: Array = [start]
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_back()
			for step in neighbors:
				var n: Vector2i = cur + step
				if remaining.has(n):
					remaining.erase(n)
					comp.append(n)
					queue.append(n)
		out.append(comp)
	return out


static func _item(id: String, cell: Vector2i, turns: int) -> Dictionary:
	return {"id": id, "cell": [cell.x, cell.y], "turns": turns}
