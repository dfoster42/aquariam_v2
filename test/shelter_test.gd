extends SceneTree
## Do plants actually hide prey from sharks?
## Run: godot --headless --script res://test/shelter_test.gd

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
	_check_wiring()
	_check_prey_in_cover_survives()
	_check_prey_without_cover_is_eaten()
	_check_flee_towards_cover()
	_check_decor_persists()

	TankStore.clear()
	if _failures.is_empty():
		print("RESULT: PASS")
		return
	for f in _failures:
		printerr("FAIL: " + f)
	print("RESULT: FAIL (%d)" % _failures.size())
	quit(1)

func _check_wiring() -> void:
	var tank := _tank()
	_check(tank.available_decor.size() >= 1, "no decor is wired into the scene")
	var sheltering := 0
	for kind: DecorKind in tank.available_decor:
		if kind.shelter_radius > 0.0:
			sheltering += 1
	_check(sheltering >= 1, "no decor offers shelter")
	tank.queue_free()

## The control and the case differ only by whether a plant is present.
func _check_prey_in_cover_survives() -> void:
	var tank := _tank()
	var shark_s := _species(tank, "Shark")
	var prey_s := _species(tank, "Clownfish")
	var kelp := _decor(tank, "Kelp")

	# Read back where the plant actually went rather than assuming it stayed where it
	# was asked for. Decor is now seated on the seabed, so the y of a placement request
	# is only a suggestion — asserting against the requested point tested the old
	# behaviour where plants hung in open water.
	var cover := tank.place_decor(kelp, Vector2(1600, 1100))
	var prey_at := cover.global_position
	var prey: Fish = tank.spawn(prey_s, prey_at)
	tank.spawn(shark_s, prey_at + Vector2(120, 0))

	# Checked on the first frame, while the prey is still where it was placed. Asserting
	# it at the end of the run instead tested something else entirely: the prey survives
	# and then wanders out of the kelp, so the flag is legitimately false by then.
	tank._process(1.0 / 30.0)
	_check(prey.sheltered, "prey placed inside kelp is not flagged as sheltered")

	var sheltered_frames := 0
	for i in 1200:
		tank._process(1.0 / 30.0)
		if prey.sheltered:
			sheltered_frames += 1
		if prey.is_eaten():
			break
	_check(not prey.is_eaten(), "prey sitting inside kelp was still eaten")
	_check(sheltered_frames > 0, "the prey was never in cover during the run")
	tank.queue_free()

func _check_prey_without_cover_is_eaten() -> void:
	var tank := _tank()
	var shark_s := _species(tank, "Shark")
	var prey_s := _species(tank, "Clownfish")

	var prey_at := Vector2(1600, 1100)
	var prey: Fish = tank.spawn(prey_s, prey_at)
	tank.spawn(shark_s, prey_at + Vector2(120, 0))

	for i in 1200:
		tank._process(1.0 / 30.0)
		if prey.is_eaten():
			break
	# Without this the first check proves nothing: a prey that survives anyway would
	# pass it whether or not cover does a thing.
	_check(prey.is_eaten(), "prey in open water survived a shark; the control is broken")
	tank.queue_free()

## Fleeing prey should break for cover rather than simply away.
func _check_flee_towards_cover() -> void:
	var tank := _tank()
	var shark_s := _species(tank, "Shark")
	var prey_s := _species(tank, "Clownfish")
	var kelp := _decor(tank, "Kelp")

	# Cover below, the shark to the side, so "toward cover" and "away from the shark"
	# are different directions. Which way round this goes is decided by the terrain now:
	# a plant is always on the floor, so the prey has to be the thing placed above it.
	var cover_at := tank.place_decor(kelp, Vector2(1600, 1100)).global_position
	var prey_at := cover_at + Vector2(0, -180)
	var prey: Fish = tank.spawn(prey_s, prey_at)
	tank.spawn(shark_s, prey_at + Vector2(150, 0))

	# Assert that it REACHES cover, not that it is nearer to cover after a fixed time.
	#
	# The distance version of this was flaky at about one run in two, and the reason is
	# behaviour rather than noise: prey steers to cover, arrives after roughly 50px,
	# becomes sheltered, and then goes back to fleeing straight away from the shark —
	# which can carry it past the plant and out the far side. Measuring the gap at a
	# fixed moment conflated "broke for cover" with "kept running once it got there".
	# Tests the DECISION, not where the fish ends up after several seconds.
	#
	# Two earlier versions measured an outcome and were both flaky at about one run in
	# two: distance-to-cover at a fixed time (which a fish that reaches cover and keeps
	# fleeing fails), then "did it reach cover" (which fails whenever the shark catches
	# it on the way, or drifts out of sight and the fish goes back to wandering). The
	# rule being implemented is "when threatened and not yet hidden, steer at the
	# nearest cover", and that is exactly what this measures.
	var before := prey.global_position
	tank._process(1.0 / 30.0)
	var moved := prey.global_position - before
	_check(moved.length() > 0.5, "the fleeing prey did not move at all")

	var to_cover := before.direction_to(cover_at)
	var angle := rad_to_deg(absf(moved.normalized().angle_to(to_cover)))
	_check(angle < 20.0,
		"fleeing prey steered %.0f degrees away from the cover it could see" % angle)

	tank.queue_free()
	_check_hidden_holds_position()

## A hidden fish holds still rather than swimming out of its own cover.
##
## Only while it can actually see the threat — out of sight it goes back to wandering,
## which is correct and is what made a first version of this check flaky: the shark sat
## right on the edge of the prey's vision and drifted in and out of it.
func _check_hidden_holds_position() -> void:
	var tank := _tank()
	var kelp := _decor(tank, "Kelp")
	var cover_at := tank.place_decor(kelp, Vector2(1600, 1100)).global_position
	var hidden: Fish = tank.spawn(_species(tank, "Clownfish"), cover_at)
	tank.spawn(_species(tank, "Shark"), cover_at + Vector2(110, 0))

	tank._process(1.0 / 30.0)
	_check(hidden.sheltered, "a fish placed in cover did not register as sheltered")
	var held := hidden.global_position
	for i in 30:
		tank._process(1.0 / 30.0)
	_check(hidden.global_position.distance_to(held) < 2.0,
		"a sheltered fish swam %.0fpx out of its own cover while threatened"
			% hidden.global_position.distance_to(held))
	_check(not hidden.is_eaten(), "a fish hiding in cover was eaten")

	tank.queue_free()

## Plants have to survive a save, or a player's tank quietly loses its cover overnight.
func _check_decor_persists() -> void:
	var tank := _tank()
	tank.clear_decor()
	var kelp := _decor(tank, "Kelp")
	var anemone := _decor(tank, "Anemone")
	var kelp_at := tank.place_decor(kelp, Vector2(900, 1200)).global_position
	tank.place_decor(anemone, Vector2(1500, 1300))
	_check(TankStore.save(tank) == OK, "saving a tank with decor failed")

	var data := TankStore.read()
	_check(data.get("decor", []).size() == 2,
		"save holds %d decor, expected 2" % data.get("decor", []).size())

	var restored := _tank()
	restored.clear_tank()
	restored.clear_decor()
	_check(restored.restore(data), "restore() reported nothing restored")
	_check(restored.decor().size() == 2,
		"restored %d decor, expected 2" % restored.decor().size())

	var found := false
	for item in restored.decor():
		if item.kind.display_name == "Kelp" and item.global_position.distance_to(kelp_at) <= 1.5:
			found = true
	_check(found, "the restored kelp is missing or in the wrong place")

	# And the restored plants must actually shelter, not just exist.
	var prey: Fish = restored.spawn(_species(restored, "Clownfish"), kelp_at)
	restored._process(1.0 / 30.0)
	_check(prey.sheltered, "a restored plant does not shelter prey")

	tank.queue_free()
	restored.queue_free()

func _tank() -> Aquarium:
	var tank: Aquarium = load("res://scenes/aquarium.tscn").instantiate()
	tank.autosave_interval = 0.0
	root.add_child(tank)
	tank.clear_tank()
	return tank

func _species(tank: Aquarium, name: String) -> FishSpecies:
	for s: FishSpecies in tank.available_species:
		if s.display_name == name:
			return s
	return null

func _decor(tank: Aquarium, name: String) -> DecorKind:
	for k: DecorKind in tank.available_decor:
		if k.display_name == name:
			return k
	return null

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
