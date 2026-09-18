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
# Multi-level apartment towers (composite; see catalog _composite_buildings) mixed
# with a couple of low-rise shops, so an imported city has real building height.
const BUILDING_IDS := ["CTT_Apartment_Tower_High", "CTT_Apartment_Tower_Low", "CTT_Apartment_Tower_Low", "SM_Bld_Shop_02"]


static func default_options() -> Dictionary:
	return {
		"cells_across": 80,
		# Google-style maps draw ROADS as neutral GREY lines on a near-WHITE land
		# background. A pixel is a road pixel when it is neutral (low saturation)
		# and its brightness falls in [road_floor, road_ceiling]: darker than the
		# white land (road_ceiling) but not as dark as black label text (road_floor).
		"road_ceiling": 0.86,
		"road_floor": 0.45,
		"road_neutral": 0.14,   # max(rgb)-min(rgb) below which a pixel is neutral grey
		# A cell becomes road when at least this fraction of its pixels are road
		# pixels. Low, because streets are thin lines inside a mostly-land cell.
		"road_fill": 0.05,
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

	# 1) Classify every cell from its pixels (fraction-based, so thin streets on
	# near-white land are still caught).
	var kind := {}   # Vector2i -> Kind
	var tally := {Kind.OTHER: 0, Kind.ROAD: 0, Kind.WATER: 0, Kind.PARK: 0}
	for cz in cells_down:
		for cx in cells_across:
			var k := _classify_cell(image, cx, cz, cells_across, cells_down, opts)
			kind[Vector2i(cx, cz)] = k
			tally[k] += 1

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
	# Prefer street-facing lots (adjacent to a sidewalk or road) so buildings line
	# the streets instead of filling one corner; then backfill interiors.
	var building_cells := {}
	if bool(opts["place_buildings"]):
		var cap := int(opts["building_cap"])
		var facing: Array = []
		var interior: Array = []
		for cell in kind:
			if road_cells.has(cell) or sidewalk_cells.has(cell) or kind[cell] != Kind.OTHER:
				continue
			var street := false
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if sidewalk_cells.has(cell + step) or road_cells.has(cell + step):
					street = true
					break
			if street:
				facing.append(cell)
			else:
				interior.append(cell)
		for cell in facing:
			if building_cells.size() >= cap:
				break
			building_cells[cell] = true
		for cell in interior:
			if building_cells.size() >= cap:
				break
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
		"road_cells_raw": tally[Kind.ROAD],
		"water_cells": tally[Kind.WATER],
		"park_cells": tally[Kind.PARK],
		"land_cells": tally[Kind.OTHER],
	}


## Scan the cell's pixels and decide its kind by category fractions. This beats
## averaging: a thin white street inside a mostly-land cell still registers as
## road, and green pins / blue labels don't tint a whole cell into a false class.
static func _classify_cell(image: Image, cx: int, cz: int, cells_across: int, cells_down: int, opts: Dictionary) -> int:
	var w := image.get_width()
	var h := image.get_height()
	var x0 := int(float(cx) / cells_across * w)
	var x1 := maxi(x0 + 1, int(float(cx + 1) / cells_across * w))
	var y0 := int(float(cz) / cells_down * h)
	var y1 := maxi(y0 + 1, int(float(cz + 1) / cells_down * h))
	# Cap samples per axis so large cells stay cheap.
	var step_x := maxi(1, (x1 - x0) / 24)
	var step_y := maxi(1, (y1 - y0) / 24)
	var road_ceiling := float(opts["road_ceiling"])
	var road_floor := float(opts["road_floor"])
	var road_neutral := float(opts["road_neutral"])
	var total := 0
	var road := 0
	var water := 0
	var park := 0
	var py := y0
	while py < y1:
		var px := x0
		while px < x1:
			var c := image.get_pixel(mini(px, w - 1), mini(py, h - 1))
			total += 1
			var bright := (c.r + c.g + c.b) / 3.0
			var spread: float = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b))
			# Water must be clearly, saturatedly blue -- a faint blue-grey road line
			# (b only slightly above r) must NOT be mistaken for water.
			if c.b - c.r > 0.12 and c.b - c.g > 0.05 and c.b > 0.55:
				water += 1
			elif c.g > c.r + 0.04 and c.g > c.b + 0.04 and c.g > 0.5:
				park += 1
			elif bright <= road_ceiling and bright >= road_floor and spread <= road_neutral:
				road += 1                                  # neutral grey road line
			elif c.r > 0.80 and c.g > 0.60 and c.b < 0.60:
				road += 1                                  # yellow/orange arterial
			px += step_x
		py += step_y
	if total == 0:
		return Kind.OTHER
	if float(water) / total > 0.40:
		return Kind.WATER
	if float(road) / total >= float(opts["road_fill"]):
		return Kind.ROAD
	if float(park) / total > 0.40:
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
