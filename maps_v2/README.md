# maps_v2 — Synty free-drive city maps (builder v2)

Committed city maps for the **map-builder v2** system. These are separate from
the old lane-graph builder's machine-local `user://maps` JSON and from the
repository `maps/` folder.

- Format id: `ctt_city_v2`, schema version 1 (see
  `scripts/map_builder_v2/city_map_schema.gd`).
- Built with `scenes/tools/synty_city_builder_v2.tscn`.
- Loaded/played via `scenes/drive/generated_city_test.tscn`
  (`scripts/drive/generated_city_loader.gd`).

A v2 map instances **real Synty Polygon City prefabs** on a 5 m grid and keeps
their Synty node names, so the approved name-driven runtime
(`scripts/drive/drive_city.gd`) navigation, lighting, signal, window and
knockable passes apply to the generated city without runtime edits. On top of
geometry, a v2 map also stores the gameplay-metadata layers the Demo currently
hardcodes: police/thief spawns, sidewalk routes, recovery points, map boundary,
and time-of-day.

Maps here are portable (unlike `user://maps`); commit approved maps so other
workstations can load them directly.
