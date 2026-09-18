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
const Tiling := preload("res://scripts/map_builder_v2/city_road_tiling.gd")

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
		# A road cell counts as a MAJOR road (lane-line tile) rather than a normal
		# two-way street (center-line tile) when this fraction of it is road pixels
		# -- thick boulevards fill a cell far more than a thin residential street.
		"major_fill": 0.55,
		"place_sidewalks": true,
		"place_buildings": true,
		"building_cap": 500,
		"building_ids": BUILDING_IDS,
		# Deskew: detect the dominant street direction and sample the map along that
		# rotated frame, so most roads land on N/S/E/W. Diagonal/curved streets that
		# don't fit the box grid then drop out as fragments (kept: the largest
		# connected axis-aligned network).
		"auto_rotate": true,
		"max_skew_deg": 30,   # only correct tilt within +/- this; ignore diagonals
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

	# 0) Deskew: find the dominant street angle and sample along it, so most roads
	# land axis-aligned (box world). Diagonals then fall out as fragments.
	var rot_deg := 0.0
	var override = opts.get("rotation_override", null)
	if override != null and is_finite(float(override)):
		rot_deg = float(override)              # user-set angle wins over auto-detect
	elif bool(opts.get("auto_rotate", true)):
		rot_deg = _detect_grid_angle(image, opts)
	var rot := deg_to_rad(-rot_deg)   # sample the source along the road direction
	var rc := cos(rot)
	var rs := sin(rot)
	var center := Vector2(w * 0.5, h * 0.5)

	# 1) Classify every cell from its pixels (fraction-based, so thin streets on
	# near-white land are still caught).
	var kind := {}       # Vector2i -> Kind
	var road_frac := {}  # Vector2i -> fraction of road pixels (for major/minor)
	var tally := {Kind.OTHER: 0, Kind.ROAD: 0, Kind.WATER: 0, Kind.PARK: 0}
	for cz in cells_down:
		for cx in cells_across:
			var cell := Vector2i(cx, cz)
			var res := _classify_cell(image, cx, cz, cells_across, cells_down, opts, rc, rs, center)
			kind[cell] = int(res["kind"])
			road_frac[cell] = float(res["road_frac"])
			tally[int(res["kind"])] += 1

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

	# 4b) Major roads: connected road cells that are mostly-filled (thick lines).
	var majors := {}
	var major_fill := float(opts["major_fill"])
	for cell in road_cells:
		if float(road_frac.get(cell, 0.0)) >= major_fill:
			majors[cell] = true

	# 5) Emit items with neighbour-aware tile + rotation (paint follows the street;
	# corners/junctions use plain asphalt; sidewalks run parallel to their road).
	var items: Array = []
	var major_count := 0
	for cell in road_cells:
		var t: Dictionary = Tiling.road_tile(cell, road_cells, majors)
		items.append({"id": t["id"], "cell": [cell.x, cell.y], "turns": int(t["turns"])})
		if majors.has(cell):
			major_count += 1
	for cell in sidewalk_cells:
		var st: Dictionary = Tiling.sidewalk_tile(cell, road_cells)
		items.append({"id": st["id"], "cell": [cell.x, cell.y], "turns": int(st["turns"])})
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
		"rotation_deg": rot_deg,
		"roads": road_cells.size(),
		"major_roads": major_count,
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
static func _classify_cell(image: Image, cx: int, cz: int, cells_across: int, cells_down: int, opts: Dictionary, rc: float, rs: float, center: Vector2) -> Dictionary:
	var w := image.get_width()
	var h := image.get_height()
	# Cell box in the (deskewed) aligned pixel frame; each sample is rotated back
	# into the source image, so the output grid follows the dominant road angle.
	var ax0 := float(cx) / cells_across * w
	var ax1 := float(cx + 1) / cells_across * w
	var ay0 := float(cz) / cells_down * h
	var ay1 := float(cz + 1) / cells_down * h
	var step_x := maxf(1.0, (ax1 - ax0) / 24.0)
	var step_y := maxf(1.0, (ay1 - ay0) / 24.0)
	var road_ceiling := float(opts["road_ceiling"])
	var road_floor := float(opts["road_floor"])
	var road_neutral := float(opts["road_neutral"])
	var total := 0
	var road := 0
	var water := 0
	var park := 0
	var ay := ay0
	while ay < ay1:
		var ax := ax0
		while ax < ax1:
			var dx := ax - center.x
			var dy := ay - center.y
			var sx := int(center.x + dx * rc - dy * rs)
			var sy := int(center.y + dx * rs + dy * rc)
			ax += step_x
			if sx < 0 or sy < 0 or sx >= w or sy >= h:
				continue
			var c := image.get_pixel(sx, sy)
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
		ay += step_y
	if total == 0:
		return {"kind": Kind.OTHER, "road_frac": 0.0}
	var rf := float(road) / total
	if float(water) / total > 0.40:
		return {"kind": Kind.WATER, "road_frac": rf}
	if rf >= float(opts["road_fill"]):
		return {"kind": Kind.ROAD, "road_frac": rf}
	if float(park) / total > 0.40:
		return {"kind": Kind.PARK, "road_frac": rf}
	return {"kind": Kind.OTHER, "road_frac": rf}


static func _is_road_pixel(c: Color, road_ceiling: float, road_floor: float, road_neutral: float) -> bool:
	if c.b - c.r > 0.12 and c.b - c.g > 0.05 and c.b > 0.55:
		return false                                       # water
	if c.g > c.r + 0.04 and c.g > c.b + 0.04 and c.g > 0.5:
		return false                                       # park
	var bright := (c.r + c.g + c.b) / 3.0
	var spread: float = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b))
	if bright <= road_ceiling and bright >= road_floor and spread <= road_neutral:
		return true
	if c.r > 0.80 and c.g > 0.60 and c.b < 0.60:
		return true
	return false


## Estimate the map's skew (small tilt) and return the angle to straighten it.
## For each candidate angle in a LIMITED range (default +/-30 deg -- a screenshot
## is roughly upright, so we only correct the grid's tilt and never swing onto a
## diagonal), it bins the road pixels into a coarse rotated grid and measures the
## LARGEST 4-connected road component. The angle that connects the most road wins
## -- directly the "majority of streets on the box grid" goal. A gentle bias
## keeps 0 deg unless a tilt is clearly better, so near-upright maps stay put.
static func _detect_grid_angle(image: Image, opts: Dictionary) -> float:
	var w := image.get_width()
	var h := image.get_height()
	var road_ceiling := float(opts["road_ceiling"])
	var road_floor := float(opts["road_floor"])
	var road_neutral := float(opts["road_neutral"])
	var step := maxi(1, int(w / 220.0))
	var pts := PackedVector2Array()
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			if _is_road_pixel(image.get_pixel(x, y), road_ceiling, road_floor, road_neutral):
				pts.append(Vector2(x, y))
			x += step
		y += step
	if pts.size() < 50:
		return 0.0
	# Coarse cell size roughly matches a street-grid cell so a road line fills a
	# coarse cell but a diagonal only clips cell corners (breaking 4-connectivity).
	var cell_px := float(step) * 4.0
	var max_skew := int(opts.get("max_skew_deg", 30))
	var best_score := -1
	var best_deg := 0.0
	for deg in range(-max_skew, max_skew + 1):
		var th := deg_to_rad(float(deg))
		var c := cos(th)
		var s := sin(th)
		var road_cells := {}
		for p in pts:
			var cxi := int(floor((p.x * c - p.y * s) / cell_px))
			var cyi := int(floor((p.x * s + p.y * c) / cell_px))
			road_cells[Vector2i(cxi, cyi)] = true
		var comp: Dictionary = _largest_component(road_cells)
		# Bias toward 0: a tilt must beat upright by >2% of connected cells.
		var score := comp.size()
		if deg == 0:
			score = int(score * 1.02) + 1
		if score > best_score:
			best_score = score
			best_deg = float(deg)
	if absf(best_deg) <= 1.0:
		return 0.0
	return best_deg


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
