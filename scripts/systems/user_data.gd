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
## SceneTree with none. Measured both ways before this was written. Every such script
## run gets its own subtree, so a test added tomorrow is protected whether or not its
## author has heard of this file.

const REAL_ROOT: String = "user://"
const SANDBOX_ROOT: String = "user://sandbox/"

static var _decided: bool = false
static var _sandboxed: bool = false

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

## The user:// path for `name` in this run's directory.
static func path(name: String) -> String:
	return (SANDBOX_ROOT if is_sandboxed() else REAL_ROOT) + name
