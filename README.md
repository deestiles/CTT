# Catch the Thief — Godot Production Project

This is the production Godot project. The browser prototype in the parent folder remains a mechanics reference.

## First playable scene

Open `project.godot` in Godot and press **F5** to run the complete game loop. Use **F6** only when intentionally testing the open chase scene by itself.

The current game loop includes:

- Station menu with police role selection and thief-mode placeholder
- Persistent rank XP, credits, completed cases, and three-life save data
- One-life-per-30-minute recovery with a visible countdown
- Case briefing and loadout summary
- Success rewards and rank progression
- Failure reasons, simulated rewarded-ad life protection, life loss, retry, and station return
- Ad-Free ownership state placeholder for future store integration

The chase scene includes:

- Portrait mobile viewport
- Procedural stylized road and city blocks
- Police and suspect vehicles built from temporary primitives
- Three-lane movement using A/D or arrow keys
- Touch swipe lane changes
- Hold Space or the Boost button for NoS
- Civilian traffic and collision damage
- 60-second escape timer
- Distance-based safe capture
- Apprehend gauge and Skilled Driving multiplier
- Manual safe-capture timing sequence
- Visible safe-capture target bracket with randomized position and difficulty-scaled window size
- Difficulty-scaled capture-marker speed with fair pass-to-pass pace variation
- Suspect traffic-scanning AI with desperation behavior
- Suspect collisions that damage the getaway car and push civilian traffic into another lane
- One short-lived backup intervention lasting seven to ten seconds before the unit is forced off screen
- Two player-aimed spike strips that slow either the thief or police car without stopping them
- Civilian traffic pulls onto the shoulder for approaching backup but not when already ahead of the thief
- Civilian and backup vehicles react to spike strips; unsafe deployment reduces Skilled Driving progress
- Win, escape, damage, and retry flow
- Dynamic follow camera with boost FOV, corner lean, and collision shake
- Switchable chase and hood/POV cameras for visibility testing
- Paused orthographic 3D tactical-map camera showing live vehicle positions
- Physical intersection sequence: suspect turns visibly offscreen, player chooses Follow Turn or Go Straight, and the chase reorients onto the selected street
- Experimental intersections are retained behind `ENABLE_JUNCTIONS` but disabled until proper curved-road meshes and path-following vehicles are available.

These are foundation visuals and mechanics, not final art.
