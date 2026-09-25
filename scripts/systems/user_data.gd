class_name UserData
extends RefCounted
## Where persistent files live, and a separate place for runs that are not the game.
##
## Tests, dev tools and the real game used to share one user:// directory
## (~/Library/Application Support/Godot/app_userdata/Aquarium on macOS). Every test and
## tool calls TankStore.clear() on startup, so running the suite locally deleted the
## player's saved aquariums, outright and not to the Trash. settings_test rewrote the
## player's mute setting the same way, and slots_test planted a legacy save in the real
## directory and migrated it into the player's slot list. CI never noticed because it
## runs in a clean container every time.
##
## The fix is decided here, once, rather than by each test remembering to opt in. A run
## started as `godot --script <file>` has a script attached to its main loop; the game
## itself — launched normally, from the editor, or as an exported build — runs a plain
## SceneTree with none. Measured both ways before this was written. So a test added
## tomorrow is protected whether or not its author has heard of this file.
##
## Each script run gets its OWN subtree, keyed by process id, created on first use. One
## shared sandbox let two runs at once — a test and a tool, say — clear each other's
## files, and because nothing created the directory, a test that only wrote a settings
## file failed on a clean checkout: ConfigFile cannot create a missing parent, and it
## had only been passing because the tests that happen to run before it made the folder.
## Subtrees left by runs that have finished are removed the next time a run starts.

const REAL_ROOT: String = "user://"
## Parent of every run's sandbox. Nothing is ever written directly into it.
const SANDBOX_ROOT: String = "user://sandbox/"

static var _decided: bool = false
static var _sandboxed: bool = false
static var _run_root: String = ""

## Whether this run keeps its files away from the player's.
static func is_sandboxed() -> bool:
	if not _decided:
		var loop := Engine.get_main_loop()
		# Only cached once a main loop exists. Asked before that — which nothing does
		# today — the answer is "sandboxed", the safe side, and it is asked again later.
		if loop == null:
			return true
		_decided = true
		_sandboxed = loop.get_script() != null
	return _sandboxed

## The user:// path for `name` in this run's directory. The directory exists on return.
static func path(name: String) -> String:
	if not is_sandboxed():
		return REAL_ROOT + name
	return run_root() + name

## This run's sandbox directory, created (and stale ones pruned) on first use.
static func run_root() -> String:
	if _run_root == "":
		_run_root = "%s%d/" % [SANDBOX_ROOT, OS.get_process_id()]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_run_root))
		prune_stale()
	return _run_root

## Removes sandboxes left by runs that are no longer running.
##
## Only directories named for a process id, only inside SANDBOX_ROOT, and never this
## run's own. The removal is recursive, so every one of those conditions is load-bearing.
static func prune_stale() -> void:
	var base := ProjectSettings.globalize_path(SANDBOX_ROOT)
	var dir := DirAccess.open(base)
	if dir == null:
		return
	var mine := OS.get_process_id()
	for name in dir.get_directories():
		if not name.is_valid_int():
			continue
		var pid := name.to_int()
		if pid == mine or OS.is_process_running(pid):
			continue
		_remove_tree(base.path_join(name), base)

## Deletes `path` and everything under it — refusing anything not strictly inside `fence`.
static func _remove_tree(path: String, fence: String) -> void:
	var inside := fence.trim_suffix("/") + "/"
	if not path.begins_with(inside) or path.length() <= inside.length():
		push_error("refused to remove %s: not strictly inside %s" % [path, inside])
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub), fence)
	DirAccess.remove_absolute(path)
