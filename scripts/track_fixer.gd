@tool
extends EditorScript

const OLD_PREFIX := "Sketchfab_model/105d2810571c4501ba07ac55c5582245_fbx/Object_2/RootNode/Root/Object_5/Skeleton3D"   # path the animation uses now
const NEW_PREFIX := "Sketchfab_model/a5167d948e6a4ec8bd09a04312151f71_fbx/Object_2/RootNode/Object_4/Skeleton3D"            # path your scene has
const ONLY_ANIM := "grenade_throw"          # "" to fix every animation

func _run() -> void:
	var player: AnimationPlayer
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is AnimationPlayer:
			player = n
	if player == null:
		push_error("Select an AnimationPlayer node first")
		return
	for lib_name in player.get_animation_library_list():
		var lib := player.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			if ONLY_ANIM != "" and anim_name != ONLY_ANIM:
				continue
			var anim := lib.get_animation(anim_name)
			for i in anim.get_track_count():
				var p := str(anim.track_get_path(i))
				if p.begins_with(OLD_PREFIX):
					anim.track_set_path(i, NodePath(NEW_PREFIX + p.trim_prefix(OLD_PREFIX)))
					print("fixed ", anim_name, ": ", p)
