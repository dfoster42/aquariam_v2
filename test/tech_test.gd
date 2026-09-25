extends SceneTree
## Faction tech trees: earned by what the simulation measures, and visible when earned.
##
## Run: godot --headless --script res://test/tech_test.gd

const STEP: float = 0.1
var _failures: Array[String] = []
var _evolved: Array[String] = []

func _initialize() -> void:
	TankStore.clear()

func _process(_delta: float) -> bool:
	_check_prerequisites_gate_the_tree()
	_check_hold_share_waits_for_its_clock()
	_check_effects_show()
	_check_surviving_a_disaster_hardens()
	_check_basins()
	_check_progress_survives_a_save()
	_check_hardness_is_capped()
	if _failures.is_empty():
		print("RESULT: PASS")
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		print("RESULT: FAIL")
	quit(0 if _failures.is_empty() else 1)
	return true

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)

func _tank() -> Aquarium:
	var tank := load("res://scenes/aquarium.tscn").instantiate() as Aquarium
	tank.autosave_interval = 0.0
	root.add_child(tank)
	tank.faction_evolved.connect(func(f: Faction, t: FactionTrait) -> void:
		_evolved.append("%s:%s" % [f.display_name, t.display_name]))
	return tank

func _faction(tank: Aquarium, name: String) -> Faction:
	for f in tank.available_factions:
		if f.display_name == name:
			return f
	_failures.append("no faction %s" % name)
	return null

func _trait(f: Faction, name: String) -> FactionTrait:
	for t in f.tech:
		if t.display_name == name:
			return t
	_failures.append("%s has no trait %s" % [f.display_name, name])
	return null

func _ground_x(tank: Aquarium, f: Faction, near: float) -> float:
	for i in 400:
		var x := near + float(i) * 12.0 * (1.0 if i % 2 == 0 else -1.0)
		if x > 150.0 and x < 3090.0 and tank.can_found(f, x):
			return x
	return near

func _advance(tank: Aquarium, seconds: float) -> void:
	for i in int(seconds / STEP):
		tank._tick_colonies(STEP)

func _done(tank: Aquarium) -> void:
	tank.clear_colonies()
	root.remove_child(tank)
	tank.free()

# -----------------------------------------------------------------------------

func _check_prerequisites_gate_the_tree() -> void:
	var tank := _tank()
	var kelp := _faction(tank, "Kelp Court")
	var p := tank.progress_for(kelp)
	var canopy := _trait(kelp, "Canopy")
	var holdfast := _trait(kelp, "Holdfast")
	_check(not p.available().has(canopy), "Canopy is available before Holdfast is earned")
	_check(p.available().has(holdfast), "Holdfast, a root of the tree, is not available")
	# Conditions met in full for a long time do not earn a locked trait.
	for i in 20:
		p.tick(10.0, {"share": 1.0, "colonies": 9, "basins": 3, "survived_disaster": false})
	_check(p.has(holdfast), "Holdfast was not earned with its condition met for 200s")
	_check(p.has(canopy), "Canopy was not earned once Holdfast was")
	_done(tank)

func _check_hold_share_waits_for_its_clock() -> void:
	var tank := _tank()
	var kelp := _faction(tank, "Kelp Court")
	var holdfast := _trait(kelp, "Holdfast")
	tank.plant_colony(kelp, Vector2(_ground_x(tank, kelp, 1500.0), 400.0), kelp.capacity)
	var p := tank.progress_for(kelp)
	_advance(tank, holdfast.hold_for * 0.5)
	_check(not p.has(holdfast), "Holdfast was earned before its %ds clock ran" % holdfast.hold_for)
	_advance(tank, holdfast.hold_for * 0.8)
	_check(p.has(holdfast), "a kelp holding %.0f%% of the sea never earned Holdfast"
		% (tank.territory().faction_share(kelp) * 100.0))
	_check(_evolved.has("Kelp Court:Holdfast"), "earning Holdfast emitted no faction_evolved")
	_done(tank)

## The point of a trait is that you can SEE it: Canopy makes the kelp's column taller.
func _check_effects_show() -> void:
	var tank := _tank()
	var kelp := _faction(tank, "Kelp Court")
	var canopy := _trait(kelp, "Canopy")
	var colony := tank.plant_colony(kelp, Vector2(_ground_x(tank, kelp, 1500.0), 400.0), kelp.capacity)
	var before := colony.extent().y
	tank.progress_for(kelp).unlock(_trait(kelp, "Holdfast"))
	tank.progress_for(kelp).unlock(canopy)
	var after := colony.extent().y
	# Read from the trait, not hard-coded: the multiplier is a tuning value, and an earlier
	# version of this check broke the first time the tree was rebalanced.
	_check(absf(after - before * canopy.reach_mul) < 1.0,
		"Canopy (x%.2f) left the column at %.0f (was %.0f)" % [canopy.reach_mul, after, before])
	_check(after > before, "Canopy did not make the column taller")
	tank._rebuild_territory()
	# Water above where the old column stopped entirely, well inside the new one's reach.
	var ground := tank.seabed().height_at(colony.global_position.x)
	var probe := Vector2(colony.global_position.x, ground - (before + (after - before) * 0.5))
	_check(tank.territory().owner_at(probe) == colony,
		"the taller column does not claim water above where the old one ended")
	print("  canopy: column %.0f -> %.0f" % [before, after])
	_done(tank)

## Surviving is rewarded: the faction that was hit and lived comes back harder.
func _check_surviving_a_disaster_hardens() -> void:
	var tank := _tank()
	var coral := _faction(tank, "Coral")
	var calcified := _trait(coral, "Calcified")
	var p := tank.progress_for(coral)
	var colony := tank.plant_colony(coral, Vector2(_ground_x(tank, coral, 1500.0), 400.0), coral.capacity)
	# A glancing strike: wounds, does not kill.
	tank.strike(colony.global_position + Vector2(Aquarium.STRIKE_RADIUS * 0.8, 0.0))
	_check(colony.is_dying(), "the glancing strike did not wound the colony")
	_check(not p.has(calcified), "Calcified was earned while the wound was still draining")
	_advance(tank, Colony.DRAIN_DURATION + 1.0)
	_check(not colony.is_dead(), "the glancing strike killed the colony")
	_check(p.has(calcified), "a coral that lived through a strike did not earn Calcified")

	var mass := colony.biomass
	var dealt := colony.damage(30.0)
	_check(absf(dealt - 30.0 * (1.0 - p.hardness)) < 0.01,
		"a calcified colony took %.1f of a 30 hit (hardness %.2f)" % [dealt, p.hardness])
	_check(dealt < 30.0 and mass > 0.0, "hardness did not reduce the damage")
	_done(tank)

## Driven through the tech pass alone, without growing or spreading anything. Left to
## run, a vent spreads — and its daughters can land in a second basin on their own, which
## earns Chemosynthesis for real and made the "one basin is not enough" half of this racy.
func _check_basins() -> void:
	var tank := _tank()
	var vent := _faction(tank, "Vent")
	var smoker := _trait(vent, "Black Smoker")
	var chemo := _trait(vent, "Chemosynthesis")
	var p := tank.progress_for(vent)
	tank.plant_colony(vent, Vector2(1847.0, 400.0), vent.capacity)
	tank._advance_tech(smoker.hold_for * 0.5)
	_check(not p.has(smoker), "Black Smoker was earned before its clock ran")
	tank._advance_tech(smoker.hold_for * 0.6)
	_check(p.has(smoker), "a vent holding a basin for %ds did not earn Black Smoker" % smoker.hold_for)
	tank._advance_tech(chemo.hold_for + 1.0)
	_check(not p.has(chemo), "Chemosynthesis was earned holding one basin; it needs two")
	tank.plant_colony(vent, Vector2(680.0, 400.0), vent.capacity)
	tank._advance_tech(chemo.hold_for + 1.0)
	_check(p.has(chemo), "a vent holding two basins did not earn Chemosynthesis")
	_done(tank)

func _check_progress_survives_a_save() -> void:
	TankStore.clear()
	var tank := _tank()
	var kelp := _faction(tank, "Kelp Court")
	tank.plant_colony(kelp, Vector2(_ground_x(tank, kelp, 1500.0), 400.0), kelp.capacity)
	tank.progress_for(kelp).unlock(_trait(kelp, "Holdfast"))
	tank.progress_for(kelp).unlock(_trait(kelp, "Canopy"))
	var tall := tank.colonies()[0].extent().y
	_check(TankStore.save(tank) == OK, "could not save")
	_done(tank)

	var back := _tank()
	back.clear_colonies()
	back.restore(TankStore.read())
	var pk := back.progress_for(_faction(back, "Kelp Court"))
	_check(pk.has(_trait(kelp, "Canopy")), "Canopy did not survive the save")
	_check(not back.colonies().is_empty() and absf(back.colonies()[0].extent().y - tall) < 1.0,
		"a restored colony does not stand as tall as the one saved")
	_done(back)
	TankStore.clear()

func _check_hardness_is_capped() -> void:
	var p := FactionProgress.new(null)
	for i in 5:
		var t := FactionTrait.new()
		t.hardness = 0.5
		p.unlock(t)
	_check(p.hardness <= FactionProgress.MAX_HARDNESS + 0.0001,
		"stacked hardness reached %.2f; a disaster must always do something" % p.hardness)
