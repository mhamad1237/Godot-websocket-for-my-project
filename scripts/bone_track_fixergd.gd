@tool
extends EditorScript

const OUTPUT_DIR := "res://fixed_animations"


func _run() -> void:
	var selection := get_editor_interface().get_selection()
	var selected := selection.get_selected_nodes()

	if selected.is_empty():
		push_error("Select the node containing your AnimationPlayer.")
		return

	var root: Node = selected[0]
	var player := find_animation_player(root)
	var skeleton := find_skeleton(root)

	if player == null or skeleton == null:
		push_error("Could not find AnimationPlayer and Skeleton3D.")
		return

	var err := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUTPUT_DIR)
	)
	if err != OK:
		push_error("Could not create output directory.")
		return

	var fixed_count := 0

	for library_name in player.get_animation_library_list():
		var original_library := player.get_animation_library(library_name)

		if original_library == null:
			continue

		var new_library := AnimationLibrary.new()

		for animation_name in original_library.get_animation_list():
			var original := original_library.get_animation(animation_name)
			var anim := original.duplicate(true) as Animation

			if anim == null:
				continue

			for i in range(anim.get_track_count()):
				var path := anim.track_get_path(i)

				if path.get_subname_count() == 0:
					continue

				var old_bone := String(
					path.get_subname(path.get_subname_count() - 1)
				)

				var separator := old_bone.rfind("_")
				if separator < 0:
					continue

				var digits := old_bone.substr(separator + 1)
				if digits.is_empty() or not digits.is_valid_int():
					continue

				var number := int(digits)
				var new_number := number

				if old_bone.begins_with("L_"):
					new_number -= 1
				elif old_bone.begins_with("R_"):
					new_number += 1
				else:
					continue

				if new_number < 0:
					continue

				var new_bone := (
					old_bone.substr(0, separator + 1)
					+ str(new_number).pad_zeros(digits.length())
				)

				# Only remap when the target bone exists.
				if skeleton.find_bone(new_bone) == -1:
					continue

				var old_suffix := ":" + old_bone
				var path_text := String(path)

				if not path_text.ends_with(old_suffix):
					continue

				var new_path := NodePath(
					path_text.substr(
						0, path_text.length() - old_suffix.length()
					) + ":" + new_bone
				)

				anim.track_set_path(i, new_path)
				fixed_count += 1

			var add_err := new_library.add_animation(
				animation_name, anim
			)

			if add_err != OK:
				push_error(
					"Failed to add animation: " + String(animation_name)
				)

		var safe_name := String(library_name).replace("/", "_")

		if safe_name.is_empty():
			safe_name = "default"

		var save_path := OUTPUT_DIR.path_join(
			safe_name + "_fixed.tres"
		)

		var save_err := ResourceSaver.save(new_library, save_path)

		if save_err != OK:
			push_error("Failed to save: " + save_path)

	print("Bone track fixer finished.")
	print("Tracks changed: ", fixed_count)
	print("Output directory: ", OUTPUT_DIR)

func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node

	for child in node.get_children():
		var result := find_animation_player(child)
		if result != null:
			return result

	return null


func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node

	for child in node.get_children():
		var result := find_skeleton(child)
		if result != null:
			return result

	return null
