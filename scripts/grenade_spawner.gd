extends MultiplayerSpawner

const GRENADE_SCENE := preload("res://scenes/grenade.tscn")


func _ready() -> void:
	add_to_group("grenade_spawner")
	spawn_function = _make_grenade


func _make_grenade(data: Dictionary) -> Node:
	var g := GRENADE_SCENE.instantiate() as RigidBody3D
	g.position = data["pos"]
	g.fuse = data["fuse"]
	g.owner_id = data["owner"]
	g.set_meta("launch_velocity", data["vel"])
	return g
