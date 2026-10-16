extends Node3D

@export var speed: float = 125.0
@export var tracer_length: float = 0.75

@onready var line_mesh: MeshInstance3D = $Line

var start_position: Vector3
var direction: Vector3
var distance_travelled: float = 0.0
var total_distance: float = 0.0
var _active: bool = false


func _ready() -> void:
	line_mesh.position = Vector3(0.0, 0.0, tracer_length)  # constant, set once


func setup(from: Vector3, to: Vector3) -> void:
	start_position = from
	distance_travelled = 0.0
	total_distance = from.distance_to(to)

	direction = (to - from).normalized()
	if direction == Vector3.ZERO:
		direction = Vector3.FORWARD

	# Orient once, with a safe up vector
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	global_position = from
	look_at(from + direction, up)

	_active = true
	visible = true


func _process(delta: float) -> void:
	if not _active:
		return

	distance_travelled += speed * delta
	if distance_travelled >= total_distance + tracer_length:
		_active = false
		visible = false
		return

	global_position = start_position + direction * minf(distance_travelled, total_distance)
