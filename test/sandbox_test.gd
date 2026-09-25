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

	# Each run has a directory of its own, so two runs at once cannot clear each other.
	_check(UserData.run_root().contains("/%d/" % OS.get_process_id()),
		"this run's sandbox %s is not its own" % UserData.run_root())
	_check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(UserData.run_root())),
		"this run's sandbox directory was not created")

	_check_pruning()

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

## Finished runs' sandboxes are removed; nothing else is.
func _check_pruning() -> void:
	var base := ProjectSettings.globalize_path(UserData.SANDBOX_ROOT)
	var dead := _dead_pid()
	var stale := base.path_join(str(dead))
	DirAccess.make_dir_recursive_absolute(stale.path_join("tanks/nested"))
	FileAccess.open(stale.path_join("tanks/tank_1.json"), FileAccess.WRITE).store_string("{}")
	FileAccess.open(stale.path_join("tanks/nested/x"), FileAccess.WRITE).store_string("x")
	# A directory named for a process that IS running, and one not named for a process at
	# all. Neither may be touched. The live one is a process of our own: an earlier version
	# used pid 1, which macOS reports as not running to an unprivileged caller — it belongs
	# to root — so the "live" directory was pruned and the test blamed the code. Every
	# sandbox belongs to a run of this same user, which is the case that has to hold.
	var sleeper := OS.create_process("sleep", ["30"])
	_check(sleeper > 0 and OS.is_process_running(sleeper), "could not start a live process to test with")
	var live := base.path_join(str(sleeper))
	var other := base.path_join("not_a_pid")
	DirAccess.make_dir_recursive_absolute(live)
	DirAccess.make_dir_recursive_absolute(other)

	UserData.prune_stale()
	_check(not DirAccess.dir_exists_absolute(stale), "a finished run's sandbox was not pruned")
	_check(DirAccess.dir_exists_absolute(live), "pruning removed a running process's sandbox")
	_check(DirAccess.dir_exists_absolute(other), "pruning removed a directory not named for a pid")
	_check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(UserData.run_root())),
		"pruning removed this run's own sandbox")
	DirAccess.remove_absolute(live)
	DirAccess.remove_absolute(other)
	OS.kill(sleeper)

	# The recursive delete refuses anything not strictly inside its fence. Both paths are
	# harmless if the guard were missing: one does not exist, one is the empty-ish base.
	UserData._remove_tree("/nonexistent_aquarium_check/x", base)
	UserData._remove_tree(base, base)
	_check(DirAccess.dir_exists_absolute(base), "the recursive delete removed its own fence")

func _dead_pid() -> int:
	for pid in range(99999, 50000, -1):
		if not OS.is_process_running(pid):
			return pid
	return 99999

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
