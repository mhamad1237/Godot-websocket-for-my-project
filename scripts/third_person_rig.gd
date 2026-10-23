extends Node3D
var grenade_mesh: Node3D = null

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
	grenade_mesh = tilt_pivot.get_parent().get_node_or_null("Grenade") as Node3D
	set_hand_visibility(false, true)
	equip_tps_weapon(TpWeaponPaths.makarov_pistol)



func equip_tps_weapon(weapon_data: TpWeaponData) -> void:
	if weapon_data == null or weapon_data.weapon_scene == null:
		push_error("equip_tps_weapon: missing weapon data or scene")
		return

	# Free the old weapon NOW so the new one doesn't get renamed to "@Node3D@2"
	if is_instance_valid(tps_weapon):
		tilt_pivot.remove_child(tps_weapon)
		tps_weapon.queue_free()
	for child in tilt_pivot.get_children():
		tilt_pivot.remove_child(child)
		child.queue_free()
	tps_weapon = null
	muzzle = null
	tps_weapon = null
	muzzle = null

	tp_current_weapon_data = weapon_data

	tps_weapon = weapon_data.weapon_scene.instantiate()
	tps_weapon.name = "weapon"
	tilt_pivot.add_child(tps_weapon)
	tps_weapon.position = weapon_data.hold_position
	tps_weapon.rotation_degrees = weapon_data.hold_rotation_degrees
	tps_weapon.scale = weapon_data.hold_scale

	muzzle = tps_weapon.get_node_or_null("muzzle")
	if muzzle and muzzle_flash_scene:
		muzzle_flash = muzzle_flash_scene.instantiate()
		muzzle.add_child(muzzle_flash)

	tps_scope = null
	tps_scope_mount = tps_weapon.get_node_or_null("ScopeMount")
	if tps_scope_mount:
		equip_tps_scope(tps_scope_index)

	var left_handle := tps_weapon.get_node_or_null("handle") as Node3D
	if left_handle:
		skeletonIK.stop()
		skeletonIK.target_node = skeletonIK.get_path_to(left_handle)
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
func set_hand_visibility(grenade: bool, weapon: bool) -> void:
	if grenade_mesh:
		grenade_mesh.visible = grenade
	if tilt_pivot:
		tilt_pivot.visible = weapon
