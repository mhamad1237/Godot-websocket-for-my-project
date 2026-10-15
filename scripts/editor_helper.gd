@tool
extends EditorScript

var tp_weapon : Node3D = null

@export var ak47 : TpWeaponData = preload("res://weapon_resources/tp/ak47.tres")
@export var makarov_pistol : TpWeaponData = preload("res://weapon_resources/tp/makarov_pistol.tres")
var current_selection = null
func _run() -> void:
	var root = get_editor_interface().get_edited_scene_root()
	var parent = root.get_node("model/Skeleton3D/WeaponBoneAttachment")
	var weapon = find_weapon(parent)
	current_selection = ak47



	if weapon:
		tp_weapon = weapon
		set_values(current_selection)
		print("Found: ", weapon.get_path())
	else:
		print("Weapon not found")


func find_weapon(node: Node) -> Node:
	for child in node.get_children():
		if child.name == "weapon":
			return child

		var result = find_weapon(child)
		if result != null:
			return result

	return null
func set_values(selection: TpWeaponData):
	tp_weapon.position = selection.hold_position
	tp_weapon.rotation_degrees = selection.hold_rotation_degrees
	tp_weapon.scale = selection.hold_scale
