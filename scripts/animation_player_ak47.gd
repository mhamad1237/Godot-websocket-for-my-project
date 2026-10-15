extends AnimationPlayer
@onready var stream_player : AudioStreamPlayer3D = $AudioStreamPlayer3D
@export var bolt_sound : AudioStream
@export var equip_sound : AudioStream
@export var reload1: AudioStream
@export var reload2: AudioStream

func play_reload1_sound():
	stream_player.stream = reload1
	stream_player.play()

func play_reload2_sound():
	stream_player.stream = reload2
	stream_player.play()
func play_bolt_sound():
	stream_player.stream = bolt_sound
	stream_player.play()
func play_equip_sound():
	stream_player.stream = equip_sound
	stream_player.play()
