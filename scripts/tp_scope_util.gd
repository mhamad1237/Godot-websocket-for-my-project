class_name TpScopeUtil

## Swaps the scope on a TP weapon. Returns the new scope node (or null for no scope).
static func apply(mount: Node3D, data: TpWeaponData, index: int, old_scope: Node3D) -> Node3D:
	if is_instance_valid(old_scope):
		var p := old_scope.get_parent()
		if p:
			p.remove_child(old_scope)   # leaves the tree now, so the old and new scope never overlap
		old_scope.queue_free()

	if mount == null or data == null:
		return null
	if index < 0 or index >= data.available_scopes.size() or data.available_scopes[index] == null:
		return null

	var scope: Node3D = data.available_scopes[index].instantiate()
	mount.add_child(scope)
	return scope
