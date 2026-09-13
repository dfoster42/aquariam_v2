extends SceneTree
## Measure where the tank actually stops holding 60 fps.
##
## Run: godot --script res://tools/benchmark.gd
##
## Needs a real window. Headless uses a dummy renderer, so it measures the simulation
## and nothing of the drawing — which is half the question.
##
## Frame time is the number that matters, not the physics time on its own: once a
## physics step overruns its budget Godot runs fewer of them rather than reporting a
## slower one, so the simulation can look cheap while the frame is already late.

const STEPS: Array[int] = [50, 100, 200, 400, 800, 1200, 1500]
const WARMUP_FRAMES: int = 30
const SAMPLE_FRAMES: int = 90
const BUDGET_MS: float = 1000.0 / 60.0

var _tank: Aquarium
var _step: int = 0
var _frames: int = 0
var _samples: Array[float] = []
var _results: Array[Dictionary] = []
var _started: bool = false

func _initialize() -> void:
	# With vsync on, every frame under the GPU's limit reports exactly 16.67 ms and the
	# headroom below 60 fps is invisible — the first run of this could not tell 50 fish
	# from 300. Disabled, the numbers are what the machine can actually do.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.add_child(load("res://scenes/main.tscn").instantiate())

func _process(delta: float) -> bool:
	if not _started:
		_started = true
		_tank = root.get_node("Main/Aquarium")
		_fill_to(STEPS[0])
		return false

	_frames += 1
	if _frames <= WARMUP_FRAMES:
		return false

	_samples.append(delta * 1000.0)
	if _samples.size() < SAMPLE_FRAMES:
		return false

	_record()
	_step += 1
	if _step >= STEPS.size():
		_report()
		return true

	_fill_to(STEPS[_step])
	_frames = 0
	_samples.clear()
	return false

func _fill_to(target: int) -> void:
	var species := _tank.available_species
	var bounds := _tank.bounds()
	var guard := 0
	while _tank.population() < target and guard < target * 2:
		guard += 1
		var pick: FishSpecies = species[_tank.population() % species.size()]
		_tank.spawn(pick, Vector2(
			randf_range(bounds.position.x, bounds.end.x),
			randf_range(bounds.position.y, bounds.end.y)))

func _record() -> void:
	var sorted := _samples.duplicate()
	sorted.sort()
	var total := 0.0
	for sample in sorted:
		total += sample
	_results.append({
		"fish": _tank.population(),
		"mean": total / sorted.size(),
		"p95": sorted[int(sorted.size() * 0.95)],
		"worst": sorted[-1],
		"physics": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	})

func _report() -> void:
	print("\n fish | mean ms | p95 ms | worst | fps@mean | physics ms | draws")
	print("------+---------+--------+-------+----------+------------+------")
	var last_ok := 0
	for r in _results:
		var fps := 1000.0 / maxf(r["mean"], 0.001)
		print(" %4d | %7.2f | %6.2f | %5.1f | %8.0f | %10.2f | %4d" % [
			r["fish"], r["mean"], r["p95"], r["worst"], fps, r["physics"], r["draws"]])
		if r["mean"] <= BUDGET_MS:
			last_ok = r["fish"]
	print("\nheld 60 fps (mean frame <= %.2f ms) up to %d fish" % [BUDGET_MS, last_ok])
	print("vsync disabled for this run, so frame times are the machine's, not the display's.")
