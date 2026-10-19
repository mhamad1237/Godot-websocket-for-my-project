extends Control


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		Input.action_press("throw_grenade")
	else:
		Input.action_release("throw_grenade")
