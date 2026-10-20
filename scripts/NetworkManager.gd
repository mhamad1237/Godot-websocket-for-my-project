# ============================================================
# NetworkManager.gd  (dedicated server + WebSocket version)
# ============================================================
# - The SERVER is a headless Godot instance (peer id 1). It is NOT a player.
# - Every player is a client that joins over wss://.
# - The first player in the room (lowest id) is the "leader" and can press Start.
extends Node
signal preload_progress(progress: float)
signal preload_finished
var offline := false

signal connection_succeeded
signal connection_failed
signal server_closed
signal player_joined(id: int, info: Dictionary)
signal player_left(id: int)
signal roster_changed
signal game_started
signal preload_failed
signal show_loading_overlay
signal debug_status(text: String)   # lobby shows these in its status label

# ---- Edit these for your project ----
const SERVER_URL := "wss://zj2a51j4thjj-production-tzymyhgd.europe-west1.suga.run"   # no port, Suga uses 443
const DEFAULT_PORT := 9080                         # server listens here (or $PORT)
const MAX_PLAYERS := 8
const GAME_VERSION := "0.1"
const LOADING_SCENE := "res://scenes/loading.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const PLAYER_SCENE_PATH := "res://scenes/player.tscn"
const SERVER_SCENE := "res://scenes/server_boot.tscn"  # empty Node scene
# -------------------------------------

## peer_id -> {"name": String}. Same on every peer (server broadcasts it).
## The dedicated server (id 1) is never in this dictionary.
var players: Dictionary = {}
var local_name := "Player"
var in_game := false
var dedicated := false

var _players_root: Node
var _spawner: MultiplayerSpawner
var _loaded_peers: Dictionary = {}
var _server_world_ready := false
var _spawned := false

var game_scene_res: PackedScene = null
var player_scene_res: PackedScene = null
var is_preloading := false
var preload_done := false
var loading_overlay: Control = null   # set by the lobby
var _loading_layer: CanvasLayer = null


var _last_conn_status := -1


## Clients: shown on screen via debug_status. Server: goes to the Suga logs.
func _dbg(text: String) -> void:
	if dedicated:
		print("[NET] ", text)
	else:
		debug_status.emit(text)


func _process(_delta: float) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null or dedicated:
		return
	var st := peer.get_connection_status()
	if st != _last_conn_status:
		_last_conn_status = st
		_dbg("Status: " + ["DISCONNECTED", "CONNECTING", "CONNECTED"][st])


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Started with:  godot --headless ... -- --server
	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args():
		start_dedicated_server()


# ============================================================
# Public API
# ============================================================
func is_online() -> bool:
	return multiplayer.multiplayer_peer is WebSocketMultiplayerPeer


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


## Id of the player allowed to press Start (lowest id in the room), or -1.
func leader_id() -> int:
	var ids := players.keys()
	if ids.is_empty():
		return -1
	return ids.min()


func is_leader() -> bool:
	return is_online() and not dedicated and my_id() == leader_id()


## Kept so the lobby's start-button check still works.
## If other scripts use is_host() to mean "has authority", use multiplayer.is_server() there.
func is_host() -> bool:
	return is_leader()


## SERVER ONLY. Runs on the headless instance.
func start_dedicated_server() -> Error:
	disconnect_game()
	var env_port := OS.get_environment("PORT")
	var port := int(env_port) if env_port != "" else DEFAULT_PORT
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)   # plain ws; Suga's gateway adds TLS
	if err != OK:
		push_error("NetworkManager: create_server failed (%s)" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	dedicated = true
	players.clear()
	Engine.max_fps = 60   # don't burn CPU on a headless server
	print("Dedicated server listening on port ", port)
	return OK


## CLIENT. Connect to the online server.
func join_online(player_name: String, url: String = SERVER_URL) -> Error:
	disconnect_game()
	local_name = _clean_name(player_name)
	_last_conn_status = -1
	_dbg("Connecting to %s as %s" % [url, local_name])
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	_dbg("create_client: " + error_string(err))
	if err != OK:
		push_warning("NetworkManager: create_client failed (%s)" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	_dbg("Searching for server...")
	return OK


## Closes the connection and resets all state. Safe to call anytime.
func disconnect_game() -> void:
	offline = false
	Global.clear_local_refs()
	if multiplayer.multiplayer_peer is WebSocketMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	_loaded_peers.clear()
	_players_root = null
	_spawner = null
	_server_world_ready = false
	_spawned = false
	in_game = false
	_clear_overlay()
func start_singleplayer(player_name: String) -> void:
	disconnect_game()
	offline = true
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()   # new
	local_name = _clean_name(player_name)
	players = {1: {"name": local_name}}
	_loaded_peers = {1: true}
	_spawned = false
	_server_world_ready = false
	in_game = true
	proceed_to_game()

## Leave a running match and go back to the lobby.
func leave_game() -> void:
	disconnect_game()
	get_tree().change_scene_to_file(LOBBY_SCENE)


## Leader presses Start. Safe to call from any client.
func start_game() -> void:
	if not is_online() or in_game:
		return
	if multiplayer.is_server():
		_do_start()
	else:
		_request_start.rpc_id(1)


## Call from the game scene's _ready(), passing the node that holds the
## players and the MultiplayerSpawner (its Spawn Path must point to that node).
## Runs on the server too, so the server has the spawner ready.
func register_world(players_root: Node, spawner: MultiplayerSpawner) -> void:
	_players_root = players_root
	_spawner = spawner
	_spawner.spawn_function = _spawn_player_func
	if offline or multiplayer.is_server():
		_server_world_ready = true
		_try_spawn()
	else:
		_peer_world_ready.rpc_id(1)


## Returns the spawned player node for a peer id, or null.
func get_player_node(id: int) -> Node:
	if _players_root == null:
		return null
	return _players_root.get_node_or_null(str(id))


# ============================================================
# Connection callbacks
# ============================================================
func _on_peer_connected(id: int) -> void:
	_dbg("peer connected: %d" % id)
	if not multiplayer.is_server():
		return
	# No join-in-progress in this version: reject anyone who connects mid-match.
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
		if node:
			node.queue_free()  # spawner despawns it on every peer
		# Everyone left a running match: send the server back to its idle state.
		if dedicated and in_game and players.is_empty():
			_reset_server.call_deferred()


func _on_connected_to_server() -> void:
	_dbg("Connected! id=%d, registering as %s" % [multiplayer.get_unique_id(), local_name])
	_register_player.rpc_id(1, local_name, GAME_VERSION)
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	_dbg("Connection FAILED: server not found or refused")
	disconnect_game()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	_dbg("Server disconnected")
	var was_in_game := in_game
	disconnect_game()
	server_closed.emit()
	if was_in_game:
		get_tree().change_scene_to_file(LOBBY_SCENE)


func _reset_server() -> void:
	in_game = false
	_loaded_peers.clear()
	_players_root = null
	_spawner = null
	_server_world_ready = false
	_spawned = false
	get_tree().change_scene_to_file(SERVER_SCENE)
	print("Match over, server back to lobby state")


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
		return   # only the leader may start
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
	# If nothing is listening (no overlay in this scene, e.g. the server), just go.
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
		Explosion.warm(self,4)
	# Safety net so the screen can never get stuck
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
	var tw := create_tween()
	tw.tween_property(loading_overlay, "modulate:a", 0.0, 0.3)
	tw.tween_callback(_clear_overlay)


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
# Spawning (server spawns once its own world AND every player has loaded)
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


# Runs on EVERY peer (set as the spawner's spawn_function).
func _spawn_player_func(data: Dictionary) -> Node:
	var scene := player_scene_res if player_scene_res else load(PLAYER_SCENE_PATH)
	var p: Node3D = (scene as PackedScene).instantiate()
	p.name = str(data["id"])
	p.set_multiplayer_authority(data["id"])
	p.position = data["pos"]
	return p


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
