extends Control

@export var idle_spread: float = 4.0
@export var walk_spread: float = 15
@export var jump_spread: float = 120.0
@export var sprint_spread: float = 100.0
@export var spread_speed: float = 10.0
@export var crouching_and_moving_spread : float = 8.0
@export var fire_punch: float = 8.0
@export var fire_punch_return_speed: float = 8.0

@export var line_length: float = 10.0
@export var line_thickness: float = 2.0
@export var dot_radius: float = 1.5

var current_spread: float = 4.0
var fire_punch_amount: float = 0.0


func _ready() -> void:
	Global.crosshair = self
	if Global.weapon_holder:
		Global.weapon_holder.weapon_fired.connect(_on_weapon_fired)
	call_deferred("_connect_weapon_signal")

func _process(delta: float) -> void:
	var player = Global.player

	if not player:
		return
	if is_instance_valid(Global.weapon_holder):
		if not Global.weapon_holder.weapon_fired.is_connected(_on_weapon_fired):
			Global.weapon_holder.weapon_fired.connect(_on_weapon_fired)
	var is_sprinting: bool = player.is_sprinting
	var is_crouching: bool = player.is_crouching

	var is_airborne: bool = player.is_airborne

	var move_input: Vector2 = Global.joystick.output if Global.joystick else Vector2.ZERO
	var is_moving := move_input.length() > 0.1

	var target_spread: float

	if is_sprinting:
		target_spread = sprint_spread
	elif is_airborne:
		target_spread = jump_spread
	elif is_crouching:
		target_spread = idle_spread * 0.6
		if is_moving:
			target_spread = crouching_and_moving_spread
	elif is_moving:
		target_spread = walk_spread
	else:
		target_spread = idle_spread

	# Normal movement spread
	current_spread = lerp(
		current_spread,
		target_spread,
		spread_speed * delta
	)

	# Fire punch returns to zero
	fire_punch_amount = lerp(
		fire_punch_amount,
		0.0,
		fire_punch_return_speed * delta
	)

	queue_redraw()

func _connect_weapon_signal() -> void:
	if Global.weapon_holder == null:
		print("Crosshair: weapon_holder is NULL")
		return

	if not Global.weapon_holder.weapon_fired.is_connected(_on_weapon_fired):
		Global.weapon_holder.weapon_fired.connect(_on_weapon_fired)

	print("Crosshair: weapon_fired connected")


func _on_weapon_fired() -> void:
	print("CROSSHAIR PUNCH!")
	fire_punch_amount += fire_punch
	fire_punch_amount = min(fire_punch_amount, 40.0)

func _draw() -> void:
	var center = size / 2
	var player = Global.player
	var is_sprinting: bool = player != null and player.is_sprinting

	draw_circle(center, dot_radius, Color.WHITE)

	if is_sprinting:
		return

	# Movement spread + shooting punch
	var spread := current_spread + fire_punch_amount

	draw_line(
		center + Vector2(0, -spread),
		center + Vector2(0, -spread - line_length),
		Color.WHITE,
		line_thickness
	)

	draw_line(
		center + Vector2(0, spread),
		center + Vector2(0, spread + line_length),
		Color.WHITE,
		line_thickness
	)

	draw_line(
		center + Vector2(-spread, 0),
		center + Vector2(-spread - line_length, 0),
		Color.WHITE,
		line_thickness
	)

	draw_line(
		center + Vector2(spread, 0),
		center + Vector2(spread + line_length, 0),
		Color.WHITE,
		line_thickness
	)
