extends SceneTree
## Things the app remembers that are not the tank itself.
## Run: godot --headless --script res://test/settings_test.gd

const MUTE_PATH: String = "user://audio.cfg"

var _started: bool = false
var _failures: Array[String] = []

func _initialize() -> void:
	if FileAccess.file_exists(MUTE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MUTE_PATH))

func _process(_d: float) -> bool:
	if _started:
		return true
	_started = true
	_run()
	return true

func _run() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.get_node("Aquarium").autosave_interval = 0.0
	root.add_child(main)

	_check(not main.is_muted(), "a fresh install should start unmuted")

	# Muting must survive a relaunch. Someone who turned the sound off did not mean
	# "until next time", and an ambient app that comes back loud gets deleted.
	main.set_muted(true)
	_check(main.is_muted(), "set_muted(true) did not take effect")
	_check(FileAccess.file_exists(MUTE_PATH), "muting wrote no settings file")

	var config := ConfigFile.new()
	_check(config.load(MUTE_PATH) == OK, "the settings file is unreadable")
	_check(bool(config.get_value("audio", "muted", false)), "the settings file does not record the mute")

	# A second instance reads it back, which is what a relaunch does.
	main.set_muted(false)
	_check(not main.is_muted(), "unmuting did not take effect")
	main.set_muted(true)

	var second: Node2D = load("res://scenes/main.tscn").instantiate()
	second.get_node("Aquarium").autosave_interval = 0.0
	root.add_child(second)
	_check(second.is_muted(), "a relaunched app came back unmuted after the sound was turned off")

	# Leave the machine as we found it.
	second.set_muted(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MUTE_PATH))

	if _failures.is_empty():
		print("RESULT: PASS")
		return
	for f in _failures:
		printerr("FAIL: " + f)
	print("RESULT: FAIL (%d)" % _failures.size())
	quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
