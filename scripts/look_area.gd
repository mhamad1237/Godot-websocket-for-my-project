# look_area.gd
extends Control

@export var sensitivity: float = 0.3

var touch_index: int = -1
var last_position: Vector2

func _ready() -> void:
	sensitivity = Settings.get_value("sensitivity")
	Settings.changed.connect(_on_setting_changed)

func _on_setting_changed(key: String, value) -> void:
	if key == "sensitivity":
		sensitivity = value

func _process(delta: float) -> void:
	
	if not Global.weapon_holder == null:

		if Global.weapon_holder.is_ads:
			sensitivity = 0.2
		else:
			sensitivity = 0.3

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_index == -1:
			touch_index = event.index
			last_position = event.position
		elif not event.pressed and event.index == touch_index:
			touch_index = -1

	elif event is InputEventScreenDrag:
		if event.index == touch_index:
			var delta: Vector2 = event.position - last_position
			last_position = event.position
			_apply_look(delta)

func _apply_look(delta: Vector2) -> void:
	Global.weapon_holder.add_look_input(-delta)
	Global.player.rotate_y(-delta.x * sensitivity * 0.01)
	var camera: Camera3D = Global.player.camera
	camera.rotation.x = clamp(
		camera.rotation.x - delta.y * sensitivity * 0.01,
		deg_to_rad(-89),
		deg_to_rad(89)
	)
