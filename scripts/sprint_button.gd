extends Control


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if Global.player.is_sprinting:
			Input.action_release("sprint")
		else:
			Input.action_press("sprint")
