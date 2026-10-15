extends Node

var socket := WebSocketPeer.new()
var last_state := -1

func _ready():
	var err := socket.connect_to_url("wss://zj2a51j4thjj-production-tzymyhgd.europe-west1.suga.run")
	print("connect result: ", err)  # 0 means OK

func _process(_d):
	socket.poll()
	var state := socket.get_ready_state()

	if state != last_state:
		last_state = state
		print("state: ", ["CONNECTING", "OPEN", "CLOSING", "CLOSED"][state])

	if state == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count():
			print("received: ", socket.get_packet().get_string_from_utf8())

	elif state == WebSocketPeer.STATE_CLOSED:
		print("closed, code: ", socket.get_close_code(), " reason: ", socket.get_close_reason())
		set_process(false)
