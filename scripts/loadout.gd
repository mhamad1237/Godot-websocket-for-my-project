extends Node

const SAVE_PATH := "user://loadout.cfg"

var all_weapons: Array[WeaponData] = [
	WeaponPaths.makarov_pistol,
	WeaponPaths.ak47,   # your real constant names
]
var weapon_data: WeaponData
var scope_index := -1   # -1 = no scope

func _ready() -> void:
	weapon_data = all_weapons[0]
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var saved: String = cfg.get_value("loadout", "weapon", "")
	for w in all_weapons:
		if w.weapon_name == saved:
			weapon_data = w
			scope_index = clampi(int(cfg.get_value("loadout", "scope", -1)), -1, w.available_scopes.size() - 1)
			break

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("loadout", "weapon", weapon_data.weapon_name)
	cfg.set_value("loadout", "scope", scope_index)
	cfg.save(SAVE_PATH)
