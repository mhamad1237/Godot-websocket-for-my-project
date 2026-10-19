
extends Node3D

static var _cached_radial_texture: Texture2D
func setup() -> void:
	var radial_texture := _get_radial_texture()

	_create_flash(radial_texture)
	_create_sparks()
	_create_smoke(radial_texture)
	_create_dust(radial_texture)
	_create_flash_light()

	_create_orange_fire(radial_texture)
	_create_black_smoke(radial_texture)

	await get_tree().create_timer(3.0).timeout
	queue_free()

# Creates a soft circular texture in memory.
func _get_radial_texture() -> Texture2D:
	if _cached_radial_texture != null:
		return _cached_radial_texture

	var image := Image.create(
		64, 64, false, Image.FORMAT_RGBA8
	)

	for y in range(64):
		for x in range(64):
			var uv := Vector2(
				float(x) / 63.0,
				float(y) / 63.0
			)

			var radius := uv.distance_to(Vector2(0.5, 0.5)) * 2.0
			var alpha := 1.0 - _smooth_step(0.15, 1.0, radius)

			image.set_pixel(x, y, Color(1, 1, 1, alpha))

	_cached_radial_texture = ImageTexture.create_from_image(image)
	return _cached_radial_texture


func _smooth_step(a: float, b: float, value: float) -> float:
	var t := clampf((value - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _two_color_gradient(start: Color, finish: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, start)
	gradient.set_color(1, finish)
	return gradient


func _make_sprite_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE

	return material


# ------------------------------------------------------------
# 1. Fast expanding flash
# ------------------------------------------------------------
func _create_flash(texture: Texture2D) -> void:
	var flash := MeshInstance3D.new()

	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	flash.mesh = quad

	flash.position = Vector3(0, 0.2, 0)
	flash.scale = Vector3.ONE * 0.03

	var material := _make_sprite_material(texture)
	material.albedo_color = Color(1.0, 0.65, 0.25, 0.95)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.25, 0.04)
	material.emission_energy_multiplier = 3.0

	flash.material_override = material
	add_child(flash)

	var tween := create_tween()

	tween.tween_property(
		flash, "scale", Vector3.ONE * 2.8, 0.08
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	tween.parallel().tween_property(
		material, "albedo_color",
		Color(1.0, 0.15, 0.02, 0.0), 0.22
	)

	tween.parallel().tween_property(
		material, "emission_energy_multiplier", 0.0, 0.22
	)


# ------------------------------------------------------------
# 2. Outward-flying glowing sparks
# ------------------------------------------------------------
func _create_sparks() -> void:
	var spark_mesh := CapsuleMesh.new()
	spark_mesh.radius = 0.018
	spark_mesh.height = 0.12

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = Color(1.0, 0.3, 0.04)
	material.emission_energy_multiplier = 1.8

	var initial_colors := _two_color_gradient(
		Color(1.0, 0.95, 0.55, 1.0),
		Color(1.0, 0.2, 0.02, 1.0)
	)

	var life_colors := _two_color_gradient(
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0)
	)

	var sparks := _make_particles(
		spark_mesh, material,
		42, 0.7,
		4.0, 10.0,
		180.0,
		Vector3(0, -12.0, 0),
		0.6, 1.2,
		initial_colors, life_colors
	)

	sparks.particle_flag_align_y = true
	sparks.position = Vector3(0, 0.2, 0)
	sparks.emission_sphere_radius = 0.1

	add_child(sparks)


# ------------------------------------------------------------
# 3. Rising smoke cloud
# ------------------------------------------------------------
func _create_smoke(texture: Texture2D) -> void:
	var smoke_mesh := QuadMesh.new()
	smoke_mesh.size = Vector2(1, 1)

	var material := _make_sprite_material(texture)

	var initial_colors := _two_color_gradient(
		Color(0.14, 0.13, 0.12, 0.78),
		Color(0.34, 0.29, 0.25, 0.9)
	)

	var life_colors := _two_color_gradient(
		Color(1, 1, 1, 0.78),
		Color(1, 1, 1, 0)
	)

	var smoke := _make_particles(
		smoke_mesh, material,
		24, 2.35,
		0.45, 1.6,
		38.0,
		Vector3(0, 1.0, 0),
		0.65, 1.45,
		initial_colors, life_colors
	)

	smoke.position = Vector3(0, 0.3, 0)
	smoke.emission_sphere_radius = 0.22

	add_child(smoke)


# ------------------------------------------------------------
# 4. Ground-level dust burst
# ------------------------------------------------------------
func _create_dust(texture: Texture2D) -> void:
	var dust_mesh := QuadMesh.new()
	dust_mesh.size = Vector2(1, 1)

	var material := _make_sprite_material(texture)

	var initial_colors := _two_color_gradient(
		Color.WHITE, Color.WHITE
	)

	var life_colors := _two_color_gradient(
		Color(0.38, 0.29, 0.17, 0.68),
		Color(0.38, 0.29, 0.17, 0)
	)

	var dust := _make_particles(
		dust_mesh, material,
		16, 1.1,
		1.3, 3.4,
		80.0,
		Vector3(0, -5.0, 0),
		0.3, 0.8,
		initial_colors, life_colors
	)

	dust.position = Vector3(0, -0.12, 0)
	dust.emission_sphere_radius = 0.35

	add_child(dust)


# ------------------------------------------------------------
# Shared particle setup
# ------------------------------------------------------------
func _make_particles(
	particle_mesh: Mesh,
	material: Material,
	particle_amount: int,
	life: float,
	velocity_min: float,
	velocity_max: float,
	spread_degrees: float,
	gravity_force: Vector3,
	scale_min: float,
	scale_max: float,
	initial_colors: Gradient,
	life_colors: Gradient
) -> CPUParticles3D:

	var particles := CPUParticles3D.new()

	particles.mesh = particle_mesh
	particles.material_override = material
	particles.amount = particle_amount
	particles.lifetime = life
	particles.one_shot = true
	particles.explosiveness = 1.0

	particles.direction = Vector3.UP
	particles.spread = spread_degrees
	particles.gravity = gravity_force

	particles.initial_velocity_min = velocity_min
	particles.initial_velocity_max = velocity_max

	particles.scale_amount_min = scale_min
	particles.scale_amount_max = scale_max

	particles.color_initial_ramp = initial_colors
	particles.color_ramp = life_colors
	particles.randomness = 0.8

	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.12

	return particles


# ------------------------------------------------------------
# 5. Brief orange light burst
# ------------------------------------------------------------
func _create_flash_light() -> void:
	var light := OmniLight3D.new()

	light.light_color = Color(1.0, 0.42, 0.1)
	light.light_energy = 5.5
	light.omni_range = 7.0
	light.position = Vector3(0, 0.25, 0)

	add_child(light)

	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.28)

# ============================================================
# EXTRA LAYER 1: Orange fire burst
# ============================================================
func _create_orange_fire(texture: Texture2D) -> void:
	var fire_mesh := QuadMesh.new()
	fire_mesh.size = Vector2(1.0, 1.0)

	var material := _make_sprite_material(texture)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.12, 0.01)
	material.emission_energy_multiplier = 2.5

	var initial_colors := _two_color_gradient(
		Color(1.0, 0.12, 0.01, 1.0),
		Color(1.0, 0.65, 0.05, 1.0)
	)

	var life_colors := _two_color_gradient(
		Color(1.0, 1.0, 1.0, 0.95),
		Color(1.0, 0.25, 0.02, 0.0)
	)

	var fire := _make_particles(
		fire_mesh,
		material,
		18,                   # Particle count
		0.55,                 # Short lifetime
		1.5, 4.5,             # Outward speed
		120.0,                # Spread
		Vector3(0, -3.0, 0),  # Falling motion
		0.45, 1.15,           # Particle scale
		initial_colors,
		life_colors
	)

	fire.position = Vector3(0, 0.18, 0)
	fire.emission_sphere_radius = 0.2

	add_child(fire)


# ============================================================
# EXTRA LAYER 2: Dark black smoke core
# ============================================================
func _create_black_smoke(texture: Texture2D) -> void:
	var smoke_mesh := QuadMesh.new()
	smoke_mesh.size = Vector2(1.0, 1.0)

	var material := _make_sprite_material(texture)

	var initial_colors := _two_color_gradient(
		Color(0.008, 0.006, 0.005, 0.95),
		Color(0.065, 0.050, 0.043, 0.9)
	)

	var life_colors := _two_color_gradient(
		Color(1.0, 1.0, 1.0, 0.85),
		Color(1.0, 1.0, 1.0, 0.0)
	)

	var smoke := _make_particles(
		smoke_mesh,
		material,
		18,                   # Particle count
		2.7,                  # Smoke linger time
		0.3, 1.0,             # Slow upward movement
		30.0,                 # Tight spread
		Vector3(0, 0.65, 0),  # Rise slowly
		0.8, 1.7,              # Large smoke puffs
		initial_colors,
		life_colors
	)

	smoke.position = Vector3(0, 0.3, 0)
	smoke.emission_sphere_radius = 0.18

	add_child(smoke)
