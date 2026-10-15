extends Control

@onready var menu_panel: VBoxContainer = $MenuPanel
@onready var join_panel: Panel = $JoinPanel
@onready var room_panel: Panel = $RoomPanel
@onready var status_label: Label = $StatusLabel
@onready var loading_overlay: Control = $LoadingOverlay
@onready var name_edit: LineEdit = $MenuPanel/NameEdit
@onready var server_list: ItemList = $JoinPanel/ServerList
@onready var manual_ip: LineEdit = $JoinPanel/ManualIP
@onready var your_ip_label: Label = $RoomPanel/YourIPLabel
@onready var player_list: ItemList = $RoomPanel/PlayerList
@onready var start_button: Button = $RoomPanel/StartButton
@onready var settings_button: Button = $MenuPanel/SettingsButton
var _server_ips: Array[String] = []


func _ready() -> void:
	$MenuPanel/HostButton.pressed.connect(_on_host_pressed)
	$MenuPanel/JoinButton.pressed.connect(_on_join_pressed)
	$JoinPanel/RefreshButton.pressed.connect(_on_refresh_pressed)
	$JoinPanel/ConnectButton.pressed.connect(_on_connect_pressed)
	$JoinPanel/BackButton.pressed.connect(_show_menu)
	settings_button.pressed.connect(_on_settings_pressed)
	server_list.item_selected.connect(_on_server_selected)
	start_button.pressed.connect(_on_start_pressed)
	$RoomPanel/LeaveButton.pressed.connect(_on_leave_pressed)
	$MenuPanel/LoadoutButton.pressed.connect(_open_loadout)
	$RoomPanel/LoadoutButton.pressed.connect(_open_loadout)
	NetworkManager.loading_overlay = loading_overlay
	NetworkManager.show_loading_overlay.connect(loading_overlay.begin)
	loading_overlay.finished.connect(NetworkManager.proceed_to_game)
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connect_failed)
	NetworkManager.server_closed.connect(_on_server_closed)
	NetworkManager.roster_changed.connect(_refresh_player_list)
	name_edit.text = Settings.get_value("player_name")
	name_edit.text_changed.connect(func(t: String) -> void: Settings.set_value("player_name", t))
	Settings.changed.connect(func(key: String, value) -> void:
		if key == "player_name" and name_edit.text != value:
			name_edit.text = value)

	_show_menu()



# ---------------- Panel switching ----------------
func _show_menu() -> void:
	menu_panel.show()
	join_panel.hide()
	room_panel.hide()
	status_label.text = ""

func _open_loadout() -> void:
	var menu := (load("res://scenes/loadout_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	menu.closed.connect(menu.queue_free)

func _show_join() -> void:
	menu_panel.hide()
	join_panel.show()
	room_panel.hide()

	_refresh_server_list()


func _show_room() -> void:
	menu_panel.hide()
	join_panel.hide()
	room_panel.show()
	your_ip_label.hide()
	start_button.visible = NetworkManager.is_host()
	_refresh_player_list()


# ---------------- Host ----------------
func _on_host_pressed() -> void:   # rename the button "Play Online"
	status_label.text = "Connecting..."
	NetworkManager.join_online(name_edit.text)

	_show_room()


# ---------------- Join ----------------
func _on_join_pressed() -> void:
	_show_join()


func _on_refresh_pressed() -> void:
	_refresh_server_list()


func _refresh_server_list() -> void:
	server_list.clear()
	_server_ips.clear()
	for ip in NetworkManager.found_servers:
		var info: Dictionary = NetworkManager.found_servers[ip]
		server_list.add_item("%s (%d/%d) — %s" % [info["name"], info["players"], info["max"], ip])
		_server_ips.append(ip)


func _on_server_selected(index: int) -> void:
	manual_ip.text = _server_ips[index]


func _on_connect_pressed() -> void:
	var ip := manual_ip.text.strip_edges()
	if ip == "":
		status_label.text = "Enter an IP or pick a server"
		return
	status_label.text = "Connecting..."
	var err = NetworkManager.join_lan(ip, name_edit.text)
	if err != OK:
		status_label.text = "Could not connect (error %d)" % err


func _on_connected() -> void:
	status_label.text = ""
	_show_room()


func _on_connect_failed() -> void:
	status_label.text = "Connection failed"


func _on_server_closed() -> void:
	status_label.text = "Host closed the game"
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
	add_child(menu)  # on a CanvasLayer if you want it above the touch controls
