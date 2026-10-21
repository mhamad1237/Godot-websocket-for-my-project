extends RigidBody3D

const DAMAGE := 120.0
const RADIUS := 8
const MIN_DAMAGE_FRACTION := 0.1

var fuse := 3.5
var owner_id := 0
var _exploded := false

# --- Smooth interpolation variables for WebSocket clients ---
var target_position: Vector3 = Vector3.ZERO
var target_rotation: Quaternion = Quaternion()

@export var synced_position: Vector3:
	set(val):
		synced_position = val
		target_position = val

@export var synced_rotation: Quaternion:
	set(val):
		synced_rotation = val
		target_rotation = val
# -----------------------------------------------------------


func _ready() -> void:
	target_position = global_position
	target_rotation = Quaternion(global_basis)
	
	if not multiplayer.is_server():
		# Clients do not run physics simulation; they display interpolated server updates
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		return

	linear_velocity = get_meta("launch_velocity", Vector3.ZERO)
	await get_tree().create_timer(fuse).timeout
	_explode()


func _process(delta: float) -> void:
	# Non-server peers smoothly glide toward the server's synced transforms
	if not multiplayer.is_server():
		global_position = global_position.lerp(target_position, delta * 20.0)
		global_basis = global_basis.slerp(Basis(target_rotation), delta * 20.0)


func _physics_process(_delta: float) -> void:
	# Server continuously captures actual physics transforms to pass down to clients
	if multiplayer.is_server():
		synced_position = global_position
		synced_rotation = Quaternion(global_basis)


func _explode() -> void:
	if _exploded or not is_inside_tree():
		return
	_exploded = true
	await get_tree().physics_frame   # space state is only readable in the physics frame
	if not is_inside_tree():
		return

	var center := global_position
	var space := get_world_3d().direct_space_state

	for id in NetworkManager.players:
		var p := NetworkManager.get_player_node(id) as Node3D
		if p == null or p.is_dead:
			continue

		var target := p.global_position + Vector3.UP
		var dist := center.distance_to(target)
		if dist > RADIUS:
			continue

		var q := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 0.1, target)
		q.exclude = [get_rid(), p.get_rid()]

		if not space.intersect_ray(q).is_empty():
			continue   # a wall is in the way

		var dmg := DAMAGE * lerpf(MIN_DAMAGE_FRACTION, 1.0, 1.0 - dist / RADIUS)
		p._server_apply_damage(dmg, owner_id)

	_explode_fx.rpc(center)
	freeze = true
	await get_tree().create_timer(2.21).timeout   # let the effect play on every peer
	queue_free()


@rpc("authority", "call_local", "reliable")
func _explode_fx(pos: Vector3) -> void:
	Explosion.spawn(get_tree().current_scene, pos)
	$explosion_sound.play()
	$model.hide()
