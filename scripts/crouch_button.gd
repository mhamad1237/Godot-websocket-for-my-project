extends Control


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			Input.action_press("crouch")
		else:
			Input.action_release("crouch")
