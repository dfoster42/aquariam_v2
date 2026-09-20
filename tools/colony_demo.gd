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
			# And at the zoom a player actually holds. The map-wide shots are how the
			# mechanic is judged; this is how the game is seen.
			_camera.setup(_tank.bounds())
			_camera.position = Vector2(_tank.bounds().size.x * 0.48,
				_tank.bounds().size.y * 0.5)
			_camera.zoom = Vector2(0.62, 0.62)
			_next = _frames + SETTLE
		2:
			_shoot("2b-player-view")
			var wide := Rect2(_tank.bounds().position - _tank.bounds().size,
				_tank.bounds().size * 3.0)
			_camera.setup(wide)
			_camera.position = _tank.bounds().get_center()
			_camera.zoom = Vector2(0.3, 0.3)
			_next = _frames + SETTLE
		3:
			# Strike the reef that actually holds the most ground by now — a demo that
			# always hits whichever colony was listed first will sooner or later
			# photograph the destruction of the smallest thing on the map.
			var target := _biggest()
			var destroyed := _tank.bleach(target.global_position)
			print("bleached %s for %.0f biomass" % [target.faction.display_name, destroyed])
			_next = _frames + 4
		4:
			_shoot("3-struck")
			_advance(AFTERMATH_SECONDS)
			_next = _frames + SETTLE
		5:
			_shoot("4-aftermath")
			_report("after the neighbours moved in")
			return true
	_step += 1
	return false

func _setup() -> void:
	# No vent among them: it is not placeable, and a lineage has to descend into a basin
	# to reach one. Whether any does is part of what this run shows.
	#
	# TWO of each benthic faction, so a share readout compares factions rather than
	# counting seeds. An earlier version planted two Corals and one Kelp and the
	# resulting 15% against 6% read as an imbalance that was not there.
	#
	# On ground each faction is actually allowed to hold, and spaced so none starts
	# touching another: the borders have to form during the run, or the first
	# shot already shows the answer.
	#
	# Positions are asked for rather than asserted — a vent can only be founded in one of
	# the three basins drawn into the backdrop, and a shelf faction cannot go down there,
	# so hard-coded x values would quietly produce a demo of two reefs and a gap.
	var bounds := _tank.bounds()
	for spec: Array in [
		["Coral", bounds.size.x * 0.10],
		["Kelp Court", bounds.size.x * 0.30],
		["Coral", bounds.size.x * 0.72],
		["Kelp Court", bounds.size.x * 0.90],
	]:
		var faction := _faction(String(spec[0]))
		if faction == null:
			continue
		_tank.plant_colony(faction, Vector2(_ground_x(faction, float(spec[1])), 400.0), 30.0)

	# And a shoal in the commons above the middle, so the demo shows the layer that owns
	# open water and the layer it depends on at the same time.
	var shoal := _faction("Deep Blue")
	if shoal != null:
		_tank.plant_colony(shoal, Vector2(bounds.size.x * 0.46, 400.0), 30.0)

	# Frame the whole map. The camera refuses to zoom out past the tank's edges, which
	# is right in the app and wrong here: the territory wash is the subject and it is
	# map-sized, so the rig is told about a tank several times larger than the real one
	# purely to raise that floor.
	var wide := Rect2(bounds.position - bounds.size, bounds.size * 3.0)
	_camera.setup(wide)
	_camera.position = bounds.get_center()
	_camera.zoom = Vector2(0.3, 0.3)
	_next = SETTLE

func _faction(name: String) -> Faction:
	for f in _tank.available_factions:
		if f.display_name == name:
			return f
	return null

## The nearest x to `near` that `faction` may be founded on.
func _ground_x(faction: Faction, near: float) -> float:
	var bounds := _tank.bounds()
	for step in 240:
		for dir: float in [1.0, -1.0]:
			var x := near + dir * float(step) * 14.0
			if x > bounds.position.x + 80.0 and x < bounds.end.x - 80.0 \
					and _tank.can_found(faction, x):
				return x
	return near

## Fast-forwards the colony simulation through the tank's own tick.
func _advance(seconds: float) -> void:
	for i in int(seconds / TICK):
		_tank._tick_colonies(TICK)

## The BENTHIC colony holding the most ground right now.
##
## Benthic on purpose: bleaching the shoal would remove a band of open water and prove
## nothing about the floor, and the floor is where the contest is.
func _biggest() -> Colony:
	var best: Colony = null
	for colony in _tank.colonies():
		if not colony.is_benthic():
			continue
		if best == null or colony.biomass > best.biomass:
			best = colony
	return best

func _report(label: String) -> void:
	var territory := _tank.territory()
	var parts: Array[String] = []
	for faction in _tank.available_factions:
		parts.append("%s %.1f%%" % [faction.display_name, territory.faction_share(faction) * 100.0])
	var adrift := 0
	for colony in _tank.colonies():
		if not colony.is_benthic() and not colony.supported:
			adrift += 1
	if adrift > 0:
		parts.append("%d shoals adrift" % adrift)
	print("%s: %s, open water %.1f%%"
		% [label, ", ".join(parts), territory.open_water() * 100.0])
	# Per-faction detail, because a share alone cannot say WHY a faction is losing:
	# stalled growth (low pressure) and being out-competed for ground look identical
	# in a percentage.
	for faction in _tank.available_factions:
		var n := 0
		var mass := 0.0
		var press := 0.0
		for colony in _tank.colonies():
			if colony.faction != faction:
				continue
			n += 1
			mass += colony.biomass
			press += colony.pressure
		if n == 0:
			print("    %-11s wiped out" % faction.display_name)
			continue
		print("    %-11s %d colonies, mean biomass %.0f/%.0f, mean pressure %.2f"
			% [faction.display_name, n, mass / n, faction.capacity, press / n])

func _shoot(name: String) -> void:
	var path := "%s/%s.png" % [_out_dir.trim_suffix("/"), name]
	root.get_texture().get_image().save_png(path)
	print("SHOT:" + ProjectSettings.globalize_path(path))
