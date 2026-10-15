extends Node
var player: CharacterBody3D = null
var joystick : TextureRect = null
var weapon_animation_player: AnimationPlayer = null
var current_ammo: int = 30
var magazine_size: int = 30
var weapon_holder : Node3D = null
var crosshair : Control = null
## Call when leaving a match so nothing keeps a dangling reference.
func clear_local_refs() -> void:
	player = null
	weapon_animation_player = null
	weapon_holder = null
