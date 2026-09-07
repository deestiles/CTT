extends Node

var builder_map_name := "city_map"

const SAVE_PATH := "user://catch_the_thief_save.json"
const LIFE_RECOVERY_SECONDS := 30 * 60
const MAX_LIVES := 3

var lives := MAX_LIVES
var next_life_at := 0
var credits := 500
var rank_xp := 0
var completed_cases := 0
var selected_role := "police"
var ad_free := false
var current_case := 1
var vehicle_id := "patrol"
var vehicle_color := "#123b63"
var vehicle_upgrades := {
	"engine": 0,
	"nitro": 0,
	"handling": 0,
	"armor": 1,
	"electronics": 0
}


func _ready() -> void:
	load_save()
	refresh_lives()


func refresh_lives() -> void:
	if lives >= MAX_LIVES:
		lives = MAX_LIVES
		next_life_at = 0
		return
	var now := int(Time.get_unix_time_from_system())
	if next_life_at <= 0:
		next_life_at = now + LIFE_RECOVERY_SECONDS
	while lives < MAX_LIVES and now >= next_life_at:
		lives += 1
		if lives < MAX_LIVES:
			next_life_at += LIFE_RECOVERY_SECONDS
		else:
			next_life_at = 0
	save_game()


func consume_life() -> bool:
	refresh_lives()
	if lives <= 0:
		return false
	lives -= 1
	if next_life_at <= 0:
		next_life_at = int(Time.get_unix_time_from_system()) + LIFE_RECOVERY_SECONDS
	save_game()
	return true


func life_countdown_text() -> String:
	refresh_lives()
	if lives >= MAX_LIVES or next_life_at <= 0:
		return "FULL"
	var remaining := maxi(0, next_life_at - int(Time.get_unix_time_from_system()))
	return "%02d:%02d" % [remaining / 60, remaining % 60]


func record_success(reward_credits: int, reward_xp: int) -> void:
	credits += reward_credits
	rank_xp += reward_xp
	completed_cases += 1
	current_case = completed_cases + 1
	save_game()


func rank_name() -> String:
	var ranks := ["CADET I", "CADET II", "PATROL OFFICER", "SENIOR OFFICER", "DETECTIVE", "SERGEANT", "LIEUTENANT", "CAPTAIN", "COMMANDER", "COMMISSIONER"]
	return ranks[mini(ranks.size() - 1, int(rank_xp / 500))]


func save_game() -> void:
	var data := {
		"lives": lives,
		"next_life_at": next_life_at,
		"credits": credits,
		"rank_xp": rank_xp,
		"completed_cases": completed_cases,
		"selected_role": selected_role,
		"ad_free": ad_free,
		"current_case": current_case,
		"vehicle_id": vehicle_id,
		"vehicle_color": vehicle_color,
		"vehicle_upgrades": vehicle_upgrades
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	lives = int(parsed.get("lives", MAX_LIVES))
	next_life_at = int(parsed.get("next_life_at", 0))
	credits = int(parsed.get("credits", 500))
	rank_xp = int(parsed.get("rank_xp", 0))
	completed_cases = int(parsed.get("completed_cases", 0))
	selected_role = str(parsed.get("selected_role", "police"))
	ad_free = bool(parsed.get("ad_free", false))
	current_case = int(parsed.get("current_case", completed_cases + 1))
	vehicle_id = str(parsed.get("vehicle_id", "patrol"))
	vehicle_color = str(parsed.get("vehicle_color", "#123b63"))
	var saved_upgrades = parsed.get("vehicle_upgrades", vehicle_upgrades)
	if saved_upgrades is Dictionary:
		for key in vehicle_upgrades.keys():
			vehicle_upgrades[key] = int(saved_upgrades.get(key, vehicle_upgrades[key]))
