# ============================================================
# Settings.gd  (Autoload name: "Settings")
# Stores, applies and saves player settings to user://settings.cfg
# To add a setting: add it to DEFAULTS, apply it in _apply(), add a row in SettingsMenu.gd
# ============================================================
extends Node

signal changed(key: String, value)
var _default_atlas := -1
const PATH := "user://settings.cfg"

# Defaults decide the type of each setting. Use floats (75.0) for slider values,
# or the saved value is rejected on load for being a different type.
const DEFAULTS := {
	"player_name": "Player",
	"sensitivity": 1.0,
	"master_volume": 1.0,
	"render_scale": 1.0,
	"max_fps": 60,
	"msaa": 0,            # 0 = off, 1 = 2x, 2 = 4x
	"show_fps": false,
	"shadows": true,
}

var _values: Dictionary = {}
var _save_timer: Timer
var _fps_layer: CanvasLayer
var _fps_label: Label


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	get_tree().node_added.connect(_on_node_added)
	_build_fps_label()
	load_settings()
	apply_all()


func _process(_delta: float) -> void:
	_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


# Sliders fire many times while dragging, so saving is debounced (see set_value).
# Also save immediately if the app is backgrounded or closed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save()


# ---------------- Public API ----------------
func get_value(key: String):
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value) -> void:
	if not DEFAULTS.has(key) or _values.get(key) == value:
		return
	_values[key] = value
	_apply(key)
	changed.emit(key, value)
	_save_timer.start()


func reset_defaults() -> void:
	for key in DEFAULTS:
		set_value(key, DEFAULTS[key])
	save()


func apply_all() -> void:
	for key in DEFAULTS:
		_apply(key)


# ---------------- Save / load ----------------
func save() -> void:
	var cfg := ConfigFile.new()
	for key in DEFAULTS:
		cfg.set_value("settings", key, get_value(key))
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: could not save (%s)" % error_string(err))


func load_settings() -> void:
	_values = DEFAULTS.duplicate()
	var phys: int = OS.get_memory_info().get("physical", -1)
	if phys > 0 and phys < 5 * 1024 * 1024 * 1024:   # under ~5 GB
		_values["render_scale"] = 0.7
		_values["msaa"] = 0
		_values["shadows"] = false
		_values["max_fps"] = 30
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return  # first launch, keep defaults
	for key in DEFAULTS:
		var v = cfg.get_value("settings", key, DEFAULTS[key])
		# Ignore corrupted or old values of the wrong type
		if typeof(v) == typeof(DEFAULTS[key]):
			_values[key] = v


# ---------------- Applying ----------------
func _apply(key: String) -> void:
	var value = get_value(key)
	match key:
		"master_volume":
			var v := float(value)
			AudioServer.set_bus_mute(0, v <= 0.001)
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001)))
		"max_fps":
			Engine.max_fps = int(value)
		"render_scale":
			get_tree().root.scaling_3d_scale = float(value)
		"msaa":
			get_tree().root.msaa_3d = int(value) as Viewport.MSAA
		"show_fps":
			_fps_layer.visible = bool(value)
			set_process(bool(value))
		"shadows":
			_apply_shadows()
		# "sensitivity", "fov", "player_name": read by other scripts / the changed signal

func _build_fps_label() -> void:
	_fps_layer = CanvasLayer.new()
	_fps_layer.layer = 128
	_fps_layer.visible = false
	_fps_label = Label.new()
	_fps_label.position = Vector2(12, 8)
	_fps_layer.add_child(_fps_label)
	add_child(_fps_layer)
	set_process(false)
func _apply_shadows() -> void:
	var root := get_tree().root
	if _default_atlas < 0:
		_default_atlas = root.positional_shadow_atlas_size
	var on := bool(get_value("shadows"))
	# 0 turns off the omni/spot shadow atlas entirely, which also frees its memory
	root.positional_shadow_atlas_size = _default_atlas if on else 0
	for light in root.find_children("*", "Light3D", true, false):
		_apply_light(light)


func _apply_light(light: Light3D) -> void:
	# Remember what the scene author set, so turning shadows back on
	# doesn't enable shadows on lights that never had them
	if not light.has_meta("shadow_orig"):
		light.set_meta("shadow_orig", light.shadow_enabled)
	light.shadow_enabled = bool(light.get_meta("shadow_orig")) and bool(get_value("shadows"))


func _on_node_added(n: Node) -> void:
	if n is Light3D:
		_apply_light(n)
