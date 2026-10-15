extends Control


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if Global.weapon_holder.is_ads:
			Global.weapon_holder.exit_ads()
		else:
			Global.weapon_holder.enter_ads()
