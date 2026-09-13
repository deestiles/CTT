extends RefCounted
## Helper for building a runtime-animated Synty pedestrian from the Mixamo pipeline
## (see the character-animation-pipeline note). Given a with-skin character FBX and a
## set of action clips (all on the shared Mixamo skeleton), it instances the character,
## textures it with the city atlas, and installs the clips in ONE AnimationPlayer under
## library "act" — no retargeting, because character and clips share the skeleton.
##
## Used via preload().new()-free static calls: MixamoChar.build(...).

const ATLAS_MAT := "res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_01_A_mat.tres"

## Instance `char_path`, texture it, and add each clip in `clips` ({name: fbx_path})
## to its AnimationPlayer as "act/<name>" (looped, position tracks stripped so it moves
## in place). Returns the instanced character root (with an AnimationPlayer child), or
## null on failure.
static func build(char_path: String, clips: Dictionary) -> Node3D:
	var packed := load(char_path) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate() as Node3D
	var mat := load(ATLAS_MAT) as Material
	if mat:
		for n in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh:
				for s in mi.mesh.get_surface_count():
					mi.set_surface_override_material(s, mat)
	var player := _find_player(root)
	if player == null:
		player = AnimationPlayer.new()
		root.add_child(player)
	var lib := AnimationLibrary.new()
	for name in clips:
		var clip := extract_clip(String(clips[name]))
		if clip:
			lib.add_animation(String(name), clip)
	if player.has_animation_library("act"):
		player.remove_animation_library("act")
	player.add_animation_library("act", lib)
	return root

## Load an action FBX, take its first non-trivial clip, drop POSITION tracks (so the
## character animates in place, driven by code), and return a looped copy.
static func extract_clip(anim_path: String) -> Animation:
	var packed := load(anim_path) as PackedScene
	if packed == null:
		return null
	var scene := packed.instantiate()
	var src: Animation = null
	for ap in scene.find_children("*", "AnimationPlayer", true, false):
		for n in (ap as AnimationPlayer).get_animation_list():
			var a := (ap as AnimationPlayer).get_animation(n)
			if a and a.length > 0.1:
				src = a
				break
		if src:
			break
	if src == null:
		scene.free()
		return null
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = Animation.LOOP_LINEAR
	for ti in src.get_track_count():
		if src.track_get_type(ti) == Animation.TYPE_POSITION_3D:
			continue
		var nt := out.add_track(src.track_get_type(ti))
		out.track_set_path(nt, src.track_get_path(ti))
		out.track_set_interpolation_type(nt, src.track_get_interpolation_type(ti))
		for ki in src.track_get_key_count(ti):
			out.track_insert_key(nt, src.track_get_key_time(ti, ki), src.track_get_key_value(ti, ki))
	scene.free()
	return out

static func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var f := _find_player(c)
		if f:
			return f
	return null
