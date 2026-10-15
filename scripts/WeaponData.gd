# ============================================================
# WeaponData.gd
# ============================================================
extends Resource
class_name WeaponData
const NO_SCOPE_NAME := "no_scope"

## The weapon's scene to instantiate when equipped.
@export var weapon_scene: PackedScene

## Local position/rotation offset when held (relative to WeaponHolder).
@export var hold_position: Vector3 = Vector3.ZERO
@export var hold_rotation_degrees: Vector3 = Vector3.ZERO
@export var hold_scale : Vector3 = Vector3.ONE
## Display
@export var weapon_name: String = ""
@export var icon: Texture2D
@export var type : String
## Firing stats
@export var fire_rate: float = 0.1
@export var damage: int = 10
@export var magazine_size: int = 30
@export var is_shotgun: bool = false
@export var pellet_count: int = 8  # only used if is_shotgun
@export var is_semi_auto: bool = false
## Falloff
@export var falloff_start: float = 20.0
@export var falloff_end: float = 60.0
@export var min_damage_multiplier: float = 0.3

## Bob tuning (weapon-specific)
@export var bob_amount: float = 0.003
@export var bob_speed: float = 8.0
@export var sprint_bob_amount: float = 0.03
@export var sprint_bob_speed: float = 11.0
@export var bob_offset: Vector3 = Vector3.ZERO
@export var bob_rotation: Vector3 = Vector3.ZERO


# Camera Recoil tuning
@export var cam_recoil_up: float = 1.8          # degrees, upward kick per shot
@export var cam_recoil_side: float = 0.6        # degrees, random left/right sway per shot
@export var cam_recoil_snap_speed: float = 25.0 # how fast the kick applies (higher = punchier)
@export var cam_recoil_decay_speed: float = 6.0 # how fast it settles back to center
## Scopes
@export var available_scopes: Array[PackedScene] = []
@export var scope_names: Array[String] = []  # matches index-to-index with available_scopes, for UI/animation lookup
## No-scope (iron sights)
## Allow cycling to "no scope" as an extra slot after the last scope.
@export var allow_no_scope: bool = true
## Start with iron sights instead of the first scope on pickup.
@export var default_no_scope: bool = false

@export var clip_ray_length : float

func get_scope_count() -> int:
	return available_scopes.size()

func get_scope_name(index: int) -> String:
	if index < 0 or index >= scope_names.size():
		return NO_SCOPE_NAME
	return scope_names[index]

func get_default_scope_index() -> int:
	if default_no_scope and allow_no_scope:
		return -1
	return 0 if available_scopes.size() > 0 else -1
