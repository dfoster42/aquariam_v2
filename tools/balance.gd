extends SceneTree
## Where each faction ends up, over many randomised starts.
##
## Balance was being read off tools/colony_demo.gd, which plants the same factions at the
## same four positions every run. That is a fixed layout, and a fixed layout measures the
## layout: a faction seeded between two rivals looked weak, a faction seeded at the map's
## edge could only spread one way, and both were mistaken for the faction being wrong.
##
## Every faction gets the same number of seeds here, at random legal positions, over many
## runs. What comes out is a mean and a spread, which is the only thing worth tuning
## against.
##
## Run: godot --headless --script res://tools/balance.gd [-- --runs N --minutes M]

const DEFAULT_RUNS: int = 12
const DEFAULT_MINUTES: float = 4.0
const SEEDS_PER_FACTION: int = 2
const STEP: float = 0.2

var _runs: int = DEFAULT_RUNS
var _minutes: float = DEFAULT_MINUTES

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--runs")
	if i != -1 and i + 1 < args.size():
		_runs = int(args[i + 1])
	i = args.find("--minutes")
	if i != -1 and i + 1 < args.size():
		_minutes = float(args[i + 1])
	TankStore.clear()

func _process(_delta: float) -> bool:
	var samples: Dictionary = {}
	var colony_counts: Dictionary = {}
	var wipeouts: Dictionary = {}
	var traits: Dictionary = {}
	var names: Array[String] = []

	for run in _runs:
		seed(run * 7919 + 13)
		var tank := _tank()
		if tank == null:
			quit(1)
			return true
		# Every faction is REPORTED, but only placeable ones are seeded. The ravine
		# dwellers have to be reached by a lineage descending into them, so seeding one
		# would measure a start the player cannot have.
		for faction in tank.available_factions:
			if not samples.has(faction.display_name):
				samples[faction.display_name] = [] as Array[float]
				colony_counts[faction.display_name] = [] as Array[float]
				traits[faction.display_name] = [] as Array[float]
				wipeouts[faction.display_name] = 0
				names.append(faction.display_name)
			if not faction.placeable:
				continue
			for s in SEEDS_PER_FACTION:
				tank.plant_colony(faction, Vector2(_legal_x(tank, faction), 400.0), 30.0)

		for step in int(_minutes * 60.0 / STEP):
			tank._tick_colonies(STEP)
		tank._rebuild_territory()

		var territory := tank.territory()
		for faction in tank.available_factions:
			var share := territory.faction_share(faction)
			(samples[faction.display_name] as Array).append(share)
			var n := 0
			for colony in tank.colonies():
				if colony.faction == faction:
					n += 1
			(colony_counts[faction.display_name] as Array).append(float(n))
			(traits[faction.display_name] as Array).append(
				float(tank.progress_for(faction).unlocked.size()))
			if n == 0:
				wipeouts[faction.display_name] = int(wipeouts[faction.display_name]) + 1
		tank.clear_colonies()
		tank.queue_free()

	print("%d runs, %d seeds each, %.0f simulated minutes\n" % [_runs, SEEDS_PER_FACTION, _minutes])
	print("%-12s %8s %8s %8s %8s %9s %8s" % ["faction", "mean", "min", "max", "colonies", "wiped", "traits"])
	for name in names:
		var shares: Array = samples[name]
		print("%-12s %7.1f%% %7.1f%% %7.1f%% %8.1f %6d/%d %8.1f"
			% [name, _mean(shares) * 100.0, shares.min() * 100.0, shares.max() * 100.0,
				_mean(colony_counts[name]), int(wipeouts[name]), _runs, _mean(traits[name])])
	quit(0)
	return true

func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v: float in values:
		total += v
	return total / float(values.size())

func _tank() -> Aquarium:
	var tank := load("res://scenes/aquarium.tscn").instantiate() as Aquarium
	if tank == null:
		return null
	tank.autosave_interval = 0.0
	root.add_child(tank)
	return tank

## A random x this faction may be founded on. Rejection sampling, because the legal
## ground for a ravine faction is three short stretches and scanning outward from a
## random point would pile every vent against the same basin edge.
func _legal_x(tank: Aquarium, faction: Faction) -> float:
	var bounds := tank.bounds()
	for attempt in 400:
		var x := randf_range(bounds.position.x + 120.0, bounds.end.x - 120.0)
		if tank.can_found(faction, x):
			return x
	return bounds.get_center().x
