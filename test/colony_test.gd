extends SceneTree
## The crux test for the god-sim prototype: does territory behave like territory?
##
## Everything else in the pivot rests on one claim — that a colony is a thing worth
## losing, and that losing it visibly changes the map. Four checks, in the order they
## would fail if the idea does not work:
##
##   1. A colony accumulates. Biomass and radius grow on their own.
##   2. Territory is contested. Two rivals split the ground between them, and the
##      bigger one holds more of it.
##   3. Being hemmed in costs something. A colony with a neighbour grows slower than
##      the same colony alone, through the map rather than through a combat rule.
##   4. A strike opens a hole AND THE NEIGHBOUR FLOWS IN. This is the whole thing. If
##      the survivor's share does not climb after the strike, there is no clip.
##   5. A bleach travels the way the faction travelled, and stops at the border. A
##      point strike is a pinprick once a faction has spread across the map — measured,
##      it moved a third-of-the-map faction's share by 0.8 points — so the power that
##      has to work is the one that propagates.
##
## Run: godot --headless --script res://test/colony_test.gd

const STEP: float = 0.1
var _failures: Array[String] = []

func _initialize() -> void:
	# The tank restores a save in preference to opening empty, so a leftover save from
	# a real session would silently change what this measures.
	TankStore.clear()

## Everything runs on the first frame, not in _initialize().
##
## A node added during _initialize() has not had _ready() called on it yet, so its
## @onready references are null and is_node_ready() is false — which made plant_colony()
## refuse every call and the whole suite fail on a tank that was never actually built.
func _process(_delta: float) -> bool:
	var tank := _tank()
	if tank != null:
		_test_accumulates(tank)
	_test_contested()
	_test_pressure()
	_test_vacuum()
	_test_bleach()

	if _failures.is_empty():
		print("RESULT: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("RESULT: FAIL")
	quit(0 if _failures.is_empty() else 1)
	return true

## A tank with no save behind it and no autosave in front of it.
##
## Cast rather than assigned: a scene whose script failed to compile instantiates as a
## bare Node2D, and assigning that to a typed variable is a runtime error the test would
## otherwise sail past on its way to printing PASS.
func _tank() -> Aquarium:
	var tank := load("res://scenes/aquarium.tscn").instantiate() as Aquarium
	if tank == null:
		_failures.append("the aquarium scene did not instantiate as an Aquarium")
		return null
	tank.autosave_interval = 0.0
	root.add_child(tank)
	return tank

## Runs the colony half of the simulation for `seconds` without needing real frames.
##
## Calls the tank's own colony tick rather than reimplementing growth, so this cannot
## quietly pass against arithmetic the app does not run.
func _advance(tank: Aquarium, seconds: float) -> void:
	var steps := int(seconds / STEP)
	for i in steps:
		tank._tick_colonies(STEP)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

# ---------------------------------------------------------------------------- 1

func _test_accumulates(tank: Aquarium) -> void:
	var faction: Faction = tank.available_factions[0]
	var colony := tank.plant_colony(faction, Vector2(600, 1200))
	_check(colony != null, "a colony could not be founded at all")
	if colony == null:
		return

	var biomass_before := colony.biomass
	var radius_before := colony.radius()
	_advance(tank, 60.0)

	_check(colony.biomass > biomass_before * 1.5,
		"a colony left alone for a minute barely grew: %.1f -> %.1f"
			% [biomass_before, colony.biomass])
	_check(colony.radius() > radius_before,
		"biomass grew but the colony's reach did not")
	# The thing that makes it worth losing: it is bigger than a fresh one.
	_check(colony.biomass > Colony.SEED_BIOMASS * 2.0,
		"a minute of growth did not clear twice the founding biomass")
	tank.clear_colonies()
	tank.queue_free()

# ---------------------------------------------------------------------------- 2

func _test_contested() -> void:
	var tank := _tank()
	if tank == null:
		return
	var big: Faction = tank.available_factions[0]
	var small: Faction = tank.available_factions[1]

	# Same starting ground, deliberately unequal mass. The border should sit nearer the
	# smaller one, which is only true if influence is compared rather than distance.
	var a := tank.plant_colony(big, Vector2(1200, 1080), 90.0)
	var b := tank.plant_colony(small, Vector2(2040, 1080), 20.0)
	tank._rebuild_territory()
	var territory := tank.territory()

	var share_a := territory.share_of_map(a)
	var share_b := territory.share_of_map(b)
	_check(share_a > 0.0 and share_b > 0.0,
		"two colonies were planted and at least one holds no ground at all")
	_check(share_a > share_b,
		"the heavier colony does not hold more ground: %.3f vs %.3f" % [share_a, share_b])
	_check(territory.open_water() > 0.1,
		"two small colonies carved up the whole map; open water should stay open")

	# The border is where influence balances, so the midpoint belongs to the big one.
	var midpoint := Vector2(1620, 1080)
	var owner := territory.owner_at(midpoint)
	_check(owner == a or owner == null,
		"the midpoint between a heavy and a light colony went to the light one")
	tank.clear_colonies()
	tank.queue_free()

# ---------------------------------------------------------------------------- 3

func _test_pressure() -> void:
	var alone := _tank()
	var crowded := _tank()
	if alone == null or crowded == null:
		return
	var lone := alone.plant_colony(alone.available_factions[0], Vector2(1620, 1080), 40.0)
	_advance(alone, 90.0)
	var lone_biomass := lone.biomass
	alone.clear_colonies()
	alone.queue_free()

	var boxed := crowded.plant_colony(crowded.available_factions[0], Vector2(1620, 1080), 40.0)
	# Ringed closely enough that the neighbours take the ground it would have reached.
	for offset in [Vector2(-420, 0), Vector2(420, 0), Vector2(0, -420), Vector2(0, 420)]:
		crowded.plant_colony(crowded.available_factions[2], Vector2(1620, 1080) + offset, 70.0)
	_advance(crowded, 90.0)
	var boxed_biomass := boxed.biomass

	_check(boxed_biomass < lone_biomass,
		"being surrounded cost nothing: boxed %.1f vs alone %.1f"
			% [boxed_biomass, lone_biomass])
	_check(boxed.pressure < 0.95,
		"a surrounded colony still reports it owns nearly all the ground it reaches")
	crowded.clear_colonies()
	crowded.queue_free()

# ---------------------------------------------------------------------------- 4

func _test_vacuum() -> void:
	var tank := _tank()
	if tank == null:
		return
	var doomed := tank.plant_colony(tank.available_factions[0], Vector2(1400, 1080), 70.0)
	var survivor := tank.plant_colony(tank.available_factions[1], Vector2(1900, 1080), 70.0)
	_advance(tank, 40.0)
	tank._rebuild_territory()

	var territory := tank.territory()
	var survivor_before := territory.share_of_map(survivor)
	var doomed_before := territory.share_of_map(doomed)
	_check(doomed_before > 0.0, "the colony about to be struck held no ground to lose")

	var destroyed := tank.strike(doomed.global_position)
	_check(destroyed > 0.0, "a strike on a colony destroyed no biomass")

	# Immediately after: the hole exists.
	var doomed_gone := doomed.is_dead() or territory.share_of_map(doomed) < doomed_before
	_check(doomed_gone, "the struck colony holds as much ground as it did before")

	# And then the neighbour grows into it. This is the clip; without it the pivot is
	# an aquarium with a delete button.
	_advance(tank, 60.0)
	tank._rebuild_territory()
	var survivor_after := territory.share_of_map(survivor)

	_check(survivor_after > survivor_before,
		"the survivor did not expand into the vacuum: %.3f -> %.3f"
			% [survivor_before, survivor_after])
	print("  vacuum: struck %.0f biomass; survivor %.1f%% -> %.1f%% of the map"
		% [destroyed, survivor_before * 100.0, survivor_after * 100.0])
	tank.clear_colonies()
	tank.queue_free()

# ---------------------------------------------------------------------------- 5

func _test_bleach() -> void:
	var tank := _tank()
	if tank == null:
		return
	var doomed: Faction = tank.available_factions[0]
	var rival: Faction = tank.available_factions[1]

	# A chain of the doomed faction, each touching the next, with a rival colony sitting
	# right at the end of it. The bleach must run the whole chain and stop at the rival.
	var chain: Array[Colony] = []
	var before: Array[float] = []
	for i in 4:
		var colony := tank.plant_colony(doomed, Vector2(700 + i * 280, 1080), 60.0)
		if colony != null:
			chain.append(colony)
			before.append(colony.biomass)
	var neighbour := tank.plant_colony(rival, Vector2(700 + 4 * 280, 1080), 60.0)
	_check(chain.size() == 4 and neighbour != null, "the bleach fixture did not build")
	if chain.size() != 4 or neighbour == null:
		return

	var rival_before := neighbour.biomass
	var destroyed := tank.bleach(chain[0].global_position)
	_check(destroyed > 0.0, "a bleach on a reef destroyed nothing")

	# Every link took damage: the disaster travelled the whole chain rather than
	# stopping at the reef it landed on.
	var untouched: Array[int] = []
	var killed := 0
	for i in chain.size():
		if chain[i].is_dead():
			killed += 1
		elif chain[i].biomass >= before[i]:
			untouched.append(i)
	_check(untouched.is_empty(),
		"the bleach skipped links in the chain: %s" % str(untouched))
	# It is MEANT to burn out — decay per hop is what stops one tap flattening a map-
	# spanning faction — so the far end surviving is the design, not a failure. What
	# matters is that it is a disaster and not a scratch.
	_check(killed >= 2,
		"the bleach killed only %d of a 4-colony chain; that is a pinprick" % killed)

	# And it must not cross the border. A disaster that flattens everyone equally
	# erases the map instead of redrawing it.
	_check(not neighbour.is_dead() and is_equal_approx(neighbour.biomass, rival_before),
		"the bleach crossed into a rival faction: %.1f -> %.1f"
			% [rival_before, neighbour.biomass])

	# Contact, not ownership: a colony of the same faction standing on its own across
	# the map is not part of the same disaster.
	var isolated := tank.plant_colony(doomed, Vector2(2800, 400), 60.0)
	_check(isolated != null, "the isolated colony was not planted")
	if isolated == null:
		return
	var survivors_before := tank.colonies().size()
	tank.bleach(isolated.global_position)
	_check(isolated.is_dead(), "a bleach on an isolated colony left it standing")
	_check(tank.colonies().size() == survivors_before - 1,
		"a bleach on an isolated colony took something else with it")

	print("  bleach: %.0f biomass, %d of 4 links killed; the rival next door untouched"
		% [destroyed, killed])
	tank.clear_colonies()
	tank.queue_free()
