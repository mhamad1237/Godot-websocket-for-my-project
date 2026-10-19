extends RigidBody3D

const DAMAGE := 120.0
const RADIUS := 6.0
const MIN_DAMAGE_FRACTION := 0.1

var fuse := 3.5
var owner_id := 0
var _exploded := false


func _ready() -> void:
	if not multiplayer.is_server():
		# Clients just display what the server sends.
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		return
	linear_velocity = get_meta("launch_velocity", Vector3.ZERO)
	await get_tree().create_timer(fuse).timeout
	_explode()


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
	await get_tree().create_timer(0.8).timeout   # let the effect play on every peer
	queue_free()


@rpc("authority", "call_local", "reliable")
func _explode_fx(_pos: Vector3) -> void:
	$explosion.setup()
