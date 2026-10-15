# ============================================================
# WeaponBase.gd
# ============================================================
extends Node3D
class_name WeaponBase
var data: WeaponData
var weapon_anim_player: AnimationPlayer
var current_scope_index: int = 0
var scope_instance: Node3D = null
@onready var scope_mount:Node3D = $ScopeMount
const NO_SCOPE := -1
signal scope_changed(index: int)
var scope_crosshair : Marker3D


func _ready() -> void:
	weapon_anim_player = get_node_or_null("model/AnimationPlayer")

func setup(weapon_data: WeaponData) -> void:
	data = weapon_data
	_on_setup()
func equip_scope(index: int) -> void:
	if not is_multiplayer_authority():
		return

	if is_instance_valid(scope_instance):
		scope_instance.queue_free()
	scope_instance = null
	var existing = scope_mount.get_node_or_null("scope")
	if existing:
		existing.queue_free()

	if index < 0 or index >= data.available_scopes.size() or data.available_scopes[index] == null:
		current_scope_index = NO_SCOPE
		scope_changed.emit(NO_SCOPE)   # was missing: remote rigs never learned about "no scope"
		return

	current_scope_index = index
	scope_instance = data.available_scopes[index].instantiate()
	scope_mount.add_child(scope_instance)
	scope_changed.emit(index)
	scope_crosshair = scope_instance.get_node("scope_crosshair")


func cycle_scope() -> void:
	if not is_multiplayer_authority():
		return
	var next := current_scope_index + 1
	if next >= data.get_scope_count():
		next = -1 if data.allow_no_scope else 0
	equip_scope(next)
## Override in weapon-specific scripts for one-time setup.
func _on_setup() -> void:
	pass


## Called every frame by WeaponHolder while moving and not firing.
## Must directly move `holder.position` and rotate `bob_pivot.rotation`.
## Override this per weapon for unique bob motion.
func get_bob_rotation(bob_timer: float, is_sprinting: bool, is_crouching: bool) -> Vector3:
	return Vector3.ZERO

func get_bob_offset(bob_timer: float, is_sprinting: bool, is_crouching: bool) -> Vector3:
	return Vector3.ZERO

func apply_bob(holder: Node3D, bob_pivot: Node3D, bob_timer: float, is_sprinting: bool, is_crouching: bool, delta: float) -> void:
	pass


## Called every frame by WeaponHolder when not moving / firing / in ADS,
## to ease bob back to rest. Override alongside apply_bob if you use
## a different motion shape that needs custom rest-easing.
func reset_bob(holder: Node3D, bob_pivot: Node3D, delta: float) -> void:
	if bob_pivot:
		bob_pivot.rotation = bob_pivot.rotation.lerp(Vector3.ZERO, data.bob_speed * delta)
