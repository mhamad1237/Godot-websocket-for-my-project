extends Node3D

@export var speed: float = 250.0
@export var tracer_length: float = 2.0

@onready var line_mesh: MeshInstance3D = $Line

var start_position: Vector3
var end_position: Vector3
var direction: Vector3
var distance_travelled: float = 0.0
var total_distance: float = 0.0


func setup(from: Vector3, to: Vector3) -> void:
	start_position = from
	end_position = to

	direction = (to - from).normalized()
	total_distance = from.distance_to(to)

	global_position = from
	look_at(from + direction, Vector3.UP)


func _process(delta: float) -> void:
	distance_travelled += speed * delta

	if distance_travelled >= total_distance + tracer_length:
		queue_free()
		return

	var head_distance: float = minf(distance_travelled, total_distance)
	var head: Vector3 = start_position + direction * head_distance
	var tail: Vector3 = head - direction * tracer_length

	global_position = head
	look_at(head + direction, Vector3.UP)

	# Move the existing line mesh so it trails behind the tracer head.
	line_mesh.position = Vector3(0.0, 0.0, tracer_length)
