@tool
@icon("res://addons/mergingmeshes/icons8-mesh-32.png")
extends Node3D


@export_tool_button("Generate Merged Mesh")
var generate_action = generate_merged_mesh

@export_tool_button("Clear Merged Mesh")
var clear_action = clear_merged_mesh

@export var generate_at_runtime: bool = false

@export_group("Search Settings")

# If true, meshes are found automatically by searching search_root's whole subtree.
# If false, the manually-assigned "meshes" array below is used instead.
@export var auto_find_meshes: bool = true

# Node to search from. If null, defaults to this node's parent.
@export var search_root: Node

@export_group("Manual Meshes")

# Only used when auto_find_meshes is false.
@export var meshes: Array[MeshInstance3D] = []

@export_group("Merge Settings")

@export var hide_source_meshes: bool = true
@export var use_original_materials: bool = true
@export var general_material: BaseMaterial3D

# Generates indexed geometry to reduce duplicated vertices.
@export var generate_indices: bool = true

# Automatically skips invisible meshes.
@export var ignore_hidden_meshes: bool = true

const MERGED_NODE_NAME := "MergedMeshInstance"

func _ready() -> void:
	# Runtime generation only.
	if Engine.is_editor_hint():
		return
	search_root = get_parent()

	if not generate_at_runtime:
		return

	generate_merged_mesh()


func get_search_root() -> Node:
	if search_root != null:
		return search_root
	return get_parent()


# Recursively walks the given node's entire subtree and collects every
# MeshInstance3D found, at any depth.
func find_all_mesh_instances(from_node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []

	if from_node == null:
		return found

	_collect_mesh_instances_recursive(from_node, found)

	return found


func _collect_mesh_instances_recursive(node: Node, found: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			# Don't pick up our own previously-generated merged mesh.
			if child.name != MERGED_NODE_NAME:
				found.append(child)

		# Keep descending regardless of type, so nested meshes under
		# non-mesh nodes (e.g. a Node3D grouping several props) are found too.
		_collect_mesh_instances_recursive(child, found)


func get_meshes_to_merge() -> Array[MeshInstance3D]:
	if auto_find_meshes:
		var root := get_search_root()

		if root == null:
			push_warning("No search_root and no parent found; cannot auto-find meshes.")
			return []

		return find_all_mesh_instances(root)

	return meshes


func generate_merged_mesh() -> void:
	clear_merged_mesh()

	var meshes_to_merge := get_meshes_to_merge()

	if meshes_to_merge.is_empty():
		push_warning("No meshes found to merge.")
		return

	var merged_instance := create_merged_instance(meshes_to_merge)

	if merged_instance == null:
		push_warning("Failed to create merged mesh.")
		return

	add_child(merged_instance)

	# Required so the node is saved into the scene in editor mode.
	if Engine.is_editor_hint():
		merged_instance.owner = get_tree().edited_scene_root

	if hide_source_meshes:
		hide_original_meshes(meshes_to_merge)


func clear_merged_mesh() -> void:
	var old := get_node_or_null(MERGED_NODE_NAME)

	if old:
		old.free()

	restore_original_meshes(get_meshes_to_merge())


func merge_multiple_meshes(meshes_to_merge: Array[MeshInstance3D]) -> ArrayMesh:
	var array_mesh := ArrayMesh.new()

	# Convert all meshes into local space of this node.
	var inverse_transform := global_transform.affine_inverse()

	# Material -> SurfaceTool
	var material_groups: Dictionary = {}

	for mesh_instance in meshes_to_merge:

		if not is_instance_valid(mesh_instance):
			continue

		if ignore_hidden_meshes and not mesh_instance.visible:
			continue

		if mesh_instance.mesh == null:
			continue

		var source_mesh: Mesh = mesh_instance.mesh
		var local_transform := inverse_transform * mesh_instance.global_transform

		for surface_index in source_mesh.get_surface_count():
			var material: Material = null

			if use_original_materials:
				material = mesh_instance.get_active_material(surface_index)

			if material == null:
				material = general_material

			# Create one SurfaceTool per material.
			if not material_groups.has(material):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				material_groups[material] = st

			var surface_tool: SurfaceTool = material_groups[material]

			# Append mesh data into merged geometry.
			surface_tool.append_from(
				source_mesh,
				surface_index,
				local_transform
			)

	# Commit all surfaces.
	for material in material_groups:
		var surface_tool: SurfaceTool = material_groups[material]

		# Generate indexed geometry.
		if generate_indices:
			surface_tool.index()

		surface_tool.commit(array_mesh)

		array_mesh.surface_set_material(
			array_mesh.get_surface_count() - 1,
			material
		)

	return array_mesh


func create_merged_instance(meshes_to_merge: Array[MeshInstance3D]) -> MeshInstance3D:
	var merged_mesh := merge_multiple_meshes(meshes_to_merge)

	if merged_mesh == null:
		return null

	var mesh_instance := MeshInstance3D.new()

	mesh_instance.name = MERGED_NODE_NAME
	mesh_instance.mesh = merged_mesh

	return mesh_instance


func hide_original_meshes(meshes_to_hide: Array[MeshInstance3D]) -> void:
	for mesh_instance in meshes_to_hide:
		if is_instance_valid(mesh_instance):
			mesh_instance.visible = false


func restore_original_meshes(meshes_to_restore: Array[MeshInstance3D]) -> void:
	for mesh_instance in meshes_to_restore:
		if is_instance_valid(mesh_instance):
			mesh_instance.visible = true
