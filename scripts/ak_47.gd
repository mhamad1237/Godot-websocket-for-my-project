
extends WeaponBase


func get_bob_rotation(
	bob_timer: float,
	is_sprinting: bool,
	is_crouching: bool
) -> Vector3:
	return Vector3(
		sin(bob_timer) * deg_to_rad(data.bob_rotation.x),
		sin(bob_timer) * deg_to_rad(data.bob_rotation.y),
		sin(bob_timer) * deg_to_rad(data.bob_rotation.z)
	)


func get_bob_offset(
	bob_timer: float,
	is_sprinting: bool,
	is_crouching: bool
) -> Vector3:
	var bob_amount := data.bob_amount

	if is_sprinting:
		bob_amount = data.sprint_bob_amount
	elif is_crouching:
		bob_amount *= 0.5

	return Vector3(
		sin(bob_timer) * bob_amount,
		abs(cos(bob_timer)) * bob_amount,
		0.0
	)
