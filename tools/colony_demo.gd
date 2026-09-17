extends SceneTree
## Stands up rival reefs, lets them fight over the map, strikes one, and photographs
## what happens next.
##
## This is not a test — colony_test.gd checks the numbers. This answers the only
## question the numbers cannot: whether a strike LOOKS like anything. The pivot rests on
## a map that visibly changes, so the deliverable is four frames anyone can flip
## through, not a passing assertion.
##
## Run: godot --script res://tools/colony_demo.gd [-- --out-dir DIR]

## Frames to let a shot settle. A sprite rescaled this frame still photographs at its
## old size, and the territory texture is uploaded during the tick.
const SETTLE: int = 8
## Seconds of SIMULATION fast-forwarded between beats, not frames waited.
##
## The two are wildly different scales and conflating them is what made the first run
## of this tool meaningless: it waited 240 frames — four seconds — for growth that takes
## a minute, photographed three untouched seed colonies, and reported that striking one
## moved its neighbours by 0.2 points. Driving the tank's own colony tick directly is
## the same code path at a useful speed.
const GROW_SECONDS: float = 150.0
const AFTERMATH_SECONDS: float = 120.0
const TICK: float = 0.1

var _main: Node2D
var _tank: Aquarium
var _camera: CameraRig
var _out_dir: String = "user://"
var _frames: int = 0
var _step: int = 0
var _next: int = 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--out-dir")
	if index != -1 and index + 1 < args.size():
		_out_dir = args[index + 1]
	TankStore.clear()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_tank = _main.get_node("Aquarium")
	_camera = _main.get_node("CameraRig")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_setup()
		return false
	if _frames < _next:
		return false

	match _step:
		0:
			_shoot("1-founded")
			_advance(GROW_SECONDS)
			_next = _frames + SETTLE
		1:
			_shoot("2-grown")
			_report("before the strike")
			_next = _frames + 4
		2:
			# Strike the reef that actually holds the most ground by now — a demo that
			# always hits whichever colony was listed first will sooner or later
			# photograph the destruction of the smallest thing on the map.
			var target := _biggest()
			var destroyed := _tank.bleach(target.global_position)
			print("bleached %s for %.0f biomass" % [target.faction.display_name, destroyed])
			_next = _frames + 4
		3:
			_shoot("3-struck")
			_advance(AFTERMATH_SECONDS)
			_next = _frames + SETTLE
		4:
			_shoot("4-aftermath")
			_report("after the neighbours moved in")
			return true
	_step += 1
	return false

func _setup() -> void:
	# Three reefs spaced so none starts touching another: the borders have to form
	# during the run, or the first shot already shows the answer.
	var bounds := _tank.bounds()
	var factions := _tank.available_factions
	var spots := [
		Vector2(bounds.size.x * 0.22, bounds.size.y * 0.62),
		Vector2(bounds.size.x * 0.52, bounds.size.y * 0.40),
		Vector2(bounds.size.x * 0.78, bounds.size.y * 0.66),
	]
	for i in mini(factions.size(), spots.size()):
		_tank.plant_colony(factions[i], spots[i], 30.0)

	# Frame the whole map. The camera refuses to zoom out past the tank's edges, which
	# is right in the app and wrong here: the territory wash is the subject and it is
	# map-sized, so the rig is told about a tank several times larger than the real one
	# purely to raise that floor.
	var wide := Rect2(bounds.position - bounds.size, bounds.size * 3.0)
	_camera.setup(wide)
	_camera.position = bounds.get_center()
	_camera.zoom = Vector2(0.3, 0.3)
	_next = SETTLE

## Fast-forwards the colony simulation through the tank's own tick.
func _advance(seconds: float) -> void:
	for i in int(seconds / TICK):
		_tank._tick_colonies(TICK)

## The colony holding the most ground right now.
func _biggest() -> Colony:
	var best: Colony = null
	for colony in _tank.colonies():
		if best == null or colony.biomass > best.biomass:
			best = colony
	return best

func _report(label: String) -> void:
	var territory := _tank.territory()
	var parts: Array[String] = []
	for faction in _tank.available_factions:
		parts.append("%s %.1f%%" % [faction.display_name, territory.faction_share(faction) * 100.0])
	print("%s: %s, open water %.1f%%"
		% [label, ", ".join(parts), territory.open_water() * 100.0])

func _shoot(name: String) -> void:
	var path := "%s/%s.png" % [_out_dir.trim_suffix("/"), name]
	root.get_texture().get_image().save_png(path)
	print("SHOT:" + ProjectSettings.globalize_path(path))
