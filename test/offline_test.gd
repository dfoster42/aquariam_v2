extends SceneTree
## Unit checks for the offline population model.

var _failures: Array[String] = []

func _initialize() -> void:
	# Nothing grows from nothing.
	_eq(Offline.project(0, 20, 0.01, 3600.0), 0, "an empty species must stay empty")
	# Already full stays full.
	_eq(Offline.project(20, 20, 0.01, 3600.0), 20, "a full species must stay full")
	# Never exceeds capacity, however long the absence.
	_eq(Offline.project(2, 20, 0.02, 1_000_000.0), 20, "capacity must be a ceiling")
	# Never shrinks.
	_ok(Offline.project(5, 20, 0.02, 600.0) >= 5, "growth must not reduce a population")
	# Monotonic in time.
	var short := Offline.project(4, 30, 0.01, 300.0)
	var long := Offline.project(4, 30, 0.01, 3600.0)
	_ok(long >= short, "longer absence must not yield fewer fish (%d vs %d)" % [long, short])
	# A non-breeding species is untouched.
	_eq(Offline.project(3, 10, 0.0, 99999.0), 3, "a species that cannot breed must not grow")

	# Clock handling.
	_eq(int(Offline.elapsed_since(0, 1000)), 0, "no save time means no credit")
	_eq(int(Offline.elapsed_since(2000, 1000)), 0, "a backwards clock must credit nothing")
	_eq(int(Offline.elapsed_since(1000, 1600)), 600, "a normal absence is credited in full")
	_eq(int(Offline.elapsed_since(0 + 1, int(1 + Offline.MAX_CATCHUP * 10))), int(Offline.MAX_CATCHUP),
		"a long absence is clamped to MAX_CATCHUP")

	# Rate derivation.
	_ok(Offline.growth_rate(0.0) == 0.0, "a zero cooldown must give a zero rate")
	_ok(Offline.growth_rate(20.0) > Offline.growth_rate(40.0), "faster breeding must give a higher rate")

	if _failures.is_empty():
		print("RESULT: PASS")
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		print("RESULT: FAIL (%d)" % _failures.size())
		quit(1)
	quit()

func _eq(got: int, want: int, message: String) -> void:
	if got != want:
		_failures.append("%s (got %d, want %d)" % [message, got, want])

func _ok(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
