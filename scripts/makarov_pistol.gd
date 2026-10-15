
extends WeaponBase


func get_bob_offset(
	bob_timer: float,
	is_sprinting: bool,
	is_crouching: bool
) -> Vector3:
	var amount: float = data.bob_amount

	if is_sprinting:
		amount = data.sprint_bob_amount
	elif is_crouching:
		amount *= 0.45

	# Controlled tactical movement.
	var horizontal_multiplier := 2.0 if is_sprinting or is_crouching else 1.0
	var horizontal := sin(bob_timer) * amount * horizontal_multiplier
	var vertical :float= abs(cos(bob_timer)) * amount

	return Vector3(horizontal, vertical, 0.0)


func get_bob_rotation(
	bob_timer: float,
	is_sprinting: bool,
	is_crouching: bool
) -> Vector3:
	var rotation_amount: Vector3 = data.bob_rotation

	var multiplier: float = 1.0

	if is_sprinting:
		multiplier = 1.5
	elif is_crouching:
		multiplier = 0.4

	# Subtle movement on all three axes.
	var pitch := sin(bob_timer * 2.0) * rotation_amount.x
	var yaw := sin(bob_timer) * rotation_amount.y
	var roll := -sin(bob_timer) * rotation_amount.z

	return Vector3(
		deg_to_rad(pitch * multiplier),
		deg_to_rad(yaw * multiplier),
		deg_to_rad(roll * multiplier)
	)
