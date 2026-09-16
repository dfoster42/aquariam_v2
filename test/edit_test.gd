extends SceneTree
## Undo, and the remove mode it mostly exists to pair with.
## Run: godot --headless --script res://test/edit_test.gd

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
	_check_nothing_to_undo()
	_check_undo_takes_back_a_placement()
	_check_undo_takes_back_decor_and_food()
	_check_remove_needs_a_target()
	_check_remove_picks_the_nearest()
	_check_remove_reaches_a_whole_plant()
	_check_undo_restores_a_removed_fish()
	_check_place_delete_undo_undo()
	_check_stale_entries_are_skipped()
	_check_breeding_is_not_undoable()
	_check_modes_are_exclusive()

	TankStore.clear()
	if _failures.is_empty():
		print("RESULT: PASS")
		return
	for f in _failures:
		printerr("FAIL: " + f)
	print("RESULT: FAIL (%d)" % _failures.size())
	quit(1)

func _check_nothing_to_undo() -> void:
	var tank := _tank()
	_check(not tank.can_undo(), "a fresh tank should have nothing to undo")
	_check(not tank.undo(), "undo() should report false with an empty history")
	_check(tank.population() == 0, "undo on an empty tank changed the population")
	tank.queue_free()

func _check_undo_takes_back_a_placement() -> void:
	var tank := _tank()
	tank.select_species(_species(tank, "Clownfish"))
	tank.place_selected(Vector2(800, 700))
	tank.place_selected(Vector2(900, 700))
	_check(tank.population() == 2, "two taps should give two fish, got %d" % tank.population())
	_check(tank.can_undo(), "two placements and nothing to undo")

	_check(tank.undo(), "undo reported nothing to do")
	_check(tank.population() == 1, "one undo should leave 1 fish, left %d" % tank.population())
	# The fish that comes back out is the LAST one placed, not either of them.
	_check(tank.fish()[0].global_position.is_equal_approx(Vector2(800, 700)),
		"undo removed the wrong fish: %s is left" % tank.fish()[0].global_position)

	_check(tank.undo(), "second undo reported nothing to do")
	_check(tank.population() == 0, "two undos should empty the tank, left %d" % tank.population())
	_check(not tank.can_undo(), "the history should be empty after undoing both")
	tank.queue_free()

func _check_undo_takes_back_decor_and_food() -> void:
	var tank := _tank()
	tank.select_decor(tank.available_decor[0])
	tank.place_selected(Vector2(1000, 1200))
	_check(tank.decor().size() == 1, "a tap with a plant armed did not plant it")
	tank.undo()
	_check(tank.decor().is_empty(), "undo left %d plants" % tank.decor().size())

	tank.set_feeding(true)
	tank.place_selected(Vector2(1000, 400))
	_check(tank.food().size() == 1, "a tap with Feed armed did not drop a pellet")
	tank.undo()
	_check(tank.food().is_empty(), "undo left %d pellets" % tank.food().size())
	tank.queue_free()

## A tap on open water removes nothing. Deleting whatever happens to be closest, however
## far away, would make the mode unusable in a crowded tank.
func _check_remove_needs_a_target() -> void:
	var tank := _tank()
	tank.select_species(_species(tank, "Clownfish"))
	tank.place_selected(Vector2(400, 400))
	tank.set_removing(true)

	_check(tank.remove_at(Vector2(2000, 1800), 48.0) == null,
		"a tap in open water removed something")
	_check(tank.population() == 1, "a miss should leave the tank alone")
	_check(tank.remove_at(Vector2(400, 400), 48.0) != null, "a tap on a fish removed nothing")
	_check(tank.population() == 0, "the fish under the tap is still there")
	tank.queue_free()

## Between two fish, the tap takes the nearer one — and reach is in world units, so the
## same tap at a tighter zoom reaches less far.
func _check_remove_picks_the_nearest() -> void:
	var tank := _tank()
	var clownfish := _species(tank, "Clownfish")
	tank.spawn(clownfish, Vector2(600, 600))
	tank.spawn(clownfish, Vector2(700, 600))

	var removed := tank.remove_at(Vector2(690, 600), 48.0) as Fish
	_check(removed != null and removed.global_position.is_equal_approx(Vector2(700, 600)),
		"the tap took the further fish")

	# Reach scales with zoom: 4 world units is what 48 screen units buys at a deep zoom,
	# and at that scale a fish 100 units away is not under the finger.
	_check(tank.remove_at(Vector2(500, 600), 4.0) == null,
		"a tap 100 units away connected at a reach of 4")
	tank.queue_free()

## A plant is rooted at its base and stands upward, so the whole plant is the target.
func _check_remove_reaches_a_whole_plant() -> void:
	var tank := _tank()
	var kind: DecorKind = tank.available_decor[0]
	tank.place_decor(kind, Vector2(1500, 1600))
	# Half way up the stem, far above the point it was planted at.
	_check(tank.remove_at(Vector2(1500, 1600 - kind.size * 0.5), 48.0) != null,
		"tapping the middle of a %.0f-unit plant missed it" % kind.size)
	_check(tank.decor().is_empty(), "the plant is still there")
	tank.queue_free()

func _check_undo_restores_a_removed_fish() -> void:
	var tank := _tank()
	var angelfish := _species(tank, "Angelfish")
	var fish := tank.spawn(angelfish, Vector2(1200, 900), 33.0)
	var age := fish.age

	tank.remove_at(Vector2(1200, 900), 48.0)
	_check(tank.population() == 0, "the fish was not removed")
	_check(tank.can_undo(), "a removal should be undoable")

	tank.undo()
	_check(tank.population() == 1, "undo did not put the fish back")
	var back := tank.fish()[0]
	_check(back.species == angelfish, "it came back as a %s" % back.species.display_name)
	_check(back.global_position.is_equal_approx(Vector2(1200, 900)),
		"it came back at %s" % back.global_position)
	# Age matters: a restored fish that started over would be young enough to breed again.
	_check(absf(back.age - age) < 0.01, "it came back aged %.1f, was %.1f" % [back.age, age])
	tank.queue_free()

## Place a fish, delete it, undo twice. The second undo has to take back the placement,
## even though undoing the deletion created a different instance to the one placed.
func _check_place_delete_undo_undo() -> void:
	var tank := _tank()
	tank.select_species(_species(tank, "Clownfish"))
	tank.place_selected(Vector2(500, 500))
	tank.set_removing(true)
	tank.place_selected(Vector2(500, 500), 48.0)
	_check(tank.population() == 0, "the fish was not deleted")

	tank.undo()
	_check(tank.population() == 1, "the first undo did not bring it back")
	tank.undo()
	_check(tank.population() == 0,
		"the second undo should take back the placement, left %d" % tank.population())
	tank.queue_free()

## A fish eaten before it could be undone is not an error: that entry is dropped and the
## button undoes the most recent thing it still can.
func _check_stale_entries_are_skipped() -> void:
	var tank := _tank()
	tank.select_species(_species(tank, "Clownfish"))
	var first := tank.place_selected(Vector2(300, 300)) as Fish
	var second := tank.place_selected(Vector2(1900, 300)) as Fish

	# The real predation path: this is the signal a shark's bite emits.
	second.eaten.emit(second)
	_check(tank.population() == 1, "the eaten fish is still in the tank")
	_check(tank.can_undo(), "the earlier placement should still be undoable")

	tank.undo()
	_check(tank.population() == 0,
		"undo should have taken back the first fish, %d left" % tank.population())
	_check(not is_instance_valid(first) or not first.is_inside_tree(),
		"the fish undo claimed to remove is still in the tank")
	tank.queue_free()

## Only the player's own taps go on the stack. Breeding and restoring both go through
## spawn(), and a tank that bred while nobody was looking would otherwise fill the undo
## stack with fish the player never placed.
func _check_breeding_is_not_undoable() -> void:
	var tank := _tank()
	var clownfish := _species(tank, "Clownfish")
	for i in 12:
		tank.spawn(clownfish, Vector2(800 + i * 25, 800), clownfish.maturity + 10.0)
	_check(not tank.can_undo(), "spawn() outside a tap went on the undo stack")

	# Counted by watching the population rather than by connecting to fish_born: a
	# GDScript lambda captures locals by value, so a counter incremented inside one
	# stays zero outside it. An earlier version of this check did exactly that and
	# reported "nothing bred" through three runs that had each bred six fish.
	var started := tank.population()
	for i in 1500:
		tank._process(1.0 / 30.0)
		if tank.population() > started:
			break
	_check(tank.population() > started, "nothing bred in 50s, so this check proves nothing")
	_check(not tank.can_undo(), "breeding put entries on the undo stack")
	tank.queue_free()

func _check_modes_are_exclusive() -> void:
	var tank := _tank()
	tank.set_feeding(true)
	tank.set_removing(true)
	_check(not tank.feeding, "arming Remove left Feed armed too")
	_check(tank.selected_decor == null, "arming Remove left a plant armed")

	tank.select_species(_species(tank, "Shark"))
	_check(not tank.removing, "picking a species left Remove armed")

	tank.set_removing(true)
	tank.select_decor(tank.available_decor[0])
	_check(not tank.removing, "picking a plant left Remove armed")

	tank.set_removing(true)
	tank.set_feeding(true)
	_check(not tank.removing, "arming Feed left Remove armed")
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
