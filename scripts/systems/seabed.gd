class_name Seabed
extends RefCounted
## Where the ground is. A GDScript transliteration of the curve the backdrop is drawn
## with, so the simulation and the picture agree about the floor.
##
## The backdrop had the only copy of this. `tools/art/draw_background.py` draws a sculpted
## sea floor and nothing in the tank knew it existed, which is why decor floated in
## mid-water, colonies floated in mid-water, and fish swam through 13-36% of the frame
## that is painted as solid rock.
##
## The port is exact rather than approximate, and cheaply so: the Python takes
## `t = x / width`, so the curve is scale-invariant in x, and `_fit_background()` computes
## a cover scale of exactly 1.0 for the shipped 3240x2160 map — backdrop pixel (x, y) IS
## world (x, y). `test/seabed_test.gd` pins the two implementations together at sample
## positions; if the art is ever redrawn with different constants, that test is what says
## so instead of the floor silently sliding out from under everything.
##
## Takes bounds rather than reading constants, because a tank whose `tank_size` stops
## matching the backdrop's aspect would otherwise desync in a way nothing reports.

## Fraction of the map height where the floor's highest crest and lowest trough sit.
## Must match FLOOR_HIGH / FLOOR_LOW in tools/art/draw_background.py.
const FLOOR_HIGH: float = 0.58
const FLOOR_LOW: float = 0.90
## Level is clamped before being mapped to a height, exactly as the Python does — the
## ravines can push the sum past 1.0 and the floor must not fall out of the map.
const LEVEL_CEILING: float = 1.35

## The basins cut into the landform: (centre, half_width, depth), all as fractions.
##
## These are LIVE. draw_background.py carries a comment saying "No ravines for now" —
## it refers only to a deleted dark-fill layer, while `RAVINES` itself has three entries
## and `floor_height` defaults to carved. The shipped backdrop has three real notches in
## it, up to ~130 world units deep, and a port that believed the comment would miss them.
const RAVINES: Array = [
	[0.21, 0.115, 0.20],
	[0.57, 0.100, 0.24],
	[0.85, 0.125, 0.17],
]

## Resolution of the cached height table, in world units. Far finer than Territory's
## 36-unit cell, so sampling error is never what a border is made of.
const LUT_STEP: float = 1.0

var _bounds: Rect2
var _seed: float
var _lut: PackedFloat32Array = PackedFloat32Array()
var _highest: float = 0.0
var _lowest: float = 0.0

func _init(bounds: Rect2, terrain_seed: float = 7.0) -> void:
	_bounds = bounds
	_seed = terrain_seed
	_build_lut()

## The landform at `x`, before anything is carved into it, 0..1.
##
## Analytic rather than sampled from noise, like the Python: a floor built from noise
## wobbles at pixel scale and reads as texture rather than as landscape.
static func terrain_level(x: float, width: float, terrain_seed: float) -> float:
	var t := x / maxf(1.0, width)
	var base := (0.52 * sin(t * TAU * 1.1 + terrain_seed)
		+ 0.30 * sin(t * TAU * 2.7 + terrain_seed * 2.0)
		+ 0.18 * sin(t * TAU * 5.3 + terrain_seed * 3.0))
	return (base + 1.0) * 0.5

## How far the floor is cut away at `x`, in level units.
static func ravine_depth(x: float, width: float) -> float:
	var t := x / maxf(1.0, width)
	var cut := 0.0
	for ravine: Array in RAVINES:
		var d := absf(t - float(ravine[0])) / float(ravine[1])
		if d < 1.0:
			# Smoothstep, not a squared falloff: squared comes to a point at the bottom,
			# which is what made these read as needles rather than as basins.
			cut += float(ravine[2]) * (1.0 - (d * d * (3.0 - 2.0 * d)))
	return cut

## The floor's world y at `x`, computed rather than looked up. The LUT is built from this.
func height_uncached(x: float) -> float:
	var local := x - _bounds.position.x
	var level := terrain_level(local, _bounds.size.x, _seed) + ravine_depth(local, _bounds.size.x)
	level = clampf(level, 0.0, LEVEL_CEILING)
	return _bounds.position.y + _bounds.size.y * (FLOOR_HIGH + (FLOOR_LOW - FLOOR_HIGH) * level)

## The floor's world y at `x`. Clamped at the map edges rather than extrapolated.
func height_at(x: float) -> float:
	if _lut.is_empty():
		return height_uncached(x)
	var i := int((x - _bounds.position.x) / LUT_STEP)
	return _lut[clampi(i, 0, _lut.size() - 1)]

## How deeply the floor at `x` is carved by a ravine, in world units.
##
## Depth alone cannot identify a ravine: the landform's own low point at x=0 sits at
## y 1871, deeper than two of the three notches, so a "deep ground only" rule would hand
## a vent faction the left edge of the map and call it a basin. This is the honest test.
func ravine_at(x: float) -> float:
	var local := x - _bounds.position.x
	return ravine_depth(local, _bounds.size.x) * _bounds.size.y * (FLOOR_LOW - FLOOR_HIGH)

## Whether `point` is inside the ground.
func is_rock(point: Vector2) -> bool:
	return point.y > height_at(point.x)

## `point` moved up out of the ground if it was in it, keeping `margin` of clearance.
##
## Only the floor is enforced here; the caller still owns the tank's rectangle. A fish
## needs both and does them in that order.
func lift_out_of_rock(point: Vector2, margin: float = 0.0) -> Vector2:
	var ceiling := height_at(point.x) - margin
	return Vector2(point.x, minf(point.y, ceiling))

## A random point in open water, never inside the ground.
func random_water_point(margin: float = 0.0) -> Vector2:
	var x := randf_range(_bounds.position.x + margin, _bounds.end.x - margin)
	var top := _bounds.position.y + margin
	var floor_y := height_at(x) - margin
	if floor_y <= top:
		return Vector2(x, top)
	return Vector2(x, randf_range(top, floor_y))

## The shallowest and deepest the floor gets, in world y. The crest is the SMALLER number.
func highest() -> float:
	return _highest

func lowest() -> float:
	return _lowest

## Fraction of the tank's rectangle that is water rather than rock.
##
## Territory's shares were divided by every cell in the grid, ground included, so a
## faction holding every drop of water on the map could never report above ~0.78 and
## "open water" counted stone as open. This is the honest denominator.
func water_fraction() -> float:
	if _bounds.size.y <= 0.0:
		return 1.0
	var total := 0.0
	for y: float in _lut:
		total += clampf((y - _bounds.position.y) / _bounds.size.y, 0.0, 1.0)
	return total / float(maxi(_lut.size(), 1))

func _build_lut() -> void:
	var count := int(_bounds.size.x / LUT_STEP) + 1
	_lut.resize(count)
	_highest = INF
	_lowest = -INF
	for i in count:
		var y := height_uncached(_bounds.position.x + float(i) * LUT_STEP)
		_lut[i] = y
		_highest = minf(_highest, y)
		_lowest = maxf(_lowest, y)
