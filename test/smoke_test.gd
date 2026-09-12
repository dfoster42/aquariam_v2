extends SceneTree
## Headless functional check of the tank: spawning, movement, bounds, predation.
## Run: godot --headless --script res://test/smoke_test.gd

const RUN_SECONDS: float = 6.0

var _tank: Aquarium
var _elapsed: float = 0.0
var _started: bool = false
var _start_positions: Dictionary = {}
var _failures: Array[String] = []

func _initialize() -> void:
	_tank = load("res://scenes/aquarium.tscn").instantiate()
	root.add_child(_tank)

## Setup runs on the first frame, not in _initialize(): the tank's @onready
## references are only live once it is actually inside the running tree.
func _begin() -> void:
	_check(_tank.available_species.size() == 3, "expected 3 species, got %d" % _tank.available_species.size())
	_check(_tank.population() == 9, "expected 9 seeded fish, got %d" % _tank.population())

	# Force a predation event: one shark dropped on top of one clownfish.
	_tank.spawn(_species_named("Clownfish"), Vector2(300, 300))
	_tank.spawn(_species_named("Shark"), Vector2(330, 300))
	_check(_tank.population() == 11, "expected 11 after seeding, got %d" % _tank.population())

	for fish: Fish in _tank.get_node("FishLayer").get_children():
		_start_positions[fish] = fish.global_position

func _process(delta: float) -> bool:
	if not _started:
		_started = true
		_begin()
	_elapsed += delta
	if _elapsed < RUN_SECONDS:
		return false
	_report()
	return true

func _report() -> void:
	var bounds := Rect2(Vector2.ZERO, _tank.get_viewport_rect().size)
	var moved := 0
	var out_of_bounds := 0

	for fish: Fish in _tank.get_node("FishLayer").get_children():
		if _start_positions.has(fish) and fish.global_position.distance_to(_start_positions[fish]) > 1.0:
			moved += 1
		if not bounds.grow(2.0).has_point(fish.global_position):
			out_of_bounds += 1

	var survivors := _tank.population()
	_check(moved > 0, "no fish moved in %.0fs" % RUN_SECONDS)
	_check(out_of_bounds == 0, "%d fish escaped the tank bounds" % out_of_bounds)
	_check(survivors < 11, "shark ate nothing: population still %d of 11" % survivors)

	print("---")
	print("species        : %d" % _tank.available_species.size())
	print("spawned        : 11")
	print("survivors      : %d" % survivors)
	print("fish that moved: %d" % moved)
	print("out of bounds  : %d" % out_of_bounds)
	if _failures.is_empty():
		print("RESULT: PASS")
	else:
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
