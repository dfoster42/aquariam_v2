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
	_test_seated_on_floor()
	_test_column_and_commons()
	_test_pelagic_needs_support()
	_test_ravine_gating()
	_test_water_denominator()
	_test_age_round_trip()

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

## A faction by name rather than by index.
##
## The roster is no longer three interchangeable reefs — it holds shelf, kelp, vent and a
## pelagic shoal, which behave differently — so a test that wanted "two benthic rivals"
## and took elements 0 and 1 was one roster edit away from silently testing something
## else.
func _faction(tank: Aquarium, name: String) -> Faction:
	for f in tank.available_factions:
		if f.display_name == name:
			return f
	_failures.append("no faction named %s in the roster" % name)
	return null

## The nearest x to `near` where `faction` is allowed to be founded.
##
## Factions now declare what ground they can live on, so a hard-coded position is a test
## that breaks the day the terrain or a faction's range changes. This asks.
func _ground_x(tank: Aquarium, faction: Faction, near: float) -> float:
	var bounds := tank.bounds()
	for step in 240:
		for dir: float in [1.0, -1.0]:
			var x := near + dir * float(step) * 14.0
			if x > bounds.position.x + 80.0 and x < bounds.end.x - 80.0 \
					and tank.can_found(faction, x):
				return x
	_failures.append("found no ground for %s near x=%.0f" % [faction.display_name, near])
	return near

# ---------------------------------------------------------------------------- 1

func _test_accumulates(tank: Aquarium) -> void:
	var faction := _faction(tank, "Coral")
	if faction == null:
		return
	var colony := tank.plant_colony(faction, Vector2(_ground_x(tank, faction, 1500.0), 400.0))
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
	var big := _faction(tank, "Coral")
	var small := _faction(tank, "Kelp Court")
	if big == null or small == null:
		return

	# Same stretch of shelf, deliberately unequal mass. The border should sit nearer the
	# smaller one, which is only true if influence is compared rather than distance.
	var ax := _ground_x(tank, big, 1200.0)
	var bx := _ground_x(tank, small, 2040.0)
	var a := tank.plant_colony(big, Vector2(ax, 400.0), 90.0)
	var b := tank.plant_colony(small, Vector2(bx, 400.0), 20.0)
	if a == null or b == null:
		_failures.append("the contested fixture did not build")
		return
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
	# Sampled just above the ground, where a benthic column is at full strength — high in
	# the water column it would be above the shorter faction's lid and prove nothing.
	var mid_x := (ax + bx) * 0.5
	var midpoint := Vector2(mid_x, tank.seabed().height_at(mid_x) - Territory.CELL)
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
	var shelf := _faction(alone, "Coral")
	if shelf == null:
		return
	var centre := _ground_x(alone, shelf, 1620.0)
	var lone := alone.plant_colony(shelf, Vector2(centre, 400.0), 40.0)
	_advance(alone, 90.0)
	var lone_biomass := lone.biomass
	alone.clear_colonies()
	alone.queue_free()

	var boxed := crowded.plant_colony(_faction(crowded, "Coral"), Vector2(centre, 400.0), 40.0)
	# Flanked closely enough that the neighbours take the floor it would have reached.
	# Left and right only: the seabed is one-dimensional, so being hemmed in is a
	# horizontal condition now and a colony above or below would be a different rule.
	var rival := _faction(crowded, "Kelp Court")
	for dx: float in [-460.0, -230.0, 230.0, 460.0]:
		crowded.plant_colony(rival, Vector2(centre + dx, 400.0), 80.0)
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
	var a := _faction(tank, "Coral")
	var b := _faction(tank, "Kelp Court")
	if a == null or b == null:
		return
	var doomed := tank.plant_colony(a, Vector2(_ground_x(tank, a, 1400.0), 400.0), 70.0)
	var survivor := tank.plant_colony(b, Vector2(_ground_x(tank, b, 1900.0), 400.0), 70.0)
	if doomed == null or survivor == null:
		_failures.append("the vacuum fixture did not build")
		return
	_advance(tank, 40.0)
	tank._rebuild_territory()

	var territory := tank.territory()
	var survivor_before := territory.share_of_map(survivor)
	var doomed_before := territory.share_of_map(doomed)
	_check(doomed_before > 0.0, "the colony about to be struck held no ground to lose")

	var destroyed := tank.strike(doomed.global_position)
	_check(destroyed > 0.0, "a strike on a colony destroyed no biomass")

	# A wound is not a subtraction. The colony must still be standing in the frame the
	# strike lands in, or there is no moment of destruction to watch — which was the
	# whole defect: the frame captured right after a disaster looked identical to the
	# frame two minutes later.
	_check(not doomed.is_dead(), "a struck colony died in the same call as the strike")
	_check(doomed.is_dying(), "a struck colony is not draining")

	# And then the hole opens, over about a second and a half.
	_advance(tank, Colony.DRAIN_DURATION + 0.4)
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
	var doomed := _faction(tank, "Coral")
	var rival := _faction(tank, "Kelp Court")
	if doomed == null or rival == null:
		return

	# A chain of the doomed faction, each touching the next, with a rival colony sitting
	# right at the end of it. The bleach must run the whole chain and stop at the rival.
	var chain: Array[Colony] = []
	var before: Array[float] = []
	var base_x := _ground_x(tank, doomed, 1300.0)
	for i in 4:
		var colony := tank.plant_colony(doomed, Vector2(base_x + i * 300.0, 400.0), 60.0)
		if colony != null:
			chain.append(colony)
			before.append(colony.biomass)
	var neighbour := tank.plant_colony(rival, Vector2(base_x + 4 * 300.0, 400.0), 60.0)
	_check(chain.size() == 4 and neighbour != null, "the bleach fixture did not build")
	if chain.size() != 4 or neighbour == null:
		return

	var rival_before := neighbour.biomass
	var destroyed := tank.bleach(chain[0].global_position)
	_check(destroyed > 0.0, "a bleach on a reef destroyed nothing")

	# The far end of the chain must NOT have been touched yet. A bleach is conceptually
	# a thing spreading, and applying every hop in the same call made it arrive
	# everywhere at once — so it could never be watched spreading.
	_advance(tank, Aquarium.BLEACH_HOP_DELAY * 0.5)
	_check(chain[0].is_dying() or chain[0].is_dead(),
		"the reef the bleach started on is not affected yet")
	_check(not chain[3].is_dying() and not chain[3].is_dead(),
		"the far end of the chain was hit before the wave could reach it")

	# Let the wave cross and drain out.
	_advance(tank, Aquarium.BLEACH_HOP_DELAY * 5.0 + Colony.DRAIN_DURATION + 0.5)

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
	# Checked as "was never wounded" rather than "has the same biomass". The wave now
	# takes seconds to cross, and a healthy colony grows during them — asserting an
	# unchanged number would fail on the rival THRIVING, which is the opposite of the
	# thing being guarded against.
	_check(not neighbour.is_dead() and not neighbour.is_dying()
			and neighbour.biomass >= rival_before,
		"the bleach crossed into a rival faction: %.1f -> %.1f"
			% [rival_before, neighbour.biomass])

	# Contact, not ownership: a colony of the same faction standing on its own across
	# the map is not part of the same disaster.
	var isolated := tank.plant_colony(doomed, Vector2(_ground_x(tank, doomed, 2900.0), 400.0), 60.0)
	_check(isolated != null, "the isolated colony was not planted")
	if isolated == null:
		return
	# Everything still standing and unwounded right before the second bleach. Compared
	# against this rather than against a colony COUNT: the chain's remnants are still
	# draining from the first bleach and die during the advance, so a count would report
	# their deaths as collateral from a disaster on the other side of the map.
	var healthy: Array[Colony] = []
	for colony in tank.colonies():
		if colony != isolated and not colony.is_dying():
			healthy.append(colony)

	tank.bleach(isolated.global_position)
	_advance(tank, Colony.DRAIN_DURATION + 0.5)
	_check(isolated.is_dead(), "a bleach on an isolated colony left it standing")
	for colony in healthy:
		_check(is_instance_valid(colony) and not colony.is_dead(),
			"a bleach on an isolated colony killed a healthy colony elsewhere")

	print("  bleach: %.0f biomass, %d of 4 links killed; the rival next door untouched"
		% [destroyed, killed])
	tank.clear_colonies()
	tank.queue_free()

# ------------------------------------------------- the seabed prerequisite

## Colonies, plants and fish all belong in the water, not in the rock.
##
## Before the floor was ported into the simulation, none of them knew it existed: a
## colony was founded wherever the finger landed, which in a side view is a reef hanging
## in mid-water, and fish sampled wander targets from the whole rectangle including the
## 13-36% of every column painted as solid ground.
func _test_seated_on_floor() -> void:
	var tank := _tank()
	if tank == null:
		return
	var seabed := tank.seabed()
	_check(seabed != null, "the tank has no seabed")
	if seabed == null:
		return

	# Kelp Court can live almost anywhere on the floor, so it is the faction that can
	# actually be asked this across the whole map.
	var anywhere := _faction(tank, "Kelp Court")
	if anywhere == null:
		return
	# A tap high in the water column still founds the reef on the ground beneath it.
	for x: float in [200.0, 680.0, 1440.0, 1847.0, 2754.0, 3000.0]:
		var colony := tank.plant_colony(anywhere, Vector2(x, 300.0))
		if colony == null:
			_failures.append("no colony could be founded at x=%.0f" % x)
			continue
		_check(absf(colony.global_position.y - seabed.height_at(x)) <= 1.0,
			"a colony at x=%.0f sits at y=%.1f, floor is %.1f"
				% [x, colony.global_position.y, seabed.height_at(x)])

	# Daughters walk along the terrain rather than off it.
	_advance(tank, 200.0)
	var airborne := 0
	for colony in tank.colonies():
		if absf(colony.global_position.y - seabed.height_at(colony.global_position.x)) > 1.0:
			airborne += 1
	_check(airborne == 0, "%d colonies are not seated on the floor after spreading" % airborne)

	# Nothing that DRAWS a rooted structure may hang in open water. A pelagic faction
	# owns no structure at all, so it must not be drawing the seabed sprite — that put
	# anemones back in the middle of the ocean after the colonies themselves had been
	# seated, which is a regression the eye catches and no assertion did.
	var shoal := _faction(tank, "Deep Blue")
	if shoal != null:
		var drifting := tank.plant_colony(shoal, Vector2(1500.0, 400.0), 60.0)
		if drifting != null:
			_check(not drifting.sprite.visible,
				"a pelagic colony draws a rooted sprite in open water")
	for colony in tank.colonies():
		if not colony.sprite.visible:
			continue
		_check(absf(colony.global_position.y - seabed.height_at(colony.global_position.x)) <= 1.0,
			"a colony drawing a sprite sits %.0f units off the floor"
				% absf(colony.global_position.y - seabed.height_at(colony.global_position.x)))

	# And no fish is ever inside the ground, over a real run.
	var stuck := 0
	for i in 240:
		tank._process(1.0 / 30.0)
	for fish in tank.fish():
		if seabed.is_rock(fish.global_position):
			stuck += 1
	_check(stuck == 0, "%d fish are inside the seabed" % stuck)

	tank.clear_colonies()
	tank.queue_free()

## Shares are fractions of the SEA, not of the tank's rectangle.
func _test_water_denominator() -> void:
	var tank := _tank()
	if tank == null:
		return
	var territory := tank.territory()
	var grid := territory.grid_size()
	_check(territory.water_cells() < grid.x * grid.y,
		"every cell in the grid counts as water; the floor mask is not being applied")
	_check(territory.water_cells() > int(0.6 * grid.x * grid.y),
		"only %d of %d cells count as water, which is too few for the shipped curve"
			% [territory.water_cells(), grid.x * grid.y])

	# An empty tank is all open sea.
	_check(is_equal_approx(territory.open_water(), 1.0),
		"an empty tank reports %.3f open water" % territory.open_water())

	# And the books balance: what everyone holds plus what nobody holds is the whole sea.
	var one := _faction(tank, "Coral")
	var two := _faction(tank, "Kelp Court")
	tank.plant_colony(one, Vector2(_ground_x(tank, one, 900.0), 400.0), 80.0)
	tank.plant_colony(two, Vector2(_ground_x(tank, two, 2100.0), 400.0), 80.0)
	_advance(tank, 60.0)
	tank._rebuild_territory()
	var held := 0.0
	for faction in tank.available_factions:
		held += territory.faction_share(faction)
	_check(absf(held + territory.open_water() - 1.0) < 0.001,
		"shares sum to %.4f, not 1.0" % (held + territory.open_water()))

	tank.clear_colonies()
	tank.queue_free()

## A colony's age is what makes an old reef different from a new one, so it has to
## survive a relaunch. It was being dropped on every save.
func _test_age_round_trip() -> void:
	TankStore.clear()
	var tank := _tank()
	if tank == null:
		return
	var age_faction := _faction(tank, "Coral")
	if age_faction == null:
		return
	var colony := tank.plant_colony(age_faction,
		Vector2(_ground_x(tank, age_faction, 1500.0), 400.0), 50.0)
	if colony == null:
		_failures.append("could not found a colony for the age round trip")
		return
	_advance(tank, 120.0)
	var aged := colony.age
	var mass := colony.biomass
	_check(aged > 100.0, "the colony only aged %.1fs over a 120s advance" % aged)
	_check(TankStore.save(tank) == OK, "saving a tank with colonies failed")

	var data := TankStore.read()
	var entries: Array = data.get("colonies", [])
	_check(entries.size() >= 1, "the save holds no colonies")

	var restored := _tank()
	if restored == null:
		return
	restored.clear_colonies()
	_check(restored.restore(data), "restore() reported nothing restored")
	var back := restored.colonies()
	_check(back.size() >= 1, "no colony came back")
	if back.size() >= 1:
		_check(absf(back[0].age - aged) <= 1.0,
			"age did not survive the save: %.1f -> %.1f" % [aged, back[0].age])
		_check(absf(back[0].biomass - mass) <= 0.5,
			"biomass did not survive the save: %.1f -> %.1f" % [mass, back[0].biomass])
	print("  round trip: a %.0fs old reef came back %.0fs old" % [aged, back[0].age if back.size() >= 1 else -1.0])

	tank.clear_colonies()
	restored.clear_colonies()
	tank.queue_free()
	restored.queue_free()

# ------------------------------------------------------ ground and water

## A benthic claim is a column standing on held ground: it stops at the floor, it stops
## at its own cap, and the water above that cap belongs to nobody.
func _test_column_and_commons() -> void:
	var tank := _tank()
	if tank == null:
		return
	var shelf := _faction(tank, "Coral")
	if shelf == null:
		return
	var x := _ground_x(tank, shelf, 1600.0)
	var colony := tank.plant_colony(shelf, Vector2(x, 400.0), shelf.capacity)
	if colony == null:
		_failures.append("the column fixture did not build")
		return
	tank._rebuild_territory()
	var territory := tank.territory()
	var ground := tank.seabed().height_at(x)

	# Just above the floor: held.
	_check(territory.owner_at(Vector2(x, ground - Territory.CELL)) == colony,
		"the colony does not own the water directly above its own ground")

	# Well above its cap: the commons. A benthic faction cannot own the open ocean, which
	# is the rule the whole scheme turns on.
	var above := ground - colony.extent().y - Territory.CELL * 4.0
	if above > tank.bounds().position.y + Territory.CELL:
		_check(territory.owner_at(Vector2(x, above)) == null,
			"a benthic colony owns water %.0f units above its own column cap"
				% (ground - colony.extent().y - above))

	# Inside the rock: never.
	_check(territory.owner_at(Vector2(x, ground + Territory.CELL * 3.0)) == null,
		"a claim reaches below the seabed")

	# And the cap rises with the colony. Height is what a faction IS; width is what it
	# earned, and they are separate axes on purpose.
	var tall := colony.extent().y
	var young := tank.plant_colony(shelf, Vector2(_ground_x(tank, shelf, 2600.0), 400.0),
		Colony.SEED_BIOMASS)
	if young != null:
		_check(young.extent().y < tall * 0.8,
			"a seed colony's column (%.0f) is nearly as tall as a full one's (%.0f)"
				% [young.extent().y, tall])
		_check(tall <= shelf.reach_up + 1.0,
			"a full column (%.0f) exceeds the faction's cap (%.0f)" % [tall, shelf.reach_up])

	tank.clear_colonies()
	tank.queue_free()

## A pelagic faction owns a band of the commons, but only while something of its own is
## rooted on the floor below it. The open ocean is valuable and indefensible.
func _test_pelagic_needs_support() -> void:
	var tank := _tank()
	if tank == null:
		return
	var shoal := _faction(tank, "Deep Blue")
	var reef := _faction(tank, "Coral")
	if shoal == null or reef == null:
		return
	_check(shoal.claim == Faction.Claim.PELAGIC, "Deep Blue is not a pelagic faction")

	# Unsupported: a shoal over open ground thins.
	var x := _ground_x(tank, reef, 1500.0)
	var adrift := tank.plant_colony(shoal, Vector2(x, 400.0), 80.0)
	if adrift == null:
		_failures.append("the pelagic fixture did not build")
		return
	_check(not adrift.is_benthic(), "a pelagic colony reports itself benthic")
	_check(absf(adrift.global_position.y
		- (tank.bounds().position.y + tank.bounds().size.y * shoal.altitude)) <= 1.0,
		"a pelagic colony was not placed at its own altitude")

	var started := adrift.biomass
	_advance(tank, 30.0)
	_check(not adrift.supported, "an unsupported shoal reports itself supported")
	_check(adrift.biomass < started,
		"an unsupported shoal grew from %.1f to %.1f" % [started, adrift.biomass])

	var adrift_ended := adrift.biomass
	tank.clear_colonies()

	# Supported: the same shoal over a reef does not thin. The reef is a DIFFERENT
	# faction on purpose — a shoal riding a rival's floor is the case worth having.
	var propped := tank.plant_colony(shoal, Vector2(x, 400.0), 80.0)
	tank.plant_colony(reef, Vector2(x, 400.0), reef.capacity)
	tank._rebuild_territory()
	if propped != null:
		var held := propped.biomass
		_advance(tank, 30.0)
		_check(propped.supported,
			"a shoal sitting over a reef reports itself unsupported")
		_check(propped.biomass > held,
			"a supported shoal went from %.1f to %.1f" % [held, propped.biomass])
		print("  pelagic: adrift %.1f -> %.1f, over a reef %.1f -> %.1f"
			% [started, adrift_ended, held, propped.biomass])

	tank.clear_colonies()
	tank.queue_free()

## Ravine-only means ravine-only. Checked against carving rather than depth, because the
## landform's own low ground at x=0 is deeper than two of the three basins.
func _test_ravine_gating() -> void:
	var tank := _tank()
	if tank == null:
		return
	var vent := _faction(tank, "Vent")
	if vent == null:
		return
	_check(vent.requires_ravine > 0.0, "the Vent faction does not require a ravine")
	var seabed := tank.seabed()

	# The map's deepest non-carved ground must be refused even though it is deep.
	var deepest_flat := -1.0
	var flat_x := 0.0
	for i in 400:
		var x := float(i) * 8.0
		if seabed.ravine_at(x) < 1.0 and seabed.height_at(x) > deepest_flat:
			deepest_flat = seabed.height_at(x)
			flat_x = x
	_check(deepest_flat > 0.0, "found no uncarved ground at all")
	_check(not tank.can_found(vent, flat_x),
		"a ravine faction was allowed onto uncarved ground at x=%.0f (y %.1f)"
			% [flat_x, deepest_flat])
	_check(tank.plant_colony(vent, Vector2(flat_x, 400.0)) == null,
		"a ravine faction was founded on uncarved ground anyway")

	# And each basin in the shipped terrain must accept one.
	var basins := 0
	for centre: float in [680.0, 1847.0, 2754.0]:
		if tank.can_found(vent, centre):
			basins += 1
			var colony := tank.plant_colony(vent, Vector2(centre, 400.0))
			_check(colony != null, "no vent could be founded in the basin at x=%.0f" % centre)
	_check(basins == 3, "only %d of the 3 drawn basins accept a vent" % basins)

	# A vent's column starts from the deepest ground on the map, so it out-reaches
	# everything. That is the payoff for being confined to 3 basins.
	var shelf := _faction(tank, "Coral")
	if shelf != null:
		_check(vent.reach_up > shelf.reach_up,
			"the vent's column is not the tallest in the game")

	tank.clear_colonies()
	tank.queue_free()
