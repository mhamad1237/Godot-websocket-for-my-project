extends Control

signal finished

@onready var bar: ProgressBar = $ProgressBar
@onready var status_label: Label = $StatusLabel

var _active := false


func _ready() -> void:
	hide()
	NetworkManager.preload_progress.connect(_on_progress)
	NetworkManager.preload_finished.connect(_finish)
	NetworkManager.preload_failed.connect(_finish)  # manager falls back to a normal load


## Called by the lobby when the match is starting.
func begin() -> void:
	_active = true
	status_label.text = "Loading..."
	show()
	mouse_filter =Control.MOUSE_FILTER_STOP
	if NetworkManager.preload_done:
		_finish()
	elif not NetworkManager.is_preloading:
		NetworkManager.preload_assets()


func cancel() -> void:
	_active = false
	mouse_filter =Control.MOUSE_FILTER_IGNORE
	hide()


func _on_progress(p: float) -> void:
	bar.value = p * 100.0


func _finish() -> void:
	if not _active:
		return
	_active = false
	mouse_filter =Control.MOUSE_FILTER_IGNORE
	bar.value = 100.0
	status_label.text = "Entering match..."
	finished.emit()
