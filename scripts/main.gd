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

func _on_tapped(world_position: Vector2) -> void:
	aquarium.spawn_selected(world_position)
