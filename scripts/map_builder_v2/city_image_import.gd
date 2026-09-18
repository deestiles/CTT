class_name CityImageImport
extends RefCounted
## Turn a top-down map image (e.g. a Google Maps screenshot, light theme) into a
## rough ctt_city_v2 layout: road grid + flanking sidewalks + block buildings.
##
## This is a FIRST PASS, not an exact trace. The builder shows the image as an
## underlay so the result can be refined by hand (drag-paint). Detection is
## colour-based and tunable; averaging thins narrow roads, so a coarser
## cells_across captures streets better than a very fine one.

const Schema := preload("res://scripts/map_builder_v2/city_map_schema.gd")

enum Kind { OTHER, ROAD, WATER, PARK }

# Prefab ids used for auto-placed geometry (must exist in the catalog scan).
const ROAD_ID := "SM_Env_Road_Lines_01"
const SIDEWALK_ID := "SM_Env_Sidewalk_Straight_01"
const BUILDING_IDS := ["SM_Bld_Shop_01", "SM_Bld_Apartment_01", "SM_Bld_Apartment_02", "SM_Bld_Apartment_03"]


static func default_options() -> Dictionary:
	return {
		"cells_across": 80,
		"road_brightness": 0.965,  # avg brightness above which a neutral cell is road
		                           # (roads are near-white ~1.0; light land is ~0.95)
		"neutral_spread": 0.12,    # max(rgb)-min(rgb) below which a cell is neutral
		"place_sidewalks": true,
		"place_buildings": true,
		"building_cap": 500,
		"building_ids": BUILDING_IDS,
	}


## Returns a ctt_city_v2 data Dictionary (items only; spawns/boundary left for the
## user). `img` may be any format; it is converted to RGBA8 internally.
static func build_map_from_image(img: Image, options: Dictionary = {}) -> Dictionary:
	var opts := default_options()
	for k in options.keys():
		opts[k] = options[k]

	var image := img.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var w := image.get_width()
	var h := image.get_height()

	var cells_across: int = maxi(4, int(opts["cells_across"]))
	var cells_down: int = maxi(4, int(round(cells_across * float(h) / float(maxi(1, w)))))

	# 1) Classify every cell by sampling a small set of pixels.
	var kind := {}   # Vector2i -> Kind
	for cz in cells_down:
		for cx in cells_across:
			kind[Vector2i(cx, cz)] = _classify(_sample_cell(image, cx, cz, cells_across, cells_down), opts)

	# 2) Road cells, reduced to the largest connected component (drivable + valid).
	var road_cells := {}
	for cell in kind:
		if kind[cell] == Kind.ROAD:
			road_cells[cell] = true
	road_cells = _largest_component(road_cells)

	# 3) Sidewalks: non-road cells 4-adjacent to a road cell.
	var sidewalk_cells := {}
	if bool(opts["place_sidewalks"]):
		for cell in road_cells:
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = cell + step
				if not road_cells.has(n) and kind.has(n) and kind[n] != Kind.WATER:
					sidewalk_cells[n] = true

	# 4) Buildings: land cells that are neither road nor sidewalk (capped).
	var building_cells := {}
	if bool(opts["place_buildings"]):
		var cap := int(opts["building_cap"])
		for cell in kind:
			if building_cells.size() >= cap:
				break
			if road_cells.has(cell) or sidewalk_cells.has(cell):
				continue
			if kind[cell] == Kind.OTHER:   # land only, skip water/park
				building_cells[cell] = true

	# 5) Emit items.
	var items: Array = []
	for cell in road_cells:
		items.append({"id": ROAD_ID, "cell": [cell.x, cell.y], "turns": 0})
	for cell in sidewalk_cells:
		items.append({"id": SIDEWALK_ID, "cell": [cell.x, cell.y], "turns": 0})
	var bids: Array = opts["building_ids"]
	var bi := 0
	for cell in building_cells:
		var id: String = String(bids[bi % bids.size()]) if not bids.is_empty() else "SM_Bld_Shop_01"
		items.append({"id": id, "cell": [cell.x, cell.y], "turns": 0})
		bi += 1

	var data: Dictionary = Schema.new_empty("imported_city")
	data["items"] = items
	return {
		"data": data,
		"cells_across": cells_across,
		"cells_down": cells_down,
		"roads": road_cells.size(),
		"sidewalks": sidewalk_cells.size(),
		"buildings": building_cells.size(),
	}


static func _sample_cell(image: Image, cx: int, cz: int, cells_across: int, cells_down: int) -> Color:
	var w := image.get_width()
	var h := image.get_height()
	var x0 := int(float(cx) / cells_across * w)
	var x1 := int(float(cx + 1) / cells_across * w)
	var y0 := int(float(cz) / cells_down * h)
	var y1 := int(float(cz + 1) / cells_down * h)
	var acc := Color(0, 0, 0, 0)
	var n := 0
	var steps := 4
	for sx in steps:
		for sy in steps:
			var px := clampi(x0 + int((x1 - x0) * (sx + 0.5) / steps), 0, w - 1)
			var py := clampi(y0 + int((y1 - y0) * (sy + 0.5) / steps), 0, h - 1)
			acc += image.get_pixel(px, py)
			n += 1
	return acc / maxi(1, n)


static func _classify(c: Color, opts: Dictionary) -> int:
	var mx: float = max(c.r, max(c.g, c.b))
	var mn: float = min(c.r, min(c.g, c.b))
	var bright := (c.r + c.g + c.b) / 3.0
	# Water: blue clearly dominant.
	if c.b > c.r + 0.06 and c.b > c.g + 0.02 and c.b > 0.45:
		return Kind.WATER
	# Roads: bright + neutral (white/light), or yellow/orange arterials.
	if bright >= float(opts["road_brightness"]) and (mx - mn) <= float(opts["neutral_spread"]):
		return Kind.ROAD
	if c.r > 0.80 and c.g > 0.60 and c.b < 0.60:
		return Kind.ROAD
	# Parks/greens.
	if c.g > c.r + 0.05 and c.g > c.b + 0.05:
		return Kind.PARK
	return Kind.OTHER


static func _largest_component(cells: Dictionary) -> Dictionary:
	var remaining := cells.duplicate()
	var best := {}
	var neighbors := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not remaining.is_empty():
		var start: Vector2i = remaining.keys()[0]
		var comp := {}
		var queue: Array = [start]
		remaining.erase(start)
		comp[start] = true
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_back()
			for step in neighbors:
				var n: Vector2i = cur + step
				if remaining.has(n):
					remaining.erase(n)
					comp[n] = true
					queue.append(n)
		if comp.size() > best.size():
			best = comp
	return best
