extends SceneTree
## How much a territory rebuild costs, against cell size and colony count.
##
## The cell went from 36 world units to 24 to kill visible stair-stepping, which
## quadruples nothing and multiplies the grid by 2.25 — 5,400 cells to 12,150. That trade
## was made on how it looked, with nobody knowing what it cost. This is the measurement.
##
## Measures `Territory.rebuild()` alone rather than a whole frame: it is the only thing
## the cell size changes, and burying it in a frame time that is dominated by a few
## hundred fish would hide whatever it does.
##
## Run: godot --headless --script res://tools/territory_benchmark.gd

const CELLS: Array[float] = [36.0, 30.0, 24.0]
const COUNTS: Array[int] = [4, 12, 24, 40]
const REPEATS: int = 20

var _tank: Aquarium

func _initialize() -> void:
	TankStore.clear()
	_tank = load("res://scenes/aquarium.tscn").instantiate()
	_tank.autosave_interval = 0.0
	root.add_child(_tank)

func _process(_delta: float) -> bool:
	var bounds := _tank.bounds()
	var seabed := _tank.seabed()
	print("map %.0fx%.0f, %d repeats per cell\n" % [bounds.size.x, bounds.size.y, REPEATS])
	print("%-7s %8s %6s %9s %9s %10s %8s"
		% ["cells", "grid", "col", "visited", "mean ms", "ns/cell", "of a sec"])

	for cell in CELLS:
		var territory := Territory.new(bounds, seabed, cell)
		var grid := territory.grid_size()
		for count in COUNTS:
			var colonies := _stand_up(count)
			# One rebuild before timing: the first touches every Dictionary for the
			# first time and is not what the running app pays.
			territory.rebuild(colonies)
			var started := Time.get_ticks_usec()
			for i in REPEATS:
				territory.rebuild(colonies)
			var mean_ms := float(Time.get_ticks_usec() - started) / float(REPEATS) / 1000.0
			# What it actually costs per second of play, at TERRITORY_INTERVAL.
			var per_second := mean_ms * (1.0 / Aquarium.TERRITORY_INTERVAL) / 1000.0
			var per_cell_ns := (mean_ms * 1000000.0) / maxf(float(territory.visited), 1.0)
			print("%-7.0f %8s %6d %9d %9.3f %10.0f %7.1f%%"
				% [cell, "%dx%d" % [grid.x, grid.y], count, territory.visited,
					mean_ms, per_cell_ns, per_second * 100.0])
			_tank.clear_colonies()
		print("")
	quit(0)
	return true

## `count` mature colonies spread across the map, on ground each faction can hold.
func _stand_up(count: int) -> Array[Colony]:
	_tank.clear_colonies()
	var bounds := _tank.bounds()
	var factions := _tank.available_factions
	var made: Array[Colony] = []
	for i in count:
		var faction: Faction = factions[i % factions.size()]
		var near := bounds.position.x + bounds.size.x * (float(i) + 0.5) / float(count)
		var colony := _tank.plant_colony(faction,
			Vector2(_ground_x(faction, near), 400.0), faction.capacity)
		if colony != null:
			made.append(colony)
	return made

func _ground_x(faction: Faction, near: float) -> float:
	var bounds := _tank.bounds()
	for step in 240:
		for dir: float in [1.0, -1.0]:
			var x := near + dir * float(step) * 14.0
			if x > bounds.position.x + 80.0 and x < bounds.end.x - 80.0 \
					and _tank.can_found(faction, x):
				return x
	return near
