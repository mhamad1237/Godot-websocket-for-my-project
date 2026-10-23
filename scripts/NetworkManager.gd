# ============================================================
# NetworkManager.gd (Tube + WebRTC peer-to-peer version)
# ============================================================
# - One player creates a Tube session and becomes server peer ID 1.
# - Other players join using the session ID / room code.
# - The host is also a real player; there is no dedicated server.
# - Uses Godot high-level multiplayer RPCs, MultiplayerSpawner and
#   the same roster / game-loading flow as the previous manager.
extends Node

signal preload_progress(progress: float)
signal preload_finished
signal connection_succeeded
signal connection_failed
signal server_closed
signal player_joined(id: int, info: Dictionary)
signal player_left(id: int)
signal roster_changed
signal game_started
signal preload_failed
signal show_loading_overlay
signal debug_status(text: String)
signal room_created(room_code: String)

var offline := false

# TubeContext resource previously created in the project.
# Change this if your .tres file lives somewhere else.
const TUBE_CONTEXT_PATH := "res://tube_context.tres"

const MAX_PLAYERS := 8
const GAME_VERSION := "0.1"
const LOADING_SCENE := "res://scenes/loading.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const PLAYER_SCENE_PATH := "res://scenes/player.tscn"

## peer_id -> {"name": String}. In a Tube room the host (peer ID 1)
## is a player and is included in this dictionary.
var players: Dictionary = {}
var local_name := "Player"
var room_code := ""
var in_game := false

# Kept for compatibility with existing scripts that check this variable.
# Tube/WebRTC sessions do not use a dedicated server.
var dedicated := false

var _tube_client: TubeClient
var _session_active := false
var _pending_action := "" # "create", "join", or ""
var _client_registration_started := false
var _suppress_session_left := false
var _multiplayer_signals_connected := false

var _players_root: Node
var _spawner: MultiplayerSpawner
var _loaded_peers: Dictionary = {}
var _server_world_ready := false
var _spawned := false

var game_scene_res: PackedScene = null
var player_scene_res: PackedScene = null
var is_preloading := false
var preload_done := false
var loading_overlay: Control = null
var _loading_layer: CanvasLayer = null
var _last_conn_status := -1


func _ready() -> void:
	# TubeClient must set the SceneTree MultiplayerAPI before we connect to
	# MultiplayerAPI signals. Otherwise these callbacks may be connected to
	# the default API instead of Tube's WebRTC API.
	_ensure_tube_client()


func _process(_delta: float) -> void:
	if offline or dedicated:
		return
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return
	var st := peer.get_connection_status()
	if st != _last_conn_status:
		_last_conn_status = st
		var labels := ["DISCONNECTED", "CONNECTING", "CONNECTED"]
		if st >= 0 and st < labels.size():
			_dbg("WebRTC status: " + labels[st])
		else:
			_dbg("WebRTC status: " + str(st))


func _dbg(message: String) -> void:
	if dedicated:
		print("[NET] ", message)
	else:
		debug_status.emit(message)


# ============================================================
# Tube setup
# ============================================================
func _ensure_tube_client() -> bool:
	if is_instance_valid(_tube_client):
		return true

	if not ResourceLoader.exists(TUBE_CONTEXT_PATH):
		var message := "TubeContext not found at " + TUBE_CONTEXT_PATH
		push_error("NetworkManager: " + message)
		_dbg(message + ". Check TUBE_CONTEXT_PATH.")
		return false

	var context_resource := load(TUBE_CONTEXT_PATH) as TubeContext
	if context_resource == null:
		push_error("NetworkManager: failed to load TubeContext: " + TUBE_CONTEXT_PATH)
		_dbg("Failed to load TubeContext resource")
		return false

	_tube_client = TubeClient.new()
	_tube_client.name = "TubeClient"
	_tube_client.context = context_resource
	# Default Tube behavior overrides the multiplayer API for the whole tree.
	# Set this before add_child(), because TubeClient configures it in _ready().
	_tube_client.multiplayer_root_node = get_tree().root

	_tube_client.session_created.connect(_on_tube_session_created)
	_tube_client.session_joined.connect(_on_tube_session_joined)
	_tube_client.session_left.connect(_on_tube_session_left)
	_tube_client.error_raised.connect(_on_tube_error_raised)

	add_child(_tube_client)

	# Connect after TubeClient._ready() has installed its MultiplayerAPI.
	if not _multiplayer_signals_connected:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		_multiplayer_signals_connected = true

	return true


# ============================================================
# Public API used by the lobby
# ============================================================
func is_online() -> bool:
	return _session_active and not offline and multiplayer.multiplayer_peer != null


func my_id() -> int:
	if is_online() or offline:
		return multiplayer.get_unique_id()
	return 1


## The lowest peer ID is the room leader. Tube's host is peer ID 1.
func leader_id() -> int:
	if players.is_empty():
		return -1
	var ids: Array = players.keys()
	ids.sort()
	return int(ids[0])


func is_leader() -> bool:
	return is_online() and my_id() == leader_id()


## Kept so the current lobby can continue checking NetworkManager.is_host().
func is_host() -> bool:
	return is_leader()


## Compatibility stub in case an old server_boot scene still calls this.
## The Tube/WebRTC version does not start or require a dedicated server.
func start_dedicated_server() -> Error:
	push_warning("NetworkManager: dedicated servers are disabled in the Tube/WebRTC version.")
	return ERR_UNAVAILABLE


## Backwards-compatible with the existing HostButton code:
## NetworkManager.join_online(name_edit.text) now creates a WebRTC room.
func join_online(player_name: String, _unused_url: String = "") -> Error:
	return create_room(player_name)


func create_room(player_name: String) -> Error:
	if not _ensure_tube_client():
		return ERR_CANT_OPEN

	disconnect_game()
	local_name = _clean_name(player_name)
	_pending_action = "create"
	_session_active = false
	_client_registration_started = false
	room_code = ""
	_last_conn_status = -1
	_dbg("Creating WebRTC room as " + local_name + "...")

	_tube_client.create_session()
	return OK


## Used by the lobby's ConnectButton: join_room(room_code, player_name).
func join_room(session_id: String, player_name: String) -> Error:
	var cleaned_session_id := session_id.strip_edges()
	if cleaned_session_id.is_empty():
		_dbg("Enter a room code first")
		return ERR_INVALID_PARAMETER
	if not _ensure_tube_client():
		return ERR_CANT_OPEN

	disconnect_game()
	local_name = _clean_name(player_name)
	_pending_action = "join"
	_session_active = false
	_client_registration_started = false
	room_code = cleaned_session_id
	_last_conn_status = -1
	_dbg("Joining WebRTC room " + cleaned_session_id + " as " + local_name + "...")

	_tube_client.join_session(cleaned_session_id)
	return OK


## Closes the active/pending Tube session and resets game/network state.
func disconnect_game() -> void:
	var needs_leave := _session_active or not _pending_action.is_empty()
	if needs_leave and is_instance_valid(_tube_client):
		_suppress_session_left = true
		_tube_client.leave_session()

	_clear_local_network_state()


func _clear_local_network_state() -> void:
	offline = false
	Global.clear_local_refs()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	players.clear()
	_loaded_peers.clear()
	_players_root = null
	_spawner = null
	_server_world_ready = false
	_spawned = false
	in_game = false
	_session_active = false
	_pending_action = ""
	_client_registration_started = false
	room_code = ""
	_last_conn_status = -1
	_clear_overlay()
	roster_changed.emit()


## Offline mode still uses Godot's OfflineMultiplayerPeer.
func start_singleplayer(player_name: String) -> void:
	disconnect_game()
	offline = true
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	local_name = _clean_name(player_name)
	players = {1: {"name": local_name}}
	_loaded_peers = {1: true}
	_spawned = false
	_server_world_ready = false
	in_game = true
	proceed_to_game()


func leave_game() -> void:
	disconnect_game()
	get_tree().change_scene_to_file(LOBBY_SCENE)


## The room leader presses Start. Host is normally peer ID 1.
func start_game() -> void:
	if not is_online() or in_game:
		return
	if multiplayer.is_server():
		_do_start()
	else:
		_request_start.rpc_id(1)


## Called by game.gd with the container for players and its MultiplayerSpawner.
func register_world(players_root: Node, spawner: MultiplayerSpawner) -> void:
	_players_root = players_root
	_spawner = spawner
	_spawner.spawn_function = _spawn_player_func

	if offline or multiplayer.is_server():
		_server_world_ready = true
		# Unlike the old dedicated-server setup, the host is a player too.
		_loaded_peers[my_id()] = true
		_try_spawn()
	else:
		_peer_world_ready.rpc_id(1)


func get_player_node(id: int) -> Node:
	if _players_root == null:
		return null
	return _players_root.get_node_or_null(str(id))


# ============================================================
# Tube + MultiplayerAPI callbacks
# ============================================================
func _on_tube_session_created() -> void:
	if _pending_action != "create":
		return

	_pending_action = ""
	_session_active = true
	dedicated = false
	room_code = _tube_client.session_id
	_client_registration_started = false
	players.clear()
	players[1] = {"name": local_name}
	_loaded_peers.clear()
	_dbg("Room created. Code: " + room_code)
	roster_changed.emit()
	room_created.emit(room_code)
	connection_succeeded.emit()


func _on_tube_session_joined() -> void:
	if _pending_action != "join":
		# May be a late signal after leaving/cancelling a session.
		return
	_pending_action = ""
	_session_active = true
	dedicated = false
	room_code = _tube_client.session_id
	_dbg("Tube session joined; registering with host...")
	_finish_client_join()


func _on_connected_to_server() -> void:
	# Godot may signal this just before or after Tube's session_joined signal.
	# _finish_client_join() prevents duplicate registration in either case.
	if not _session_active:
		_session_active = true
		_pending_action = ""
		if is_instance_valid(_tube_client):
			room_code = _tube_client.session_id
	_finish_client_join()


func _finish_client_join() -> void:
	if not _session_active or offline or multiplayer.is_server():
		return
	if _client_registration_started:
		return
	_client_registration_started = true
	_register_client_on_next_frame()


func _register_client_on_next_frame() -> void:
	# Let the WebRTC MultiplayerAPI finish updating peer state before sending RPCs.
	await get_tree().process_frame
	if not _session_active or offline or multiplayer.is_server():
		_client_registration_started = false
		return

	_dbg("Connected! id=%d, registering as %s" % [multiplayer.get_unique_id(), local_name])
	_register_player.rpc_id(1, local_name, GAME_VERSION)
	connection_succeeded.emit()


func _on_tube_error_raised(code: int, message: String) -> void:
	_dbg("Tube error %s: %s" % [str(code), message])
	if not _pending_action.is_empty():
		_fail_pending_connection("WebRTC setup failed: " + message)


func _on_tube_session_left() -> void:
	if _suppress_session_left:
		_suppress_session_left = false
		return
	if not _session_active and _pending_action.is_empty():
		return

	var was_connecting := not _pending_action.is_empty()
	var was_in_game := in_game
	_dbg("WebRTC session ended")
	_clear_local_network_state()

	if was_connecting:
		connection_failed.emit()
	else:
		server_closed.emit()
	if was_in_game:
		get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_connection_failed() -> void:
	if not _pending_action.is_empty():
		_fail_pending_connection("WebRTC connection failed")


func _fail_pending_connection(reason: String) -> void:
	_dbg(reason)
	if is_instance_valid(_tube_client):
		_suppress_session_left = true
		_tube_client.leave_session()
	_clear_local_network_state()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	if _suppress_session_left or (not _session_active and not in_game):
		return
	var was_in_game := in_game
	_dbg("Host disconnected")
	_clear_local_network_state()
	server_closed.emit()
	if was_in_game:
		get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_peer_connected(id: int) -> void:
	_dbg("peer connected: %d" % id)
	if not multiplayer.is_server():
		return
	# No join-in-progress in this version. Refuse a peer if the match started.
	if in_game:
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if not players.has(id):
		return
	players.erase(id)
	_loaded_peers.erase(id)
	player_left.emit(id)
	roster_changed.emit()

	if multiplayer.is_server():
		_sync_roster.rpc(players)
		var node := get_player_node(id)
		if node != null:
			node.queue_free()


# ============================================================
# RPCs
# ============================================================
@rpc("any_peer", "call_remote", "reliable")
func _register_player(pname: String, version: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_dbg("register request from %d name=%s version=%s" % [id, pname, version])
	if version != GAME_VERSION or players.size() >= MAX_PLAYERS or in_game:
		_dbg("rejected %d (version/full/in_game)" % id)
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return

	players[id] = {"name": _clean_name(pname)}
	_sync_roster.rpc(players)
	player_joined.emit(id, players[id])


@rpc("authority", "call_local", "reliable")
func _sync_roster(roster: Dictionary) -> void:
	players = roster
	_dbg("Roster: %d player(s)" % players.size())
	roster_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_start() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != leader_id():
		return
	_do_start()


func _do_start() -> void:
	if in_game or players.is_empty():
		return
	in_game = true
	_loaded_peers.clear()
	_spawned = false
	_server_world_ready = false
	_load_game.rpc()


@rpc("authority", "call_local", "reliable")
func _load_game() -> void:
	in_game = true
	game_started.emit()
	if show_loading_overlay.get_connections().is_empty():
		proceed_to_game()
	else:
		_show_loading()


func _show_loading() -> void:
	if _loading_layer:
		return
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 100
	get_tree().root.add_child(_loading_layer)
	loading_overlay = (load(LOADING_SCENE) as PackedScene).instantiate()
	_loading_layer.add_child(loading_overlay)
	loading_overlay.finished.connect(proceed_to_game, CONNECT_ONE_SHOT)
	loading_overlay.begin()


func proceed_to_game() -> void:
	if game_scene_res:
		get_tree().change_scene_to_packed(game_scene_res)
	else:
		get_tree().change_scene_to_file(GAME_SCENE)
		Explosion.warm(self, 4)
	get_tree().create_timer(15.0).timeout.connect(_clear_overlay)


## The local player calls this once its camera is current.
func notify_local_player_ready() -> void:
	if _loading_layer == null:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not is_instance_valid(_loading_layer):
		return
	var tween := create_tween()
	tween.tween_property(loading_overlay, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_clear_overlay)


func _clear_overlay() -> void:
	if is_instance_valid(_loading_layer):
		_loading_layer.queue_free()
	_loading_layer = null
	loading_overlay = null


@rpc("any_peer", "call_remote", "reliable")
func _peer_world_ready() -> void:
	if not multiplayer.is_server():
		return
	_loaded_peers[multiplayer.get_remote_sender_id()] = true
	_try_spawn()


# ============================================================
# Spawning: the host waits for its own world and every player's world.
# ============================================================
func _try_spawn() -> void:
	if _spawned or not _server_world_ready or _spawner == null:
		return
	for pid in players:
		if not _loaded_peers.has(pid):
			return
	_spawned = true
	_spawn_all()


func _spawn_all() -> void:
	var points := get_tree().get_nodes_in_group("spawn_points")
	var i := 0
	for pid in players:
		var pos := Vector3.ZERO
		if points.size() > 0:
			pos = (points[i % points.size()] as Node3D).global_position
		i += 1
		_spawner.spawn({"id": pid, "pos": pos})


func _spawn_player_func(data: Dictionary) -> Node:
	var scene := player_scene_res if player_scene_res else load(PLAYER_SCENE_PATH)
	var player: Node3D = (scene as PackedScene).instantiate()
	player.name = str(data["id"])
	player.set_multiplayer_authority(data["id"])
	player.position = data["pos"]
	return player


# ============================================================
# Utility / threaded preload
# ============================================================
func _clean_name(n: String) -> String:
	n = n.strip_edges().substr(0, 16)
	return n if n != "" else "Player"


func preload_assets() -> void:
	if is_preloading or preload_done:
		return
	is_preloading = true
	ResourceLoader.load_threaded_request(GAME_SCENE)
	ResourceLoader.load_threaded_request(PLAYER_SCENE_PATH)
	_poll_preload()


func _poll_preload() -> void:
	var game_progress := []
	var player_progress := []
	var game_status := ResourceLoader.load_threaded_get_status(GAME_SCENE, game_progress)
	var player_status := ResourceLoader.load_threaded_get_status(PLAYER_SCENE_PATH, player_progress)

	var total := 0.0
	total += (game_progress[0] if game_progress.size() > 0 else 0.0)
	total += (player_progress[0] if player_progress.size() > 0 else 0.0)
	preload_progress.emit(total / 2.0)

	if game_status == ResourceLoader.THREAD_LOAD_LOADED and player_status == ResourceLoader.THREAD_LOAD_LOADED:
		game_scene_res = ResourceLoader.load_threaded_get(GAME_SCENE)
		player_scene_res = ResourceLoader.load_threaded_get(PLAYER_SCENE_PATH)
		is_preloading = false
		preload_done = true
		preload_finished.emit()
		return

	if game_status == ResourceLoader.THREAD_LOAD_FAILED or player_status == ResourceLoader.THREAD_LOAD_FAILED:
		push_warning("NetworkManager: preload failed")
		is_preloading = false
		preload_failed.emit()
		return

	get_tree().create_timer(0.05).timeout.connect(_poll_preload)
