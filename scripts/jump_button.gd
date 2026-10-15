extends Control


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			Input.action_press("jump")
		else:
			Input.action_release("jump")
