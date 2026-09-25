extends SceneTree
## Tests and tools must never touch the player's saves.
##
## They used to share one user:// directory with the game, and every one of them calls
## TankStore.clear() on startup — so running the suite locally deleted the player's saved
## aquariums, outright, on every run. CI runs in a clean container and could never see it.
##
## This test is built to be safe even when the thing it guards has regressed. Every path
## is checked BEFORE any storage is touched, and a single failure there quits on the spot:
## a broken sandbox must produce a failing test, not another deletion.
##
## Run: godot --headless --script res://test/sandbox_test.gd

var _failures: Array[String] = []

func _initialize() -> void:
	_check(UserData.is_sandboxed(), "a --script run is not sandboxed")
	var paths := {
		"tanks dir": TankStore.dir(),
		"tank index": TankStore.index_path(),
		"legacy save": TankStore.legacy_path(),
		"slot file": TankStore.slot_path("tank_1"),
		"mute setting": load("res://scripts/main.gd").mute_path(),
	}
	for label: String in paths:
		_check(String(paths[label]).begins_with(UserData.SANDBOX_ROOT),
			"the %s resolves to %s, outside the sandbox" % [label, paths[label]])
	if not _failures.is_empty():
		# Stop here. Everything below writes and clears; with any of these paths pointing
		# at the player's directory, carrying on would do the exact damage being tested.
		_finish()
		return

	var before := _snapshot()

	# A full round trip in the sandbox: create a slot, write a tank, read it, clear.
	TankStore.clear()
	var id := TankStore.create_slot("Sandbox check")
	_check(FileAccess.file_exists(TankStore.index_path()), "creating a slot wrote no index")
	_check(id != "", "no slot was created")
	TankStore.clear()
	_check(not FileAccess.file_exists(TankStore.index_path()), "clear() left the sandbox index")

	var after := _snapshot()
	_check(before == after,
		"the player's tanks directory changed during a sandboxed run:\n  before %s\n  after  %s"
			% [before, after])
	print("  real tanks directory: %d file(s), unchanged" % before.size())
	_finish()

## Every file in the player's real tanks directory, with its size, time and contents hash.
## Read-only: nothing here writes to that directory.
func _snapshot() -> Dictionary:
	var shot := {}
	var real := ProjectSettings.globalize_path(UserData.REAL_ROOT + "tanks")
	var dir := DirAccess.open(real)
	if dir == null:
		return shot
	for name in dir.get_files():
		var full := real.path_join(name)
		shot[name] = "%d:%d:%s" % [FileAccess.get_file_as_bytes(full).size(),
			FileAccess.get_modified_time(full), FileAccess.get_md5(full)]
	return shot

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("RESULT: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("RESULT: FAIL")
	quit(0 if _failures.is_empty() else 1)
