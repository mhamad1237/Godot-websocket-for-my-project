extends Resource
class_name TpWeaponData
## The weapon's scene to instantiate when equipped.
@export var weapon_scene: PackedScene

## Local position/rotation offset when held (relative to WeaponHolder).
@export var hold_position: Vector3 = Vector3.ZERO
@export var hold_rotation_degrees: Vector3 = Vector3.ZERO
@export var hold_scale : Vector3 = Vector3.ONE

@export var available_scopes: Array[PackedScene] = []
