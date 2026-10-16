# ============================================================
# WeaponHolder.gd
# ============================================================
extends Node3D
var crosshair: Control
var last_holder_bob_offset: Vector3 = Vector3.ZERO
var tp_rig : Node3D = null

var wall_avoid_rotation: float = 0.0
var _tracer_pool: Array[Node3D] = []
const TRACER_POOL_SIZE := 10
var _tracer_i := 0

@export var debug_draw_rays: bool = true
const MAX_HOLES := 30
@export var sway_amount: float = 0.0007
@export var sway_speed: float = 4.0
const BULLET_TRACER = preload("res://scenes/bullet_tracer.tscn")
@export_group("Look Sway")
@export var look_sway_amount: float = 0.025
@export var look_sway_speed: float = 10.0
@export var look_sway_max_angle: float = 3.0
@export_group("Idle Animation")
@export var idle_sway_amount: float = 0.005
@export var idle_sway_speed: float = 1.5
@export var idle_blend_speed: float = 3.0

var idle_timer: float = 0.0
var idle_blend: float = 0.0
var idle_offset: Vector3 = Vector3.ZERO
var look_input: Vector2 = Vector2.ZERO
var look_sway_rotation: Vector3 = Vector3.ZERO
const HOLE_LIFETIME := 3.0
var _spawn_counter := 0
var _holes: Array[MeshInstance3D] = []
var _hole_i := 0
@export var wall_check_ray: RayCast3D
@export var wall_avoid_angle: float = 90.0
@export var wall_avoid_speed: float = 8.0

@export var recoil_pivot: Node3D
var muzzle: Marker3D = null

var ads_base_position: Vector3
@export var bob_pivot: Node3D
@export var sprint_tilt_deg: float = 90.0
@export var sprint_tilt_speed: float = 8.0
@export var recoil_scale: float = 1.0
var clip_offset := 0.0
@export var recoil_kick_back: float = 0.04
@export var recoil_recover_speed: float = 12
var weapon_clip_amount: float = 0.0
@export var animation_player: AnimationPlayer
var player:CharacterBody3D = null
var base_position: Vector3
var bob_timer: float = 0.0
var recoil_offset: Vector3 = Vector3.ZERO
var scope_crosshair: Marker3D =null
var current_weapon: WeaponBase = null
var current_weapon_data: WeaponData = null

var current_ammo: int
var is_firing := false
var is_reloading := false
var fire_timer: Timer
var shoot_sound: AudioStreamPlayer3D
var weapon_clip_offset := 0.0
var is_ads := false
var was_ads := false
const NO_SCOPE_NAME := "no_scope"

# ============================================================
# ACCURACY SYSTEM
# ============================================================

@export_group("Accuracy - Spread (Degrees)")

@export var standing_spread: float = 0.15
@export var crouch_spread: float = 0.05
@export var walking_spread: float = 0.8
@export var crouch_moving_spread: float = 0.45
@export var sprinting_spread: float = 4.0
@export var airborne_spread: float = 6.0

@export_group("Accuracy - ADS")

@export var ads_spread_multiplier: float = 0.35

@export_group("Accuracy - Firing")

@export var shot_bloom: float = 0.12
@export var max_shot_bloom: float = 1.5
@export var bloom_recovery_speed: float = 2.0

var current_shot_bloom: float = 0.0

signal weapon_fired

func _ready() -> void:
	if not is_multiplayer_authority():
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	
	base_position = position
	Global.weapon_holder = self
	equip_weapon(Loadout.weapon_data, Loadout.scope_index)
	

	await get_tree().process_frame
	crosshair = Global.crosshair
	player = Global.player
	tp_rig = player.get_node("ThirdPersonRig")
	fire_timer = Timer.new()
	fire_timer.one_shot = true
	add_child(fire_timer)
	_init_bullet_holes()
	_warm_up_bullet_holes()
	_warm_up_tracer()
	_init_tracer_pool()
func _warm_up_tracer() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if _tracer_pool.is_empty():
		_init_tracer_pool()

	var cam: Camera3D = player.camera
	var from := cam.global_position - cam.global_transform.basis.z * 0.5
	var to := from - cam.global_transform.basis.z * 2.0  # give it real direction/length

	var tracer = _tracer_pool[0]
	tracer.setup(from, to)

	await get_tree().process_frame
	await get_tree().process_frame


func _init_tracer_pool() -> void:
	for i in TRACER_POOL_SIZE:
		var t = BULLET_TRACER.instantiate()
		t.visible = false
		get_tree().root.add_child.call_deferred(t)
		_tracer_pool.append(t)

func _warm_up_bullet_holes() -> void:
	# Wait until the deferred add_child calls have finished
	await get_tree().process_frame
	await get_tree().process_frame

	var cam: Camera3D = player.camera
	var hole := _holes[0]
	# Must be inside the camera frustum, or it gets culled and never compiles
	hole.global_transform = Transform3D(
		cam.global_transform.basis,
		cam.global_position - cam.global_transform.basis.z * 0.5
	)
	hole.visible = true

	await get_tree().process_frame
	await get_tree().process_frame
	hole.visible = false


## Call this to swap weapons at runtime, e.g. equip_weapon(pistol_data)
func equip_weapon(weapon_data: WeaponData, scope_index := -1) -> void:

	if not is_multiplayer_authority():
		return
	print("equip_weapon: ", weapon_data.weapon_name, " | type=", weapon_data.type)
	if current_weapon:
		current_weapon.queue_free()

	var existing_weapon := recoil_pivot.get_node_or_null("weapon")
	if existing_weapon:
		existing_weapon.queue_free()

	current_weapon_data = weapon_data
	current_weapon = weapon_data.weapon_scene.instantiate()
	# Set explicitly so the weapon's own guards never depend on inheritance
	current_weapon.set_multiplayer_authority(get_multiplayer_authority())
	recoil_pivot.add_child(current_weapon)

	position = weapon_data.hold_position
	rotation_degrees = weapon_data.hold_rotation_degrees
	scale = weapon_data.hold_scale

	current_weapon.setup(weapon_data)
	shoot_sound = current_weapon.get_node_or_null("shoot_sound")
	muzzle = current_weapon.get_node_or_null("muzzle")
	current_ammo = weapon_data.magazine_size
	base_position = position


	current_weapon.equip_scope(scope_index)

	scope_crosshair = current_weapon.scope_crosshair

	current_weapon.scope_changed.connect(func(i: int) -> void: Global.player.sync_scope.rpc(i))
	await get_tree().process_frame
	await get_tree().process_frame
	Global.player.sync_weapon.rpc(weapon_data.weapon_name, weapon_data.type)
	Global.player.sync_scope.rpc(scope_index)
	current_weapon.weapon_anim_player.play("equip")

func apply_loadout_on_respawn() -> void:
	is_firing = false
	is_reloading = false   # a reload cut off by death never finishes
	if is_ads:
		var anim := _get_ads_anim()
		if animation_player and animation_player.has_animation(anim):
			animation_player.play(anim)
			animation_player.seek(0.0, true)
			animation_player.stop()
		is_ads = false
		if crosshair:
			crosshair.show()

	var changed := current_weapon == null \
		or Loadout.weapon_data != current_weapon_data \
		or Loadout.scope_index != current_weapon.current_scope_index
	if changed:
		equip_weapon(Loadout.weapon_data, Loadout.scope_index)
	elif current_weapon_data:
		current_ammo = current_weapon_data.magazine_size

func _physics_process(_delta: float) -> void:
	process_weapon_input()
func process_weapon_input() -> void:
	if not current_weapon or current_weapon.weapon_anim_player == null:
		return

	if is_reloading:
		return

	if current_ammo <= 0:
		if is_firing:
			is_firing = false
			start_reload()
		elif Input.is_action_just_pressed("fire") or Input.is_action_just_pressed("reload"):
			start_reload()
		return
	
	if current_weapon_data.is_semi_auto :
		# SEMI-AUTO: one shot per press.
		is_firing = false

		if Input.is_action_just_pressed("fire") and fire_timer.is_stopped():
			is_firing = true
			_fire_shot()
			is_firing = false

	else:
		# FULL-AUTO: keep firing while held.
		if Input.is_action_just_pressed("fire"):
			is_firing = true
			if fire_timer.is_stopped():
				_fire_shot()

		if is_firing:
			if not Input.is_action_pressed("fire"):
				is_firing = false
			elif fire_timer.is_stopped():
				_fire_shot()

	if Input.is_action_just_pressed("reload") \
	and current_ammo < current_weapon_data.magazine_size:
		start_reload()




func start_reload() -> void:
	if is_ads:
		exit_ads()
		await animation_player.animation_finished
	is_reloading = true
	_on_reload_start()


func _on_reload_start() -> void:
	if current_weapon.weapon_anim_player and current_weapon.weapon_anim_player.has_animation("reload"):
		current_weapon.weapon_anim_player.play("reload")
		await current_weapon.weapon_anim_player.animation_finished
	current_ammo = current_weapon_data.magazine_size
	is_reloading = false

func _fire_shot() -> void:
	if current_weapon.weapon_anim_player.is_playing() or wall_check_ray.is_colliding():
		return

	if player.is_sprinting:
		Input.action_release("sprint")
		await get_tree().create_timer(0.2).timeout

	fire_timer.start(current_weapon_data.fire_rate)
	current_ammo -= 1

	# Increase inaccuracy when firing.
	current_shot_bloom = minf(
		current_shot_bloom + shot_bloom,
		max_shot_bloom
	)

	weapon_fired.emit()
	_on_fire()

	if current_weapon_data.is_shotgun:
		_do_shotgun_raycasts()
	else:
		_do_raycast()


func _on_fire() -> void:
	if shoot_sound:
		shoot_sound.play()
	apply_recoil()
	player.apply_cam_recoil(
	current_weapon_data.cam_recoil_up,
	current_weapon_data.cam_recoil_side,
	current_weapon_data.cam_recoil_snap_speed,
	current_weapon_data.cam_recoil_decay_speed
)




func _get_aim_transform() -> Transform3D:
	if scope_crosshair and is_ads:
		return scope_crosshair.global_transform
	return player.camera.global_transform


func _raycast(from: Vector3, dir: Vector3, max_dist: float = 100.0) -> Dictionary:
	var space_state := player.get_world_3d().direct_space_state
	if not space_state:
		return {}

	var to := from + dir * max_dist
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]

	var result := space_state.intersect_ray(query)

	# Spawn tracer to the hit point, or the ray endpoint on a miss.
	var hit_position: Vector3 = (
		result.position
		if result
		else to
	)

	spawn_tracer(muzzle.global_position, hit_position)

	if debug_draw_rays and OS.is_debug_build():
		_debug_draw_ray(from, to, result)

	return result



func _debug_draw_ray(from: Vector3, to: Vector3, result: Dictionary) -> void:
	var duration := 2.0
	if result:
		var hit: Vector3 = result.position
		# Green: origin to hit
		DebugDraw3D.draw_line(from, hit, Color.GREEN, duration)
		# Red: hit marker
		DebugDraw3D.draw_sphere(hit, 0.05, Color.RED, duration)
		# Yellow: surface normal at the hit point
		DebugDraw3D.draw_line(hit, hit + result.normal * 0.3, Color.YELLOW, duration)
	else:
		# Gray: miss, full ray length
		DebugDraw3D.draw_line(from, to, Color.GRAY, duration)
func _do_raycast() -> void:
	var aim := _get_aim_transform()
	var from := aim.origin

	var spread_degrees := _get_current_spread_degrees()
	var dir := _get_spread_direction(
		aim,
		spread_degrees
	)

	var result := _raycast(from, dir)

	if result:
		_apply_hit(result, from)
	else:
		print("missed")
func spawn_tracer(from: Vector3, to: Vector3) -> void:
	if _tracer_pool.is_empty():
		_init_tracer_pool()
	var tracer = _tracer_pool[_tracer_i]
	_tracer_i = (_tracer_i + 1) % TRACER_POOL_SIZE
	tracer.setup(from, to)

func _do_shotgun_raycasts() -> void:
	var aim := _get_aim_transform()
	var from := aim.origin

	var spread_degrees :float= (
		current_weapon_data.pellet_spread_degrees
		+ _get_current_spread_degrees()
	)

	var spread_rad := deg_to_rad(spread_degrees)

	for i in current_weapon_data.pellet_count:
		var angle := randf() * TAU
		var radius := sqrt(randf()) * tan(spread_rad)

		var local_dir := Vector3(
			cos(angle) * radius,
			sin(angle) * radius,
			-1.0
		).normalized()

		var dir := (aim.basis * local_dir).normalized()

		var result := _raycast(from, dir)

		if result:
			_apply_hit(result, from)
func _apply_hit(result: Dictionary, from: Vector3) -> void:
	var distance := from.distance_to(result.position)
	var damage_multiplier := 1.0

	if distance > current_weapon_data.falloff_start:
		damage_multiplier = remap(
			clampf(distance, current_weapon_data.falloff_start, current_weapon_data.falloff_end),
			current_weapon_data.falloff_start, current_weapon_data.falloff_end,
			1.0, current_weapon_data.min_damage_multiplier
		)

	if result.collider.has_method("take_damage"):
		result.collider.take_damage(current_weapon_data.damage * damage_multiplier)
	_spawn_bullet_hole(result)
func _init_bullet_holes() -> void:
	if not _holes.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = preload("res://models/textures/bullet_hole.png")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5

	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	quad.material = mat

	for i in MAX_HOLES:
		var m := MeshInstance3D.new()
		m.mesh = quad
		m.visible = false
		m.top_level = true  # unaffected by any parent transform
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_holes.append(m)       # append first, so a later error can't leave it empty
		get_tree().root.add_child.call_deferred(m)

func _spawn_bullet_hole(result: Dictionary) -> void:
	if _holes.is_empty():
		_init_bullet_holes()
	if result.collider is CharacterBody3D or result.collider.is_in_group("enemy"):
		return

	var n: Vector3 = result.normal
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := up.cross(n).normalized()
	var y := n.cross(x)

	var hole := _holes[_hole_i]
	_hole_i = (_hole_i + 1) % MAX_HOLES
	hole.global_transform = Transform3D(Basis(x, y, n), result.position + n * 0.005)
	hole.rotate_object_local(Vector3.BACK, randf() * TAU)
	hole.visible = true

	# Hide after the lifetime, unless this hole was recycled in the meantime
	_spawn_counter += 1
	var id := _spawn_counter
	hole.set_meta("id", id)
	get_tree().create_timer(HOLE_LIFETIME).timeout.connect(func() -> void:
		if is_instance_valid(hole) and hole.get_meta("id", -1) == id:
			hole.visible = false
	)
func _get_scope_string() -> String:
	return current_weapon_data.get_scope_name(current_weapon.current_scope_index)

func _get_ads_anim() -> String:
	return current_weapon_data.weapon_name + "/zoom_in_" + _get_scope_string()


func enter_ads() -> void:
	if is_ads or not animation_player or not current_weapon_data or  player.is_airborne or is_reloading or wall_check_ray.is_colliding():
		return
	if player.is_sprinting:
		Input.action_release("sprint")
		await get_tree().create_timer(0.2).timeout
	var anim := _get_ads_anim()
	if not animation_player.has_animation(anim):
		push_warning("Missing ADS animation: " + anim)
		return
	crosshair.hide()
	position -= last_holder_bob_offset
	last_holder_bob_offset = Vector3.ZERO
	is_ads = true
	animation_player.play(anim)


func exit_ads() -> void:
	if not is_ads or not animation_player or not current_weapon_data or player.is_sprinting or player.is_airborne or is_reloading:
		return
	var anim := _get_ads_anim()
	if not animation_player.has_animation(anim):
		push_warning("Missing ADS animation: " + anim)
		return
	crosshair.show()
	is_ads = false
	animation_player.play_backwards(anim)
func _process(delta: float) -> void:
	var target_rotation_for_clipping := 0.0
	if wall_check_ray.is_colliding():
		if is_ads:
			exit_ads()
			await animation_player.animation_finished
		var hit_point = wall_check_ray.get_collision_point()
		var hit_distance = wall_check_ray.global_position.distance_to(hit_point)
		var max_distance = wall_check_ray.target_position.length()
		var t = 1.0 - clamp(hit_distance / max_distance, 0.0, 1.0)
		target_rotation_for_clipping = deg_to_rad(wall_avoid_angle) * t

	wall_avoid_rotation = lerp(wall_avoid_rotation, target_rotation_for_clipping, wall_avoid_speed * delta)
	rotation.x = wall_avoid_rotation
	if not current_weapon:
		return
	_update_accuracy(delta)

	var mouse_look := look_input
	look_input = Vector2.ZERO

	var move_input: Vector2 = (
		Global.joystick.output
		if Global.joystick
		else Vector2.ZERO
	)

	var is_sprinting: bool = (
		player != null and player.is_sprinting
	)

	var is_crouching: bool = (
		player != null and player.is_crouching
	)

	if (player != null and player.is_airborne) or is_ads:
		Input.action_release("sprint")

	# ---------------------------------------------------------
	# RECOIL RECOVERY
	# ---------------------------------------------------------
	recoil_offset = recoil_offset.lerp(
		Vector3.ZERO,
		clampf(recoil_recover_speed * delta, 0.0, 1.0)
	)

	if recoil_pivot:
		recoil_pivot.position = recoil_offset
	# ---------------------------------------------------------
	# IDLE WEAPON ANIMATION (POSITION ONLY)
	# ---------------------------------------------------------
	var is_idle :bool= (
		player != null
		and player.velocity.length() < 0.1
		and not player.is_airborne
		and not is_sprinting
		and not is_crouching
		and not is_firing
		and not is_reloading
	)

	idle_blend = move_toward(
		idle_blend,
		1.0 if is_idle else 0.0,
		idle_blend_speed * delta
	)

	idle_timer += delta * idle_sway_speed

	var target_idle_offset := Vector3(
		sin(idle_timer * 0.7) * idle_sway_amount,
		cos(idle_timer) * idle_sway_amount,
		sin(idle_timer * 0.5) * idle_sway_amount * 0.5
	)

	idle_offset = target_idle_offset * idle_blend
	# ---------------------------------------------------------
	# ADS
	# Keep the ADS animation in control of WeaponHolder.position.
	# Disable bob and look sway while aiming.
	# ---------------------------------------------------------
	if is_ads or (animation_player and animation_player.is_playing()):
		bob_timer = 0.0
		look_sway_rotation = Vector3.ZERO

		if bob_pivot:
			bob_pivot.rotation = Vector3.ZERO

		return

	# ---------------------------------------------------------
	# MOVEMENT AND POSITIONAL LOOK SWAY
	# ---------------------------------------------------------
	var target_sway := Vector3(
		-mouse_look.x,
		mouse_look.y,
		0.0
	) * sway_amount

	# Smooth rotational sway from camera look input.
	var target_look_rotation := Vector3(
		deg_to_rad(mouse_look.y * look_sway_max_angle),
		deg_to_rad(mouse_look.x * look_sway_max_angle),
		deg_to_rad(-mouse_look.x * look_sway_max_angle)
	) * look_sway_amount

	look_sway_rotation = look_sway_rotation.lerp(
		target_look_rotation,
		clampf(look_sway_speed * delta, 0.0, 1.0)
	)

	var is_moving: bool = (
		move_input.length() > 0.1
		and not is_firing
		and player != null
		and player.velocity.length() > 0.1
	)

	var rest_offset: Vector3 = (
		current_weapon_data.bob_offset
		if is_sprinting
		else Vector3.ZERO
	)

	# Remove the previous frame's bob.
	position -= last_holder_bob_offset
	last_holder_bob_offset = Vector3.ZERO

	# Smooth the holder position toward its resting position.
	position = position.lerp(
	base_position + target_sway + rest_offset + idle_offset,
	clampf(sway_speed * delta, 0.0, 1.0)
)

	# ---------------------------------------------------------
	# LOOK SWAY + SPRINT TILT
	# ---------------------------------------------------------
	if bob_pivot:
		var target_rotation := look_sway_rotation

		if is_sprinting:
			target_rotation += Vector3(
				deg_to_rad(current_weapon_data.bob_rotation.x),
				deg_to_rad(current_weapon_data.bob_rotation.y),
				deg_to_rad(current_weapon_data.bob_rotation.z)
			)

		bob_pivot.rotation = bob_pivot.rotation.lerp(
			target_rotation,
			clampf(sprint_tilt_speed * delta, 0.0, 1.0)
		)

	# ---------------------------------------------------------
	# WALKING / SPRINTING / CROUCHING BOB
	# ---------------------------------------------------------
	if is_moving:
		var current_bob_speed: float = (
			current_weapon_data.sprint_bob_speed
			if is_sprinting
			else current_weapon_data.bob_speed
		)

		if is_crouching:
			current_bob_speed = current_weapon_data.bob_speed * 0.5

		bob_timer += delta * current_bob_speed

		var bob_offset: Vector3 = current_weapon.get_bob_offset(
			bob_timer,
			is_sprinting,
			is_crouching
		)

		position += bob_offset
		last_holder_bob_offset = bob_offset
	else:
		bob_timer =0.0

func apply_recoil() -> void:
	var recoil_multiplier := 0.4 if is_ads else 1.0
	recoil_offset.z += recoil_kick_back * recoil_multiplier
func _exit_tree() -> void:
	if Global.weapon_holder == self:
		Global.weapon_holder = null
func add_look_input(input: Vector2) -> void:
	look_input += input
func _get_current_spread_degrees() -> float:
	var spread: float = standing_spread

	var move_input: Vector2 = (
		Global.joystick.output
		if Global.joystick
		else Vector2.ZERO
	)

	var is_moving: bool = move_input.length() > 0.1

	if player.is_airborne:
		spread = airborne_spread

	elif player.is_sprinting:
		spread = sprinting_spread

	elif player.is_crouching:
		if is_moving:
			spread = crouch_moving_spread
		else:
			spread = crouch_spread

	elif is_moving:
		spread = walking_spread

	# Reduce spread while aiming down sights.
	if is_ads:
		spread *= ads_spread_multiplier

	# Add temporary spread from repeated firing.
	spread += current_shot_bloom

	# Apply the current weapon's accuracy multiplier.
	if is_instance_valid(current_weapon_data):
		spread *= current_weapon_data.accuracy_multiplier

	return spread

func _get_spread_direction(
	aim: Transform3D,
	spread_degrees: float
) -> Vector3:
	var spread_rad := deg_to_rad(spread_degrees)

	# Uniform distribution inside the aiming cone.
	var angle := randf() * TAU
	var radius := sqrt(randf()) * tan(spread_rad)

	var local_dir := Vector3(
		cos(angle) * radius,
		sin(angle) * radius,
		-1.0
	).normalized()

	return (aim.basis * local_dir).normalized()


func _update_accuracy(delta: float) -> void:
	current_shot_bloom = move_toward(
		current_shot_bloom,
		0.0,
		bloom_recovery_speed * delta
	)
