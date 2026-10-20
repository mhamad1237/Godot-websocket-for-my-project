class_name Explosion
extends Node3D
## Pooled explosion. Everything is built ONCE, then replayed, so spawning
## costs almost nothing (no node/material/light creation at runtime).
##
## Usage anywhere in your game:
##   Explosion.warm(self, 4)                 # once at level start (optional)
##   Explosion.spawn(self, hit_position)     # every explosion

signal shake_requested(strength: float)

@export var size_multiplier: float = 1.0
@export var density: float = 0.5   # 1.0 = full, 0.5 = half the particles
static var _cached_radial_texture: Texture2D
static var _cached_ring_texture: Texture2D
static var _pool: Array = []

var _built := false
var _busy := false
var _particles: Array[CPUParticles3D] = []
var _flash: MeshInstance3D
var _flash_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _tween_flash: Tween
var _tween_ring: Tween


# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------
static func spawn(parent: Node, pos: Vector3) -> void:
	var e: Explosion = null
	for x in _pool:
		if is_instance_valid(x) and x.is_inside_tree() and not x._busy:
			e = x
			break

	if e == null:
		_pool = _pool.filter(func(n): return is_instance_valid(n))
		e = Explosion.new()
		_pool.append(e)
		parent.add_child(e)

	e.global_position = pos
	e.play()


## Pre-create `count` explosions so nothing is built during gameplay.
static func warm(parent: Node, count: int = 4) -> void:
	for i in count:
		var e := Explosion.new()
		_pool.append(e)
		parent.add_child(e)


## One-off use (e.g. the lobby shader pre-warm): builds, plays, frees itself.
func setup() -> void:
	_ensure_built()
	play()
	await get_tree().create_timer(4.1).timeout
	queue_free()


func play() -> void:
	_ensure_built()
	_busy = true

	for p in _particles:
		p.restart()

	# Core flash
	_flash.visible = true
	_flash.scale = Vector3.ONE * 0.1
	_flash_mat.albedo_color = Color(1.0, 0.9, 0.6, 1.0)
	if _tween_flash: _tween_flash.kill()
	_tween_flash = create_tween()
	_tween_flash.tween_property(_flash, "scale", Vector3.ONE * 6.5 * size_multiplier, 0.1) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween_flash.parallel().tween_property(_flash_mat, "albedo_color", Color(1.0, 0.3, 0.05, 0.0), 0.28)

	# Shockwave
	_ring.visible = true
	_ring.scale = Vector3.ONE * 0.5
	_ring_mat.albedo_color = Color(1.0, 0.75, 0.4, 0.9)
	if _tween_ring: _tween_ring.kill()
	_tween_ring = create_tween()
	_tween_ring.tween_property(_ring, "scale", Vector3.ONE * 16.0 * size_multiplier, 0.45) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween_ring.parallel().tween_property(_ring_mat, "albedo_color", Color(1.0, 0.4, 0.1, 0.0), 0.45)


	shake_requested.emit(0.6 * size_multiplier)

	await get_tree().create_timer(4.0).timeout
	_flash.visible = false
	_ring.visible = false
	_busy = false


# ------------------------------------------------------------
# One-time build
# ------------------------------------------------------------
func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true

	var radial := _get_radial_texture()
	var ring_tex := _get_ring_texture()

	_build_core_flash(radial)
	_build_shockwave(ring_tex)
	_build_fireball(radial)
	_build_inner_fire(radial)
	_build_sparks()
	_build_debris()
	_build_smoke(radial)
	_build_black_smoke(radial)
	_build_dust_ring(radial)


# ------------------------------------------------------------
# Textures (built-in gradients, no GDScript pixel loops)
# ------------------------------------------------------------
func _get_radial_texture() -> Texture2D:
	if _cached_radial_texture != null:
		return _cached_radial_texture
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_cached_radial_texture = tex
	return tex


func _get_ring_texture() -> Texture2D:
	if _cached_ring_texture != null:
		return _cached_ring_texture
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 0.88, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	_cached_ring_texture = tex
	return tex


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
func _gradient(colors: Array, offsets: Array = []) -> Gradient:
	var offs := PackedFloat32Array()
	for i in colors.size():
		offs.append(offsets[i] if offsets.size() > i else float(i) / float(colors.size() - 1))
	var g := Gradient.new()
	g.offsets = offs
	g.colors = PackedColorArray(colors)
	return g


func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	return c


func _sprite_material(texture: Texture2D, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = texture
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


func _quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	return q


func _make_particles(
	mesh: Mesh, material: Material,
	amount: int, life: float,
	vel_min: float, vel_max: float,
	spread: float, gravity: Vector3,
	scale_min: float, scale_max: float,
	start_colors: Gradient, life_colors: Gradient,
	scale_curve: Curve = null
) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var s := size_multiplier

	p.emitting = false
	p.mesh = mesh
	p.material_override = material
	p.amount = maxi(2, int(amount * density))
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.8

	p.direction = Vector3.UP
	p.spread = spread
	p.gravity = gravity
	p.initial_velocity_min = vel_min * s
	p.initial_velocity_max = vel_max * s

	p.scale_amount_min = scale_min * s
	p.scale_amount_max = scale_max * s
	if scale_curve != null:
		p.scale_amount_curve = scale_curve

	p.color_initial_ramp = start_colors
	p.color_ramp = life_colors

	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2 * s
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(p)
	_particles.append(p)
	return p


# ------------------------------------------------------------
# Layers
# ------------------------------------------------------------
func _build_core_flash(texture: Texture2D) -> void:
	_flash = MeshInstance3D.new()
	_flash.mesh = _quad()
	_flash.position = Vector3(0, 0.4 * size_multiplier, 0)
	_flash_mat = _sprite_material(texture, true)
	_flash.material_override = _flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)


func _build_shockwave(texture: Texture2D) -> void:
	_ring = MeshInstance3D.new()
	_ring.mesh = _quad()
	_ring.rotation_degrees = Vector3(-90, 0, 0)
	_ring.position = Vector3(0, 0.05, 0)
	_ring_mat = _sprite_material(texture, true)
	_ring_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)


func _build_fireball(texture: Texture2D) -> void:
	var start := _gradient([Color(1.0, 0.35, 0.03, 1.0), Color(1.0, 0.7, 0.1, 1.0)])
	var life := _gradient(
		[Color(1.0, 0.95, 0.7, 0.0), Color(1.0, 0.8, 0.4, 0.9), Color(0.8, 0.2, 0.02, 0.6), Color(0.3, 0.05, 0.0, 0.0)],
		[0.0, 0.12, 0.55, 1.0])
	var curve := _curve([Vector2(0, 0.3), Vector2(0.25, 1.0), Vector2(1, 0.6)])
	var p := _make_particles(_quad(), _sprite_material(texture, true), 22, 0.9,
		1.5, 5.0, 180.0, Vector3(0, 1.5, 0), 1.0, 20, start, life, curve)
	p.position = Vector3(0, 0.5 * size_multiplier, 0)


func _build_inner_fire(texture: Texture2D) -> void:
	var start := _gradient([Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 1.0, 0.8, 1.0)])
	var life := _gradient([Color(1, 1, 1, 1.0), Color(1.0, 0.5, 0.1, 0.0)])
	var curve := _curve([Vector2(0, 0.5), Vector2(0.2, 1.0), Vector2(1, 0.2)])
	var p := _make_particles(_quad(), _sprite_material(texture, true), 10, 0.5,
		0.5, 2.5, 120.0, Vector3.ZERO, 1.4, 2.4, start, life, curve)
	p.position = Vector3(0, 0.4 * size_multiplier, 0)


func _build_sparks() -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.02
	mesh.height = 0.22
	mesh.radial_segments = 6
	mesh.rings = 1

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var start := _gradient([Color(1.0, 0.95, 0.55, 1.0), Color(1.0, 0.45, 0.05, 1.0)])
	var life := _gradient([Color(1, 1, 1, 1), Color(1, 0.3, 0.05, 0)])
	var p := _make_particles(mesh, mat, 60, 1.0,
		8.0, 20.0, 180.0, Vector3(0, -14.0, 0), 0.7, 1.5, start, life)
	p.particle_flag_align_y = true
	p.position = Vector3(0, 0.3 * size_multiplier, 0)


func _build_debris() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.1, 0.1, 0.1)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var start := _gradient([Color(0.12, 0.09, 0.07, 1.0), Color(0.3, 0.22, 0.15, 1.0)])
	var life := _gradient([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 0.7, 1.0])
	var p := _make_particles(mesh, mat, 20, 1.5,
		5.0, 13.0, 90.0, Vector3(0, -22.0, 0), 0.5, 1.6, start, life)
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.position = Vector3(0, 0.2 * size_multiplier, 0)


func _build_smoke(texture: Texture2D) -> void:
	var start := _gradient([Color(0.2, 0.17, 0.14, 1.0), Color(0.42, 0.36, 0.3, 1.0)])
	var life := _gradient([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0)], [0.0, 0.15, 1.0])
	var curve := _curve([Vector2(0, 0.35), Vector2(1, 1.0)])
	var p := _make_particles(_quad(), _sprite_material(texture, false), 24, 3.2,
		0.8, 3.0, 60.0, Vector3(0, 1.2, 0), 1.0, 2.2, start, life, curve)
	p.position = Vector3(0, 0.6 * size_multiplier, 0)


func _build_black_smoke(texture: Texture2D) -> void:
	var start := _gradient([Color(0.01, 0.01, 0.01, 1.0), Color(0.07, 0.06, 0.05, 1.0)])
	var life := _gradient([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0)], [0.0, 0.2, 1.0])
	var curve := _curve([Vector2(0, 0.4), Vector2(1, 1.0)])
	var p := _make_particles(_quad(), _sprite_material(texture, false), 16, 3.6,
		0.4, 1.8, 35.0, Vector3(0, 1.6, 0), 1.2, 1.4, start, life, curve)
	p.position = Vector3(0, 0.8 * size_multiplier, 0)


func _build_dust_ring(texture: Texture2D) -> void:
	var start := _gradient([Color.WHITE, Color.WHITE])
	var life := _gradient([Color(0.45, 0.36, 0.24, 0.0), Color(0.45, 0.36, 0.24, 0.65), Color(0.45, 0.36, 0.24, 0.0)], [0.0, 0.15, 1.0])
	var curve := _curve([Vector2(0, 0.4), Vector2(1, 1.0)])
	var p := _make_particles(_quad(), _sprite_material(texture, false), 22, 1.6,
		5.0, 11.0, 90.0, Vector3(0, -2.0, 0), 1.0, 2.2, start, life, curve)
	p.direction = Vector3(0, 0.05, 0)
	p.damping_min = 4.0
	p.damping_max = 7.0
	p.position = Vector3(0, 0.1, 0)
