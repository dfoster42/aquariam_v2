extends Node2D
## Top-level wiring: hands the camera the tank's bounds and routes taps into it.
##
## The tank does not read input and the camera does not know about fish. A tap is
## only a tap once the camera has ruled out a drag, so spawning has to be driven
## from there rather than from the tank's own _unhandled_input.

@onready var aquarium: Aquarium = $Aquarium
@onready var camera: CameraRig = $CameraRig

func _ready() -> void:
	camera.setup(aquarium.bounds())
	camera.tapped.connect(_on_tapped)
	# Desktop closes via the window; a phone usually just suspends the app and may
	# never deliver a close request at all, so backgrounding has to save too.
	get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			aquarium.save()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_GO_BACK_REQUEST:
			aquarium.save()

func _on_tapped(world_position: Vector2) -> void:
	aquarium.spawn_selected(world_position)
