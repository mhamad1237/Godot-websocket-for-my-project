extends TextureRect

@export var knob_path: NodePath
@export var max_distance: float = 60.0  # how far the knob can travel from center, in pixels
@export var dead_zone: float = 0.15     # ignore tiny movements
@export var return_speed: float = 15.0  # speed at which the knob glides back to center

var knob: Control
var touch_index: int = -1
var center: Vector2
var output: Vector2 = Vector2.ZERO  # -1 to 1 on both axes, read by player script

func _ready() -> void:
	knob = get_node(knob_path)
	center = knob.position
	Global.joystick = self

func _process(delta: float) -> void:
	# Smoothly return the knob position and output when released
	if touch_index == -1:
		knob.position = knob.position.lerp(center, return_speed * delta)
		output = output.lerp(Vector2.ZERO, return_speed * delta)
		
		# Snip micro-values near zero to prevent endless tiny calculations
		if output.length() < 0.01:
			output = Vector2.ZERO

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_index == -1:
			touch_index = event.index
			_update_knob(event.position)
		elif not event.pressed and event.index == touch_index:
			touch_index = -1
			# _reset_knob() is no longer needed since _process handles the glide

	elif event is InputEventScreenDrag:
		if event.index == touch_index:
			_update_knob(event.position)

func _update_knob(touch_pos: Vector2) -> void:
	var offset := touch_pos - (size / 2.0)
	var distance := offset.length()

	if distance > max_distance:
		offset = offset.normalized() * max_distance
		distance = max_distance

	knob.position = (size / 2.0) + offset - (knob.size / 2.0)

	var magnitude := distance / max_distance
	if magnitude < dead_zone:
		output = Vector2.ZERO
	else:
		output = offset / max_distance
