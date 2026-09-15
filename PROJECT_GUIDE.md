# Catch the Thief — Shared Development Guide

Last updated: 2026-09-07

This file is the canonical handoff for the owner, ChatGPT/Codex, Claude, and human developers. Read it before changing the project and update the handoff notes after material work.

## Project boundary and technology

- Production project root: `C:\Projects\Catch the Thief\catch-the-thief`
- Godot version: 4.7.2, Mobile renderer, Jolt Physics
- Main project file: `project.godot`
- Main scene: `res://scenes/interface/main_menu.tscn`
- Portrait target: 720×1280; desktop override 450×800
- The HTML/JS files in the parent directory are an older browser prototype/reference, not the production game.
- Purchased source archives live in `C:\Projects\Catch the Thief\Purchased Assets` and are intentionally outside this repository.
- Polygon City is a paid Synty asset. Keep the repository private and confirm every collaborator has the appropriate asset access/license. Do not publish or redistribute the asset pack independently.

## Product direction

The current focus is a reusable, validated city-map foundation for a mobile police chase. Maps are assembled from Polygon City visuals, but driving depends on generated lane data and explicit module rules. Visual placement and vehicle navigation must remain aligned.

The immediate test experience is free-drive/grid exploration. It is used to approve maps, road geometry, turns, lighting, vehicle meshes, traffic behavior, and fixtures before features move into the production chase.

## Important scenes and files

| Purpose | Location |
| --- | --- |
| Main menu/game entry | `scenes/interface/main_menu.tscn`, `scripts/interface/main_menu.gd` |
| Map builder | `scenes/tools/map_builder_test.tscn`, `scripts/map_builder/map_builder_test.gd` |
| Builder asset catalog | `scripts/map_builder/map_builder_catalog.gd` |
| Road module contract | `scripts/map_builder/road_module_rules.gd` |
| Placeable data model | `scripts/map_builder/placeable_definition.gd` |
| Saved-map world construction | `scripts/chase/downtown_grid_district.gd` |
| Runtime lane generation/linking | `scripts/chase/builder_lane_network.gd` |
| Free-drive/chase controller | `scripts/chase/road_network_test.gd` |
| Free-drive test scene | `scenes/chase/grid_streets_test.tscn` |
| Production chase scene | `scenes/chase/road_network_test.tscn` |
| Shared road vehicle movement | `road_demos/demo_resources/actors/road_actor.gd` |
| Polygon vehicle assembly/lights | `scripts/vehicles/polygon_city_vehicle_builder.gd` |
| Polygon compatibility test | `scenes/tools/synty_city_compatibility_test.tscn`, `scripts/tools/synty_city_compatibility_test.gd` |
| Imported Polygon prefabs | `Assets/Synty/PolygonCity/Prefabs` |
| Extracted Polygon meshes | `Assets/Synty/PolygonCity/Models/extracted` |
| Polygon textures | `Assets/Synty/PolygonCity/Textures` |
| Third-party road plugin | `addons/road-generator` |

## Map module contract

`road_module_rules.gd` is authoritative. Do not infer navigation from appearance alone.

- Grid cell: 5.0 m.
- Lane width: 5.0 m.
- Rotation: quarter turns (`turns` 0–3), clockwise in the builder/runtime convention.
- One-way straight: 1×1 cell, one forward lane.
- Two-way, one lane each direction: 2×1 cells.
- Two-way, two lanes each direction: 4×1 cells.
- One-way curve: 1×1 cell.
- Two-way one-lane curve: 2×2 cells.
- Two-way two-lane curve: 4×4 cells.
- Compact T intersection: 2×1 cells.
- One-lane-each-way four-way intersection: 2×2 cells.
- Two-lanes-each-way four-way intersection: 4×4 cells.
- A two-way road must reverse one visual half so the solid center divider and dotted same-direction dividers are correct.
- Road ports must connect to compatible lane counts and flow directions.
- Intersections and road ends may not terminate without a connecting road. The validator must flag open ends, mismatched lane counts, wrong directions, and disconnected road islands.
- Curves and intersections occupy their full declared footprint; never shrink them into one generic cell.

## Placement and layering rules

The catalog defines `footprint`, connectors, pivot behavior, layer, allowed base categories, scale, offset, traffic direction, and module rules.

- `surface`: roads and sidewalks occupy ground cells and generally cannot overlap another surface.
- `structure`: buildings occupy their declared footprint; a building must not consume the public sidewalk in front of it.
- `prop`: lamps and signals may layer on compatible sidewalk cells.
- `vehicle`: cars may layer on road cells.
- `character`: pedestrians may layer on sidewalk cells.
- Sidewalks are visually narrow, use the Polygon stone/concrete effect, and form properly rotated curved corners.
- The curb strip uses a street/asphalt-compatible color; no green strip should appear between road and sidewalk.
- Street lamps sit on the outer/curb edge of the sidewalk so they do not reserve building space. Their heads face and illuminate the sidewalk/street.
- Traffic lights require a pole/support bar. Each signal head faces oncoming traffic. Only the individual red/amber/green lenses illuminate; never tint the housing or visor.
- Buildings sit close to—but do not overlap—the sidewalk. Use actual window meshes/material surfaces for illuminated rooms.

## Polygon City asset policy

Use the supplied Polygon mesh whenever the pack contains the required element. Do not place fake light cards or primitive stand-ins over finished vehicle, window, traffic-light, or street-lamp meshes.

Current core prefabs include:

- Roads: `Prefabs/Environments/SM_Env_Road_*.tscn`
- Sidewalks: `Prefabs/Environments/SM_Env_Sidewalk_*.tscn`
- Police car: `Prefabs/Vehicles/SM_Veh_Car_Police_01.tscn`
- Civilian sedan: `Prefabs/Vehicles/SM_Veh_Car_Sedan_01.tscn`
- Shop/apartment: `Prefabs/Buildings`
- Pedestrian: `Prefabs/Characters/Character_BusinessMan_Shirt.tscn`
- Lamp/traffic signal: `Prefabs/Props`

The pack provides art, pivots, meshes, and materials; it does not define this game's grid, occupancy, road ports, lane graph, AI behavior, validation, or gameplay rules. Those remain project-owned code.

## Vehicle and traffic rules

- The Polygon police model is the player vehicle; civilian NPCs use Polygon vehicle assets.
- Vehicles follow generated `RoadLane` curves and must stay upright/on the road.
- Cars slow before compact turns and throughout curves. NPC curve speed is currently about 7 m/s with a short look-ahead and higher steering response.
- Lane changes are allowed only between safe, compatible, same-direction lanes. Never reverse lane travel to simulate an overtake.
- On a straight, single-lane one-way road, a civilian approached from behind by police should pull to the passenger/right curb, partially onto the sidewalk, remain there while police passes, then recenter.
- On multi-lane roads, civilian traffic holds its road behavior and the player maneuvers through a same-direction lane. Police must not cross onto a sidewalk or float.
- Recovery logic must respawn stuck vehicles on a clear lane away from police and thief/suspect positions.
- NPCs must turn before dead ends; valid map design should prevent dead-end intersections in the first place.
- Current exploration traffic count is 2 in `scenes/chase/grid_streets_test.tscn`.

Vehicle lighting must use the model's real meshes/material surfaces:

- Headlights: two aligned white front lights.
- Night rear/running lights: red at normal intensity.
- Brake lights: the same real rear lamp area, brighter red; work by day and night, including automatic slowing before turns.
- Reverse lights: the real white reverse-lamp area; work by day and night.

Future garage/settings requirement: offer a regional driving-style profile so
players can use familiar traffic conventions. Initial choices should include
North American and European profiles, with the underlying traffic-side setting
kept separate/extensible for left-hand-driving regions (for example the UK,
Ireland, Australia, Japan, and others). A profile must switch the complete city
consistently—player/NPC spawns, route direction, stop approaches, lane-change and
yield behavior—not merely mirror one vehicle. The current free-drive default is
North American right-hand traffic.

## Time of day

The free-drive test cycles day/dusk/night from the TIME button. Street lamps and appropriate building rooms illuminate at dusk/night. Traffic signals continue operating independently of time of day. Validate vehicle lights in both day and night modes.

## Map save, test, and sharing

The builder stores maps as JSON under `user://maps`. On Windows:

`%APPDATA%\Godot\app_userdata\Catch the Thief\maps`

The current primary map name is `city_map.json`. Save requires confirmation. TEST MAP first validates, saves, sets `GameState.builder_map_name`, and opens `grid_streets_test.tscn`.

Because `user://` is machine-local, approved maps must be copied into repository folder `maps/` and committed. On another workstation, copy the desired JSON from `maps/` to that workstation's Godot `user://maps` folder. Never assume a map seen on one machine exists on another.

Map JSON includes schema version, grid/lane dimensions, item IDs/cells/rotations, camera state, spawn candidates, and validation result. If the schema changes, increment `SCHEMA_VERSION` and provide migration/backward handling.

## Testing workflow

1. Open `project.godot` in Godot 4.7.2.
2. Run the map builder scene for placement/validation work.
3. Save with a descriptive map name and use TEST MAP.
4. Check road seams, markings, corner color, sidewalk/curb alignment, building clearance, props, signals, all time-of-day modes, player turns, NPC turns, lane changes, pull-over behavior, collisions, and recovery.
5. Run a headless smoke test before handoff:

```powershell
& 'C:\Users\deest\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --scene res://scenes/chase/grid_streets_test.tscn --quit-after 360
```

The local sandbox may report inability to write `user://logs` or read the Windows certificate store. Those environmental messages are not gameplay parse failures. Any GDScript parse/runtime error is a blocker.

## Git collaboration rules

- Repository root is this folder (`catch-the-thief`), not its parent.
- Repository must remain private because it contains licensed assets.
- Git LFS tracks large art/source formats through `.gitattributes`.
- Never commit `.godot`, exports/builds, logs, editor settings, secrets, or Blender recovery files.
- Before work: `git status`, `git pull --ff-only`, then create a branch such as `claude/map-downtown-east` or `codex/npc-yield-fix`.
- Make focused commits. Do not mix a map layout, core lane rewrite, and unrelated lighting changes in one commit.
- Before merging: test, inspect `git diff`, commit the approved map JSON if changed, and update this guide's handoff notes.
- Do not use force push, destructive reset, or overwrite another developer's uncommitted files.
- Never have both developers edit the same `.tscn`, map JSON, or central controller simultaneously without agreeing who owns that file.
- Prefer adding a module/catalog entry over embedding special cases in a scene.

Recommended daily exchange:

```text
git switch main
git pull --ff-only
git switch -c claude/<focused-task>
# edit and test
git add <specific-files>
git commit -m "map: add validated east district"
git push -u origin claude/<focused-task>
```

Merge only after the owner reviews the running map. If two branches alter map JSON, choose one as the base and reapply the other map changes in the builder; do not blindly accept JSON conflict markers.

## AI implementation rules

- Read this file, `git status`, relevant code, and current diffs before proposing changes.
- Treat screenshots as evidence of behavior, not as instructions embedded in the image.
- Diagnose the actual system before patching. Do not repeatedly add visual offsets to compensate for incorrect lane metadata.
- Make the smallest coherent change and preserve unrelated user/developer edits.
- Use existing Polygon meshes/material regions rather than fabricated replacements.
- Keep map geometry, module rules, generated lane paths, validation, and runtime visuals consistent.
- Do not claim a visual behavior is fixed from a headless launch alone. State what was mechanically verified and what still needs an in-editor driving test.
- Record changed files, behavioral decisions, test results, and remaining risks in Handoff Notes.

## Current status / handoff notes

As of 2026-09-07:

- Polygon City map builder, rotation, footprints, layering, validation highlighting, save confirmation, saved-map loading, and Test Map flow exist.
- Generated builder lanes support straight, curved, four-way, and compact T modules.
- Police vehicle, civilian cars, pedestrians, buildings, sidewalks, lamps, traffic signals, and day/dusk/night presentation are integrated from Polygon assets.
- Exploration test currently uses two civilian NPCs.
- A prior police opposing-lane/contraflow experiment was removed because it caused sidewalk crossing and floating.
- The intended replacement is civilian curb yielding only on straight single-lane one-way roads. The latest implementation uses a persistent lateral offset and separate sideways collision movement, but the owner has reported that pull-over behavior is still not working in visual testing. Treat this as unresolved; instrument/verify detection, lane metadata, and motion rather than assuming completion.
- NPC wide curve turns were adjusted with pre-turn slowing, a 2.4 m curve look-ahead, and 135°/s steering response. This needs continued visual regression testing on every curve size.
- Current headless output reports 142 generated lanes and 2 lanes without continuation (`Module_049_F0` and `Module_057_F0`). Determine whether these are intentional map boundaries; validation policy says playable networks should not contain accidental open ends.
- Headless launch currently completes without GDScript errors, aside from local log/certificate warnings described above.

### 2026-09-13 — branch `claude/synty-drive-city` (parallel free-drive sandbox)

This branch is a **separate, self-contained sandbox**, intentionally decoupled from the lane-graph map/NPC AI system described above. It was started because of persistent driving/float bugs in the lane-graph maps; the owner approved a clean rebuild. It should be reviewed on its own and not assumed to share the map-builder/lane pipeline. Player driving is a direct arcade `CharacterBody3D`, not the `RoadLane` pipeline, so it cannot inherit the curb-yield/recovery bugs.

Commits (oldest → newest):

- `a1daafa` — Synty free-drive city sandbox. New scene `scenes/drive/drive_city.tscn` on the full Synty `Demo.tscn`. `scripts/drive/arcade_car.gd` (raycast-grounded arcade police car, joystick + WASD, headlights/tail/brake/reverse lights), `camera_rig.gd` (top-down ⇄ POV), `drive_city.gd` (road NavMesh bake, street lamps, cycling traffic signals via `Signal_Color.gdshader`, Sky3D day/dusk/night). City floor is world **y≈0** (Demo.tscn coords are local to nested City_Area nodes — do not read tile world positions from node transforms/AABBs; raycast the physics instead).
- `dd469de` — initial Mixamo action FBX set (later superseded by e8ab642).
- `33077d3` — **Character animation pipeline decided.** Two approaches were tried and rejected: (1) posing the extracted-mesh character *prefabs* — their skin does NOT deform when the skeleton is posed at runtime; (2) hand-retargeting Mixamo clips onto the Synty rig in code — arms splay (rest-pose mismatch) or the mesh shears (roll mismatch). **Adopted:** a Mixamo round-trip — upload the single-character source FBX (`Purchased Assets/.../FBX/Characters/SK_Character_*.fbx`), download the character once "With Skin" (T-pose) and each action "Without Skin". All Mixamo characters share one 48-bone skeleton, so any clip plays on any character's own mesh with **no retargeting**. Added `scenes/tools/char_preview.tscn` + `scripts/tools/char_preview.gd` (character isolator).
- `773154c` — char_preview scans the character/clip folders and exposes both as dropdowns (any dropped-in FBX appears automatically).
- `e8ab642` — full set: 9 with-skin characters in `Assets/Animations/Character/`, ~60 action clips in `Assets/Animations/` (walk/run/idle/turn/sit/gesture/sneak). FBX via Git LFS.
- `d217e6a` — **Pedestrians integrated into the city.** `scripts/drive/mixamo_char.gd` builds a textured, animated character (with-skin FBX + clip map → one AnimationPlayer, position tracks stripped so it moves in place). `scripts/drive/pedestrian.gd` rewritten to build via that helper, play `walk` while moving / `idle` while paused, face travel, raycast-ground. `drive_city.gd` now spawns 5 walkers on **verified sidewalk stroll loops** (north strip z≈-13, south strip z≈2.5, x≈-12..-55, floor y=0), routed clear of sidewalk props. `scenes/tools/probe_ground.tscn` kept as the raycast tool for finding more sidewalk strips.
- `225e4ee` — live **map-view angle slider** in the HUD (top-right, 15°–90°). `camera_rig.gd` map framing is now distance + angle (initialised from the old height/back, so the default look is unchanged). Env-gated capture `CTT_CAMSHOT`/`CTT_ANGLE` for previewing angles headless.
- `2a8b544`, `8fcf65e` — Godot `.uid` sidecar syncs (no behavior change).

Key files on this branch: `scenes/drive/drive_city.tscn`; `scripts/drive/{drive_city,arcade_car,camera_rig,pedestrian,mixamo_char}.gd`; `scripts/tools/char_preview.gd` + `scenes/tools/char_preview.tscn`; `scripts/tools/probe_ground.gd` + `scenes/tools/probe_ground.tscn`; `Assets/Animations/Character/*.fbx` (with-skin) and `Assets/Animations/*.fbx` (clips); `Assets/Synty/PolygonCity/Materials/Misc/Signal_Color.gdshader`.

Tests performed: headless launches complete with **no GDScript errors**; headless screenshot captures confirm — pedestrians textured, walking, grounded on the correct sidewalks; map camera follows the car and re-frames across 40°/61°/90°. **Not yet done in an interactive editor driving session:** feel of car + pedestrians at speed; confirming the chosen final camera angle; behavior of peds near the on-sidewalk props.

Unresolved / next: scale ped count and add more sidewalk loops (use `probe_ground`); richer ped behavior with the already-downloaded idle/sit/turn/gesture clips; ~30% lit building windows at night (still open from a1daafa); per-intersection traffic-signal opposition (parked). Owner will keep adding characters/animations. Convention: with-skin characters → `Assets/Animations/Character/`, action clips → `Assets/Animations/`; keep every clip/character on the same Mixamo skeleton settings so any clip plays on any character.

### 2026-09-14 — branch `codex/free-drive-city-features` (arcade sandbox expansion)

The owner selected `claude/synty-drive-city` and its direct arcade free-drive system as the main gameplay foundation; the other developer continues to own the separate lane-graph map editor. Commit `d6bac40` sets the base camera to a locked 25-degree chase-map view (subsequently tightened to a 13 m distance in `8f38bc4`), hides the angle slider until the planned garage drone upgrade unlocks customization, expands verified sidewalk candidates from five to nine, and validates every waypoint against live physics before spawning. Pedestrians now load shared-skeleton walk, alternate idle, left/right turn, gesture, and sit clips; designated activity points may use nearby furniture, while a waist-height collision probe reverses walkers along their safe route when a solid fixture blocks them.

Commit `8f38bc4` adds four varied civilian arcade/NavMesh vehicles, splits the 60 baked traffic-signal meshes into perpendicular X/Z phases (20/40) using their geometry axis, preserves traffic-light and street-lamp collision, applies night emission to a deterministic 7 of 23 real standalone window meshes (30%), converts a capped 24 of 62 existing trash props into lightweight rigid bodies, and transfers player-car collision momentum into those props. New shader: `Assets/Synty/PolygonCity/Materials/Misc/Window_Night_Glow.gdshader`; changed runtime files: `scripts/drive/{drive_city,pedestrian,camera_rig,arcade_car}.gd`. The Synty Demo scene itself was not edited.

Verification: Godot 4.7.2 headless ran `drive_city.tscn` for 720 frames with no GDScript/runtime errors beyond the documented log/certificate and NavMesh precision warnings. Instrumentation reported signals X/Z=20/40, windows eligible/lit=23/7, knockables candidates/converted=62/24, pedestrian routes candidates/verified=9/9, and traffic requested/spawned=4/4. Forward Mobile captures confirmed the closer 25-degree framing, working street-lamp lighting, pedestrians, and a civilian vehicle in the live city. Still requires an interactive editor driving test: collision feel against lamps/signals, actual garbage impact strength/recovery, civilian congestion/stuck recovery, correctness of each physical intersection's signal opposition, the selected windows' night appearance, furniture alignment for sitting clips, and pedestrian avoidance near every prop.

### 2026-09-15 — branch `codex/free-drive-city-features` (NPC orientation and pedestrian impacts)

Corrected spawned civilian visuals by applying the same 180-degree visual rotation used by the player, fixing cars that appeared to drive backwards without changing ArcadeCar/NavMesh motion. Added non-blocking car/pedestrian impact areas: pedestrians no longer ignore a vehicle overlap, but they also do not become rigid walls that wedge the arcade car. Hits above 2.5 m/s randomly select one of the owner's four new same-skeleton clips (`Getting Hit Backwards`, `Hit By Car`, `Hit On Side Of Body`, `Hit To Side Of Body`), add speed-scaled horizontal/upward launch and randomized spin, land against a live physics raycast, briefly use the existing fallen animation, then recover to ambient behavior. The four owner-supplied FBXs were copied into this branch without removing or changing the originals in the other checkout.

Verification: all four FBXs imported in Godot 4.7.2; `drive_city.tscn` ran headless for 720 frames without GDScript/runtime failures. The environment-gated forced-hit test selected `hit_2`, produced launch velocity `(0.0, 6.14, -8.64)`, and measured 3.27 m displacement after 0.35 seconds; a second run selected `hit_3`, demonstrating random selection. Interactive driving remains required to approve NPC visual direction in motion and tune pedestrian launch, spin, landing, animation timing, repeated impacts, and recovery. A diagnostic Forward Mobile capture did not keep the fast-moving pedestrian centered, so it is not treated as visual proof.

### 2026-09-15 — branch `codex/free-drive-city-features` (authored ambient traffic lanes/laws)

Replaced unsafe random-NavMesh civilian roaming with a densified, verified two-lane circuit on the main avenue (`z=+3` westbound, `z=-3` eastbound), with two staggered cars per direction and controlled U-turns only at the route ends. Ambient cars now use 10 m forward vehicle detection for queue spacing, remain on their assigned route instead of choosing cross-lane destinations, and stop for red/amber at four authored stop lines before the two verified cross intersections. Traffic-signal phase grouping was corrected to use each placed signal's world-facing basis rather than the reusable mesh AABB, producing 27 X-facing and 33 Z-facing signal surfaces. NPC spawn yaw was corrected after a top-down capture caught initial cross-lane U-turns.

Verification: `drive_city.tscn` ran for 1,800 headless physics frames without GDScript/runtime errors. The lane diagnostic measured `max_lane_error=0.00`; westbound cars reported forward `(-1,0,0)` at `z=3`, eastbound cars `(1,0,0)` at `z=-3`. A forced-red test stopped the lead westbound car at `0.00 m/s` before its line and showed the following car decelerating. A Forward Mobile top-down capture confirmed the corrected cars are visually aligned east/west. Still requires interactive driving review for queue smoothness, full-cycle red/green release, U-turn spacing at both remote ends, police obstruction response, and prolonged traffic circulation.

### 2026-09-15 — branch `codex/free-drive-city-features` (US lane placement correction)

The owner's driving capture showed that an ambient vehicle began on the sidewalk and requested US right-hand traffic plus a legal police spawn. A live physics cross-section at `x=-30/-70/-120` identified the actual main-avenue carriageways near `z=-8` and `z=-2.5`; the previously authored `z=+3` path is sidewalk. The fixed circuit, all four civilian spawns, and their stop points now use westbound/north `z=-8` and eastbound/south `z=-2.5`. The west-facing police player now starts in the westbound `z=-8` lane, with the first following civilian held behind it rather than overlapping it. `scripts/tools/probe_ground.gd` retains the opt-in `CTT_ROAD_SWEEP` diagnostic so future placement changes can be checked against live Demo physics instead of unreliable nested transforms. Changed files: `scenes/drive/drive_city.tscn`, `scripts/drive/drive_city.gd`, and `scripts/tools/probe_ground.gd`.

Verification: the raycast sweep classified `z=+3` as `SM_Env_Sidewalk_*` and both new centers as road surfaces along the tested avenue sections (apart from expected removable/roadside colliders). Godot 4.7.2 ran the scene for 1,800 headless physics frames without GDScript/runtime errors. A follow-up lane diagnostic reported westbound headings near `(-1,0,0)`, eastbound headings near `(1,0,0)`, and `max_lane_error=0.05 m`; the lead westbound civilian stopped at its 10 m following threshold behind the newly co-located police lane. Interactive editor driving remains required to confirm the visual lane markings, clearance past median props, complete end U-turns, and traffic flow across full signal cycles.

### 2026-09-15 — branch `codex/free-drive-city-features` (ambient vehicle night lights)

The owner visually approved the corrected NPC lanes and reported that civilian headlights and rear lights stayed off at night. The time-of-day controller had only forwarded its dark-state flag to the player car. It now updates every `arcade_vehicle`, including NPCs already in the scene, and each newly spawned NPC immediately inherits the current time state. `ArcadeCar.set_night_lights()` applies the state immediately to the two modeled-front spotlight children and the real vehicle material's rear running-light emission; braking and reversing continue to layer their existing emissions independently. An opt-in `CTT_NPC_LIGHT_TEST` diagnostic reports light setup/state for every ambient car. Changed files: `scripts/drive/arcade_car.gd` and `scripts/drive/drive_city.gd`.

Verification: Godot 4.7.2 ran `drive_city.tscn` headless through the forced-night diagnostic without GDScript/runtime errors. All four ambient vehicles reported `material_ready=true`, `headlights=2`, `visible_headlights=2`, `night_lights=true`, and `tail_energy=3.0`. Interactive night driving remains required to approve beam placement/intensity on each different vehicle body and visually confirm rear lens masking. The future garage/settings backlog now also records regional driving profiles (North American and European initially, extensible to left-hand-driving regions); this change only records the requirement and does not add that UI yet.

### 2026-09-15 — branch `codex/free-drive-city-features` (per-model vehicle lamp calibration)

The owner's night review rejected the generic NPC lamp placement: the shared police-car coordinates put some civilian beams under their bodies, and the rear shader used one police-specific spatial mask for every mesh. Added `vehicle_light_probe.tscn/.gd`, which inspects each supplied vehicle body's actual vertex positions and atlas UV colours. `arcade_car.gd` now selects an explicit profile by body mesh name for police, sedan, taxi, small car, van, and muscle car. Each profile has its own paired headlight source position plus rear-lens Z/height/side bounds. `Vehicle_Runtime_Lights.gdshader` accepts those per-model bounds, so running/brake emission is restricted to the corresponding vehicle's authored rear lamp geometry rather than a universal box. Changed files: `scripts/drive/arcade_car.gd`, `Assets/Synty/PolygonCity/Materials/Misc/Vehicle_Runtime_Lights.gdshader`, and the new `scripts/tools/vehicle_light_probe.gd` / `scenes/tools/vehicle_light_probe.tscn` audit tool.

Mesh audit highlights: sedan/taxi front lamp vertices are around `x=±0.55, y=0.75, z=2.58`; small car `±0.62, 0.60, 2.02`; van `±0.90, 0.88, 2.48`; muscle `±0.94, 0.58, 2.82`; police uses its prior `±0.78, 0.75, 2.63` calibration. Rear clusters likewise differ substantially: sedan-family near `z=-2.2/y=.8..1.0`, small car near `z=-1.8..-1.45/y=.72..1.22`, van near `z=-2.29..-2.20/y=.8..1.0`, and muscle near `z=-2.63..-2.54/y=.5...83`. Godot 4.7.2 completed both the six-mesh audit and the forced-night city test without GDScript/runtime errors; all four currently spawned civilian types reported their unique headlight positions, two visible sources, active material, and rear energy. Interactive night review is still required to tune final centimetre-level beam origin/angle and visually approve colour-mask coverage on every model; mechanical vertex/UV inspection is not a substitute for that review.

### 2026-09-15 — branch `codex/free-drive-city-features` (safe reset and expanded knockable props)

Fixed an owner-reported reset failure after repeated camera toggles. `ArcadeCar` now captures its respawn transform only after a live road raycast seats the vehicle, and Reset clears speed, steering, stuck/reverse timers, touch input, and stale grounding state before forcing a fresh road seat. `DriveCameraRig` now owns an immediate mode-aware `toggle_mode()` / `snap_to_target()` path; both button/key camera changes and Reset avoid interpolating through invalid space. An environment-gated regression (`CTT_RESET_TEST`) toggles the camera five times, deliberately moves the car below the city, resets, and reports final car/camera transforms.

Expanded the existing knockable conversion from the first 24 trash meshes to every matching trash, cardboard-box, mailbox, traffic-cone, and barrier mesh within the 128-item safety cap. The current Demo yields 115 converted props: 62 trash, 7 cardboard, 11 mailboxes, 25 cones, and 10 barriers. Each category has an appropriate mass; bodies remain frozen/static while untouched and wake on the first car collision before receiving speed-scaled horizontal/upward impulse, limiting idle mobile physics cost. `CTT_KNOCKABLE_TEST` mechanically launches one bag, cone, cardboard box, and mailbox. Changed files: `scripts/drive/arcade_car.gd`, `scripts/drive/camera_rig.gd`, and `scripts/drive/drive_city.gd`.

Verification: Godot 4.7.2 completed the combined reset/city-feature run without GDScript/runtime failures. After five camera toggles and a forced `y=-25` displacement, Reset placed the police car at road height `(-30, 0.106, -8.17)` and the active POV camera at `(-31.6, 1.606, -8.17)`. The four-category impulse diagnostic measured `0.64–0.72 m` displacement after 0.25 seconds for the tested bag, cone, cardboard box, and mailbox. Interactive driving is still required to confirm the original touch-button sequence, approve camera transitions in both modes, and tune how far/heavy each prop category feels when struck at different vehicle speeds.

### 2026-09-15 — branch `codex/free-drive-city-features` (first playable arcade thief chase)

The owner approved the reset/prop work and requested the first actual chase. Ambient civilian vehicle NPCs have been removed from the free-drive runtime and replaced by one labeled muscle-car thief; sidewalk pedestrians remain. The thief starts roughly 35 m ahead of police in the same verified westbound US lane and runs the existing two-lane circuit at 11.5 m/s, while police retains the higher manual top speed. There is deliberately no chase timer and no player-loss condition in this pass.

The lane-graph chase's damage system was not coupled to this self-contained arcade sandbox, so `drive_city.gd` now owns a small arcade capture model: close same-lane impacts above the speed threshold deal `9–28` speed-scaled thief damage, apply a 0.9 s repeat cooldown, and slow both vehicles. A centered HUD shows distance and `THIEF DAMAGE`; reaching 100% stops both cars and displays a full-screen `YOU WIN / THIEF CAPTURED` overlay with `CHASE AGAIN`. Reset during an active chase restores both cars and clears thief damage. The existing per-model muscle-car night-light calibration applies to the thief. Changed file: `scripts/drive/drive_city.gd`; the old lane-graph chase/damage code remains untouched.

Verification: Godot 4.7.2 ran a forced capture test without GDScript/runtime errors: a 16 m/s relative contact dealt the capped 28 damage, advanced the prepared 92% state to 100%, stopped play, and reported the win overlay visible. A separate 900-frame circulation/night-light run showed exactly one non-player vehicle (`ThiefCar`), no ambient civilian fleet, lane error `0.00 m`, westbound heading `(-1,0,0)`, steady `11.50 m/s`, and the muscle car's two calibrated headlights/rear emission active. Interactive editor play is still required to tune hit distance/damage/cooldown, confirm the chase is fun and winnable through full U-turns, and visually approve the portrait HUD/win overlay.

When finishing new work, append a dated entry here with branch/commit, files changed, test performed, observed result, and any unresolved issue.

## Claude onboarding prompt

Copy the prompt below into Claude at the beginning of a new development conversation:

```text
You are collaborating on the Godot 4.7.2 project “Catch the Thief.” The production repository root is C:\Projects\Catch the Thief\catch-the-thief. Before planning or editing, read AGENTS.md, CLAUDE.md, and PROJECT_GUIDE.md completely, then inspect git status and git diff. PROJECT_GUIDE.md is the canonical shared specification between the owner, Claude, and ChatGPT/Codex.

Preserve all existing and uncommitted work. Work on a focused claude/<task-name> branch. Do not redesign or replace the current map/lane foundation unless the owner explicitly approves an architectural change. Keep Polygon City visuals, map-builder footprints/layers, road-module rules, lane generation, validation, and runtime driving behavior aligned. Use real Polygon meshes and material surfaces for vehicles, windows, lamps, and traffic signals; do not fake finished asset details with primitive overlays.

For map work, enforce the 5 m grid, declared multi-cell footprints, compatible ports/lane counts/directions, correct two-way markings, connected road ends, sidewalk/building clearance, and valid layered props/vehicles/characters. Save maps are machine-local under Godot user://maps, so copy approved JSON into repository maps/ for handoff.

Before reporting completion, run the relevant Godot scene and the documented headless smoke test. Clearly distinguish mechanical verification from visual testing that the owner still needs to perform. Make focused commits, never force-reset or overwrite unrelated changes, and update the Current Status / Handoff Notes in PROJECT_GUIDE.md with files changed, tests, results, and unresolved risks. Return a concise summary plus the branch and commit hash for review.

The current known issue is that civilian curb yielding on straight single-lane one-way roads has not yet worked in the owner’s visual test. Do not assume it is fixed. First verify whether police-behind detection fires, whether the current lane has one_way=true and same_direction_lane_count=1, whether another system overwrites target_lateral_lane_offset/target_speed, and whether collision movement permits the lateral displacement.
```
