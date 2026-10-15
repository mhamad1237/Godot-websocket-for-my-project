extends MeshInstance3D
@export var scope_viewport: SubViewport
@export var reticle_viewport: SubViewport
var scope_material: ShaderMaterial
func _ready() -> void:
	var base := get_active_material(0)
	if base == null:
		return
	scope_material = base.duplicate() as ShaderMaterial
	set_surface_override_material(0, scope_material)

	scope_material.set_shader_parameter("scope_texture", scope_viewport.get_texture())
	scope_material.set_shader_parameter("reticle_texture", reticle_viewport.get_texture())

	_apply_render_scale()
	_update_scope_state()

	Settings.changed.connect(_on_setting_changed)

func _process(_delta: float) -> void:
	var ads := false

	if is_instance_valid(Global.weapon_holder):
		ads = Global.weapon_holder.is_ads
	if is_multiplayer_authority():
		_update_scope_state()
	else:
		scope_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if ads
		else SubViewport.UPDATE_DISABLED
	)
		reticle_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if ads
			else SubViewport.UPDATE_DISABLED
		)
func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)
func _on_setting_changed(key: String, _value) -> void:
	if key == "render_scale":
		_apply_render_scale()
func _apply_render_scale() -> void:
	if not is_instance_valid(scope_viewport):
		return
	scope_viewport.scaling_3d_scale = clampf(
		float(Settings.get_value("render_scale")), 0.25, 1.0
	)

func _update_scope_state() -> void:
	if not is_instance_valid(scope_viewport):
		return
	var ads := false

	if is_instance_valid(Global.weapon_holder):
		ads = Global.weapon_holder.is_ads

	# Stop rendering the scope viewport when not aiming.
	scope_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if ads
		else SubViewport.UPDATE_DISABLED
	)

	# Keep the reticle viewport rendering if needed.
	if is_instance_valid(reticle_viewport):
		reticle_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if ads
			else SubViewport.UPDATE_DISABLED
		)

	if not is_instance_valid(scope_material):
		return

	# Multiplayer: disable expensive eyebox and shadow effects while ADS.
	var multiplayer_active := multiplayer.has_multiplayer_peer()

	# Skip the eyebox, shadow and edge effects in multiplayer
	# while aiming down sights.
	scope_material.set_shader_parameter(
		"use_scope_effects",
		not (ads and multiplayer_active)
	)
