extends Node3D
@export var controls_root: Control   # drag the Control that holds your buttons here

func _ready() -> void:
	add_to_group("hud")
	NetworkManager.register_world($Players, $MultiplayerSpawner)


func bind_player(p: Node) -> void:
	p.died.connect(func(_attacker: int) -> void: _set_controls_visible(false))
	p.respawned.connect(func() -> void: _set_controls_visible(true))


func _set_controls_visible(on: bool) -> void:
	if not is_instance_valid(controls_root):
		return
	controls_root.visible = on
	if on:
		return
	# Hiding a control mid-touch can leave things stuck, so clear them
	if is_instance_valid(Global.joystick):
		Global.joystick.output = Vector2.ZERO
	for action in InputMap.get_actions():
		Input.action_release(action)
