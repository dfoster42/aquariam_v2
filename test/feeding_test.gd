extends SceneTree
## Feeding: pellets sink, hungry fish chase them, eating refills, hunger slows breeding.
## Run: godot --headless --script res://test/feeding_test.gd

var _started: bool = false
var _failures: Array[String] = []

func _initialize() -> void:
	TankStore.clear()

func _process(_d: float) -> bool:
	if _started:
		return true
	_started = true
	_run()
	return true

func _run() -> void:
	_check_pellet_sinks()
	_check_hungry_fish_eats()
	_check_full_fish_ignores_food()
	_check_sharks_ignore_food()
	_check_hunger_slows_breeding()

	TankStore.clear()
	if _failures.is_empty():
		print("RESULT: PASS")
		return
	for f in _failures:
		printerr("FAIL: " + f)
	print("RESULT: FAIL (%d)" % _failures.size())
	quit(1)

func _check_pellet_sinks() -> void:
	var tank := _tank()
	var pellet := tank.drop_food(Vector2(1600, 400))
	var start_y := pellet.global_position.y
	for i in 60:
		tank._process(1.0 / 30.0)
	_check(pellet.global_position.y > start_y + 20.0,
		"a pellet did not sink (%.0f -> %.0f)" % [start_y, pellet.global_position.y])
	tank.queue_free()

func _check_hungry_fish_eats() -> void:
	var tank := _tank()
	var prey: Fish = tank.spawn(_species(tank, "Clownfish"), Vector2(1600, 1000))
	prey.fullness = 0.1
	_check(prey.is_hungry(), "a fish at 10% full does not report as hungry")

	var pellet := tank.drop_food(Vector2(1600, 1150))
	for i in 300:
		tank._process(1.0 / 30.0)
		if pellet.is_eaten():
			break
	_check(pellet.is_eaten(), "a hungry fish did not eat a pellet dropped beside it")
	_check(prey.fullness > 0.1, "eating did not make the fish any fuller")
	tank.queue_free()

## A full fish should not chase food, or pellets vanish the instant they are dropped.
func _check_full_fish_ignores_food() -> void:
	var tank := _tank()
	var prey: Fish = tank.spawn(_species(tank, "Clownfish"), Vector2(1600, 1000))
	prey.fullness = 1.0
	var pellet := tank.drop_food(Vector2(1600, 1060))
	for i in 60:
		tank._process(1.0 / 30.0)
	_check(not pellet.is_eaten(), "a full fish ate a pellet it should have ignored")
	tank.queue_free()

func _check_sharks_ignore_food() -> void:
	var tank := _tank()
	var shark: Fish = tank.spawn(_species(tank, "Shark"), Vector2(1600, 1000))
	_check(not shark.is_hungry(), "a shark reports hunger; it should be driven by prey")
	var pellet := tank.drop_food(Vector2(1600, 1060))
	for i in 90:
		tank._process(1.0 / 30.0)
	_check(not pellet.is_eaten(), "a shark ate a food pellet")
	tank.queue_free()

## Feeding is a reward, not an obligation: hunger halves the breeding rate rather than
## killing anything.
func _check_hunger_slows_breeding() -> void:
	var tank := _tank()
	var species := _species(tank, "Clownfish")

	var fed: Fish = tank.spawn(species, Vector2(1000, 1000))
	fed.fullness = 1.0
	fed.note_bred()
	var fed_wait := fed.breed_wait()

	var hungry: Fish = tank.spawn(species, Vector2(1200, 1000))
	hungry.fullness = 0.05
	hungry.note_bred()
	var hungry_wait := hungry.breed_wait()

	_check(hungry_wait > fed_wait,
		"a hungry fish breeds as often as a fed one (%.0fs vs %.0fs)" % [hungry_wait, fed_wait])
	_check(species.starve_time == 0.0,
		"fish can starve to death; an unattended tank should not die out")
	tank.queue_free()

func _tank() -> Aquarium:
	var tank: Aquarium = load("res://scenes/aquarium.tscn").instantiate()
	tank.autosave_interval = 0.0
	root.add_child(tank)
	tank.clear_tank()
	tank.clear_decor()
	return tank

func _species(tank: Aquarium, name: String) -> FishSpecies:
	for s: FishSpecies in tank.available_species:
		if s.display_name == name:
			return s
	return null

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
