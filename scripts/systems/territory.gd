class_name Territory
extends RefCounted
## Who owns which part of the map, as a coarse grid, and a texture to draw it with.
##
## This is the piece that makes the rest legible. Colonies growing and dying is a
## simulation; a map whose colours visibly advance and retreat is something worth
## watching, and the difference between the two is entirely this class. Without a
## territory layer a strike kills an object. With one, a strike opens a hole that the
## neighbours flow into, and the flowing-in is the part worth showing anyone.
##
## The grid is deliberately coarse and the texture is drawn with linear filtering, so
## 90x60 cells come out as soft regions rather than as a chequerboard. Recomputed a few
## times a second rather than per frame: territory moves at the speed colonies grow,
## which is nothing like 60 Hz.

## World units per cell. 24 gives 135x90 over the shipped 3240x2160 map — 12,150 cells,
## still trivial several times a second, and fine enough that a border reads as a curve
## rather than as a staircase. At 36 the steps were plainly visible at the zoom a player
## actually holds, and the seabed crust showed them worst because it traces a slope.
const CELL: float = 24.0
## How many of its own radii a colony's claim can extend. The inverse-square falloff
## would otherwise have every colony testing every cell on the map for a contribution
## far below anything that could win.
const REACH: float = 2.4
## Influence below this is unclaimed water. Absolute rather than relative, so open
## ocean stays open instead of being carved up by whoever is least far away.
const MIN_CLAIM: float = 3.0
## Alpha the wash reaches at the heart of a mature claim.
##
## Territory is a stain in the water, not a coat of paint. At 0.5 it was a coat of paint:
## the washes became the most visually dominant thing on screen and the least interesting,
## flat opaque fields that buried the fish, the colonies and the terrain underneath them.
## The tank has to stay the thing you are looking at.
const MAX_ALPHA: float = 0.34
## Alpha of the crust: the row of cells a benthic faction's held seabed runs through.
##
## Higher than the wash on purpose. The seabed is the contested real estate — 3240 units
## long, finite, and zero-sum, where the water above it is a commons — so the ground a
## faction holds should be the most saturated thing on screen, and a border between two
## factions should read as a seam on the floor rather than as two clouds meeting.
const CRUST_ALPHA: float = 0.6
## How many cell rows above the floor the crust covers. Two at the finer cell size, so
## the rind stays the same thickness in world units as it was at 36.
const CRUST_ROWS: int = 2
## Influence at which a claim counts as fully established. Above a young colony's centre
## value, so a colony's heart deepens in colour as it grows rather than starting at full.
##
## This is no longer the alpha divisor. Dividing by an absolute constant meant a mature
## colony — biomass 130 against a constant of 40 — was above the ceiling across almost
## its whole claim, so the wash had no internal gradient at all and drew as a flat slab
## with a fringe. Alpha is now taken RELATIVE to each colony's own peak, which gives
## every claim a centre and an edge, and this constant only decides how dark a claim gets
## to be overall.
const FULL_INFLUENCE: float = 40.0
## How dim the faintest new colony's heart is, against a fully established one's.
const YOUNG_DIMMING: float = 0.55

var _cols: int = 0
var _rows: int = 0
var _bounds: Rect2 = Rect2()
var _seabed: Seabed
## Cell index -> owning colony. Absent means unclaimed.
var _owner: Dictionary = {}
## Colony -> cells owned.
var _owned: Dictionary = {}
## Colony -> cells within its reach, owned or not.
var _reached: Dictionary = {}
## Colony -> { neighbouring colony -> true }, built from cells that actually touch.
var _adjacent: Dictionary = {}
## Cell index -> true when the cell is open water. Ground is never claimable.
var _water: Dictionary = {}
var _water_cells: int = 0
## Column -> the lowest water row in it, i.e. the row the seabed runs through.
var _floor_row: PackedInt32Array = PackedInt32Array()
var _image: Image
var _texture: ImageTexture

func _init(bounds: Rect2, seabed: Seabed = null) -> void:
	_bounds = bounds
	_seabed = seabed
	_cols = maxi(1, ceili(bounds.size.x / CELL))
	_rows = maxi(1, ceili(bounds.size.y / CELL))
	_image = Image.create(_cols, _rows, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, 0))
	_texture = ImageTexture.create_from_image(_image)
	_mask_water()

## Marks which cells are open water, once. The floor never moves.
##
## Without this, a third of the grid was stone that could be claimed and painted, and
## every share was a fraction of a rectangle rather than of the sea: measured on the
## shipped curve, water is 76.6% of the tank, so a faction holding every drop of it could
## never report above 0.766 and `open_water()` counted bedrock as open.
func _mask_water() -> void:
	_water.clear()
	_water_cells = 0
	_floor_row.resize(_cols)
	for cx in _cols:
		_floor_row[cx] = _rows - 1
	for cy in _rows:
		for cx in _cols:
			var centre := _bounds.position + Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)
			if _seabed == null or not _seabed.is_rock(centre):
				_water[cy * _cols + cx] = true
				_water_cells += 1
				_floor_row[cx] = cy
	if _water_cells == 0:
		_water_cells = _cols * _rows

## Recomputes ownership from `colonies` and repaints the texture.
##
## Cost is the colonies' reach, not the map: each colony visits only the cells it could
## plausibly claim, so an empty map costs nothing and a crowded one costs what it looks
## like it should.
func rebuild(colonies: Array) -> void:
	_owner.clear()
	_owned.clear()
	_reached.clear()
	_adjacent.clear()
	_image.fill(Color(0, 0, 0, 0))

	var best: Dictionary = {}
	for colony: Colony in colonies:
		if colony == null or colony.is_dead():
			continue
		_owned[colony] = 0
		_reached[colony] = 0
		_adjacent[colony] = {}
		# The reach box is per-axis now, so a crust visits a wide flat strip and a plume
		# a tall narrow one. Either visits FEWER cells than the square that bounded the
		# old disc, so anisotropy made the rebuild cheaper rather than dearer.
		var reach := colony.extent() * REACH
		var local := colony.global_position - _bounds.position
		var min_x := maxi(0, floori((local.x - reach.x) / CELL))
		var max_x := mini(_cols - 1, floori((local.x + reach.x) / CELL))
		var min_y := maxi(0, floori((local.y - reach.y) / CELL))
		var max_y := mini(_rows - 1, floori((local.y + reach.y) / CELL))

		for cy in range(min_y, max_y + 1):
			for cx in range(min_x, max_x + 1):
				var key := cy * _cols + cx
				if not _water.has(key):
					continue
				var centre := Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)
				var offset := centre - local
				var influence := colony.influence_at(offset)
				if influence < MIN_CLAIM:
					continue
				# Counted only where the colony could actually claim, not everywhere its
				# search box reaches. "Reached" has to mean "what I would own if nobody
				# opposed me", or pressure punishes a claim for the shape of the box
				# around it: a pelagic band is thin inside a box 2.4 extents tall, so it
				# scored a structurally tiny pressure, its growth ceiling collapsed to
				# the MIN_PRESSURE floor, and a shoal shrank to a fifth of its size no
				# matter how much open water it held.
				_reached[colony] = int(_reached[colony]) + 1
				if influence > float(best.get(key, 0.0)):
					best[key] = influence
					_owner[key] = colony

	# Each colony's own strongest influence, so the wash can be drawn relative to it.
	var peak: Dictionary = {}
	for key: int in _owner:
		var owner: Colony = _owner[key]
		peak[owner] = maxf(float(peak.get(owner, 0.0)), float(best[key]))

	for key: int in _owner:
		var colony: Colony = _owner[key]
		_owned[colony] = int(_owned.get(colony, 0)) + 1
		var tint := colony.faction.color if colony.faction != null else Color.WHITE

		# Remapped from MIN_CLAIM rather than from zero, so alpha reaches zero exactly
		# where the claim does. Measured against an absolute ceiling, the faintest claimed
		# cell still drew at 0.14 alpha against unclaimed water's 0.0, and the whole outer
		# border came out as a cliff no amount of filtering could soften.
		#
		# And relative to THIS COLONY's peak rather than to a constant, so every claim has
		# a centre and an edge. Against a constant, a mature colony — biomass 130 against
		# a ceiling of 40 — sat above that ceiling across almost its entire claim and drew
		# as a flat opaque slab with a thin fringe. Flat slabs were the single worst thing
		# about how this looked: the most dominant element on screen and the least
		# interesting one, burying the fish and the terrain underneath.
		var top := maxf(float(peak.get(colony, MIN_CLAIM)), MIN_CLAIM + 0.001)
		var strength := clampf((float(best[key]) - MIN_CLAIM) / (top - MIN_CLAIM), 0.0, 1.0)
		# How dark a claim is allowed to get at all stays absolute, so a seedling does not
		# paint as boldly as an established reef.
		var standing := lerpf(YOUNG_DIMMING, 1.0, clampf(top / FULL_INFLUENCE, 0.0, 1.0))
		# sqrt, not linear: most of a linear fade happens in the last cell, which puts the
		# whole transition inside one cell. This spreads it over several.
		tint.a = MAX_ALPHA * standing * sqrt(strength)

		# The held seabed is drawn as a bright rind rather than as more wash. It is the
		# only zero-sum ground in the game and it is where every border between two
		# benthic factions actually is, so it should be the most saturated thing on the
		# screen and legible in a thumbnail.
		var cx := key % _cols
		var cy := key / _cols
		if colony.is_benthic() and cx < _floor_row.size() \
				and cy >= _floor_row[cx] - CRUST_ROWS:
			tint.a = maxf(tint.a, CRUST_ALPHA * standing * sqrt(maxf(strength, 0.25)))
		_image.set_pixel(cx, cy, tint)

	_build_adjacency()
	_texture.update(_image)

## Records which colonies actually share a border, from the cells themselves.
##
## Replaces a contact test that compared the sum of two radii against their separation.
## That test could only ever describe circles, and it judged contact by geometry the
## player cannot see — two colonies whose discs overlapped were "touching" even with a
## third colony's territory wedged between them. A shared cell edge is the border that is
## actually painted on screen, so a disaster now travels the line the player can see.
func _build_adjacency() -> void:
	for key: int in _owner:
		var colony: Colony = _owner[key]
		var cx := key % _cols
		# Right and down only: every pair is visited once and recorded both ways.
		if cx < _cols - 1:
			_note_adjacent(colony, _owner.get(key + 1, null))
		if key + _cols < _cols * _rows:
			_note_adjacent(colony, _owner.get(key + _cols, null))

func _note_adjacent(a: Colony, b: Colony) -> void:
	if b == null or a == b:
		return
	(_adjacent[a] as Dictionary)[b] = true
	(_adjacent[b] as Dictionary)[a] = true

## The colonies whose territory touches `colony`'s.
func neighbours(colony: Colony) -> Array[Colony]:
	var found: Array[Colony] = []
	for other: Colony in _adjacent.get(colony, {}):
		found.append(other)
	return found

## Fraction of the ground it reaches for that `colony` actually holds, 0..1.
##
## This is what Aquarium feeds back as the colony's growth pressure. A colony alone on
## the map owns nearly everything within its falloff and runs free; one pressed on all
## sides owns a sliver and stalls.
func pressure_for(colony: Colony) -> float:
	var reached := int(_reached.get(colony, 0))
	if reached <= 0:
		return 1.0
	return clampf(float(int(_owned.get(colony, 0))) / float(reached), 0.0, 1.0)

## Fraction of the SEA this colony holds, 0..1. What a readout would show.
##
## Divided by water cells, not by every cell in the grid — see `_mask_water`.
func share_of_map(colony: Colony) -> float:
	return float(int(_owned.get(colony, 0))) / float(_water_cells)

## Fraction of the whole map a faction holds across all its colonies.
func faction_share(faction: Faction) -> float:
	var cells := 0
	for colony: Colony in _owned:
		if colony.faction == faction:
			cells += int(_owned[colony])
	return float(cells) / float(_water_cells)

## Fraction of the sea nobody holds.
func open_water() -> float:
	return 1.0 - (float(_owner.size()) / float(_water_cells))

## Which colony holds the cell containing `point`, or null for open water.
func owner_at(point: Vector2) -> Colony:
	var local := point - _bounds.position
	var cx := clampi(floori(local.x / CELL), 0, _cols - 1)
	var cy := clampi(floori(local.y / CELL), 0, _rows - 1)
	return _owner.get(cy * _cols + cx, null)

func texture() -> ImageTexture:
	return _texture

func grid_size() -> Vector2i:
	return Vector2i(_cols, _rows)

## How many cells are open water. The denominator of every share above.
func water_cells() -> int:
	return _water_cells
