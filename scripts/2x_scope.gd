extends MeshInstance3D

@export var scope_viewport: SubViewport
@export var reticle_viewport: SubViewport

var scope_material: ShaderMaterial
var _scope_active := false

func _ready() -> void:
	var base := get_active_material(0)
	if base == null:
		return

	scope_material = base.duplicate() as ShaderMaterial
	set_surface_override_material(0, scope_material)

	scope_material.set_shader_parameter("scope_texture", scope_viewport.get_texture())
	scope_material.set_shader_parameter("reticle_texture", reticle_viewport.get_texture())

	_apply_render_scale()
	_set_scope_active(false, true)

	Settings.changed.connect(_on_setting_changed)

func _process(_delta: float) -> void:
	if scope_material == null:
		return

	var ads := false

	if is_multiplayer_authority() and is_instance_valid(Global.weapon_holder):
		ads = Global.weapon_holder.is_ads

	_set_scope_active(ads)

func _set_scope_active(active: bool, force := false) -> void:
	if active == _scope_active and not force:
		return
	_scope_active = active

	var mode := SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if is_instance_valid(scope_viewport):
		scope_viewport.render_target_update_mode = mode
	if is_instance_valid(reticle_viewport):
		reticle_viewport.render_target_update_mode = mode

	scope_material.set_shader_parameter("scope_enabled", active)

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
