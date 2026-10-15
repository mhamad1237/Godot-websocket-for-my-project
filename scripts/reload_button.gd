extends Control


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			Input.action_press("reload")
		else:
			Input.action_release("reload")
