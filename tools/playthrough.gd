extends SceneTree
## Plays the game through the real UI and photographs it at the zoom a player holds.
##
## tools/colony_demo.gd drives the tank from code and pulls the camera out to the whole
## map, which is how the mechanic was judged and not how anyone will see it. This does
## only what a player can: presses picker tiles by their label and taps through
## `main._on_tapped`, where the camera delivers a tap. Time between beats is
## fast-forwarded through the tank's own colony tick, so a session's worth of growth
## fits in a capture.
##
## Run: godot --script res://tools/playthrough.gd [-- --out-dir DIR]

const SETTLE: int = 10

var _main: Node2D
var _tank: Aquarium
var _ui: CanvasLayer
var _camera: CameraRig
var _out_dir: String = "user://"
var _frames: int = 0
var _next: int = 0
var _step: int = 0
var _target: Colony

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out-dir")
	if i != -1 and i + 1 < args.size():
		_out_dir = args[i + 1]
	TankStore.clear()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_tank = _main.get_node("Aquarium")
		_tank.autosave_interval = 0.0
		_ui = _main.get_node("UI")
		_camera = _main.get_node("CameraRig")
		_camera.position = Vector2(1500, 1080)
		_next = SETTLE
		return false
	if _frames < _next:
		return false

	match _step:
		0:
			# Found a few reefs the way a player would.
			_found("Coral", 900.0)
			_found("Coral", 1250.0)
			_found("Kelp Court", 1600.0)
			_found("Kelp Court", 2150.0)
			_press("Deep Blue")
			_tap(Vector2(1500.0, 500.0))
			_shoot("1-founded")
			_advance(150.0)
			_next = _frames + SETTLE
		1:
			_shoot("2-grown")
			_report()
			_target = _biggest()
			if _target == null:
				push_warning("no reef on screen to bleach")
				quit(1)
				return true
			print("bleaching %s at x=%.0f" % [_target.faction.display_name, _target.global_position.x])
			_press("Bleach")
			_tap(_target.global_position + Vector2(0, -60))
			_next = _frames + 3
		2:
			_shoot("3-bleach-landing")
			_advance(0.5)
			_next = _frames + 3
		3:
			_shoot("4-bleach-travelling")
			_advance(90.0)
			_next = _frames + SETTLE
		4:
			_shoot("5-aftermath")
			_report()
			var tech := _ui.find_child("TechButton", true, false) as Button
			if tech != null:
				tech.pressed.emit()
			_next = _frames + SETTLE
		5:
			_shoot("6-tech")
			quit(0)
			return true
	_step += 1
	return false

func _found(faction: String, near: float) -> void:
	if not _press(faction):
		return
	var f: Faction = null
	for candidate in _tank.available_factions:
		if candidate.display_name == faction:
			f = candidate
	var x := near
	for i in 200:
		var probe := near + float(i) * 14.0 * (1.0 if i % 2 == 0 else -1.0)
		if f != null and _tank.can_found(f, probe):
			x = probe
			break
	_tap(Vector2(x, 400.0))

func _press(label: String) -> bool:
	var picker: HBoxContainer = _ui.get_node("%Picker")
	for child in picker.get_children():
		var button := child as Button
		if button != null and button.text == label:
			button.button_pressed = true
			button.pressed.emit()
			return true
	push_warning("no %s tile" % label)
	return false

func _tap(world: Vector2) -> void:
	_main._on_tapped(world)

func _advance(seconds: float) -> void:
	for i in int(seconds / 0.1):
		_tank._tick_colonies(0.1)

## The biggest reef the player can actually SEE. The first version picked the biggest on
## the whole map, which was off-screen, and photographed a disaster nobody could watch.
func _biggest() -> Colony:
	var view := root.get_visible_rect().size / _camera.zoom
	var seen := Rect2(_camera.get_screen_center_position() - view * 0.5, view)
	var best: Colony = null
	for colony in _tank.colonies():
		if not colony.is_benthic() or not seen.has_point(colony.global_position):
			continue
		if best == null or colony.biomass > best.biomass:
			best = colony
	return best

func _report() -> void:
	var parts: Array[String] = []
	for faction in _tank.available_factions:
		parts.append("%s %.1f%%" % [faction.display_name,
			_tank.territory().faction_share(faction) * 100.0])
	print(", ".join(parts))

func _shoot(name: String) -> void:
	var path := "%s/%s.png" % [_out_dir.trim_suffix("/"), name]
	root.get_texture().get_image().save_png(path)
	print("SHOT:" + path.get_file())
