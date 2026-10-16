extends Control

@onready var menu_panel: VBoxContainer = $MenuPanel
@onready var room_panel: Panel = $RoomPanel
@onready var status_label: Label = $StatusLabel
@onready var loading_overlay: Control = $LoadingOverlay
@onready var name_edit: LineEdit = $MenuPanel/NameEdit
@onready var play_button: Button = $MenuPanel/HostButton
@onready var your_ip_label: Label = $RoomPanel/YourIPLabel
@onready var player_list: ItemList = $RoomPanel/PlayerList
@onready var start_button: Button = $RoomPanel/StartButton
@onready var settings_button: Button = $MenuPanel/SettingsButton

var _log_lines: Array[String] = []
var _connecting := false
var _dots_time := 0.0
var _play_text := ""

func _ready() -> void:
	_play_text = play_button.text
	play_button.pressed.connect(_on_play_online_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	start_button.pressed.connect(_on_start_pressed)
	$RoomPanel/LeaveButton.pressed.connect(_on_leave_pressed)
	$MenuPanel/LoadoutButton.pressed.connect(_open_loadout)
	$RoomPanel/LoadoutButton.pressed.connect(_open_loadout)
	NetworkManager.loading_overlay = loading_overlay
	$MenuPanel/SingleplayerButton.pressed.connect(func() -> void:
		NetworkManager.start_singleplayer(name_edit.text))
	NetworkManager.show_loading_overlay.connect(loading_overlay.begin)
	loading_overlay.finished.connect(NetworkManager.proceed_to_game)
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connect_failed)
	NetworkManager.server_closed.connect(_on_server_closed)
	NetworkManager.roster_changed.connect(_refresh_player_list)
	NetworkManager.debug_status.connect(_log)
	name_edit.text = Settings.get_value("player_name")
	name_edit.text_changed.connect(func(t: String) -> void: Settings.set_value("player_name", t))
	Settings.changed.connect(func(key: String, value) -> void:
		if key == "player_name" and name_edit.text != value:
			name_edit.text = value)

	_show_menu()


# ---------------- Status log (shown in the label) ----------------
func _log(t: String) -> void:
	_log_lines.append(t)
	if _log_lines.size() > 6:
		_log_lines.pop_front()
	status_label.text = "\n".join(_log_lines)


# ---------------- Panel switching ----------------
func _show_menu() -> void:
	menu_panel.show()
	room_panel.hide()
	_set_connecting(false)


func _show_room() -> void:
	menu_panel.hide()
	room_panel.show()
	your_ip_label.hide()
	_set_connecting(false)
	start_button.visible = NetworkManager.is_host()
	_refresh_player_list()




func _open_loadout() -> void:
	var menu := (load("res://scenes/loadout_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	menu.closed.connect(menu.queue_free)


# ---------------- Play online ----------------
func _on_play_online_pressed() -> void:
	_log_lines.clear()
	_log("Play Online pressed")
	_set_connecting(true)
	var err :Error= NetworkManager.join_online(name_edit.text)
	if err != OK:
		_set_connecting(false)

func _on_connected() -> void:
	_log("Connected, showing room")
	_show_room()


func _on_connect_failed() -> void:
	_log("Connection failed")
	_show_menu()


func _on_server_closed() -> void:
	_log("Server closed the game")
	_show_menu()


# ---------------- Room ----------------
func _refresh_player_list() -> void:
	player_list.clear()
	for id in NetworkManager.players:
		var pname: String = NetworkManager.players[id]["name"]
		player_list.add_item(pname + (" (you)" if id == NetworkManager.my_id() else ""))
	start_button.visible = NetworkManager.is_host()


func _on_start_pressed() -> void:
	NetworkManager.start_game()


func _on_leave_pressed() -> void:
	NetworkManager.disconnect_game()
	_show_menu()


func _on_settings_pressed() -> void:
	var menu := (load("res://scenes/settings.tscn") as PackedScene).instantiate()
	add_child(menu)
func _process(delta: float) -> void:
	if not _connecting:
		return
	_dots_time += delta
	var dots := 1 + int(_dots_time * 3.0) % 3   # 1, 2, 3 dots
	play_button.text = "Connecting" + ".".repeat(dots)


func _set_connecting(on: bool) -> void:
	_connecting = on
	_dots_time = 0.0
	play_button.disabled = on
	if not on:
		play_button.text = _play_text
