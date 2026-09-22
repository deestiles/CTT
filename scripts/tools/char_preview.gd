extends Node3D
## Character animation preview — the "character isolator". Pick a with-skin Mixamo
## character and an action clip from the dropdowns; the clip plays on the character's
## own mesh DIRECTLY (both share the same 48-bone skeleton, so no retargeting). Mesh is
## textured with the city atlas. Sky3D day/night (T) + drag-orbit / wheel-zoom.
##
## Sequence builder: pick a clip and press "Add ▸" to queue it, repeat to build a chain
## of movements, then "Play ▶" to watch them play back to back (the whole list loops) so
## you can see how the character transitions between actions. "Clear" empties the queue
## and returns to single-clip preview.
##
## Drop new characters in Assets/Animations/Character and clips in Assets/Animations —
## they appear in the dropdowns automatically on next launch.
##
## Env (headless): CTT_CHAR / CTT_ANIM (name substring to preselect), CTT_SHOT=1 saves
## user://char_preview.png and quits, SHOT_TIME 0/1/2, SHOT_YAW/PITCH/ZOOM.

const ATLAS_MAT := "res://Assets/Synty/PolygonCity/Materials/Alts/PolygonCity_01_A_mat.tres"
const TOD := [["DAY", 12.0, 1.0], ["DUSK", 18.6, 0.7], ["NIGHT", 22.5, 0.4]]
# Drop new with-skin characters in CHAR_DIR and action clips in ANIM_DIR; both are
# scanned at launch and appear in the dropdowns automatically — no code changes.
const CHAR_DIR := "res://Assets/Animations/Character"
const ANIM_DIR := "res://Assets/Animations"

var _sky: Sky3D
var _cam: Camera3D
var _char: Node3D
var _label: Label
var _char_picker: OptionButton
var _anim_picker: OptionButton
var _chars: Array[String] = []
var _anims: Array[String] = []
var _char_idx: int = 0
var _anim_idx: int = 0
var _yaw: float = 0.4
var _pitch: float = 0.12
var _zoom: float = 0.6
var _center: Vector3 = Vector3.ZERO
var _base_radius: float = 3.0
var _time_idx: int = 0
var _dragging: bool = false
# Action sequence builder: queue several clips and watch them play back to back (looping
# the whole list), to see how the character transitions between movements.
var _playlist: Array[String] = []      # anim paths, in play order
var _seq_player: AnimationPlayer       # the loaded character's AnimationPlayer
var _seq_pos: int = 0
var _seq_playing: bool = false
var _playlist_label: Label

func _ready() -> void:
	_scan()
	# Defaults (overridable by CTT_CHAR / CTT_ANIM substring for headless capture).
	_char_idx = _find(_chars, OS.get_environment("CTT_CHAR") if OS.has_environment("CTT_CHAR") else "Male_Police")
	_anim_idx = _find(_anims, OS.get_environment("CTT_ANIM") if OS.has_environment("CTT_ANIM") else "Walking")
	if OS.has_environment("SHOT_TIME"):
		_time_idx = clampi(int(OS.get_environment("SHOT_TIME")), 0, TOD.size() - 1)
	if OS.has_environment("SHOT_YAW"): _yaw = float(OS.get_environment("SHOT_YAW"))
	if OS.has_environment("SHOT_PITCH"): _pitch = float(OS.get_environment("SHOT_PITCH"))
	if OS.has_environment("SHOT_ZOOM"): _zoom = float(OS.get_environment("SHOT_ZOOM"))
	_build_stage()
	_build_hud()
	_load_character()
	_apply_time()
	if OS.has_environment("CTT_SHOT"):
		call_deferred("_capture")

## Scan the character folder (with-skin FBX) and the animation folder (action FBX,
## excluding the Character subfolder). Any *.fbx dropped in later shows up here.
func _scan() -> void:
	var cd := DirAccess.open(CHAR_DIR)
	if cd:
		for f in cd.get_files():
			if f.ends_with(".fbx"):
				_chars.append("%s/%s" % [CHAR_DIR, f])
	var ad := DirAccess.open(ANIM_DIR)
	if ad:
		for f in ad.get_files():
			if f.ends_with(".fbx"):
				_anims.append("%s/%s" % [ANIM_DIR, f])
	_chars.sort()
	_anims.sort()

func _find(arr: Array[String], substr: String) -> int:
	for i in arr.size():
		if arr[i].get_file().contains(substr):
			return i
	return 0

func _build_stage() -> void:
	var ground := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(40, 1, 40)
	ground.mesh = plane
	ground.position = Vector3(0, -0.5, 0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#3b4048")
	ground.material_override = gm
	add_child(ground)
	_sky = Sky3D.new()
	add_child(_sky)
	_sky.game_time_enabled = false
	_sky.editor_time_enabled = false
	_cam = Camera3D.new()
	_cam.current = true
	_cam.far = 500.0
	add_child(_cam)

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	_char_picker = OptionButton.new()
	_char_picker.offset_left = 16
	_char_picker.offset_top = 12
	_char_picker.offset_right = 300
	_char_picker.offset_bottom = 48
	for c in _chars:
		_char_picker.add_item(c.get_file())
	_char_picker.select(_char_idx)
	_char_picker.item_selected.connect(_on_char_pick)
	hud.add_child(_char_picker)

	_anim_picker = OptionButton.new()
	_anim_picker.offset_left = 312
	_anim_picker.offset_top = 12
	_anim_picker.offset_right = 600
	_anim_picker.offset_bottom = 48
	for a in _anims:
		_anim_picker.add_item(a.get_file())
	_anim_picker.select(_anim_idx)
	_anim_picker.item_selected.connect(_on_anim_pick)
	hud.add_child(_anim_picker)

	# Sequence-builder buttons, to the right of the anim dropdown.
	_add_button(hud, "Add ▸", 612, 700, _on_add_clip)
	_add_button(hud, "Play ▶", 708, 800, _on_play_sequence)
	_add_button(hud, "Clear", 808, 892, _on_clear_sequence)

	var tb := Button.new()
	tb.text = "Time (T)"
	tb.offset_left = 16
	tb.offset_top = 56
	tb.offset_right = 150
	tb.offset_bottom = 92
	tb.pressed.connect(_cycle_time)
	hud.add_child(tb)

	# Shows the queued action sequence and which step is playing.
	_playlist_label = Label.new()
	_playlist_label.offset_left = 16
	_playlist_label.offset_top = 96
	_playlist_label.add_theme_font_size_override("font_size", 15)
	_playlist_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_playlist_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(_playlist_label)
	_update_playlist_label()

	_label = Label.new()
	_label.offset_left = 160
	_label.offset_top = 58
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(_label)

func _add_button(hud: Node, text: String, left: int, right: int, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.offset_left = left
	b.offset_top = 12
	b.offset_right = right
	b.offset_bottom = 48
	b.pressed.connect(cb)
	hud.add_child(b)


## Append the clip currently selected in the dropdown to the play sequence.
func _on_add_clip() -> void:
	if _anims.is_empty():
		return
	_playlist.append(_anims[clampi(_anim_idx, 0, _anims.size() - 1)])
	_update_playlist_label()


func _on_clear_sequence() -> void:
	_playlist.clear()
	_seq_playing = false
	_update_playlist_label()
	# Return to previewing the single dropdown clip.
	_load_character()
	_apply_time()


## Load the character with every queued clip installed, then play them back to back,
## looping the whole list, so transitions between movements are visible.
func _on_play_sequence() -> void:
	if _playlist.is_empty():
		return
	_load_character()          # rebuild a clean character
	_apply_time()
	if _seq_player == null:
		return
	var lib := AnimationLibrary.new()
	for i in _playlist.size():
		var clip := _extract_clip(_playlist[i], false)   # one-shot; sequence loops instead
		if clip:
			lib.add_animation("seq_%d" % i, clip)
	if _seq_player.has_animation_library("seq"):
		_seq_player.remove_animation_library("seq")
	_seq_player.add_animation_library("seq", lib)
	if not _seq_player.animation_finished.is_connected(_on_seq_step_done):
		_seq_player.animation_finished.connect(_on_seq_step_done)
	_seq_playing = true
	_seq_pos = 0
	_play_seq_step()


func _play_seq_step() -> void:
	if not _seq_playing or _seq_player == null:
		return
	var key := "seq/seq_%d" % _seq_pos
	if not _seq_player.has_animation(key):
		return
	_seq_player.play(key)
	_update_playlist_label()


func _on_seq_step_done(anim_name: StringName) -> void:
	if not _seq_playing:
		return
	if String(anim_name) != "seq/seq_%d" % _seq_pos:
		return
	_seq_pos = (_seq_pos + 1) % _playlist.size()   # loop the whole list
	_play_seq_step()


func _update_playlist_label() -> void:
	if _playlist_label == null:
		return
	if _playlist.is_empty():
		_playlist_label.text = "Sequence: (empty) — pick a clip, press Add ▸, repeat, then Play ▶"
		return
	var parts: Array[String] = []
	for i in _playlist.size():
		var mark := "▶ " if (_seq_playing and i == _seq_pos) else ""
		parts.append("%s%d. %s" % [mark, i + 1, _playlist[i].get_file().trim_suffix(".fbx")])
	_playlist_label.text = "Sequence (loops):  " + "    ".join(parts)


func _on_char_pick(idx: int) -> void:
	_char_idx = idx
	_load_character()
	_apply_time()

func _on_anim_pick(idx: int) -> void:
	_anim_idx = idx
	_seq_playing = false      # dropdown preview overrides a running sequence
	_load_character()
	_apply_time()

func _load_character() -> void:
	if _char:
		_char.queue_free()
		_char = null
	if _chars.is_empty():
		push_warning("No characters in %s" % CHAR_DIR)
		return
	var char_path: String = _chars[clampi(_char_idx, 0, _chars.size() - 1)]
	var anim_path: String = _anims[clampi(_anim_idx, 0, _anims.size() - 1)] if not _anims.is_empty() else ""

	_char = (load(char_path) as PackedScene).instantiate()
	add_child(_char)

	# Texture the skinned mesh with the shared city atlas material.
	var mat := load(ATLAS_MAT) as Material
	for n in _char.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh and mat:
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, mat)

	# Copy the action clip onto the character's own AnimationPlayer and play it.
	# Both rigs share the same skeleton + node paths, so no retargeting is needed;
	# position tracks are dropped so the walk plays in place.
	var player := _char.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_seq_player = player
	var walk := _extract_walk(anim_path) if anim_path != "" else null
	var ok := false
	if player and walk:
		var lib := AnimationLibrary.new()
		lib.add_animation("walk", walk)
		if player.has_animation_library("act"):
			player.remove_animation_library("act")
		player.add_animation_library("act", lib)
		player.play("act/walk")
		ok = true
	if OS.has_environment("CTT_LC"):
		print("[CHAR] player=%s walk=%s playing=%s" % [player != null, walk != null, ok])

	_frame_camera()

## Single-clip preview: looped, position stripped (in place).
func _extract_walk(anim_path: String) -> Animation:
	return _extract_clip(anim_path, true)


## Load the action FBX, take its (first non-trivial) clip, strip position tracks so the
## character animates in place, and return a copy looped or one-shot per `looped`.
func _extract_clip(anim_path: String, looped: bool) -> Animation:
	var scene := (load(anim_path) as PackedScene).instantiate()
	var src: Animation = null
	for ap in scene.find_children("*", "AnimationPlayer", true, false):
		for n in (ap as AnimationPlayer).get_animation_list():
			var a := (ap as AnimationPlayer).get_animation(n)
			if a and a.length > 0.1:
				src = a
				break
		if src: break
	if src == null:
		scene.free()
		return null
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	for ti in src.get_track_count():
		if src.track_get_type(ti) == Animation.TYPE_POSITION_3D:
			continue  # drop root/hip translation -> animate in place
		var nt := out.add_track(src.track_get_type(ti))
		out.track_set_path(nt, src.track_get_path(ti))
		out.track_set_interpolation_type(nt, src.track_get_interpolation_type(ti))
		for ki in src.track_get_key_count(ti):
			out.track_insert_key(nt, src.track_get_key_time(ti, ki), src.track_get_key_value(ti, ki))
	scene.free()
	return out

func _combined_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var has := false
	for n in root.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		var world := vi.global_transform * vi.get_aabb()
		if not has:
			out = world
			has = true
		else:
			out = out.merge(world)
	if not has:
		out = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 2, 1))
	return out

func _frame_camera() -> void:
	var ab := _combined_aabb(_char)
	_char.position.y -= ab.position.y   # seat feet on ground
	ab = _combined_aabb(_char)
	_center = ab.position + ab.size * 0.5
	_base_radius = maxf(ab.size.length() * 0.7, 1.2)
	_update_orbit()
	_update_label()

func _update_orbit() -> void:
	var d: float = _base_radius * _zoom + 0.4
	var cp := cos(_pitch)
	var dir := Vector3(sin(_yaw) * cp, sin(_pitch), cos(_yaw) * cp)
	_cam.global_position = _center + dir * d
	_cam.look_at(_center, Vector3.UP)

func _apply_time() -> void:
	var t: Array = TOD[_time_idx]
	if _sky:
		_sky.current_time = float(t[1])
		_sky.tonemap_exposure = float(t[2])
	_update_label()

func _update_label() -> void:
	if _label:
		var cn := _chars[_char_idx].get_file() if not _chars.is_empty() else "(no character)"
		var an := _anims[_anim_idx].get_file() if not _anims.is_empty() else "(no clip)"
		_label.text = "%s  ·  %s  ·  %s\ndrag rotate · wheel zoom · T time" % [TOD[_time_idx][0], cn, an]

func _cycle_time() -> void:
	_time_idx = (_time_idx + 1) % TOD.size()
	_apply_time()

func _process(delta: float) -> void:
	var turn := Input.get_axis("ui_left", "ui_right")
	var pit := Input.get_axis("ui_down", "ui_up")
	if absf(turn) > 0.01 or absf(pit) > 0.01:
		_yaw += turn * delta * 1.5
		_pitch = clampf(_pitch + pit * delta * 1.2, -1.4, 1.4)
		_update_orbit()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_T:
		_cycle_time()
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * 0.9, 0.15, 6.0); _update_orbit()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * 1.1, 0.15, 6.0); _update_orbit()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
	elif e is InputEventMouseMotion and _dragging:
		var mm := e as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.01
		_pitch = clampf(_pitch + mm.relative.y * 0.01, -1.4, 1.4)
		_update_orbit()

func _capture() -> void:
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://char_preview.png")
	print("[CHAR] ", ProjectSettings.globalize_path("user://char_preview.png"))
	get_tree().quit()
