extends SceneTree
## Headless functional check of the whole main scene: tank, camera and UI.
## Run: godot --headless --script res://test/smoke_test.gd

const RUN_SECONDS: float = 5.0
const PAUSE_SECONDS: float = 1.5

var _main: Node2D
var _tank: Aquarium
var _camera: CameraRig
var _ui: CanvasLayer

var _elapsed: float = 0.0
var _started: bool = false
var _paused_at: Dictionary = {}
var _pause_phase: bool = false
var _start_positions: Dictionary = {}
var _population_before_run: int = 0
var _failures: Array[String] = []
# A member, not a local: a GDScript lambda captures locals by value.
var _eaten: int = 0

func _initialize() -> void:
	# The tank restores a save in preference to seeding, so a leftover save from a real
	# session would silently change what this test is measuring.
	TankStore.clear()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)

## Setup runs on the first frame, not in _initialize(): @onready references are
## only live once the scene is actually inside the running tree.
func _begin() -> void:
	_tank = _main.get_node("Aquarium")
	# Autosave off for every tank a test creates. Several tanks live at once here, and
	# each one writing to the same user://tank.json mid-test made this file flaky:
	# a run would fail three checks and then pass unchanged on the next invocation.
	_tank.autosave_interval = 0.0
	_camera = _main.get_node("CameraRig")
	_ui = _main.get_node("UI")
	_tank.fish_died.connect(func(_s: FishSpecies, old: bool) -> void:
		if not old: _eaten += 1)

	# Not a magic number: the scene's list is the source of truth, so this checks it is
	# populated and free of duplicates rather than asserting a count that every new
	# species would break.
	_check(_tank.available_species.size() >= 3,
		"expected at least 3 species, got %d" % _tank.available_species.size())
	var seen_species: Array[String] = []
	for species: FishSpecies in _tank.available_species:
		_check(not seen_species.has(species.resource_path),
			"species %s is listed twice" % species.display_name)
		seen_species.append(species.resource_path)
	# A new aquarium opens empty and the player fills it. This is the contract, so it is
	# asserted rather than assumed — everything below needs fish, and a tank that seeded
	# itself again would hide the regression behind a passing test.
	_check(_tank.population() == 0,
		"a new tank should open empty, got %d fish" % _tank.population())

	# Derived, not hardcoded: seeding follows each species' starting_count, so a tuning
	# change should not read as a test failure.
	var seeded := 0
	for species: FishSpecies in _tank.available_species:
		seeded += species.starting_count
	_tank.seed_starting_population()
	_check(_tank.population() == seeded,
		"seeding should give %d fish, got %d" % [seeded, _tank.population()])
	_check(_tank.bounds().size == _tank.tank_size, "bounds %s do not match tank_size %s" % [_tank.bounds().size, _tank.tank_size])

	_check_ui_passes_touches()
	_check_ui_on_screen()
	_check_safe_insets()
	_check_persistence()
	_check_species_selection()
	_check_tap_spawns()

	# Force a predation event: one shark dropped on top of one clownfish.
	_tank.spawn(_species_named("Clownfish"), Vector2(300, 300))
	_tank.spawn(_species_named("Shark"), Vector2(330, 300))
	_population_before_run = _tank.population()

	for fish in _tank.fish():
		_start_positions[fish] = fish.global_position

## Nothing VISIBLE may swallow a tap meant for the tank unless it says so.
##
## A Control defaults to MOUSE_FILTER_STOP, and one full-rect container left at the
## default silently eats every tap: fish stop spawning and nothing reports an error.
##
## Some controls block on purpose — the dock the picker scrolls inside, the population
## chip, the switcher that covers the tank while it is open. Those declare it by joining
## the `ui_blocker` group, so the check is "is this deliberate?" rather than "is this a
## Button?". Declaring one is not enough on its own: the blockers together must still
## leave the middle of the screen tappable, or a dock that grew to fill the view would
## pass this by being honest about it.
func _check_ui_passes_touches() -> void:
	var undeclared: Array[String] = []
	var blockers: Array[Rect2] = []
	var queue: Array[Node] = [_ui]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		queue.append_array(node.get_children())
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if control is Button:
			continue
		if not control.is_in_group("ui_blocker"):
			undeclared.append(control.name)
		blockers.append(control.get_global_rect())
	_check(undeclared.is_empty(),
		"UI nodes swallow tank taps without declaring it: %s" % ", ".join(undeclared))

	# The centre of the screen is where a player taps to drop a fish. Nothing may be
	# over it in the app's normal, panel-closed state.
	var view := Rect2(Vector2.ZERO, _ui.get_viewport().get_visible_rect().size)
	var centre := view.get_center()
	var covering: Array[String] = []
	for rect in blockers:
		if rect.has_point(centre):
			covering.append(str(rect))
	_check(covering.is_empty(), "the middle of the tank is covered by %s" % ", ".join(covering))

	# And the switcher must start closed, or the app opens onto a panel.
	var panel := _ui.get_node_or_null("Root/Sheet") as Control
	_check(panel != null and not panel.visible, "the tank switcher should start hidden")

## Every control must lie inside the viewport. A safe-area inset measured against the
## wrong rectangle put the pause button ~500px past the right edge and the picker below
## the bottom one, and nothing errored — the controls existed, reported visible, and
## simply were not where anyone could see them.
func _check_ui_on_screen() -> void:
	var view := Rect2(Vector2.ZERO, _ui.get_viewport().get_visible_rect().size)
	var offscreen: Array[String] = []
	var queue: Array[Node] = [_ui]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		queue.append_array(node.get_children())
		var control := node as Control
		if control == null or not control.is_visible_in_tree() or control.get_rect().get_area() <= 0.0:
			continue
		if not view.grow(1.0).encloses(control.get_global_rect()):
			offscreen.append("%s at %s" % [control.name, control.get_global_rect()])
	_check(offscreen.is_empty(), "UI outside the viewport: %s" % ", ".join(offscreen))


## The inset arithmetic, on rectangles the platform will not produce headlessly.
func _check_safe_insets() -> void:
	# A notched phone, fullscreen: a top inset for the notch, a bottom one for the
	# home indicator, and nothing either side in portrait.
	var phone: Vector4 = TankUI.safe_insets(
		Rect2i(0, 141, 1179, 2274), Vector2.ZERO, Vector2(1179, 2556))
	_check(phone.is_equal_approx(Vector4(0, 141, 0, 141)), "phone insets wrong: %s" % phone)

	# A desktop window on a screen with no notch: the safe area is the whole screen.
	var desktop: Vector4 = TankUI.safe_insets(
		Rect2i(0, 0, 1512, 982), Vector2.ZERO, Vector2(1512, 982))
	_check(desktop == Vector4.ZERO, "desktop insets should be zero, got %s" % desktop)

	# A window on a second screen offset from the origin: insets are relative to that
	# screen, not to the desktop origin.
	var offset: Vector4 = TankUI.safe_insets(
		Rect2i(1512, 0, 1512, 982), Vector2(1512, 0), Vector2(1512, 982))
	_check(offset == Vector4.ZERO, "offset-screen insets should be zero, got %s" % offset)

	# A desktop-style safe area, which means something else entirely: macOS reports the
	# screen minus the menu bar and the Dock, 66 and 180 on a 982px screen. Uncapped,
	# that 180 became a 330px-tall control bar over a 1280px tank. The cap is what keeps
	# a platform that means something else by "safe area" from eating the layout — and
	# _apply_safe_area does not ask a desktop in the first place.
	var macos: Vector4 = TankUI.safe_insets(
		Rect2i(0, 66, 1512, 736), Vector2.ZERO, Vector2(1512, 982))
	var ceiling := 982.0 * TankUI.MAX_INSET_FRACTION
	_check(macos.is_equal_approx(Vector4(0, 66, 0, ceiling)),
		"macOS insets should cap at %.1f, got %s" % [ceiling, macos])
	_check(not TankUI.platform_has_cutouts() or OS.get_name() in ["iOS", "Android"],
		"only the handhelds should report cutouts, not %s" % OS.get_name())

	# A platform reporting nothing must not produce negative margins.
	var empty: Vector4 = TankUI.safe_insets(Rect2i(0, 0, 0, 0), Vector2.ZERO, Vector2(800, 600))
	_check(empty == Vector4.ZERO, "empty safe area should give zero insets, got %s" % empty)


## Save and restore must round-trip: same count, same species, same positions.
func _check_persistence() -> void:
	var before: Array[Dictionary] = []
	for f in _tank.fish():
		before.append({"species": f.species.resource_path, "pos": f.global_position})

	_check(TankStore.save(_tank) == OK, "saving the tank failed")
	var data := TankStore.read()
	_check(data.get("fish", []).size() == before.size(),
		"save holds %d fish, tank has %d" % [data.get("fish", []).size(), before.size()])

	# Restore into a second tank and compare.
	var other: Aquarium = load("res://scenes/aquarium.tscn").instantiate()
	other.autosave_interval = 0.0
	root.add_child(other)
	other.clear_tank()
	_check(other.restore(data), "restore() reported nothing restored")
	_check(other.population() == before.size(),
		"restored %d fish, expected %d" % [other.population(), before.size()])

	# Compare as sets, not as two lists paired by sorted x.
	#
	# Pairing by a single coordinate mis-matches as soon as two fish share an x, which
	# is common once a tank holds dozens — the earlier version reported "restored fish
	# 18 is the wrong species" purely because the pairing had slipped.
	var expected_keys: Array[String] = []
	for entry: Dictionary in before:
		expected_keys.append("%s@%d,%d" % [
			entry["species"], roundi(entry["pos"].x), roundi(entry["pos"].y)])
	var restored_keys: Array[String] = []
	for f in other.fish():
		restored_keys.append("%s@%d,%d" % [
			f.species.resource_path, roundi(f.global_position.x), roundi(f.global_position.y)])
	expected_keys.sort()
	restored_keys.sort()

	var missing := 0
	for key in expected_keys:
		if not restored_keys.has(key):
			missing += 1
	_check(missing == 0, "%d of %d fish did not come back at the same species and place"
		% [missing, expected_keys.size()])

	# A save naming a species the build no longer has must cost that fish, not the tank.
	var salted := data.duplicate(true)
	salted["fish"] = (salted["fish"] as Array).duplicate(true)
	(salted["fish"] as Array).append({"species": "res://resources/species/ghost.tres", "x": 10, "y": 10})
	var third: Aquarium = load("res://scenes/aquarium.tscn").instantiate()
	third.autosave_interval = 0.0
	root.add_child(third)
	third.clear_tank()
	_check(third.restore(salted), "restore() gave up because of one unknown species")
	_check(third.population() == before.size(),
		"unknown species should be skipped: got %d, expected %d" % [third.population(), before.size()])

	other.queue_free()
	third.queue_free()
	TankStore.clear()


func _tank_fish(tank: Aquarium) -> Array[Fish]:
	return tank.fish()


func _check_species_selection() -> void:
	var shark := _species_named("Shark")
	var seen: Array[FishSpecies] = []
	_tank.species_selected.connect(func(s: FishSpecies) -> void: seen.append(s))
	_tank.select_species(shark)
	_check(_tank.selected_species == shark, "select_species did not change the selection")
	_check(seen.size() == 1 and seen[0] == shark, "species_selected did not fire exactly once")

func _check_tap_spawns() -> void:
	var before := _tank.population()
	_camera.tapped.emit(_tank.bounds().get_center())
	_check(_tank.population() == before + 1, "a tap did not spawn a fish")

func _process(delta: float) -> bool:
	if not _started:
		_started = true
		_begin()
		return false

	_elapsed += delta

	if not _pause_phase:
		if _elapsed < RUN_SECONDS:
			return false
		_report_movement()
		_pause_phase = true
		_elapsed = 0.0
		_tank.set_paused(true)
		for fish in _tank.fish():
			_paused_at[fish] = fish.global_position
		return false

	if _elapsed < PAUSE_SECONDS:
		return false
	_report_pause()
	_finish()
	return true

func _report_movement() -> void:
	var bounds := _tank.bounds()
	var moved := 0
	var escaped := 0
	for fish in _tank.fish():
		if _start_positions.has(fish) and fish.global_position.distance_to(_start_positions[fish]) > 1.0:
			moved += 1
		if not bounds.grow(2.0).has_point(fish.global_position):
			escaped += 1

	_check(moved > 0, "no fish moved in %.0fs" % RUN_SECONDS)
	_check(escaped == 0, "%d fish escaped the tank bounds" % escaped)
	# Breeding can add fish during the run, so count the eaten directly rather than
	# inferring predation from the population falling.
	_check(_eaten > 0, "shark ate nothing in %.0fs" % RUN_SECONDS)
	print("moved %d, escaped %d, survivors %d" % [moved, escaped, _tank.population()])

func _report_pause() -> void:
	var drifted := 0
	for fish in _tank.fish():
		if _paused_at.has(fish) and fish.global_position.distance_to(_paused_at[fish]) > 0.01:
			drifted += 1
	_check(drifted == 0, "%d fish moved while the tank was paused" % drifted)
	_check(_tank.is_paused(), "tank does not report itself paused")
	print("paused for %.1fs, drifted %d" % [PAUSE_SECONDS, drifted])

func _finish() -> void:
	print("---")
	if _failures.is_empty():
		print("RESULT: PASS")
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	print("RESULT: FAIL (%d)" % _failures.size())
	quit(1)

func _species_named(name: String) -> FishSpecies:
	for species: FishSpecies in _tank.available_species:
		if species.display_name == name:
			return species
	return null

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
