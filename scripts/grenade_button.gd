extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	var tapped := false
	if event is InputEventScreenTouch and event.pressed:
		tapped = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true

	if not tapped:
		return

	accept_event()
	print("grenade button tapped | player:", Global.player)
	if is_instance_valid(Global.player):
		Global.player.toggle_grenade()
