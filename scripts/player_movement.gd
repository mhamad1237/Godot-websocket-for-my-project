extends CharacterBody3D

# --- Movement constants ---
const WALK_SPEED := 3.0
const SPRINT_SPEED := 6.0
const CROUCH_SPEED := 1.5
const ADS_SPEED:= 1.0
var _prev_pos := Vector3.ZERO

const ACCELERATION := 20.0
@onready var gun_camera : Camera3D = $WeaponViewportContainer/SubViewport/WeaponCamera
var desired_velocity := Vector3.ZERO
@export var landing_smooth_speed := 4.0
var _r_move := Vector2.ZERO
var _r_airborne := false
const STEP_REACH_WALK := 0.045
const STEP_REACH_CROUCH := 0.03
const STEP_REACH_SPRINT := 0.06
const STEP_PROBE := 0.15  # trigger when a riser is within this distance
var STEP_REACH := 0.03  # how far past the riser to land on the tread
const STEP_MARGIN := 0.04
const STEP_MIN_HEIGHT := 0.001
const MAX_STEP_HEIGHT := 0.55
var _r_crouching := false
var _r_sprinting := false
var _r_looped := false
signal respawned
@export var death_sound: AudioStream
const LAND_DECELERATION := 15.0
const AIR_CONTROL := 2.0
const GRAVITY := 20.0
const JUMP_VELOCITY := 6.0
const DEAD_ZONE := 0.15

enum Stance { RIFLE, PISTOL }
var stance: Stance = Stance.PISTOL

@onready var tps_rig:Node3D = $ThirdPersonRig
var camera_base_position: Vector3
@onready var weapon_holder : Node3D = %WeaponHolder
@onready var camera:Camera3D = $CameraPivot/Camera3D
var last_frame_was_on_floor := -INF
@onready var anim_tree : AnimationTree = $ThirdPersonRig/mesh/model/AnimationTree
@onready var collision_standing: CollisionShape3D = $CollisionShape_Standing
@onready var collision_crouching: CollisionShape3D = $CollisionShape_Crouching
@onready var collision_crouch_walking: CollisionShape3D = $CollisionShape_CrouchWalking
@onready var collision_air: CollisionShape3D = $CollisionShape_Air
const STANDING_HEIGHT := 1.708
const CROUCHING_HEIGHT := 1.162
const CROUCH_WALKING_HEIGHT := 1.374
const AIR_HEIGHT := 1.3
const STEP_TREAD_MIN_Y := 0.98  # tread normal must be nearly flat

const COLLISION_BOTTOM := 0.0
@onready var stairs_below_raycast: RayCast3D = $StairsBelowRayCast3D
@onready var stairs_ahead_raycast: RayCast3D = $StairsAheadRayCast3D
signal health_changed(current: float, maximum: float)
signal died(attacker_id: int)

const MAX_DAMAGE_PER_HIT := 150.0   # sanity cap against tampered clients
const RESPAWN_TIME := 3.0
@export var max_health := 100.0
var health := 100.0
var is_dead := false

var is_crouching := false
var is_sprinting := false
var is_moving := false
var is_airborne := false
var is_landing := false
var has_switched_to_jump_loop := false
var current_crouch_mode := ""
var snapped_to_stairs_last_frame := false
@onready var camera_pivot :Node3D = $CameraPivot
@export_group("Head Bob")
@export var head_bob_enabled: bool = true
@export var head_bob_walk_speed: float = 8.0
@export var head_bob_sprint_speed: float = 11.0
@export var head_bob_walk_amount: Vector2 = Vector2(0.0, 0.085)
@export var head_bob_sprint_amount: Vector2 = Vector2(0.0, 0.14)
@export var head_bob_smooth: float = 12.0
var landing_offset_y: float = 0.0
var head_bob_timer: float = 0.0
var head_bob_offset: Vector3 = Vector3.ZERO
var head_bob_base_position: Vector3

var was_airborne: bool = false
@export_group("CameraRecoil")
var recoil_up: float = 0.0
var recoil_side: float = 0.0
var current_recoil_up: float = 0.0
var current_recoil_side: float = 0.0
var previous_recoil_up_applied: float = 0.0
var previous_recoil_side_applied: float = 0.0
var active_recoil_snap_speed: float = 25.0
var active_recoil_decay_speed: float = 6.0
@export var sync_move := Vector2.ZERO      # movement input (x, -y), same as blend_position
@export var sync_sprinting := false
@export var sync_crouching := false
@export var sync_airborne := false
var sync_falling := false

var _state_sync_timer := 0.0
const STATE_SYNC_INTERVAL := 0.05 # 20 updates per second

var current_collision_mode := ""
func _ready() -> void:
	_apply_stance_to_tree()
	floor_snap_length = MAX_STEP_HEIGHT
	if is_multiplayer_authority():
		Global.player = self
		camera.current = true
		head_bob_base_position = camera_pivot.position
		NetworkManager.notify_local_player_ready()
		tps_rig.hide()
		health = max_health
		get_tree().call_group("hud", "bind_player", self)
		call_deferred("_init_walking_animation")

	else:
		camera.current = false
		weapon_holder.hide()
		set_physics_process(false)
		call_deferred("_init_walking_animation")
	set_collision("standing")
func _exit_tree() -> void:
	if Global.player == self:
		Global.player = null

func _init_walking_animation() -> void:
	var locomotion_playback: AnimationNodeStateMachinePlayback = _loco_playback()
	if locomotion_playback:
		locomotion_playback.travel("walking")
func _apply_stance_to_tree() -> void:
	anim_tree.set(
		"parameters/WeaponTransition/transition_request",
		"pistol" if stance == Stance.PISTOL else "rifle"
	)
func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		_remote_anim(delta)
		return

	# Send this player's animation state to the other peers.
	_state_sync_timer += delta

	if _state_sync_timer >= STATE_SYNC_INTERVAL:
		_state_sync_timer = 0.0

		if multiplayer.has_multiplayer_peer():
			receive_remote_anim_state.rpc(
				sync_move,
				is_sprinting,
				is_crouching,
				is_airborne or is_landing,
				is_airborne and velocity.y < 0.0,
				current_collision_mode
			)

	landing_offset_y = move_toward(
		landing_offset_y,
		0.0,
		landing_smooth_speed * delta
	)

	if absf(landing_offset_y) < 0.0005:
		landing_offset_y = 0.0

	_set_pivot_position()
	update_cam_recoil(delta)
func _loco_name() -> String:
	return "LocoPistol" if stance == Stance.PISTOL else "LocoRifle"

func _lp(sub: String) -> String:
	return "parameters/%s/%s" % [_loco_name(), sub]

func _loco_playback() -> AnimationNodeStateMachinePlayback:
	return anim_tree.get(_lp("playback"))

# The pistol crouching state is a BlendTree, so its blend path is one level deeper
func _crouch_blend_path() -> String:
	if stance == Stance.PISTOL:
		return _lp("crouching/CrouchLegs/blend_position")
	return _lp("crouching/blend_position")

func set_stance(new_stance: Stance) -> void:
	if new_stance == stance:
		return
	stance = new_stance
	anim_tree.set(
		"parameters/WeaponTransition/transition_request",
		"pistol" if stance == Stance.PISTOL else "rifle"
	)
	# Put the newly active state machine in the matching state
	var state := "walking"
	if sync_crouching:
		state = "crouching"
	elif sync_sprinting:
		state = "sprinting"
	var pb := _loco_playback()
	if pb:
		pb.start(state)
@rpc("authority", "call_remote", "unreliable_ordered")
func receive_remote_anim_state(
	move: Vector2,
	sprinting: bool,
	crouching: bool,
	airborne: bool,
	falling: bool,
	collision_mode: String
) -> void:
	sync_move = move
	sync_sprinting = sprinting
	sync_crouching = crouching
	sync_airborne = airborne
	sync_falling = falling

	# Also acts as a fallback for the initial collision state.
	if collision_mode != current_collision_mode:
		set_collision(collision_mode)
func _remote_anim(delta: float) -> void:
	var loco: AnimationNodeStateMachinePlayback = _loco_playback()
	var jump: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/Jumping/playback")
	if not loco:
		return
	_r_move = _r_move.lerp(sync_move, 12.0 * delta)

	# Air / landing
	if sync_airborne != _r_airborne:
		_r_airborne = sync_airborne
		_r_looped = false
		var tw := create_tween()
		if sync_airborne:
			tw.tween_property(anim_tree, "parameters/JumpBlend/blend_amount", 1.0, 0.15)
			if jump: jump.travel("JumpStart")
		else:
			if jump: jump.travel("Land")
			tw.tween_interval(0.4)
			tw.tween_property(anim_tree, "parameters/JumpBlend/blend_amount", 0.0, 0.15)
	if _r_airborne and not _r_looped and sync_falling:
		_r_looped = true
		if jump: jump.travel("JumpLoop")

	# Crouch
	if sync_crouching != _r_crouching:
		_r_crouching = sync_crouching
		var tw2 := create_tween()
		tw2.tween_property(anim_tree, "parameters/SpineHipLock/blend_amount", 0.7 if sync_crouching else 0.0, 0.2)
		loco.travel("crouching" if sync_crouching else "walking")
		_r_sprinting = false

	# Sprint
	if not sync_crouching and sync_sprinting != _r_sprinting:
		_r_sprinting = sync_sprinting
		loco.travel("sprinting" if sync_sprinting else "walking")

	# Blend positions and speed (same math as the authority)
	var len := _r_move.length()
	if sync_crouching:
		anim_tree.set(_crouch_blend_path(), _r_move)
		anim_tree.set("parameters/Locomotion_TimeScale/scale", 1.0 if len < 0.01 else clampf(len, 0.3, 1.0))
	elif sync_sprinting:
		var angle := atan2(_r_move.x, _r_move.y)
		anim_tree.set(_lp("sprinting/blend_position"), clampf(angle / deg_to_rad(60), -1.0, 1.0))
	else:
		anim_tree.set(_lp("walking/blend_position"), _r_move)
		anim_tree.set("parameters/Locomotion_TimeScale/scale", remap(clampf(len, 0.0, 1.0), 0.0, 1.0, 0.6, 1.0))
	
func update_cam_recoil(delta: float) -> void:
	current_recoil_up = lerp(current_recoil_up, recoil_up, active_recoil_snap_speed * delta)
	current_recoil_side = lerp(current_recoil_side, recoil_side, active_recoil_snap_speed * delta)

	camera.rotation.x += deg_to_rad(current_recoil_up - previous_recoil_up_applied)
	camera.rotation.y += deg_to_rad(current_recoil_side - previous_recoil_side_applied)
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	previous_recoil_up_applied = current_recoil_up
	previous_recoil_side_applied = current_recoil_side
func _physics_process(delta: float) -> void:
	if is_on_floor():
		last_frame_was_on_floor = Engine.get_physics_frames()

	desired_velocity = Vector3.ZERO
	var raw_input := get_dead_zoned_input()
	var input_length := raw_input.length()
	is_moving = raw_input != Vector2.ZERO
	var blocks_sprint: bool = (Global.weapon_holder != null and Global.weapon_holder.current_weapon != null and (Global.weapon_holder.is_firing or Global.weapon_holder.is_reloading)) or is_airborne or (weapon_holder.is_ads)
	sync_move = Vector2(raw_input.x, -raw_input.y)
	sync_sprinting = is_sprinting
	sync_crouching = is_crouching
	sync_airborne = is_airborne or is_landing
	if is_landing:
		process_landing(delta)
		return

	if is_airborne:
		process_airborne(delta, raw_input)
		return

	if not is_on_floor() and not snapped_to_stairs_last_frame \
		and Engine.get_physics_frames() - last_frame_was_on_floor > 3:
		enter_air()
		return

	if Input.is_action_just_pressed("jump") and not is_crouching:
		try_jump()
		return

	if Input.is_action_just_pressed("crouch"):
		is_crouching = not is_crouching
		update_crouch_visuals()

	var target_y = 1.0 if is_crouching else 1.513
	camera.position.y = lerp(camera.position.y, target_y, 10.0 * delta)

	if is_crouching:
		process_crouch(delta, raw_input, input_length)
		return

	update_sprint_state(raw_input, input_length, blocks_sprint)

	if not is_moving:
		if not is_sprinting:
			var loco: AnimationNodeStateMachinePlayback = \
				_loco_playback()
			if loco and loco.get_current_node() != "walking":
				loco.travel("walking")
			anim_tree.set(_lp("walking/blend_position"), Vector2.ZERO)
			anim_tree.set("parameters/Locomotion_TimeScale/scale", 0.6)

		apply_horizontal_velocity(Vector3.ZERO, ACCELERATION, delta)
		_slide_clamped(delta)
		snap_down_to_stairs()
		return

	if is_sprinting:
		process_sprint(raw_input)
	else:
		process_walk(raw_input, input_length)

	if snap_up_to_stairs(delta):
		return

	update_head_bob(delta)
	_slide_clamped(delta)
	snap_down_to_stairs()
func _slide_clamped(delta: float) -> void:
	var before := global_position
	var limit := Vector2(velocity.x, velocity.z).length() * delta * 1.1 + 0.002
	move_and_slide()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z)
	if moved.length() > limit:
		var capped := moved.normalized() * limit
		global_position.x = before.x + capped.x
		global_position.z = before.z + capped.y


# ---------------------------------------------------------
# Input helper
# ---------------------------------------------------------
func get_dead_zoned_input() -> Vector2:
	var raw_input: Vector2 = Global.joystick.output
	var input_length := raw_input.length()
	if input_length < DEAD_ZONE:
		return Vector2.ZERO
	input_length = remap(input_length, DEAD_ZONE, 1.0, 0.0, 1.0)
	return raw_input.normalized() * input_length


# ---------------------------------------------------------
# Shared velocity helper - replaces repeated move_toward pairs
# ---------------------------------------------------------
func apply_horizontal_velocity(target: Vector3, accel: float, delta: float) -> void:
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)


func world_direction(raw_input: Vector2) -> Vector3:
	var input_dir := Vector3(raw_input.x, 0, raw_input.y)
	return (global_transform.basis * input_dir).normalized()


# ---------------------------------------------------------
# Landing / Air
# ---------------------------------------------------------
func process_landing(delta: float) -> void:
	apply_horizontal_velocity(Vector3.ZERO, LAND_DECELERATION, delta)
	_slide_clamped(delta)
	if is_moving:
		snap_up_to_stairs(delta)

	update_head_bob(delta)

	var jump_playback: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/Jumping/playback")

	if jump_playback:
		var play_pos := jump_playback.get_current_play_position()
		var anim_len := jump_playback.get_current_length()
		var current_node := jump_playback.get_current_node()

		if current_node != "Land" or (anim_len > 0.0 and play_pos >= anim_len - 0.05):
			is_landing = false
			is_airborne = false
			reset_jump_blend()
func process_airborne(delta: float, raw_input: Vector2) -> void:
	velocity.y -= GRAVITY * delta

	var jump_playback: AnimationNodeStateMachinePlayback = anim_tree.get(
		"parameters/Jumping/playback"
	)

	if not has_switched_to_jump_loop and velocity.y < 0.0:
		has_switched_to_jump_loop = true

		if jump_playback:
			jump_playback.travel("JumpLoop")

	var direction := world_direction(raw_input)
	apply_horizontal_velocity(direction * AIR_CONTROL, 5.0, delta)



	_slide_clamped(delta)

	update_head_bob(delta)

	if is_on_floor() and velocity.y <= 0.0:
		is_landing = true
		is_airborne = false
		set_collision("standing")
func has_valid_landing_surface() -> bool:
	if not stairs_below_raycast.is_colliding():
		return false

	var hit_point := stairs_below_raycast.get_collision_point()
	var distance := global_position.y - hit_point.y

	return distance >= 0.0 and distance <= 0.15
func enter_air() -> void:
	is_airborne = true
	is_landing = false
	has_switched_to_jump_loop = false

	set_collision("air")

	var tween := create_tween()
	tween.tween_property(
		anim_tree,
		"parameters/JumpBlend/blend_amount",
		1.0,
		0.15
	)

	var jump_playback: AnimationNodeStateMachinePlayback = anim_tree.get(
		"parameters/Jumping/playback"
	)

	if jump_playback:
		jump_playback.travel("JumpStart")
func _set_pivot_position() -> void:
	camera_pivot.position = head_bob_base_position + head_bob_offset + Vector3(0.0, landing_offset_y, 0.0)
	
func try_jump() -> void:
	if is_on_floor() or snapped_to_stairs_last_frame:
		velocity.y = JUMP_VELOCITY
		snapped_to_stairs_last_frame = false
		enter_air()
		
func confirm_landing() -> void:
	if is_landing:
		return

	is_landing = true
	is_airborne = false
	set_collision("standing")
# ---------------------------------------------------------
# Crouch
# ---------------------------------------------------------
func process_crouch(delta: float, raw_input: Vector2, input_length: float) -> void:
	var target_mode := "crouch_walking" if raw_input.length() > DEAD_ZONE else "crouching"
	if target_mode != current_crouch_mode:
		current_crouch_mode = target_mode
		set_collision(target_mode)

	var move_input := Vector2(raw_input.x, -raw_input.y)
	anim_tree.set(_crouch_blend_path(), move_input)
	var time_scale := 1.0 if input_length == 0.0 else clampf(input_length, 0.3, 1.0)
	anim_tree.set("parameters/Locomotion_TimeScale/scale", time_scale)

	var direction := world_direction(raw_input)
	var base_speed := ADS_SPEED if weapon_holder.is_ads else CROUCH_SPEED
	var current_speed := base_speed * clampf(input_length, 0.0, 1.0)
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed
	desired_velocity = direction * current_speed
	if snap_up_to_stairs(delta):
		return

	_slide_clamped(delta)
	snap_down_to_stairs()
	
func update_crouch_visuals() -> void:
	var spine_target := 0.7 if is_crouching else 0.0
	var tween := create_tween()
	tween.tween_property(anim_tree, "parameters/SpineHipLock/blend_amount", spine_target, 0.2)

	var locomotion_playback: AnimationNodeStateMachinePlayback = _loco_playback()
	if locomotion_playback:
		locomotion_playback.travel("crouching" if is_crouching else "walking")

	if is_crouching:
		anim_tree.set("parameters/JumpBlend/blend_amount", 0.0)
		current_crouch_mode = ""
		set_collision("crouching")
	else:
		set_collision("standing")


# ---------------------------------------------------------
# Sprint / Walk
# ---------------------------------------------------------
func update_sprint_state(
	raw_input: Vector2,
	input_length: float,
	blocks_sprint: bool
) -> void:
	var angle := atan2(raw_input.x, -raw_input.y)

	# Only allow:
	# Forward        = 0°
	# Forward-left   = negative angle
	# Forward-right  = positive angle
	var wants_to_sprint: bool = (
		not blocks_sprint
		and input_length > 0.75
		and Input.is_action_pressed("sprint")
		and abs(angle) < deg_to_rad(60)
	)

	if is_sprinting and (
		blocks_sprint
		or input_length <= 0.75
		or not Input.is_action_pressed("sprint")
		or abs(angle) >= deg_to_rad(60)
	):
		is_sprinting = false
		Input.action_release("sprint") #bc it's toggle sprinting
		set_locomotion_anim( "walking")

	elif not is_sprinting and wants_to_sprint:
		is_sprinting = true
		set_locomotion_anim("sprinting")
		
func process_sprint( raw_input: Vector2) -> void:
	anim_tree.set("parameters/JumpBlend/blend_amount", 0.0)

	var angle := atan2(raw_input.x, -raw_input.y)
	var blend_x := clampf(angle / deg_to_rad(60), -1.0, 1.0)
	anim_tree.set(_lp("sprinting/blend_position"), blend_x)
	
	var direction := world_direction(raw_input)
	desired_velocity = direction * SPRINT_SPEED
	apply_horizontal_velocity(
		direction * SPRINT_SPEED,
		ACCELERATION,
		get_physics_process_delta_time()
	)
	
func process_walk( raw_input: Vector2, input_length: float) -> void:
	var locomotion_playback: AnimationNodeStateMachinePlayback = _loco_playback()

	if locomotion_playback:
		if locomotion_playback.get_current_node() != "walking":
			locomotion_playback.travel("walking")

	anim_tree.set("parameters/JumpBlend/blend_amount", 0.0)

	var move_input := Vector2(raw_input.x, -raw_input.y)
	anim_tree.set(_lp("walking/blend_position"), move_input)

	var time_scale := remap(
		clampf(input_length, 0.0, 1.0),
		0.0,
		1.0,
		0.6,
		1.0
	)

	anim_tree.set("parameters/Locomotion_TimeScale/scale", time_scale)

	var direction := world_direction(raw_input)
	var base_speed := ADS_SPEED if weapon_holder.is_ads else WALK_SPEED
	var target_speed := base_speed * clampf(input_length, 0.0, 1.0)
	desired_velocity = direction * target_speed
	apply_horizontal_velocity(
		direction * target_speed,
		ACCELERATION,
		get_physics_process_delta_time()
	)

func set_locomotion_anim(anim_name: String) -> void:
	var locomotion_playback: AnimationNodeStateMachinePlayback = _loco_playback()
	if locomotion_playback:
		locomotion_playback.travel(anim_name)
	var spine_tween := create_tween()
	spine_tween.tween_property(anim_tree, "parameters/SpineHipLock/blend_amount", 0.0, 0.2)
	
func update_head_bob(delta: float) -> void:
	if not head_bob_enabled:
		return

	if not is_on_floor() or is_crouching:
		head_bob_timer = 0.0
		head_bob_offset = head_bob_offset.lerp(
			Vector3.ZERO,
			head_bob_smooth * delta
		)

		_set_pivot_position()
		return

	if not is_moving:
		head_bob_timer = 0.0

		head_bob_offset = head_bob_offset.lerp(
			Vector3.ZERO,
			head_bob_smooth * delta
		)

		_set_pivot_position()
		return

	var bob_speed := head_bob_sprint_speed if is_sprinting else head_bob_walk_speed
	var bob_amount := head_bob_sprint_amount if is_sprinting else head_bob_walk_amount

	if weapon_holder.is_ads:
		bob_speed *= 0.5
		bob_amount *= 0.8
	head_bob_timer += delta * bob_speed

	# Side-to-side movement
	var x := cos(head_bob_timer) * bob_amount.x

	# Up/down movement
	var y : float= abs(sin(head_bob_timer)) * bob_amount.y

	var target_offset := Vector3(x, y, 0.0)

	head_bob_offset = head_bob_offset.lerp(
		target_offset,
		head_bob_smooth * delta
	)

	_set_pivot_position()

func reset_jump_blend() -> void:
	var tween := create_tween()
	tween.tween_property(
		anim_tree,
		"parameters/JumpBlend/blend_amount",
		0.0,
		0.15
	)

# ---------------------------------------------------------
# Collision
# ---------------------------------------------------------
func set_collision(mode: String) -> void:
	if mode not in ["standing", "crouching", "crouch_walking", "air"]:
		push_warning("Invalid collision mode: " + mode)
		return

	var changed := current_collision_mode != mode

	collision_standing.disabled = mode != "standing"
	collision_crouching.disabled = mode != "crouching"
	collision_crouch_walking.disabled = mode != "crouch_walking"
	collision_air.disabled = mode != "air"

	current_collision_mode = mode

	# Only the player who owns this character broadcasts its changes.
	if changed and is_multiplayer_authority() \
	and multiplayer.has_multiplayer_peer():
		sync_collision_mode.rpc(mode)


@rpc("authority", "call_remote", "reliable")
func sync_collision_mode(mode: String) -> void:
	if mode != current_collision_mode:
		set_collision(mode)
func is_surface_too_steep(normal: Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > floor_max_angle

# ---------------------------------------------------------
# Stairs
# ---------------------------------------------------------
func snap_down_to_stairs() -> void:
	var did_snap := false

	stairs_below_raycast.force_raycast_update()

	var floor_below: bool = (
		stairs_below_raycast.is_colliding()
		and not is_surface_too_steep(
			stairs_below_raycast.get_collision_normal()
		)
	)

	var was_on_floor_last_frame := (
		Engine.get_physics_frames() == last_frame_was_on_floor
	)

	if (
		not is_on_floor()
		and velocity.y <= 0.0
		and (was_on_floor_last_frame or snapped_to_stairs_last_frame)
		and floor_below
	):
		var body_test_result := KinematicCollision3D.new()

		if test_move(
			global_transform,
			Vector3(0.0, -MAX_STEP_HEIGHT, 0.0),
			body_test_result
		):
			var translate_y := body_test_result.get_travel().y

			position.y += translate_y

			apply_floor_snap()
			did_snap = true

	snapped_to_stairs_last_frame = did_snap
func snap_up_to_stairs(delta: float) -> bool:
	if not is_on_floor() and not snapped_to_stairs_last_frame:
		return false
	if velocity.y > 0.0:
		return false

	var flat := Vector3(desired_velocity.x, 0.0, desired_velocity.z)
	if flat.length_squared() < 0.0001:
		return false
	var direction := flat.normalized()
	var body_transform := global_transform

	var block := KinematicCollision3D.new()
	if not test_move(body_transform, direction * STEP_PROBE, block):
		return false
	var reach := STEP_REACH_WALK
	if is_sprinting:
		reach = STEP_REACH_SPRINT
	elif is_crouching:
		reach = STEP_REACH_CROUCH
	var forward := direction * (block.get_travel().length() + reach)

	var lift := Vector3.UP * (MAX_STEP_HEIGHT + STEP_MARGIN)
	var ceiling_hit := KinematicCollision3D.new()
	if test_move(body_transform, lift, ceiling_hit):
		lift = ceiling_hit.get_travel()
		if lift.y < STEP_MIN_HEIGHT:
			return false
	var raised_transform := body_transform.translated(lift)

	if test_move(raised_transform, forward):
		return false
	raised_transform.origin += forward

	var down_hit := KinematicCollision3D.new()
	if not test_move(raised_transform, Vector3.DOWN * (lift.y + STEP_MARGIN), down_hit):
		return false

	var tread_probe := down_hit.get_position() + direction * 0.03
	var tread_query := PhysicsRayQueryParameters3D.create(
		tread_probe + Vector3.UP * 0.3,
		tread_probe + Vector3.DOWN * 0.1
	)
	tread_query.exclude = [get_rid()]
	var tread := get_world_3d().direct_space_state.intersect_ray(tread_query)
	if tread.is_empty() or tread.normal.y < STEP_TREAD_MIN_Y:
		return false

	var step_height := raised_transform.origin.y + down_hit.get_travel().y - global_position.y
	if step_height < STEP_MIN_HEIGHT or step_height > MAX_STEP_HEIGHT:
		return false

	var final_transform := raised_transform.translated(down_hit.get_travel())
	if step_height < 0.02:
		var max_move := flat.length() * delta + 0.005
		if forward.length() > max_move:
			final_transform.origin -= direction * (forward.length() - max_move)
	var max_hop := flat.length() * delta * 2.0 + 0.04
	if forward.length() > max_hop:
		raised_transform.origin -= direction * (forward.length() - max_hop)
	global_transform = final_transform
	velocity.y = 0.0
	snapped_to_stairs_last_frame = true
	landing_offset_y = -step_height
	return true

func apply_cam_recoil(up_amount: float, side_amount: float, snap_speed: float, decay_speed: float) -> void:
	var recoil_multiplier := 1.0
	if is_crouching:
		recoil_multiplier *= 0.6
	if weapon_holder.is_ads:
		recoil_multiplier *= 0.5

	recoil_up += up_amount * recoil_multiplier
	recoil_side += randf_range(-side_amount, side_amount) * recoil_multiplier
	active_recoil_snap_speed = snap_speed
	active_recoil_decay_speed = decay_speed
@rpc("authority", "call_local", "reliable")
func sync_scope(index: int) -> void:
	tps_rig.equip_tps_scope(index)
@rpc("authority", "call_local", "reliable")
func sync_weapon(weapon_name: String, weapon_type: String) -> void:
	print("sync_weapon: ", weapon_name, " | type=", weapon_type, " | stance before=", stance)

	tps_rig.equip_tps_weapon(TpWeaponPaths.get_data(weapon_name))
	var new_stance := Stance.PISTOL if weapon_type.to_lower() == "pistol" else Stance.RIFLE
	set_stance(new_stance)
@rpc("authority", "call_remote", "unreliable")
func sync_muzzle_flash() -> void:
	tps_rig.play_muzzle_flash()
func take_damage(amount: float) -> void:
	if is_dead or is_multiplayer_authority():
		return  # dead, or you shot yourself
	if multiplayer.is_server():
		_server_apply_damage(amount, multiplayer.get_unique_id())
	else:
		_request_damage.rpc_id(1, amount)


@rpc("any_peer", "call_remote", "reliable")
func _request_damage(amount: float) -> void:
	if not multiplayer.is_server():
		return
	_server_apply_damage(amount, multiplayer.get_remote_sender_id())


func _server_apply_damage(amount: float, attacker_id: int) -> void:
	if is_dead or attacker_id == get_multiplayer_authority():
		return
	health = maxf(health - clampf(amount, 0.0, MAX_DAMAGE_PER_HIT), 0.0)
	_apply_health.rpc(health, attacker_id)


# Server -> everyone (including itself)
@rpc("any_peer", "call_local", "reliable")
func _apply_health(new_health: float, attacker_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 1 and sender != 0:
		return  # only the server may set health
	health = new_health
	health_changed.emit(health, max_health)
	if health <= 0.0 and not is_dead:
		_die(attacker_id)
func _die(attacker_id: int) -> void:
	is_dead = true
	died.emit(attacker_id)
	_play_death_sound()

	# Disable every collision shape on every peer.
	collision_standing.disabled = true
	collision_crouching.disabled = true
	collision_crouch_walking.disabled = true
	collision_air.disabled = true
	current_collision_mode = ""

	if is_multiplayer_authority():
		set_physics_process(false)
		weapon_holder.hide()

		# Back to standing state now, so respawn doesn't start crouched
		is_crouching = false
		is_sprinting = false
		current_crouch_mode = ""

		# Physics is off, so these must be set by hand or remote copies keep the crouch pose
		sync_crouching = false
		sync_sprinting = false
		sync_airborne = false
		sync_move = Vector2.ZERO

		var tw := create_tween()
		tw.tween_property(
			anim_tree,
			"parameters/SpineHipLock/blend_amount",
			0.0,
			0.2
		)

		anim_tree.set("parameters/JumpBlend/blend_amount", 0.0)

		var loco: AnimationNodeStateMachinePlayback = anim_tree.get(
			"parameters/Locomotion/playback"
		)

		if loco:
			loco.travel("walking")
	if not is_multiplayer_authority():
		tps_rig.hide()

	if multiplayer.is_server():
		await get_tree().create_timer(RESPAWN_TIME).timeout

		var points := get_tree().get_nodes_in_group("spawn_points")
		var pos := Vector3.ZERO

		if points.size() > 0:
			pos = (points.pick_random() as Node3D).global_position

		_respawn.rpc(pos)


func _play_death_sound() -> void:
	if death_sound == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = death_sound
	p.max_distance = 60.0
	get_tree().current_scene.add_child(p)   # not a child of the player, so it never cuts off
	p.global_position = global_position
	p.finished.connect(p.queue_free)
	p.play()
@rpc("any_peer", "call_local", "reliable")
func _respawn(pos: Vector3) -> void:
	var sender := multiplayer.get_remote_sender_id()

	if sender != 1 and sender != 0:
		return

	is_dead = false
	health = max_health
	global_position = pos
	velocity = Vector3.ZERO

	# Re-enable only the standing collision shape.
	set_collision("standing")
	if not is_multiplayer_authority():
		tps_rig.show()

	health_changed.emit(health, max_health)
	respawned.emit()

	if is_multiplayer_authority():
		set_physics_process(true)
		weapon_holder.show()

		snapped_to_stairs_last_frame = false

		camera.position.y = 1.513

		# Gravity applies right away.
		enter_air()
