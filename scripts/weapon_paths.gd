extends Node

const _PATHS := {
	"makarov_pistol": "res://weapon_resources/makarov_pistol.tres",
	"ak47": "res://weapon_resources/ak47.tres",
}

func get_data(weapon_name: String) -> WeaponData:
	return load(_PATHS.get(weapon_name, _PATHS["ak47"])) as WeaponData

# Keeps existing `WeaponPaths.ak47` calls working
var ak47: WeaponData:
	get:
		return get_data("ak47")
var makarov_pistol: WeaponData:
	get:
		return get_data("makarov_pistol")
