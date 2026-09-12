extends SceneTree
## Runs the tank in a real window, lets it settle, captures a frame to PNG.
## Run: godot --script res://tools/screenshot.gd

const SETTLE_FRAMES: int = 150

var _frames: int = 0

func _initialize() -> void:
	root.add_child(load("res://scenes/aquarium.tscn").instantiate())

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	var image := root.get_texture().get_image()
	var path := "user://tank.png"
	image.save_png(path)
	print("SHOT:" + ProjectSettings.globalize_path(path))
	return true
