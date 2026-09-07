# Web Map Builder

A browser-based, top-down map builder for **Catch the Thief**. It places the same
Polygon City module catalog the mobile game uses, enforces the same grid/footprint/
lane rules, runs the same validation, and writes maps in the **exact JSON schema the
game loads** — so a map built here drives in the game with no conversion step.

It is a design/authoring tool. The actual 3D Polygon City meshes are rendered by the
game at load time; this builder draws a clear top-down schematic (asphalt, lane
arrows, one-way/two-way center lines, curves, intersections, sidewalks, buildings,
props, vehicles, pedestrians) which is the right view for fast grid layout.

## Quick start

```bash
python tools/web_map_builder/save_bridge.py
```

Then open the URL it prints (default `http://localhost:8777`).

The **save bridge** is a tiny local Python server (standard library only, no installs).
It serves the builder and lets you Save/Load maps straight to disk:

- repository `maps/<name>.json` (for git handoff), and
- Godot `user://maps/<name>.json` — on Windows
  `%APPDATA%\Godot\app_userdata\Catch the Thief\maps` — so the game sees the map
  immediately.

You can also run the builder **without** the bridge (open `index.html` directly, or
serve the folder any other way). Saving then falls back to **Export** (download the
JSON) and **Import** (open a JSON file). Copy the file into `maps/` and `user://maps/`
by hand — the same manual step described in `PROJECT_GUIDE.md`. Expert players who
don't have the repo use this Export/Import path and submit their JSON.

## Using it

1. **New** — set the map name and play-area size (columns × rows). Cells are 5 m.
   Light gridlines appear; every 5th line is emphasized, and the play-area box is
   outlined in blue.
2. Pick an asset from the left palette (grouped Roads / Sidewalks / Buildings /
   Street Fixtures / Vehicles / Pedestrians).
3. **Place** tool: click or click-drag to paint. Press **R** to rotate (90° steps).
   **Erase** removes the top item in a cell. **Select** shows item info; Delete removes it.
4. Pan with middle-drag (or Alt+drag); zoom with the scroll wheel.
5. Watch the **Validation** panel. A map is valid when it has no open road ends, no
   lane mismatches, no one-way direction conflicts, no disconnected road islands, no
   misoriented fixtures, and at least two vehicle spawns. Problem cells are outlined
   (red = blocking, amber = warning).
6. Set **Playable as** — Police, Criminal, or both.
7. **Save** (bridge) or **Export** (download).

To drive a map in the game: set `GameState.builder_map_name` to the map name (the
in-engine **TEST MAP** flow does this), then run `scenes/chase/grid_streets_test.tscn`.

## Asset thumbnails (real prefab images)

Edged/mesh assets — sidewalks (incl. corners), buildings, lamps, traffic
lights, vehicles, pedestrians — are drawn using **real top-down renders** of
the actual Polygon City prefabs, so you can see how a piece looks and how a
rotation will land. Roads keep the arrow/center-line schematic on purpose:
every road id uses the same bare-road prefab, so its meaning is procedural, not
in the mesh.

The images live in `thumbs/<id>.png`. Regenerate them (e.g. after changing the
catalog or the prefabs) with a **real renderer** — not `--headless`, which
cannot capture pixels:

```bash
& 'C:\Users\deest\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tools/render_thumbnails/render_thumbnails.gd
```

It renders each non-road prefab from an orthographic top-down camera, auto-frames
by the mesh bounds (so corner-pivoted pieces sit square), and writes transparent
PNGs. They are kept in normal git (not LFS) via `thumbs/.gitattributes` because
they are small and generated.

## Rules mirrored from the game

`catalog.js` and `rules.js` are faithful ports of, and must stay in sync with:

- `scripts/map_builder/map_builder_catalog.gd` — the placeable catalog
- `scripts/map_builder/road_module_rules.gd` — footprints, lane counts, ports
- `scripts/map_builder/placeable_definition.gd` — the data model
- `scripts/map_builder/map_builder_test.gd` — placement, occupancy/layering,
  validation, and spawn-candidate generation

If any of those change in the game, update the two JS files to match. A quick check:
load an existing approved map and confirm the Validation panel reports the same
`vehicle_spawn_candidates` / `pedestrian_spawn_candidates` / `valid` as the saved
`validation` block in its JSON.

## Output schema

Top level: `version`, `grid_size` (5), `lane_width` (5), `items`
(`{id, cell:[x,y], turns}`), `camera` (`{x,z,size}`), `spawn_candidates`
(`{vehicles:[{cell,road_id,turns}], pedestrians:[{cell,turns}]}`), and `validation`.

Builder-only metadata the current game loader ignores (safe/forward-compatible):
`roles` (`["police"]` / `["criminal"]` / both), `name`, `author`, `created`,
`play_area`, `builder`. When the game later wants to filter maps by mode, it can read
`roles`.

## Files

| File | Purpose |
| --- | --- |
| `index.html` | UI shell + styling |
| `catalog.js` | Polygon City catalog + road-module contract (port) |
| `rules.js` | Placement, validation, spawn-candidate logic (port) |
| `app.js` | Canvas rendering, interaction, save/load/IO |
| `save_bridge.py` | Local server: serves the app + writes maps to repo and `user://` |
