extends Node

@onready var bar: GodotxHealthBarControl = get_parent() as GodotxHealthBarControl


func _ready() -> void:
	add_to_group("hud")


## Called by the local player when it spawns.
func bind_player(p: Node) -> void:
	bar.min_value = 0.0
	bar.max_value = 100.0   # the plugin works in percent, keep these fixed
	bar.style.label_custom_max = p.max_health
	bar.set_value(p.health / p.max_health * 100.0, false)   # snap, no animation
	p.health_changed.connect(_on_health_changed)


func _on_health_changed(current: float, maximum: float) -> void:
	bar.style.label_custom_max = maximum
	bar.set_value(current / maximum * 100.0, true)   # animated
