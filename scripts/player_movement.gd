extends CharacterBody3D

# --- Movement constants ---
const WALK_SPEED := 3.0
const SPRINT_SPEED := 6.0
const CROUCH_SPEED := 1.5
var _idle_frames : int = 0
var target_position: Vector3 = Vector3.ZERO   # <--- Add this variable near the top with other vars

const GRENADE_EXPLOSION = preload(
	"res://scenes/explosion.tscn"
)
var _has_triggered_start_step : bool = false
const GRENADE_SHOT := "parameters/GrenadeShot/request"
const GRENADE_FUSE := 3.5            # seconds from the moment you start cooking
const GRENADE_FP_PAUSE_TIME := 0.15  # seconds into the FP grenade_throw
const GRENADE_TP_PAUSE_TIME := 0.83   # seconds into the TP throw
const GRENADE_THROW_SPEED := 12.0
const GRENADE_RELEASE_TIME := 0.2    # seconds into the FP throw when it leaves the hand
var _fp_held := false
var _tp_held := false
@onready var grenade_label: Label = get_node_or_null("GrenadeLabel")
var _throwing := false
var _throw_id := 0   # changes when a throw is cancelled (death)

var fade_speed : float = 40.0  # Speed of the volume fade per second

const ADS_SPEED:= 1.0
@onready var respawn_label: Label = $RespawnLabel
const ACCELERATION := 20.0
const FOOTSTEP_DIR := "res://sounds/footsteps/"
const FOOTSTEP_STRIDE_WALK := 1.4     # metres between steps
const FOOTSTEP_STRIDE_SPRINT := 2.2
var _footsteps: Array[AudioStream] = []
var _step_players: Array[AudioStreamPlayer3D] = []
var _step_toggle := 0
var _step_dist := 0.0
var _last_step_idx := -1
var _prev_step_pos := Vector3.ZERO
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
const STATE_SYNC_INTERVAL := 0.033
@onready var loadout_button: Button = $RespawnContainer/LoadoutButton
var _loadout_layer: CanvasLayer = null
@onready var respawn_container: Control = $RespawnContainer
@onready var respawn_button: Button = $RespawnContainer/RespawnButton
var _death_time_ms := 0
var current_collision_mode := ""
@export_category("LAND KICK TUNING")
const LAND_KICK_MIN_SPEED := 4.0    # slower landings do nothing
const LAND_KICK_MAX_SPEED := 16.0   # speed that gives the biggest kick
const LAND_KICK_MIN := 0.04         # camera dip at the minimum speed
const LAND_KICK_MAX := 0.3          # camera dip at the maximum speed
var land_kick_y := 0.0
var _fall_speed := 0.0
var _land_tween: Tween
var _weapon_tween: Tween
const AIR_FLOAT_JUMP := 0.02   # weapon lift when jumping
const AIR_FLOAT_FALL := 0.03   # weapon lift when falling off a ledge
func _ready() -> void:
	if not NetworkManager.dedicated:   # the headless server needs no audio
		_load_footsteps()
		for n in 2:   # two players so a step's tail isn't cut off by the next one
			var p := AudioStreamPlayer3D.new()
			p.max_distance = 25.0
			p.unit_size = 4.0
			add_child(p)
			_step_players.append(p)
		_prev_step_pos = global_position
	_apply_stance_to_tree()
	respawn_container.hide()
	respawn_label.hide()   # hidden on every peer, including remote copies
	floor_snap_length = MAX_STEP_HEIGHT
	if is_multiplayer_authority():
		target_position = global_position
		if NetworkManager.offline:
			_add_debug_kill_button()
		loadout_button.pressed.connect(_on_loadout_pressed)
		respawn_button.pressed.connect(_on_respawn_pressed)
		Global.player = self
		camera.current = true
		head_bob_base_position = camera_pivot.position
		NetworkManager.notify_local_player_ready()
		tps_rig.hide()
		health = max_health
		get_tree().call_group("hud", "bind_player", self)
		call_deferred("_init_walking_animation")
	else:
		target_position = global_position
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
func _add_debug_kill_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var b := Button.new()
	b.text = "KILL ME"
	b.position = Vector2(20, 120)
	b.custom_minimum_size = Vector2(160, 70)
	b.pressed.connect(func() -> void:
		if not is_dead:
			_server_apply_damage(MAX_DAMAGE_PER_HIT, 0))
	layer.add_child(b)

func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		_remote_anim(delta)
		
		# --- Smoothly interpolate remote player position ---
		global_position = global_position.lerp(target_position, delta * 20.0)
		return
	_update_footsteps()

	if is_moving:
		# Mute them completely when moving
		$Breathing.volume_db = move_toward($Breathing.volume_db, -50, fade_speed * delta)
		$Wind.volume_db = move_toward($Wind.volume_db, -80, fade_speed * delta)
	else:
		# Very faint, whisper-quiet background levels when idle
		$Breathing.volume_db = move_toward($Breathing.volume_db, -45.0, fade_speed * delta)
		$Wind.volume_db = move_toward($Wind.volume_db, -40.0, fade_speed * delta)
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
				current_collision_mode,
				global_position   # <--- Pass global_position here
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
	collision_mode: String,
	pos: Vector3   # <--- Added parameter
) -> void:
	sync_move = move
	sync_sprinting = sprinting
	sync_crouching = crouching
	sync_airborne = airborne
	sync_falling = falling
	target_position = pos   # <--- Update interpolation target

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
	if Input.is_action_just_pressed("throw_grenade"):
		_try_throw_grenade()

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
	_fall_speed = maxf(-velocity.y, 0.0)


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
		_land_kick(_fall_speed)
func _air_weapon_float(jumping: bool) -> void:
	if not weapon_holder:
		return
	if _weapon_tween:
		_weapon_tween.kill()
	_weapon_tween = create_tween()
	var amount := AIR_FLOAT_JUMP if jumping else AIR_FLOAT_FALL
	var time := 0.15 if jumping else 0.35
	_weapon_tween.tween_property(weapon_holder, "land_kick_y", amount, time) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
func _land_kick(speed: float) -> void:
	var kick := 0.0
	if speed >= LAND_KICK_MIN_SPEED:
		var t := clampf(inverse_lerp(LAND_KICK_MIN_SPEED, LAND_KICK_MAX_SPEED, speed), 0.0, 1.0)
		kick = lerpf(LAND_KICK_MIN, LAND_KICK_MAX, t)

		# Camera: quick dip, slower recovery
		if _land_tween:
			_land_tween.kill()
		_land_tween = create_tween()
		_land_tween.tween_property(self, "land_kick_y", -kick, 0.07) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_land_tween.tween_property(self, "land_kick_y", 0.0, 0.35) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)

	# Weapon: always settles back from the air float, dips only on a real landing
	if weapon_holder:
		if _weapon_tween:
			_weapon_tween.kill()
		_weapon_tween = create_tween()
		if kick > 0.0:
			_weapon_tween.tween_property(weapon_holder, "land_kick_y", -kick * 0.5, 0.12) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_weapon_tween.tween_property(weapon_holder, "land_kick_y", 0.0, 0.35) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
func has_valid_landing_surface() -> bool:
	if not stairs_below_raycast.is_colliding():
		return false

	var hit_point := stairs_below_raycast.get_collision_point()
	var distance := global_position.y - hit_point.y

	return distance >= 0.0 and distance <= 0.15
func enter_air() -> void:
	# Jumping or falling cancels sprint (sprint is a toggle)
	if is_sprinting:
		is_sprinting = false
	Input.action_release("sprint")
	_air_weapon_float(velocity.y > 0)
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
	camera_pivot.position = head_bob_base_position + head_bob_offset + Vector3(0.0, landing_offset_y + land_kick_y, 0.0)
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
func play_grenade_tp() -> void:
	anim_tree.set(GRENADE_SHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


@rpc("authority", "call_remote", "reliable")
func sync_grenade_throw() -> void:
	play_grenade_tp()

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
	_death_time_ms = Time.get_ticks_msec()
	died.emit(attacker_id)
	_play_death_sound()

	collision_standing.disabled = true
	collision_crouching.disabled = true
	collision_crouch_walking.disabled = true
	collision_air.disabled = true
	current_collision_mode = ""

	if is_multiplayer_authority():
		tps_rig.skeletonIK.start()
		set_physics_process(false)
		weapon_holder.hide()
		weapon_holder.reset_grenade_fp()
		is_crouching = false
		_throwing = false
		_throw_id += 1
		_fp_held = false
		_tp_held = false
		set_grenade_tp_hold(false)
		anim_tree.set("parameters/GrenadeShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		if grenade_label:
			grenade_label.hide()
		is_sprinting = false
		current_crouch_mode = ""
		sync_crouching = false
		sync_sprinting = false
		sync_airborne = false
		sync_move = Vector2.ZERO

		var tw := create_tween()
		tw.tween_property(anim_tree, "parameters/SpineHipLock/blend_amount", 0.0, 0.2)
		anim_tree.set("parameters/JumpBlend/blend_amount", 0.0)
		var loco := _loco_playback()
		if loco:
			loco.travel("walking")
	else:
		tps_rig.hide()

	# Owner sees a countdown, then gets the buttons
	if is_multiplayer_authority():
		weapon_holder.hide_grenade_arms()
		var end_ms := _death_time_ms + int(RESPAWN_TIME * 1000.0)
		respawn_label.show()
		while is_dead and is_inside_tree():
			var left := (end_ms - Time.get_ticks_msec()) / 1000.0
			if left <= 0.0:
				break
			respawn_label.text = "Respawn in %d" % ceili(left)
			await get_tree().process_frame
		respawn_label.hide()
		if not is_inside_tree() or not is_dead:
			return
		respawn_button.disabled = false
		respawn_container.show()


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

func _on_respawn_pressed() -> void:
	if not is_dead:
		return
	respawn_button.disabled = true
	if multiplayer.is_server():
		_server_do_respawn()
	else:
		_request_respawn.rpc_id(1)
		await get_tree().create_timer(2.0).timeout
		if is_dead and is_inside_tree():
			respawn_button.disabled = false   # no answer, allow another try


@rpc("any_peer", "call_remote", "reliable")
func _request_respawn() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return   # only the owner can respawn their own player
	_server_do_respawn()


func _server_do_respawn() -> void:
	if not is_dead:
		return
	if Time.get_ticks_msec() - _death_time_ms < int(RESPAWN_TIME * 1000.0) - 250:
		return   # pressed too early
	var points := get_tree().get_nodes_in_group("spawn_points")
	var pos := Vector3.ZERO
	if points.size() > 0:
		pos = (points.pick_random() as Node3D).global_position
	_respawn.rpc(pos)
@rpc("any_peer", "call_local", "reliable")
func _respawn(pos: Vector3) -> void:
	var sender := multiplayer.get_remote_sender_id()

	if sender != 1 and sender != 0:
		return

	is_dead = false
	respawn_container.hide()
	respawn_label.hide()
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
		weapon_holder.apply_loadout_on_respawn()   # new

		snapped_to_stairs_last_frame = false

		camera.position.y = 1.513

		# Gravity applies right away.
		enter_air()
func _on_loadout_pressed() -> void:
	if not is_dead or _loadout_layer != null:
		return
	_loadout_layer = CanvasLayer.new()
	_loadout_layer.layer = 100   # above the touch controls
	add_child(_loadout_layer)
	var menu := (load("res://scenes/loadout_menu.tscn") as PackedScene).instantiate()
	_loadout_layer.add_child(menu)
	respawn_container.hide()
	menu.closed.connect(_close_loadout_menu)


func _close_loadout_menu() -> void:
	if is_instance_valid(_loadout_layer):
		_loadout_layer.queue_free()
	_loadout_layer = null
	if is_dead:
		respawn_container.show()
func _load_footsteps() -> void:
	for f in DirAccess.get_files_at(FOOTSTEP_DIR):
		# exported builds list "name.mp3.import" or ".remap", so strip those
		var fname := f.trim_suffix(".import").trim_suffix(".remap")
		if fname.get_extension() in ["mp3", "ogg", "wav"]:
			var s := load(FOOTSTEP_DIR + fname) as AudioStream
			if s and not _footsteps.has(s):
				_footsteps.append(s)
func _update_footsteps() -> void:
	if _footsteps.is_empty():
		return
		
	var pos := global_position
	var moved := Vector2(pos.x - _prev_step_pos.x, pos.z - _prev_step_pos.z).length()
	_prev_step_pos = pos
	
	# Skip: dead, airborne, or teleports
	if is_dead or sync_airborne or moved > 1.0:
		_idle_frames = 10
		_has_triggered_start_step = false
		return
		
	if sync_crouching:
		_idle_frames = 10
		_has_triggered_start_step = false
		return   # crouch-walking is silent

	# Check if player is standing still
	if moved < 0.0005:
		_idle_frames += 1
		# Must be standing still for at least 5 frames before resetting the start trigger
		if _idle_frames > 5:
			_has_triggered_start_step = false
		return

	# We are actively moving, reset idle counter
	_idle_frames = 0

	# If we just started moving from a true stop, play instantly ONCE
	if not _has_triggered_start_step:
		_has_triggered_start_step = true
		_step_dist = 0.0
		_play_footstep()
		return

	# Normal distance-based stepping while walking/running
	_step_dist += moved
	var stride := FOOTSTEP_STRIDE_SPRINT if sync_sprinting else FOOTSTEP_STRIDE_WALK
	if _step_dist >= stride:
		_step_dist = 0.0
		_play_footstep()

func _play_footstep() -> void:
	var i := randi() % _footsteps.size()
	if _footsteps.size() > 1 and i == _last_step_idx:
		i = (i + 1 + randi() % (_footsteps.size() - 1)) % _footsteps.size()
	_last_step_idx = i
	_step_toggle = 1 - _step_toggle
	var p := _step_players[_step_toggle]
	p.stream = _footsteps[i]
	
	# Determine pitch multiplier based on movement state
	var pitch_mult := 0.9
	if is_sprinting:
		pitch_mult = 1.35  # Higher pitch for faster/harder steps

	p.volume_db = -10
	p.pitch_scale = randf_range(0.95, 1.05) * pitch_mult
	p.play()
func _try_throw_grenade() -> void:
	if _throwing or is_dead or is_airborne or is_landing:
		return
	if weapon_holder.is_reloading or weapon_holder.is_ads:
		return
	_throwing = true

	tps_rig.skeletonIK.stop()
	_throw_id += 1
	var id := _throw_id
	_fp_held = false
	_tp_held = false
	is_sprinting = false
	Input.action_release("sprint")

	# 1) FP: weapon hides
	await weapon_holder.play_weapon_anim("hide")
	if id != _throw_id:
		return
	weapon_holder.show_grenade_arms()   # bob_pivot hides, grenade_arms shows

	# 2) Start both throws, each with its OWN pause timer

	weapon_holder.start_grenade_fp()
	play_grenade_tp()
	sync_grenade_throw.rpc()

	get_tree().create_timer(GRENADE_FP_PAUSE_TIME).timeout.connect(func() -> void:
		if id == _throw_id and Input.is_action_pressed("throw_grenade"):
			weapon_holder.hold_grenade_fp(GRENADE_FP_PAUSE_TIME)   # was pause_grenade_fp()
			_fp_held = true)

	get_tree().create_timer(GRENADE_TP_PAUSE_TIME).timeout.connect(func() -> void:
		if id == _throw_id and Input.is_action_pressed("throw_grenade"):
			set_grenade_tp_hold(true)
			sync_grenade_hold.rpc(true)
			_tp_held = true)

	# Wait for both pause points, but stop early if the button is released
	var t := 0.0
	var wait := maxf(GRENADE_FP_PAUSE_TIME, GRENADE_TP_PAUSE_TIME) + 0.05
	while t < wait and Input.is_action_pressed("throw_grenade"):
		await get_tree().process_frame
		if id != _throw_id:
			return
		t += get_process_delta_time()

	# 3) Cook while both are held and the button stays down
	var fuse := GRENADE_FUSE
	while Input.is_action_pressed("throw_grenade") and fuse > 0.0:
		fuse -= get_process_delta_time()
		if grenade_label:
			grenade_label.text = "%.1f" % maxf(fuse, 0.0)
			grenade_label.show()
		await get_tree().process_frame
		if id != _throw_id:
			return
	if grenade_label:
		grenade_label.hide()

	# 4) Resume whatever is paused
	if _tp_held:
		set_grenade_tp_hold(false)
		sync_grenade_hold.rpc(false)
		_tp_held = false
	_fp_held = false

	var release_in := maxf(GRENADE_RELEASE_TIME - weapon_holder.grenade_fp_position(), 0.0)
	if fuse <= 0.0:
		_on_grenade_cooked_off()
	else:
		var fuse_at_release := maxf(fuse - release_in, 0.0)
		get_tree().create_timer(release_in).timeout.connect(func() -> void:
			if id == _throw_id:
				_on_grenade_release(fuse_at_release))

	await weapon_holder.resume_grenade_fp()
	if id != _throw_id:
		return
	weapon_holder.hide_grenade_arms()   # opposite: arms hide, bob_pivot shows

	await weapon_holder.play_weapon_anim("equip")
	if id == _throw_id:
		_throwing = false
		tps_rig.skeletonIK.start()

func _on_grenade_release(fuse_left: float) -> void:
	var t := camera.global_transform
	var dir := -t.basis.z
	var origin = weapon_holder.get_grenade_spawn_position()
	var vel := dir * GRENADE_THROW_SPEED + Vector3.UP * 2.0 + velocity * 0.5
	_launch_grenade(origin, vel, fuse_left)


func _on_grenade_cooked_off() -> void:
	_launch_grenade(global_position + Vector3.UP, Vector3.ZERO, 0.0)
func _launch_grenade(origin: Vector3, vel: Vector3, fuse_left: float) -> void:
	if multiplayer.is_server():
		_server_spawn_grenade(origin, vel, fuse_left)
	else:
		_request_grenade.rpc_id(1, origin, vel, fuse_left)


@rpc("any_peer", "call_remote", "reliable")
func _request_grenade(origin: Vector3, vel: Vector3, fuse_left: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority() or is_dead:
		return
	if origin.distance_to(global_position) > 6.0:
		return   # thrown from too far from where the server has this player
	var max_speed := GRENADE_THROW_SPEED * 2.0
	if vel.length() > max_speed:
		vel = vel.normalized() * max_speed
	_server_spawn_grenade(origin, vel, clampf(fuse_left, 0.0, GRENADE_FUSE))


func _server_spawn_grenade(origin: Vector3, vel: Vector3, fuse_left: float) -> void:
	var spawner := get_tree().get_first_node_in_group("grenade_spawner") as MultiplayerSpawner
	if spawner == null:
		push_error("No GrenadeSpawner in the game scene")
		return
	spawner.spawn({"pos": origin, "vel": vel, "fuse": fuse_left, "owner": get_multiplayer_authority()})

func set_grenade_tp_hold(on: bool) -> void:
	anim_tree.set("parameters/GrenadeTimeScale/scale", 0.0 if on else 1.0)


@rpc("authority", "call_remote", "reliable")
func sync_grenade_hold(on: bool) -> void:
	set_grenade_tp_hold(on)
