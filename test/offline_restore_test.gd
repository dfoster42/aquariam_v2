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
	root.add_child(first)
	var tank: Aquarium = first.get_node("Aquarium")

	var before := tank.population()
	var oldest_before := _oldest_age(tank)
	_check(TankStore.save(tank) == OK, "saving failed")

	# Backdate the save, exactly as an absence would.
	var data := TankStore.read()
	data["saved_at"] = int(Time.get_unix_time_from_system()) - AWAY_SECONDS
	var file := FileAccess.open(TankStore.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

	var second: Node2D = load("res://scenes/main.tscn").instantiate()
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
	root.add_child(third)
	var again: Aquarium = third.get_node("Aquarium")
	_check(absi(again.population() - after) <= 3,
		"restoring twice gave different populations (%d vs %d)" % [again.population(), after])

	TankStore.clear()
	if _failures.is_empty():
		print("RESULT: PASS")
		return
	for f in _failures:
		printerr("FAIL: " + f)
	print("RESULT: FAIL (%d)" % _failures.size())
	quit(1)

func _oldest_age(tank: Aquarium) -> float:
	var oldest := 0.0
	for fish in tank.fish():
		oldest = maxf(oldest, fish.age)
	return oldest

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
