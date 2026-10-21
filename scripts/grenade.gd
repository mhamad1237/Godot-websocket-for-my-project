extends RigidBody3D

const DAMAGE := 120.0
const RADIUS := 8
const MIN_DAMAGE_FRACTION := 0.1
const GRENADE_INTERPOLATION_DELAY := 0.06
const MAX_GRENADE_SNAPSHOTS := 12

var _grenade_snapshots: Array[Dictionary] = []

var _last_recorded_position: Vector3 = Vector3.ZERO
var _last_recorded_rotation: Quaternion = Quaternion()
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

	_last_recorded_position = target_position
	_last_recorded_rotation = target_rotation

	if not multiplayer.is_server():
		_push_grenade_snapshot(
			target_position,
			target_rotation
		)

		# Clients display the server's grenade physics.
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		return

	linear_velocity = get_meta("launch_velocity", Vector3.ZERO)

	await get_tree().create_timer(fuse).timeout
	_explode()

func _process(_delta: float) -> void:
	if multiplayer.is_server():
		return

	# A synchronizer may update position and rotation separately.
	# Record their latest combined values only once per frame.
	if (
		target_position != _last_recorded_position
		or target_rotation != _last_recorded_rotation
	):
		_push_grenade_snapshot(
			target_position,
			target_rotation
		)

		_last_recorded_position = target_position
		_last_recorded_rotation = target_rotation

	_interpolate_grenade_transform()
func _physics_process(_delta: float) -> void:
	if multiplayer.is_server():
		synced_position = global_position
		synced_rotation = Quaternion(global_basis)
func _push_grenade_snapshot(
	pos: Vector3,
	rot: Quaternion
) -> void:
	var now := float(Time.get_ticks_usec()) / 1_000_000.0

	_grenade_snapshots.append({
		"time": now,
		"position": pos,
		"rotation": rot
	})

	while _grenade_snapshots.size() > MAX_GRENADE_SNAPSHOTS:
		_grenade_snapshots.pop_front()


func _interpolate_grenade_transform() -> void:
	var snapshots := _grenade_snapshots

	if snapshots.size() < 2:
		return

	var render_time := (
		float(Time.get_ticks_usec()) / 1_000_000.0
		- GRENADE_INTERPOLATION_DELAY
	)

	while snapshots.size() > 2:
		var second_time: float = snapshots[1]["time"]

		if second_time >= render_time:
			break

		snapshots.pop_front()

	var first: Dictionary = snapshots[0]

	if render_time <= float(first["time"]):
		global_position = first["position"]
		global_basis = Basis(first["rotation"])
		return

	for i in range(1, snapshots.size()):
		var previous: Dictionary = snapshots[i - 1]
		var next: Dictionary = snapshots[i]

		var time_a: float = previous["time"]
		var time_b: float = next["time"]

		if render_time <= time_b:
			var duration := maxf(time_b - time_a, 0.0001)
			var alpha := clampf(
				(render_time - time_a) / duration,
				0.0,
				1.0
			)

			var pos_a: Vector3 = previous["position"]
			var pos_b: Vector3 = next["position"]

			var rot_a: Quaternion = previous["rotation"]
			var rot_b: Quaternion = next["rotation"]

			global_position = pos_a.lerp(pos_b, alpha)
			global_basis = Basis(rot_a.slerp(rot_b, alpha))
			return

	# Wait at the latest available position instead of overshooting.
	var latest: Dictionary = snapshots.back()
	global_position = latest["position"]
	global_basis = Basis(latest["rotation"])

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
