extends SceneTree
## Where does a predator actually catch prey?
##
## Run: godot --headless --script res://test/bite_test.gd
##
## Reported from the simulator: prey was only eaten once it reached the middle of the
## shark. Bite range was measured centre to centre, and a shark sprite is ~213px long,
## so its mouth sits ~106px ahead of the point being measured from.

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
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.get_node("Aquarium").autosave_interval = 0.0
	root.add_child(main)
	var tank: Aquarium = main.get_node("Aquarium")
	tank.clear_tank()

	var shark_species := _species(tank, "Shark")
	var prey_species := _species(tank, "Clownfish")

	var shark: Fish = tank.spawn(shark_species, Vector2(540, 900))
	tank._process(0.016)
	var reach := shark.half_length()
	print("shark half-length %.0fpx, mouth at %s from centre %s"
		% [reach, shark.mouth_position(), shark.global_position])
	_check(reach > 50.0, "shark half-length looks wrong: %.1f" % reach)

	# Each case gets the tank to itself. With both prey present at once the shark simply
	# targets whichever is nearest, and the second case never gets tested — which is how
	# this test first "failed" against behaviour that was already correct.

	# Prey just ahead of the mouth must be eaten.
	var ahead: Fish = tank.spawn(prey_species, shark.mouth_position() + shark.facing() * 8.0)
	for i in 3:
		tank._process(0.016)
	_check(ahead.is_eaten(), "prey directly in front of the mouth was not eaten")

	# Prey sitting on the shark's centre must NOT be eaten: that is inside the body,
	# behind the mouth, and it is exactly the case that looked wrong on the simulator.
	tank.clear_tank()
	var shark2: Fish = tank.spawn(shark_species, Vector2(540, 900))
	tank._process(0.016)
	var inside: Fish = tank.spawn(prey_species, shark2.global_position)
	for i in 3:
		tank._process(0.016)
	_check(not inside.is_eaten(), "prey at the shark's CENTRE was eaten; bite is not using the mouth")

	# And prey a little behind the tail must not be eaten either.
	tank.clear_tank()
	var shark3: Fish = tank.spawn(shark_species, Vector2(540, 900))
	tank._process(0.016)
	var behind: Fish = tank.spawn(prey_species, shark3.global_position - shark3.facing() * (shark3.half_length() + 40.0))
	for i in 3:
		tank._process(0.016)
	_check(not behind.is_eaten(), "prey behind the shark's tail was eaten")

	if _failures.is_empty():
		print("RESULT: PASS")
		return
	for f in _failures:
		printerr("FAIL: " + f)
	print("RESULT: FAIL (%d)" % _failures.size())
	quit(1)

func _species(tank: Aquarium, name: String) -> FishSpecies:
	for s: FishSpecies in tank.available_species:
		if s.display_name == name:
			return s
	return null

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
