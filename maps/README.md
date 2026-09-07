# Versioned map handoff

The in-game builder saves JSON maps to Godot's `user://maps` directory. On Windows this project currently resolves to:

`%APPDATA%\Godot\app_userdata\Catch the Thief\maps`

Those local files are not automatically visible to another developer. After approving a map, copy its JSON file into this directory and commit it. A receiving developer copies the selected JSON back into their local `user://maps` directory before loading/testing it.

Do not edit map JSON by hand unless the schema in `scripts/map_builder/road_module_rules.gd` is deliberately being migrated. Keep the same filename on both machines because `GameState.builder_map_name` selects it by name.
