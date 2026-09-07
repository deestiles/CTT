extends Control

const SHOW_DEVELOPER_TESTS := false

var station_screen: Control
var briefing_screen: Control
var lives_label: Label
var recovery_label: Label
var credits_label: Label
var rank_label: Label
var start_button: Button


func _ready() -> void:
	build_background()
	build_station()
	build_briefing()
	show_station()


func _process(_delta: float) -> void:
	GameState.refresh_lives()
	update_account_labels()


func build_background() -> void:
	var background := ColorRect.new()
	background.color = Color("#050d17")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var glow := ColorRect.new()
	glow.color = Color(0.03, 0.34, 0.48, 0.18)
	glow.set_anchors_preset(Control.PRESET_TOP_WIDE)
	glow.offset_bottom = 360.0
	background.add_child(glow)


func build_station() -> void:
	station_screen = Control.new()
	station_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(station_screen)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-270.0, -460.0)
	box.size = Vector2(540.0, 920.0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	station_screen.add_child(box)

	var eyebrow := make_label("CITY PURSUIT UNIT", 18, Color("#22d9ff"))
	box.add_child(eyebrow)
	var title := make_label("CATCH THE THIEF", 54, Color("#f4fbff"))
	box.add_child(title)
	var subtitle := make_label("CHOOSE YOUR SIDE", 16, Color("#91aabd"))
	box.add_child(subtitle)

	var role_row := HBoxContainer.new()
	role_row.alignment = BoxContainer.ALIGNMENT_CENTER
	role_row.add_theme_constant_override("separation", 12)
	box.add_child(role_row)
	var police := make_button("POLICE\nAVAILABLE", open_briefing)
	role_row.add_child(police)
	var thief := make_button("THIEF\nCOMING LATER", func(): pass)
	thief.disabled = true
	role_row.add_child(thief)

	var account := PanelContainer.new()
	account.custom_minimum_size = Vector2(500.0, 145.0)
	box.add_child(account)
	var account_grid := GridContainer.new()
	account_grid.columns = 2
	account.add_child(account_grid)
	rank_label = make_label("", 18, Color("#22d9ff"))
	account_grid.add_child(rank_label)
	credits_label = make_label("", 18, Color("#ffca55"))
	account_grid.add_child(credits_label)
	lives_label = make_label("", 24, Color("#ff5260"))
	account_grid.add_child(lives_label)
	recovery_label = make_label("", 16, Color("#9db3c2"))
	account_grid.add_child(recovery_label)

	box.add_child(make_button("GARAGE · COMING NEXT", func(): pass, true))
	box.add_child(make_label("Police campaign first · Thief campaign follows the MVP", 13, Color("#758c9d")))


func build_briefing() -> void:
	briefing_screen = Control.new()
	briefing_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(briefing_screen)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-270.0, -440.0)
	box.size = Vector2(540.0, 880.0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 15)
	briefing_screen.add_child(box)
	box.add_child(make_label("DISPATCH BRIEFING", 18, Color("#22d9ff")))
	box.add_child(make_label("CASE %03d" % GameState.current_case, 44, Color("#f4fbff")))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(510.0, 370.0)
	box.add_child(card)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 13)
	card.add_child(details)
	details.add_child(make_detail("CRIME", "VEHICLE THEFT"))
	details.add_child(make_detail("DISTRICT", "DOWNTOWN GRID"))
	details.add_child(make_detail("SUSPECT", "RED GETAWAY COUPE"))
	details.add_child(make_detail("TIME LIMIT", "60 SECONDS"))
	details.add_child(make_detail("DIFFICULTY", "CADET"))
	details.add_child(make_detail("LOADOUT", "1 BACKUP · 2 SPIKE STRIPS"))
	start_button = make_button("START PURSUIT", start_chase)
	box.add_child(start_button)
	if SHOW_DEVELOPER_TESTS:
		box.add_child(make_button("LEGACY CHASE TEST", start_legacy_chase_test))
	box.add_child(make_button("RETURN TO STATION", show_station))


func open_briefing() -> void:
	GameState.selected_role = "police"
	GameState.save_game()
	station_screen.visible = false
	briefing_screen.visible = true
	start_button.disabled = GameState.lives <= 0
	start_button.text = "START PURSUIT" if GameState.lives > 0 else "NO LIVES · RECOVERING"


func show_station() -> void:
	station_screen.visible = true
	briefing_screen.visible = false
	update_account_labels()


func start_chase() -> void:
	GameState.refresh_lives()
	if GameState.lives <= 0:
		return
	get_tree().change_scene_to_file("res://scenes/chase/road_network_test.tscn")


func start_legacy_chase_test() -> void:
	get_tree().change_scene_to_file("res://scenes/chase/main.tscn")


func update_account_labels() -> void:
	if not lives_label:
		return
	rank_label.text = "RANK\n" + GameState.rank_name()
	credits_label.text = "CREDITS\n%d CR" % GameState.credits
	lives_label.text = "LIVES\n" + "♥ ".repeat(GameState.lives) + "♡ ".repeat(GameState.MAX_LIVES - GameState.lives)
	recovery_label.text = "NEXT LIFE\n" + GameState.life_countdown_text()


func make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func make_button(text: String, callback: Callable, disabled := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(245.0, 86.0)
	button.add_theme_font_size_override("font_size", 17)
	button.disabled = disabled
	button.pressed.connect(callback)
	return button


func make_detail(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	var key_label := make_label(key, 14, Color("#7f98aa"))
	key_label.custom_minimum_size.x = 175.0
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(key_label)
	var value_label := make_label(value, 16, Color("#f4fbff"))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(value_label)
	return row
