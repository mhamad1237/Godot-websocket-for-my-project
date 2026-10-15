@tool
extends EditorScript


func _run() -> void:
	DirAccess.remove_absolute("user://crumb.txt")
