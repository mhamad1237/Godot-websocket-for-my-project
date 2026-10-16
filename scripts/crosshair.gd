
extends Control

@export var idle_spread: float = 4.0
@export var walk_spread: float = 15.0
@export var jump_spread: float = 120.0
@export var sprint_spread: float = 100.0
@export var spread_speed: float = 10.0
@export var crouching_and_moving_spread: float = 8.0

@export var fire_punch: float = 8.0
@export var fire_punch_return_speed: float = 8.0

@export var line_length: float = 10.0
@export var line_thickness: float = 2.0
@export var dot_radius: float = 1.5

var current_spread: float = 4.0
var fire_punch_amount: float = 0.0


func _ready() -> void:
	Global.crosshair = self
	call_deferred("_connect_weapon_signal")


func _process(delta: float) -> void:
	var player = Global.player

	if not is_instance_valid(player):
		return

	_connect_weapon_signal()

	var is_sprinting: bool = player.is_sprinting
	var is_crouching: bool = player.is_crouching
	var is_airborne: bool = player.is_airborne

	var move_input: Vector2 = (
		Global.joystick.output
		if is_instance_valid(Global.joystick)
		else Vector2.ZERO
	)

	var is_moving: bool = move_input.length() > 0.1

	var target_spread: float

	if is_sprinting:
		target_spread = sprint_spread

	elif is_airborne:
		target_spread = jump_spread

	elif is_crouching:
		if is_moving:
			target_spread = crouching_and_moving_spread
		else:
			target_spread = idle_spread * 0.6

	elif is_moving:
		target_spread = walk_spread

	else:
		target_spread = idle_spread

	# Apply the current weapon's accuracy multiplier.
	var holder = Global.weapon_holder

	if is_instance_valid(holder):
		if is_instance_valid(holder.current_weapon_data):
			target_spread *= holder.current_weapon_data.accuracy_multiplier

	# Smooth movement spread.
	current_spread = lerpf(
		current_spread,
		target_spread,
		clampf(spread_speed * delta, 0.0, 1.0)
	)

	# Return the firing punch to zero.
	fire_punch_amount = lerpf(
		fire_punch_amount,
		0.0,
		clampf(fire_punch_return_speed * delta, 0.0, 1.0)
	)

	queue_redraw()


func _connect_weapon_signal() -> void:
	var holder = Global.weapon_holder

	if not is_instance_valid(holder):
		return

	if not holder.weapon_fired.is_connected(_on_weapon_fired):
		holder.weapon_fired.connect(_on_weapon_fired)


func _on_weapon_fired() -> void:
	fire_punch_amount += fire_punch
	fire_punch_amount = minf(fire_punch_amount, 40.0)


func _draw() -> void:
	var center: Vector2 = size / 2.0

	var player = Global.player
	var is_sprinting: bool = (
		is_instance_valid(player)
		and player.is_sprinting
	)

	# Always draw the center dot.
	draw_circle(center, dot_radius, Color.WHITE)

	# Hide the crosshair lines while sprinting.
	if is_sprinting:
		return

	# Movement spread + firing punch.
	var spread: float = current_spread + fire_punch_amount

	# Top line.
	draw_line(
		center + Vector2(0, -spread),
		center + Vector2(0, -spread - line_length),
		Color.WHITE,
		line_thickness
	)

	# Bottom line.
	draw_line(
		center + Vector2(0, spread),
		center + Vector2(0, spread + line_length),
		Color.WHITE,
		line_thickness
	)

	# Left line.
	draw_line(
		center + Vector2(-spread, 0),
		center + Vector2(-spread - line_length, 0),
		Color.WHITE,
		line_thickness
	)

	# Right line.
	draw_line(
		center + Vector2(spread, 0),
		center + Vector2(spread + line_length, 0),
		Color.WHITE,
		line_thickness
	)
