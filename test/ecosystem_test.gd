extends SceneTree
## Does the tank sustain itself?
##
## Run: godot --headless --script res://test/ecosystem_test.gd
##
## The prototype could only lose fish: sharks ate, nothing replaced the prey, and every
## tank drained to zero. Breeding is meant to fix that, and "meant to" is not evidence —
## this runs the tank for long enough to see whether it settles, collapses or runs away.
##
## Time is compressed by stepping the tank directly rather than waiting in real time.

const SIM_SECONDS: float = 900.0
const STEP: float = 1.0 / 30.0
const SAMPLE_EVERY: float = 60.0

var _tank: Aquarium
var _started: bool = false
var _failures: Array[String] = []

# Members, not locals. A GDScript lambda captures locals by value, so `births += 1`
# inside a signal handler updated a copy and every counter stayed 0 while the tank was
# visibly losing fish.
var _births: int = 0
var _eaten: int = 0
var _natural_deaths: int = 0

func _initialize() -> void:
	TankStore.clear()
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.get_node("Aquarium").autosave_interval = 0.0
	root.add_child(main)
	_tank = main.get_node("Aquarium")

func _process(_delta: float) -> bool:
	if _started:
		return true
	_started = true
	_run()
	return true

func _run() -> void:
	# Two sharks on top of a seeded tank: enough predation to matter.
	var shark := _species_named("Shark")
	for i in 1:
		_tank.spawn(shark, Vector2(randf_range(100, 900), randf_range(100, 1800)))

	var elapsed := 0.0
	var next_sample := SAMPLE_EVERY
	var series: Array[int] = []
	var lowest := _tank.population()
	var highest := _tank.population()
	_tank.fish_born.connect(func(_s: FishSpecies) -> void: _births += 1)
	_tank.fish_died.connect(func(_s: FishSpecies, old: bool) -> void:
		if old: _natural_deaths += 1
		else: _eaten += 1)

	print(" minute | population | prey | sharks")
	print("--------+------------+------+-------")
	while elapsed < SIM_SECONDS:
		_tank._process(STEP)
		elapsed += STEP
		lowest = mini(lowest, _tank.population())
		highest = maxi(highest, _tank.population())
		if elapsed >= next_sample:
			next_sample += SAMPLE_EVERY
			series.append(_tank.population())
			print(" %6d | %10d | %4d | %6d" % [
				int(elapsed / 60.0), _tank.population(), _count_prey(), _count("Shark")])

	print("\nbirths %d, eaten %d, old age %d" % [_births, _eaten, _natural_deaths])
	print("population low %d, high %d, final %d" % [lowest, highest, _tank.population()])

	_check(lowest > 0, "the tank died out (population reached 0)")
	# "Did not reach zero" is too weak a bar: a tank that craters to three fish and
	# stays there is a failed ecosystem even though nothing hit zero.
	var seeded := 0
	for species: FishSpecies in _tank.available_species:
		seeded += species.starting_count
	_check(_tank.population() >= seeded / 2,
		"population collapsed to %d, below half the %d it started with" % [_tank.population(), seeded])
	_check(_count_prey() > 0, "all prey were eaten; the tank cannot recover")
	_check(_tank.population() < Aquarium.MAX_POPULATION,
		"population ran away to the hard cap (%d)" % _tank.population())
	_check(_births > 0, "nothing ever bred")
	_check(_eaten > 0, "nothing was ever eaten; the predator is not applying pressure")
	# The last third should not still be climbing steeply — that would mean it has not
	# found a ceiling and is only capped by the carrying capacity.
	if series.size() >= 6:
		var early: int = series[series.size() / 2]
		var late: int = series[-1]
		_check(late <= maxi(early * 2, early + 15),
			"population still climbing steeply: %d -> %d over the second half" % [early, late])

	if _failures.is_empty():
		print("RESULT: PASS")
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	print("RESULT: FAIL (%d)" % _failures.size())
	quit(1)

func _count(name: String) -> int:
	var n := 0
	for fish in _tank.fish():
		if fish.species.display_name == name:
			n += 1
	return n

func _count_prey() -> int:
	return _tank.population() - _count("Shark")

func _species_named(name: String) -> FishSpecies:
	for species: FishSpecies in _tank.available_species:
		if species.display_name == name:
			return species
	return null

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
