extends HSlider

@export var weapon_root: Node3D

func _ready() -> void:
	value_changed.connect(_on_value_changed)
	_on_value_changed(value)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		print("TOUCH: ", event.position)

	if event is InputEventScreenDrag:
		print("DRAG: ", event.position)

	if event is InputEventMouseButton:
		print("MOUSE: ", event.position, " pressed=", event.pressed)

	if event is InputEventMouseMotion:
		print("MOUSE MOTION")

func _on_value_changed(new_value: float) -> void:
	if weapon_root:
		weapon_root._apply_z_clip_scale(get_parent())
