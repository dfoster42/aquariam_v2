extends SceneTree
## Pins the GDScript floor curve to the Python that draws the backdrop.
##
## The two implementations have no shared source of truth — one is in
## tools/art/draw_background.py and paints a JPEG, the other is in scripts/systems/seabed.gd
## and decides where colonies sit. If they drift, nothing errors: objects simply stand a
## little above or below a floor that is only a picture, which is the exact class of bug
## the whole port exists to remove. So the expected values below were dumped FROM the
## Python at the shipped 3240x2160 with seed 7, and this test is the thing that notices.
##
## Regenerate with:
##   python3 -c "import sys; sys.path.insert(0,'tools/art')
##   from draw_background import floor_height
##   print([round(floor_height(x,3240,2160,7),4) for x in (0,680,1440,1847,2160,2754,3239)])"
##
## Run: godot --headless --script res://test/seabed_test.gd

## Tolerance in world units. The LUT samples every 1.0 unit and does not interpolate, and
## the curve's steepest gradient is well under a unit of y per unit of x, so agreement is
## expected to be far tighter than this.
const TOLERANCE: float = 1.0

## x -> floor y, straight out of the Python.
const EXPECTED: Dictionary = {
	0: 1871.2212,
	180: 1783.3641,
	360: 1740.4898,
	540: 1832.5213,
	680: 1803.2210,
	900: 1664.7683,
	1080: 1734.1669,
	1260: 1689.2268,
	1440: 1476.3981,
	1620: 1428.1485,
	1847: 1528.8157,
	2000: 1410.4984,
	2160: 1426.2859,
	2340: 1648.5249,
	2520: 1714.6741,
	2754: 1704.4633,
	2880: 1732.6362,
	3060: 1712.1347,
	3239: 1679.6748,
}

## The extremes of the shipped curve, also from the Python.
const EXPECTED_HIGHEST: float = 1380.5869
const EXPECTED_LOWEST: float = 1871.2298

var _failures: Array[String] = []

func _initialize() -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(3240, 2160))
	var seabed := Seabed.new(bounds, 7.0)

	for x: int in EXPECTED:
		var want := float(EXPECTED[x])
		var got := seabed.height_at(float(x))
		_check(absf(got - want) <= TOLERANCE,
			"floor at x=%d: expected %.4f, got %.4f" % [x, want, got])

	# The uncached path is what builds the table, so it is checked separately — a LUT
	# that is wrong in the same way as its source would agree with itself perfectly.
	for x: int in EXPECTED:
		var want := float(EXPECTED[x])
		var got := seabed.height_uncached(float(x))
		_check(absf(got - want) <= 0.001,
			"uncached floor at x=%d: expected %.4f, got %.4f" % [x, want, got])

	_check(absf(seabed.highest() - EXPECTED_HIGHEST) <= TOLERANCE,
		"highest crest: expected %.4f, got %.4f" % [EXPECTED_HIGHEST, seabed.highest()])
	_check(absf(seabed.lowest() - EXPECTED_LOWEST) <= TOLERANCE,
		"lowest trough: expected %.4f, got %.4f" % [EXPECTED_LOWEST, seabed.lowest()])

	# The three ravines are live in the shipped art despite the comment saying otherwise,
	# so the port must carry them. Each centre must sit measurably below the landform it
	# was cut into.
	for ravine: Array in Seabed.RAVINES:
		var x := float(ravine[0]) * 3240.0
		var carved := seabed.height_uncached(x)
		var uncarved := 2160.0 * (Seabed.FLOOR_HIGH + (Seabed.FLOOR_LOW - Seabed.FLOOR_HIGH)
			* Seabed.terrain_level(x, 3240.0, 7.0))
		_check(carved > uncarved + 20.0,
			"ravine at x=%.0f is not cut: carved %.1f vs uncarved %.1f" % [x, carved, uncarved])

	# Rock is rock, water is water.
	_check(seabed.is_rock(Vector2(1620, 2100)), "a point near the bottom is not rock")
	_check(not seabed.is_rock(Vector2(1620, 200)), "a point near the surface is rock")
	_check(not seabed.is_rock(seabed.lift_out_of_rock(Vector2(1620, 2100), 8.0)),
		"lift_out_of_rock left the point in the ground")
	# A point already in water must not be moved.
	var already := Vector2(1620, 300)
	_check(seabed.lift_out_of_rock(already) == already,
		"lift_out_of_rock moved a point that was already in open water")

	for i in 400:
		var point := seabed.random_water_point(12.0)
		if seabed.is_rock(point):
			_failures.append("random_water_point returned a point inside rock: %s" % point)
			break

	# The honest denominator. Rock runs from the floor to the bottom of the map, so water
	# is a clear majority but nothing like the whole rectangle.
	var water := seabed.water_fraction()
	_check(water > 0.70 and water < 0.82,
		"water fraction %.4f is outside the range the shipped curve implies" % water)
	print("  water is %.1f%% of the tank rectangle; floor spans y %.1f..%.1f"
		% [water * 100.0, seabed.highest(), seabed.lowest()])

	# Bounds-relative, not constant-bound: a half-size tank must put its floor at the
	# same FRACTION, or the day tank_size changes the floor silently stops matching.
	var half := Seabed.new(Rect2(Vector2.ZERO, Vector2(1620, 1080)), 7.0)
	_check(absf(half.height_at(340.0) / 1080.0 - seabed.height_at(680.0) / 2160.0) <= 0.002,
		"the curve is not scale-invariant in x")

	if _failures.is_empty():
		print("RESULT: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("RESULT: FAIL")
	quit(0 if _failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
