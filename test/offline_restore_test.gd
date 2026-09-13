extends SceneTree
## End-to-end: does a tank actually advance while the app is closed?
##
## Run: godot --headless --script res://test/offline_restore_test.gd
##
## Saves a tank, rewrites saved_at to backdate it, restores into a fresh tank, and
## checks that fish aged and the population grew toward capacity.

const AWAY_SECONDS: int = 45 * 60

var _started: bool = false
var _failures: Array[String] = []

func _initialize() -> void:
	TankStore.clear()

func _process(_delta: float) -> bool:
	if _started:
		return true
	_started = true
	_run()
	return true

func _run() -> void:
	var first: Node2D = load("res://scenes/main.tscn").instantiate()
	first.get_node("Aquarium").autosave_interval = 0.0
	root.add_child(first)
	var tank: Aquarium = first.get_node("Aquarium")

	var before := tank.population()
	var oldest_before := _oldest_age(tank)
	_check(TankStore.save(tank) == OK, "saving failed")

	# Backdate the save, exactly as an absence would.
	var data := TankStore.read()
	data["saved_at"] = int(Time.get_unix_time_from_system()) - AWAY_SECONDS
	var file := FileAccess.open(TankStore.slot_path(TankStore.active_slot()), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

	var second: Node2D = load("res://scenes/main.tscn").instantiate()
	second.get_node("Aquarium").autosave_interval = 0.0
	root.add_child(second)
	var restored: Aquarium = second.get_node("Aquarium")

	var after := restored.population()
	var oldest_after := _oldest_age(restored)

	print("before %d fish (oldest %.0fs) -> away %d min -> after %d fish (oldest %.0fs)"
		% [before, oldest_before, AWAY_SECONDS / 60, after, oldest_after])

	_check(after > before, "the tank did not grow while away (%d -> %d)" % [before, after])
	_check(oldest_after > oldest_before, "no fish aged while away")

	var capacity := 0
	for species: FishSpecies in restored.available_species:
		capacity += species.capacity
	_check(after <= capacity, "grew past total capacity: %d > %d" % [after, capacity])

	# A second restore of the same save must not compound: the save is not rewritten
	# by restoring, so the elapsed time is the same, not cumulative.
	var third: Node2D = load("res://scenes/main.tscn").instantiate()
	third.get_node("Aquarium").autosave_interval = 0.0
	root.add_child(third)
	var again: Aquarium = third.get_node("Aquarium")
	_check(absi(again.population() - after) <= 3,
		"restoring twice gave different populations (%d vs %d)" % [again.population(), after])

	_check_long_absence()

	TankStore.clear()
	if _failures.is_empty():
		print("RESULT: PASS")
		return
	for f in _failures:
		printerr("FAIL: " + f)
	print("RESULT: FAIL (%d)" % _failures.size())
	quit(1)

## An absence far longer than any fish lives must turn the population over, not wipe it.
## Growing to capacity and then ageing everyone to death left one immortal shark.
func _check_long_absence() -> void:
	var seed_tank: Node2D = load("res://scenes/main.tscn").instantiate()
	seed_tank.get_node("Aquarium").autosave_interval = 0.0
	root.add_child(seed_tank)
	var tank: Aquarium = seed_tank.get_node("Aquarium")
	var before := tank.population()
	TankStore.save(tank)

	var data := TankStore.read()
	data["saved_at"] = int(Time.get_unix_time_from_system()) - 3 * 3600
	var file := FileAccess.open(TankStore.slot_path(TankStore.active_slot()), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

	var after_tank: Node2D = load("res://scenes/main.tscn").instantiate()
	after_tank.get_node("Aquarium").autosave_interval = 0.0
	root.add_child(after_tank)
	var after: Aquarium = after_tank.get_node("Aquarium")

	print("3 hours away: %d fish -> %d fish" % [before, after.population()])
	_check(after.population() >= before,
		"a 3-hour absence shrank the tank (%d -> %d)" % [before, after.population()])

	var prey := 0
	for fish in after.fish():
		if fish.species.breed_distance > 0.0:
			prey += 1
	_check(prey > 0, "every breeding species died out over a 3-hour absence")

func _oldest_age(tank: Aquarium) -> float:
	var oldest := 0.0
	for fish in tank.fish():
		oldest = maxf(oldest, fish.age)
	return oldest

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
