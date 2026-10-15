extends Node3D

var muzzle_flash: Node3D
var tps_weapon: Node3D = null
var muzzle: Node3D = null
@export var crouch_tilt_deg := Vector3(0.0, 0.0, -15)  # tune sign and amount
@export var crouch_tilt_speed := 10.0
var tilt_pivot : Node3D = null
@onready var owner_player := get_parent()  # the CharacterBody3D this rig belongs to

var tp_current_weapon_data: TpWeaponData = null
var tps_scope: Node3D = null
var tps_scope_mount: Node3D = null
var tps_scope_index: int = -1
var skeletonIK : SkeletonIK3D =null
@export var muzzle_flash_scene :PackedScene
var player_mesh : Node3D = null
func _ready() -> void:
	player_mesh = get_node("mesh")
	tilt_pivot = player_mesh.tilt_pivot
	skeletonIK = player_mesh.lefthandleIK
	equip_tps_weapon(TpWeaponPaths.makarov_pistol)  # default; synced later if it changes


func equip_tps_weapon(weapon_data: TpWeaponData) -> void:
	if is_instance_valid(tps_weapon):
		tps_weapon.queue_free()
	var existing =tilt_pivot.get_node_or_null("weapon")
	if existing:
		existing.queue_free()
	tp_current_weapon_data = weapon_data

	tps_weapon = weapon_data.weapon_scene.instantiate()
	tilt_pivot.add_child(tps_weapon)
	tps_weapon.position = weapon_data.hold_position
	tps_weapon.rotation_degrees = weapon_data.hold_rotation_degrees
	tps_weapon.scale = weapon_data.hold_scale

	# Refresh the muzzle for the new weapon (the old reference was freed)
	muzzle = tps_weapon.get_node_or_null("muzzle")

	tps_scope = null
	tps_scope_mount = tps_weapon.get_node_or_null("ScopeMount")
	equip_tps_scope(tps_scope_index)
	muzzle_flash = muzzle_flash_scene.instantiate()
	muzzle.add_child(muzzle_flash)
	var left_handle : Node3D = tps_weapon.get_node("handle")
	skeletonIK.target_node = left_handle.get_path()
	skeletonIK.start()


func equip_tps_scope(index: int) -> void:
	tps_scope_index = index
	tps_scope = TpScopeUtil.apply(tps_scope_mount, tp_current_weapon_data, index, tps_scope)
func _process(delta: float) -> void:
	if owner_player == null:
		return

	var tilt := Vector3.ZERO
	if owner_player.sync_crouching and owner_player.stance == owner_player.Stance.PISTOL:
		tilt = Vector3(
			deg_to_rad(crouch_tilt_deg.x),
			deg_to_rad(crouch_tilt_deg.y),
			deg_to_rad(crouch_tilt_deg.z)
		)

	tilt_pivot.rotation = tilt_pivot.rotation.lerp(
		tilt,
		clampf(crouch_tilt_speed * delta, 0.0, 1.0)
	)

func play_muzzle_flash() -> void:
	muzzle_flash.play()
