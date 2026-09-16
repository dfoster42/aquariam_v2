extends Node2D
## Top-level wiring: hands the camera the tank's bounds and routes taps into it.
##
## The tank does not read input and the camera does not know about fish. A tap is
## only a tap once the camera has ruled out a drag, so spawning has to be driven
## from there rather than from the tank's own _unhandled_input.

const MUTE_PATH: String = "user://audio.cfg"

@onready var aquarium: Aquarium = $Aquarium
@onready var camera: CameraRig = $CameraRig
@onready var ambient: AudioStreamPlayer = $Ambient
@onready var plop: AudioStreamPlayer = $Plop

func _ready() -> void:
	camera.setup(aquarium.bounds())
	camera.tapped.connect(_on_tapped)
	# Desktop closes via the window; a phone usually just suspends the app and may
	# never deliver a close request at all, so backgrounding has to save too.
	get_tree().auto_accept_quit = false

	var config := ConfigFile.new()
	if config.load(MUTE_PATH) == OK:
		AudioServer.set_bus_mute(
			AudioServer.get_bus_index("Master"), bool(config.get_value("audio", "muted", false)))

func _notification(what: int) -> void:
	var names := {
		NOTIFICATION_WM_CLOSE_REQUEST: "WM_CLOSE_REQUEST",
		NOTIFICATION_WM_GO_BACK_REQUEST: "WM_GO_BACK_REQUEST",
		NOTIFICATION_WM_WINDOW_FOCUS_OUT: "WM_WINDOW_FOCUS_OUT",
		NOTIFICATION_APPLICATION_PAUSED: "APPLICATION_PAUSED",
		NOTIFICATION_APPLICATION_FOCUS_OUT: "APPLICATION_FOCUS_OUT",
	}
	if names.has(what):
		print("[lifecycle] %s" % names[what])
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			aquarium.save()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_GO_BACK_REQUEST:
			aquarium.save()

func _on_tapped(world_position: Vector2) -> void:
	# The tank works in world units and a finger is a fixed size on the glass, so the
	# grab radius for remove mode is converted here, where the camera's zoom is known.
	var placed := aquarium.place_selected(
		world_position, Aquarium.REMOVE_REACH * camera.world_per_screen_unit())
	if placed is Food:
		plop.play()

## Muting is remembered across launches: a player who turned the sound off did not mean
## "until next time".
func set_muted(muted: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)
	var config := ConfigFile.new()
	config.set_value("audio", "muted", muted)
	config.save(MUTE_PATH)

func is_muted() -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))
