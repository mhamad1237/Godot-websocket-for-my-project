# ============================================================
# SettingsMenu.gd  (root node of settings.tscn, type Control)
#
# Scene tree:
#   SettingsMenu (Control, Full Rect)   <- this script
#   └─ Panel (Panel)
#      ├─ Scroll (ScrollContainer)
#      │  └─ List (VBoxContainer)
#      ├─ ResetButton (Button)
#      └─ BackButton (Button)
#
# Rows are built from ROWS below, so you never place sliders by hand.
# ============================================================
extends Control

signal closed

const ROWS := [
	{"key": "player_name", "label": "Name", "type": "text"},
	{"key": "sensitivity", "label": "Look sensitivity", "type": "slider", "min": 0.1, "max": 3.0, "step": 0.05},
	{"key": "master_volume", "label": "Volume", "type": "slider", "min": 0.0, "max": 1.0, "step": 0.05},
	{"key": "render_scale", "label": "3D resolution", "type": "slider", "min": 0.5, "max": 1.0, "step": 0.05},
	{"key": "max_fps", "label": "FPS cap", "type": "option", "options": [
		{"t": "30", "v": 30}, {"t": "60", "v": 60}, {"t": "90", "v": 90}, {"t": "120", "v": 120}]},
	{"key": "msaa", "label": "Anti-aliasing", "type": "option", "options": [
		{"t": "Off", "v": 0}, {"t": "2x", "v": 1}, {"t": "4x", "v": 2}]},
	{"key": "show_fps", "label": "Show FPS", "type": "toggle"},
	{"key": "shadows", "label": "Shadows", "type": "toggle"},
]

@onready var list: VBoxContainer = $Panel/Scroll/List


func _ready() -> void:
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	$Panel/BackButton.pressed.connect(_on_back_pressed)
	$Panel/ResetButton.pressed.connect(_on_reset_pressed)
	_build_rows()
	


func _build_rows() -> void:
	for child in list.get_children():
		child.queue_free()
	for row in ROWS:
		_add_row(row)


func _add_row(row: Dictionary) -> void:
	var key: String = row["key"]
	var current = Settings.get_value(key)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = row["label"]
	label.custom_minimum_size.x = 260
	box.add_child(label)

	match row["type"]:
		"slider":
			var step: float = row["step"]
			var s := HSlider.new()
			s.min_value = row["min"]
			s.max_value = row["max"]
			s.step = step
			s.value = current  # set before connecting so it doesn't count as a change
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.custom_minimum_size = Vector2(240, 48)
			var val_label := Label.new()
			val_label.custom_minimum_size.x = 60
			val_label.text = _fmt(current, step)
			s.value_changed.connect(func(v: float) -> void:
				val_label.text = _fmt(v, step)
				Settings.set_value(key, v))
			box.add_child(s)
			box.add_child(val_label)

		"toggle":
			var c := CheckButton.new()
			c.button_pressed = current
			c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
			box.add_child(c)

		"option":
			var options: Array = row["options"]
			var o := OptionButton.new()
			o.custom_minimum_size = Vector2(160, 48)
			for i in options.size():
				o.add_item(options[i]["t"])
				if options[i]["v"] == current:
					o.select(i)
			o.item_selected.connect(func(i: int) -> void: Settings.set_value(key, options[i]["v"]))
			box.add_child(o)

		"text":
			var t := LineEdit.new()
			t.text = current
			t.max_length = 16
			t.custom_minimum_size = Vector2(240, 48)
			t.text_changed.connect(func(txt: String) -> void: Settings.set_value(key, txt))
			box.add_child(t)

	list.add_child(box)


func _fmt(v: float, step: float) -> String:
	return "%.2f" % v if step < 1.0 else "%d" % int(v)


func _on_reset_pressed() -> void:
	Settings.reset_defaults()
	_build_rows()


func _on_back_pressed() -> void:
	Settings.save()
	closed.emit()
	queue_free()
