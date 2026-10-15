extends Control

signal closed

@onready var weapon_list: VBoxContainer = %WeaponList
@onready var preview_container: SubViewportContainer = %PreviewContainer
@onready var weapon_pivot: Node3D = %WeaponPivot
@onready var scope_label: Label = %ScopeLabel
@onready var weapon_label: Label = %WeaponLabel
@onready var stats_label: Label = %StatsLabel
@onready var dots: HBoxContainer = %Dots
@onready var prev_btn: Button = %PrevScope
@onready var next_btn: Button = %NextScope
@onready var deploy_btn: Button = %Done
var preview_scope: Node3D = null
var preview_tp_data: TpWeaponData = null
var weapon_i := 0
var scope_i := -1
var preview_weapon: Node3D
@export var normal_button_stylebox: StyleBox
@export var pressed_button_stylebox: StyleBox

var weapon_buttons: Array[Button] = []
var weapon_group := ButtonGroup.new()
func _ready() -> void:
	
	for i in Loadout.all_weapons.size():
		var b := Button.new()
		b.text = Loadout.all_weapons[i].weapon_name
		b.custom_minimum_size = Vector2(0, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 18)

		b.toggle_mode = true
		b.button_group = weapon_group
		b.add_theme_stylebox_override("normal", normal_button_stylebox)
		b.add_theme_stylebox_override("hover", normal_button_stylebox)
		b.add_theme_stylebox_override("pressed", pressed_button_stylebox)
		b.add_theme_stylebox_override("hover_pressed", pressed_button_stylebox)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

		b.pressed.connect(_select_weapon.bind(i))
		weapon_list.add_child(b)
		weapon_buttons.append(b)
	prev_btn.pressed.connect(_cycle_scope.bind(-1))
	next_btn.pressed.connect(_cycle_scope.bind(1))
	deploy_btn.pressed.connect(_on_deploy)
	preview_container.gui_input.connect(_on_preview_input)

	var saved_scope :int= Loadout.scope_index
	_select_weapon(maxi(0, Loadout.all_weapons.find(Loadout.weapon_data)))
	scope_i = clampi(saved_scope, -1, _scope_count() - 1)
	_apply_scope()

func _current() -> WeaponData:
	return Loadout.all_weapons[weapon_i]

func _scope_count() -> int:
	# Use whatever your WeaponData has for its scope list
	return _current().available_scopes.size()
func _select_weapon(i: int) -> void:
	weapon_i = i
	weapon_buttons[i].set_pressed_no_signal(true)
	scope_i = -1
	var data := _current()

	if preview_weapon:
		preview_weapon.queue_free()
	preview_scope = null   # it was a child of the old weapon

	preview_tp_data = TpWeaponPaths.get_data(data.weapon_name)
	preview_weapon = preview_tp_data.weapon_scene.instantiate()
	weapon_pivot.add_child(preview_weapon)
	weapon_pivot.rotation = Vector3.ZERO

	weapon_label.text = data.weapon_name
	stats_label.text = "Damage: %s\nMagazine: %s\nFire rate: %s" % [
		data.damage, data.magazine_size, data.fire_rate]
	_apply_scope()

func _cycle_scope(dir: int) -> void:
	var count := _scope_count()
	if count == 0:
		return
	# Options are -1 (no scope) .. count-1, so count + 1 total
	scope_i = wrapi(scope_i + dir + 1, 0, count + 1) - 1
	_apply_scope()

func _apply_scope() -> void:
	var count := _scope_count()
	_equip_preview_scope(scope_i)
	_disable_subviewports(preview_weapon)

	scope_label.text = "No Scope" if scope_i == -1 else _current().get_scope_name(scope_i)
	prev_btn.visible = count > 0
	next_btn.visible = count > 0

	for c in dots.get_children():
		c.queue_free()
	for n in count + 1:
		var d := Label.new()
		d.text = "●" if n == scope_i + 1 else "○"
		dots.add_child(d)
	Loadout.weapon_data = _current()
	Loadout.scope_index = scope_i
	Loadout.save()

func _equip_preview_scope(index: int) -> void:
	var mount := preview_weapon.get_node_or_null("ScopeMount") as Node3D
	preview_scope = TpScopeUtil.apply(mount, preview_tp_data, index, preview_scope)
# Scope lens cameras are expensive on mobile, so don't render them in the preview
func _disable_subviewports(n: Node) -> void:
	for c in n.get_children():
		if c is SubViewport:
			c.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_disable_subviewports(c)

func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		weapon_pivot.rotate_y(event.relative.x * 0.01)
	elif event is InputEventMouseMotion and not DisplayServer.is_touchscreen_available() \
	and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		weapon_pivot.rotate_y(event.relative.x * 0.01)

func _on_deploy() -> void:
	closed.emit()
