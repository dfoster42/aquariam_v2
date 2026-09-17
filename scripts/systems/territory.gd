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

## World units per cell. 36 gives 90x60 over the shipped 3240x2160 map — 5400 cells,
## cheap enough to redo several times a second and fine enough that a border reads as a
## curve once the texture is filtered.
const CELL: float = 36.0
## How many of its own radii a colony's claim can extend. The inverse-square falloff
## would otherwise have every colony testing every cell on the map for a contribution
## far below anything that could win.
const REACH: float = 2.4
## Influence below this is unclaimed water. Absolute rather than relative, so open
## ocean stays open instead of being carved up by whoever is least far away.
const MIN_CLAIM: float = 3.0
## Alpha the wash reaches at full confidence. Territory is a stain in the water, not a
## coat of paint: the tank underneath has to stay the thing you are looking at.
const MAX_ALPHA: float = 0.5
## Influence at which the wash reaches MAX_ALPHA. Above a young colony's centre value,
## so a colony's heart deepens in colour as it grows rather than starting at full.
const FULL_INFLUENCE: float = 40.0

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
	for cy in _rows:
		for cx in _cols:
			var centre := _bounds.position + Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)
			if _seabed == null or not _seabed.is_rock(centre):
				_water[cy * _cols + cx] = true
				_water_cells += 1
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
				_reached[colony] = int(_reached[colony]) + 1
				var influence := colony.influence_at(offset)
				if influence < MIN_CLAIM:
					continue
				if influence > float(best.get(key, 0.0)):
					best[key] = influence
					_owner[key] = colony

	for key: int in _owner:
		var colony: Colony = _owner[key]
		_owned[colony] = int(_owned.get(colony, 0)) + 1
		var tint := colony.faction.color if colony.faction != null else Color.WHITE
		# Remapped from MIN_CLAIM rather than from zero, so alpha reaches zero exactly
		# where the claim does. Measured against FULL_INFLUENCE alone, the faintest
		# claimed cell still drew at 0.14 alpha against unclaimed water's 0.0, and the
		# whole outer border came out as a hard stair-step that no amount of texture
		# filtering could soften — it was a cliff, not an aliased slope.
		var span := maxf(FULL_INFLUENCE - MIN_CLAIM, 0.001)
		var strength := clampf((float(best[key]) - MIN_CLAIM) / span, 0.0, 1.0)
		# sqrt, not linear: most of a linear fade happens in the last cell, which puts
		# the whole transition inside one 36-unit square. This spreads it over several.
		tint.a = MAX_ALPHA * sqrt(strength)
		_image.set_pixel(key % _cols, key / _cols, tint)

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
