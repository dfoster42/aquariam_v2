extends SceneTree
## Runs the tank in a real window, lets it settle, captures the UI's states to PNG.
## Run: godot --script res://tools/screenshot.gd [-- --out-dir DIR]
##
## Several shots in one run rather than one: the controls are only worth looking at
## over moving water, and relaunching for each state gives a different tank behind each
## one, which makes two shots impossible to compare.

const SETTLE_FRAMES: int = 150
## Frames between shots. A Control resized this frame reports its old rect until the
## next layout pass, so a panel opened and captured in the same frame photographs at
## the wrong size — which reads as a layout bug that is not there.
const SHOT_GAP: int = 6

var _main: Node2D
var _ui: CanvasLayer
var _frames: int = 0
var _step: int = 0
var _out_dir: String = "user://"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--out-dir")
	if index != -1 and index + 1 < args.size():
		_out_dir = args[index + 1]
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_ui = _main.get_node("UI")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		# Not in _initialize(): a node added there is not ready until the first frame,
		# so spawn() refuses and every shot comes back of an empty tank. Seeded only
		# when there is nothing saved, so a real tank is photographed as it is.
		var tank: Aquarium = _main.get_node("Aquarium")
		if tank.population() == 0:
			tank.seed_starting_population()
	if _frames < SETTLE_FRAMES:
		return false
	if (_frames - SETTLE_FRAMES) % SHOT_GAP != 0:
		return false

	match _step:
		0:
			_shoot("tank")
		1:
			# The picker's last entry: the strip has to be scrolled to reach it on a
			# phone, which is the whole reason it scrolls.
			var picker: HBoxContainer = _ui.get_node("%Picker")
			var last := picker.get_child(picker.get_child_count() - 1) as Button
			last.button_pressed = true
			last.pressed.emit()
			_ui.get_node("%PickerScroll").scroll_horizontal = 9999
		2:
			_shoot("picker-end")
		3:
			_main.get_node("Aquarium").set_paused(true)
			_ui.get_node("%Tanks").pressed.emit()
		4:
			_shoot("switcher")
		_:
			return true
	_step += 1
	return false

func _shoot(name: String) -> void:
	var path := "%s/%s.png" % [_out_dir.trim_suffix("/"), name]
	root.get_texture().get_image().save_png(path)
	print("SHOT:" + ProjectSettings.globalize_path(path))
