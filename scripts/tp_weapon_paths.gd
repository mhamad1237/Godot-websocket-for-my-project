extends Node

const _PATHS := {
	"makarov_pistol": "res://weapon_resources/tp/makarov_pistol.tres",
	"ak47": "res://weapon_resources/tp/ak47.tres",
}

func get_data(weapon_name: String) -> TpWeaponData:
	return load(_PATHS.get(weapon_name, _PATHS["ak47"])) as TpWeaponData

var ak47: TpWeaponData:
	get:
		return get_data("ak47")
var makarov_pistol : TpWeaponData:
	get:
		return get_data("makarov_pistol")
