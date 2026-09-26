class_name Aquarium
extends Node2D
## Owns the tank: population, the per-frame spatial hash, and spawning.
##
## Running one loop here (rather than letting each fish drive itself) means the
## broad-phase grid is rebuilt exactly once per frame no matter how many fish
## are alive.
##
## The tank is a fixed world rather than whatever the viewport happens to be. A
## camera looks at part of it, so fish must not swim to the edge of the screen —
## they swim to the edge of the tank, and the screen moves independently.

signal population_changed(count: int)
signal fish_born(species: FishSpecies)
signal fish_died(species: FishSpecies, of_old_age: bool)
signal species_selected(species: FishSpecies)
signal paused_changed(paused: bool)
signal decor_changed(count: int)
signal food_changed(count: int)
## Fires after a territory pass whose ownership differs from the last one.
signal territory_changed(colonies: int)
signal colony_founded(faction: Faction)
signal colony_lost(faction: Faction)
## A faction earned a trait from its tech tree.
signal faction_evolved(faction: Faction, trait_: FactionTrait)
## A beaten lineage reached down and founded `to` on deeper ground.
signal faction_descended(from: Faction, to: Faction)
## A thriving lineage released `to` into the open water above it.
signal faction_ascended(from: Faction, to: Faction)
## A faction's last colony died.
signal faction_extinct(faction: Faction)
## Fires when the undo button should enable or disable.
signal undo_changed(available: bool)

const FISH_SCENE: PackedScene = preload("res://scenes/fish.tscn")
const DECOR_SCENE: PackedScene = preload("res://scenes/decor.tscn")
const FOOD_SCENE: PackedScene = preload("res://scenes/food.tscn")
const COLONY_SCENE: PackedScene = preload("res://scenes/colony.tscn")
const SHOCKWAVE_SCENE: PackedScene = preload("res://scenes/shockwave.tscn")
## Food is cheap but not free, and a held finger can drop a lot of it.
const MAX_FOOD: int = 250
## Refuse to spawn beyond this; keeps a stray tap-and-hold from hanging the app.
const MAX_POPULATION: int = 1500
## How close a tap in remove mode has to land, in SCREEN units. The caller converts it
## to world units, because a finger is a fixed size on the glass and what sits under it
## is whatever the zoom says: at the widest zoom one screen unit is about eight world
## units, at the tightest about a third of one. A world-space constant would grab a fish
## three body-lengths away when zoomed out and miss the one under the finger zoomed in.
const REMOVE_REACH: float = 48.0
## Colonies a tank may hold. Territory is recomputed against every one of them, and
## past this the map is a mosaic rather than a set of rival reefs.
const MAX_COLONIES: int = 40
## Seconds between territory passes. Territory moves at the speed colonies grow, which
## is nothing like 60 Hz; recomputing it per frame would be the most expensive thing in
## the tank and would look identical.
const TERRITORY_INTERVAL: float = 0.25
## World radius a strike reaches.
const STRIKE_RADIUS: float = 360.0
## How many points across a pelagic colony's width are tested for benthic support.
const SUPPORT_SAMPLES: int = 5
## How far from its parent a daughter is founded, in the parent's extents. Close enough
## to join the parent's ground, far enough not to be founded inside it.
const SPREAD_MIN_GAP: float = 1.2
const SPREAD_MAX_GAP: float = 2.3
## How much deeper the ground has to be before it counts as a descent, in world units.
## Without a floor on it, a colony "descends" onto the gentle dip next door forever.
const DESCENT_DROP: float = 90.0
## How far along the seabed a colony will look for deeper ground.
const DESCENT_SEARCH: float = 1400.0
## Seconds a bleach takes to carry from one colony to the next.
##
## The BFS knew the hop distance and threw it away, applying every colony's damage in the
## same call — so a disaster that is conceptually a thing SPREADING arrived everywhere at
## once and could not be watched spreading. Staggering by hop is what makes the wave
## visible, and it costs one integer.
const BLEACH_HOP_DELAY: float = 0.38
## Biomass a strike takes out at its centre, falling to nothing at its edge. Tuned so a
## single hit kills a young colony outright and badly wounds a mature one — a power
## that only chips at a reef gives the player nothing to watch.
const STRIKE_POWER: float = 90.0
## Fraction of its strength a bleach keeps at each hop. Below about 0.7 it dies out
## before it reaches the far side of a large faction, which is the whole point of it.
const BLEACH_DECAY: float = 0.82
## Bleach strength at the colony it starts on, as a fraction of that colony's biomass.
## Above 1.0 so the first reef always dies outright — a disaster that leaves its origin
## standing does not read as a disaster.
const BLEACH_POWER: float = 1.4

## Every species the tank can spawn. Populated in the inspector — drop a new
## .tres in here and it appears in the picker with no code change. An exported
## array rather than a directory scan, because exported builds rewrite
## res://...tres to .tres.remap and a filename scan would come back empty.
@export var available_species: Array[FishSpecies] = []

## Everything the player can place that is not a fish. Same contract as
## `available_species`: drop a .tres in and it appears in the picker.
@export var available_decor: Array[DecorKind] = []

## The reef factions that can hold ground here. Same contract again: one .tres per
## faction, dropped in, no code.
@export var available_factions: Array[Faction] = []

## The tank's size in world units — a map several screens wide, not one screen. The
## camera shows a portrait slice of it and pans across; see tools/art/draw_background.py
## for the terrain it is drawn against.
@export var tank_size: Vector2 = Vector2(3240, 2160)

## Seconds between automatic saves. 0 disables them.
##
## The tank cannot rely on being told it is closing. On iOS, backgrounding the app
## produced no NOTIFICATION_APPLICATION_PAUSED at this node and no save was written —
## measured on an iPhone 17 Pro simulator, with the platform's own log confirming the
## scene had backgrounded. A mobile OS can also kill a suspended app outright with no
## callback at all, so a lifecycle hook is at best a bonus and autosave is the mechanism.
@export var autosave_interval: float = 15.0

## Multiplied into the backdrop. White now that the backdrop is drawn to sit under
## the fish rather than compete with them — it was a stopgap that dimmed the
## photograph this replaced, and applying it to the drawn backdrop would crush it.
@export var backdrop_tint: Color = Color.WHITE

var selected_species: FishSpecies
## What a tap places. A species, a decor kind, or food — never more than one.
var selected_decor: DecorKind
var feeding: bool = false
## Taps take things out instead of putting them in.
var removing: bool = false
## Which faction a tap founds a colony for. Null unless a faction tile is armed.
var selected_faction: Faction
## Taps call down a strike instead of placing anything.
var striking: bool = false
## Taps bleach the reef under the finger and everything of its faction it touches.
##
## Its own mode, and not a variant of the strike, because the two are different verbs:
## a strike is a hole punched at a point, a bleach is a disaster that travels. The UI
## shipped with only the strike reachable, which meant the thing every measurement and
## every screenshot in the prototype was about — the travelling bleach — could only be
## triggered by the demo and the tests. The player could not do it.
var bleaching: bool = false

var _fish: Array[Fish] = []
var _decor: Array[Decor] = []
var _food: Array[Food] = []
var _shelter_hash: SpatialHash
## Food sinks, so unlike decor its grid is rebuilt every frame.
var _food_hash: SpatialHash
var _predator_map: Dictionary = {}
var _hash: SpatialHash
var _bounds: Rect2 = Rect2()
var _paused: bool = false
var _since_autosave: float = 0.0
var _history := TankHistory.new()
var _undo_available: bool = false
var _colonies: Array[Colony] = []
var _territory: Territory
var _seabed: Seabed
## Each faction's progress through its tech tree in this tank.
var _progress: Dictionary = {}
## Colonies a disaster has wounded, watched until they either die or stop draining.
var _wounded: Dictionary = {}
## Factions with a colony that lived through a disaster since the last progress pass.
var _survived: Dictionary = {}
## Damage that has been decided but has not landed yet: [{colony, amount, at}].
var _pending: Array[Dictionary] = []
var _disaster_clock: float = 0.0
var _since_territory: float = 0.0

@onready var background: Sprite2D = $Background
@onready var fish_layer: Node2D = $FishLayer
@onready var decor_back: Node2D = $DecorBack
@onready var decor_front: Node2D = $DecorFront
@onready var food_layer: Node2D = $FoodLayer
@onready var colony_layer: Node2D = $ColonyLayer
@onready var territory_layer: Sprite2D = $TerritoryLayer

func _ready() -> void:
	available_species = available_species.filter(func(s: FishSpecies) -> bool: return s != null)
	if available_species.is_empty():
		push_error("Aquarium has no species assigned; set available_species in the inspector.")
		return
	available_species.sort_custom(func(a: FishSpecies, b: FishSpecies) -> bool:
		return a.display_name < b.display_name)

	_bounds = Rect2(Vector2.ZERO, tank_size)
	available_decor = available_decor.filter(func(d: DecorKind) -> bool: return d != null)
	_predator_map = _derive_predators(available_species)
	_hash = SpatialHash.new(_largest_sight())
	_shelter_hash = SpatialHash.new(_largest_shelter())
	_food_hash = SpatialHash.new(_largest_sight())
	selected_species = available_species[0]

	available_factions = available_factions.filter(func(f: Faction) -> bool: return f != null)
	_seabed = Seabed.new(_bounds)
	_territory = Territory.new(_bounds, _seabed)
	for f in available_factions:
		_progress[f] = FactionProgress.new(f)

	background.modulate = backdrop_tint
	_fit_background()
	_fit_territory()

	# A new aquarium opens EMPTY and the player fills it. There is no seeding step:
	# restore() simply finds nothing to restore, and the picker's hint line is the
	# instruction. Stocking a new tank with 55 fish made "start a new aquarium" mean
	# "start someone else's aquarium".
	restore(TankStore.read())

## The largest step a fish will take in one frame. After a stall, an unclamped delta
## teleports every fish across the tank in a single tick.
const MAX_STEP: float = 0.1

## Deliberately _process and not _physics_process. The tank has no collision and no
## rigid bodies, so nothing here needs the fixed clock — and running on it was actively
## harmful. Measured with tools/benchmark.gd: past ~500 fish one simulation step
## overran its 16.67 ms budget, so the engine ran extra steps to catch up, which made
## the next step later still, until it pinned at max_physics_steps_per_frame (8) and
## the frame time locked to exactly 8 x 16.67 = 133.33 ms — 7 fps, from 60, over one
## step of the benchmark. On _process a heavy frame is simply a longer frame.
func _process(delta: float) -> void:
	if _paused:
		return
	var step := minf(delta, MAX_STEP)
	_hash.clear()
	for fish in _fish:
		_hash.insert(fish)
	_mark_sheltered()

	_food_hash.clear()
	for pellet in _food:
		pellet.tick(step)
		_food_hash.insert(pellet)

	for fish in _fish:
		fish.tick(step, _hash, _shelter_hash, _food_hash)
	_reap()
	_breed()
	_tick_colonies(step)
	# A fish the player placed and a shark then ate cannot be un-placed, so the button
	# has to go dark when the last thing it could undo disappears on its own.
	_note_undo_state()

	if autosave_interval > 0.0:
		_since_autosave += delta
		if _since_autosave >= autosave_interval:
			_since_autosave = 0.0
			save()


# ------------------------------------------------------------------- colonies

## Grows every colony and refreshes the map a few times a second.
##
## Territory is not recomputed per frame. It moves at the speed colonies grow, so a
## 60 Hz pass would be the most expensive thing in the tank and would look exactly the
## same as a 4 Hz one.
func _tick_colonies(delta: float) -> void:
	_tick_pending(delta)
	if _colonies.is_empty():
		return
	for colony: Colony in _colonies.duplicate():
		colony.tick(delta)

	_since_territory += delta
	if _since_territory < TERRITORY_INTERVAL:
		return
	# The time that actually passed, not the interval. A pass fires once the accumulator
	# OVERSHOOTS the interval, so crediting the interval ran every tech clock slow — by
	# 17% at ten ticks a second: 32 seconds of play counted as 26.5.
	var elapsed := _since_territory
	_since_territory = 0.0
	_rebuild_territory()
	_advance_tech(elapsed)

## Every faction's earned traits, keyed by faction resource path. What a save keeps.
func progress_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for f: Faction in _progress:
		var progress := _progress[f] as FactionProgress
		if not progress.is_empty():
			out[f.resource_path] = progress.to_save()
	return out

## This faction's progress in this tank. Made on demand for a faction the tank was not
## built with, so a colony is never left reading raw stats.
func progress_for(faction: Faction) -> FactionProgress:
	if faction == null:
		return null
	if not _progress.has(faction):
		_progress[faction] = FactionProgress.new(faction)
	return _progress[faction]

## Moves every faction along its tech tree by `elapsed` seconds.
##
## Run on the territory pass, not per frame: every condition is about ground held or
## colonies standing, which only change when the map is recomputed.
func _advance_tech(elapsed: float) -> void:
	_settle_wounded()
	var facts: Dictionary = {}
	for f: Faction in _progress:
		facts[f] = {"share": 0.0, "colonies": 0, "basins": 0,
			"survived_disaster": _survived.has(f)}
	var basins: Dictionary = {}
	for colony in _colonies:
		var f := colony.faction
		if not facts.has(f):
			continue
		facts[f]["colonies"] += 1
		var basin := _seabed.basin_at(colony.global_position.x) if colony.is_benthic() else -1
		if basin >= 0:
			if not basins.has(f):
				basins[f] = {}
			(basins[f] as Dictionary)[basin] = true
	for f: Faction in _progress:
		facts[f]["share"] = _territory.faction_share(f)
		facts[f]["basins"] = (basins.get(f, {}) as Dictionary).size()
		for earned in (_progress[f] as FactionProgress).tick(elapsed, facts[f]):
			faction_evolved.emit(f, earned)
	_survived.clear()

## Notes which wounded colonies have come through. A colony counts as having survived
## once its wound has fully drained and it is still standing.
func _settle_wounded() -> void:
	for colony: Variant in _wounded.keys():
		if not is_instance_valid(colony) or (colony as Colony).is_dead():
			_wounded.erase(colony)
			continue
		if not (colony as Colony).is_dying():
			_survived[(colony as Colony).faction] = true
			_wounded.erase(colony)

## Lands any scheduled damage whose moment has come.
##
## Kept on its own clock rather than on real time, so the fast-forward in
## tools/colony_demo.gd and the tests drive it through exactly the path the app does.
func _tick_pending(delta: float) -> void:
	if _pending.is_empty():
		return
	_disaster_clock += delta
	var still_waiting: Array[Dictionary] = []
	for entry in _pending:
		if float(entry["at"]) > _disaster_clock:
			still_waiting.append(entry)
			continue
		var colony: Colony = entry["colony"]
		if colony == null or not is_instance_valid(colony) or colony.is_dead():
			continue
		if colony.damage(float(entry["amount"])) > 0.0:
			_wounded[colony] = true
		_mark_disaster(colony.global_position, colony.extent().x,
			colony.faction.color if colony.faction != null else Color.WHITE)
	_pending = still_waiting
	if _pending.is_empty():
		_disaster_clock = 0.0

## Draws a ring where a disaster just landed.
func _mark_disaster(where: Vector2, radius: float, tint: Color) -> void:
	if not is_node_ready():
		return
	var ring: Shockwave = SHOCKWAVE_SCENE.instantiate()
	ring.configure(radius, tint)
	ring.global_position = where
	colony_layer.add_child(ring)

## Recomputes ownership and feeds each colony back the share of ground it holds.
##
## The feedback is the whole competition model: a colony that owns the ground it
## reaches for grows to its faction's capacity, and one boxed in by neighbours stalls.
## Nothing else arbitrates between colonies, which means what throttles a reef is
## exactly what the player can see on the map.
func _rebuild_territory() -> void:
	if _territory == null:
		return
	_territory.rebuild(_colonies)
	for colony in _colonies:
		colony.pressure = _territory.pressure_for(colony)
		if not colony.is_benthic():
			colony.supported = _benthic_under(colony)
	territory_layer.texture = _territory.texture()
	_fit_territory()
	territory_changed.emit(_colonies.size())

## Whether ANY benthic claim sits beneath `colony`, anywhere along its width.
##
## This is the rule that makes open water worth having and impossible to hold: a shoal
## owns a band of the commons, but only while somebody's reef is rooted on the floor
## below it. Deliberately not its OWN reef — requiring that made the condition almost
## unreachable and, worse, made the interesting case impossible: a shoal living over a
## rival's reef is a dependency the player can attack sideways. Strike the reef and the
## shoal above it starves, several seconds later and in a different part of the frame,
## without ever being targeted.
##
## Sampled across the band rather than at its centre, so a shoal half over a reef still
## counts — losing support should take clearing the floor, not clipping one end of it.
func _benthic_under(colony: Colony) -> bool:
	if _territory == null or _seabed == null:
		return true
	var half := colony.extent().x
	for i in SUPPORT_SAMPLES:
		var t := 0.0 if SUPPORT_SAMPLES <= 1 else float(i) / float(SUPPORT_SAMPLES - 1)
		var x := colony.global_position.x + lerpf(-half, half, t)
		if x < _bounds.position.x or x > _bounds.end.x:
			continue
		# Just above the ground, where a benthic column is always at full strength.
		var holder := _territory.owner_at(
			Vector2(x, _seabed.height_at(x) - _territory.cell_size()))
		if holder != null and holder.is_benthic():
			return true
	return false

## Stretches the coarse ownership grid over the whole map. Linear filtering on the
## sprite is what turns 135x90 cells into soft regions instead of a chequerboard.
func _fit_territory() -> void:
	if _territory == null or territory_layer == null:
		return
	var grid := _territory.grid_size()
	if grid.x <= 0 or grid.y <= 0:
		return
	territory_layer.position = _bounds.position
	territory_layer.scale = Vector2(
		_bounds.size.x / float(grid.x), _bounds.size.y / float(grid.y))

## Founds a colony for `faction` at `position`. Returns null when the tank is full or
## the faction is missing.
func plant_colony(faction: Faction, position: Vector2, start_biomass: float = -1.0) -> Colony:
	if not is_node_ready() or faction == null or _colonies.size() >= MAX_COLONIES:
		return null
	var where := _bounds.get_center() if not _bounds.has_point(position) else position
	var ground := _seabed.height_at(where.x)
	if not can_found(faction, where.x):
		return null

	var colony: Colony = COLONY_SCENE.instantiate()
	colony.configure(faction, start_biomass, ground)
	colony.progress = progress_for(faction)
	# A reef grows on the ground: a tap anywhere in a column founds one on the seabed
	# below the finger rather than leaving it hanging in open water, which is what made
	# the colonies read as anemones floating in mid-air. A shoal instead sits in its own
	# band, wherever the tap was in x.
	if colony.is_benthic():
		colony.global_position = Vector2(where.x, ground)
	else:
		colony.global_position = Vector2(where.x,
			_bounds.position.y + _bounds.size.y * faction.altitude)
	colony.released.connect(_on_colony_released)
	colony.spreading.connect(_on_colony_spreading)
	colony.descending.connect(_on_colony_descending)
	colony.ascending.connect(_on_colony_ascending)
	colony.died.connect(_on_colony_died)
	colony_layer.add_child(colony)
	_colonies.append(colony)
	_rebuild_territory()
	colony_founded.emit(faction)
	return colony

## Whether `faction` may be founded on the ground at `x`.
##
## Benthic factions declare the stretch of floor they can live on as a fraction of map
## height, which is what turns the terrain into the board: a deep faction can only take
## the three ravines already drawn into the backdrop — about 6% of the map's floor length
## and the deepest start in the game — while a shelf faction cannot go down there at all.
func can_found(faction: Faction, x: float) -> bool:
	if faction == null or _seabed == null:
		return false
	if faction.claim != Faction.Claim.BENTHIC:
		return true
	if _bounds.size.y <= 0.0:
		return true
	# The basins belong to whoever belongs in them, both ways round: a vent faction is
	# refused the open floor and a shelf faction is refused a basin. One threshold and
	# one flag, so the two can never disagree about where the boundary is.
	var in_basin := _seabed.ravine_at(x) >= Territory.BASIN_CARVING
	if in_basin != faction.likes_ravines:
		return false
	var depth := (_seabed.height_at(x) - _bounds.position.y) / _bounds.size.y
	return depth >= faction.floor_depth_range.x and depth <= faction.floor_depth_range.y

## Calls down a strike centred on `position`.
##
## Damage falls off linearly to nothing at the edge, so where the player taps is a
## decision rather than a formality. Returns total biomass destroyed — what a readout
## would report, and what the test measures.
func strike(position: Vector2, radius: float = STRIKE_RADIUS,
		power: float = STRIKE_POWER) -> float:
	var destroyed := 0.0
	for colony: Colony in _colonies.duplicate():
		var distance := colony.global_position.distance_to(position)
		if distance > radius:
			continue
		var dealt := colony.damage(power * (1.0 - distance / radius))
		if dealt > 0.0:
			_wounded[colony] = true
		destroyed += dealt
	# Marked whether or not it connected: a tap on open water that shows nothing is a
	# tap the player cannot tell from a tap the game missed.
	_mark_disaster(position, radius * 0.6, Color(1.0, 0.95, 0.85))
	if destroyed > 0.0:
		_rebuild_territory()
	return destroyed

## Bleaches the reef under `position` and everything of the same faction it touches.
##
## A point strike turned out to be a pinprick once factions spread: measured, hitting
## one colony of a faction holding a third of the map moved that share by 0.8 points,
## because the faction had a dozen other colonies and none of them cared. A disaster has
## to travel the same way the thing it is destroying travelled.
##
## Spreads only within one faction. A bleaching that crossed between rivals would erase
## the borders that make the map worth looking at, and the point of the power is to open
## ground for a rival, not to flatten everyone equally.
##
## Returns the biomass destroyed.
func bleach(position: Vector2, radius: float = STRIKE_RADIUS) -> float:
	var origin := _nearest_colony(position, radius)
	if origin == null:
		# Marked even when it finds nothing, as a strike is: a tap that shows nothing
		# cannot be told from a tap the game missed.
		_mark_disaster(position, radius * 0.4, Color(0.92, 0.94, 0.9))
		return 0.0

	var faction := origin.faction
	var frontier: Array[Colony] = [origin]
	var strength: Dictionary = {origin: origin.biomass * BLEACH_POWER}
	var hop: Dictionary = {origin: 0}
	var seen: Dictionary = {origin: true}
	var destroyed := 0.0

	# Breadth-first across touching colonies of the same faction, losing strength at
	# each hop, so a bleach burns out somewhere inside a large faction rather than
	# always taking all of it.
	while not frontier.is_empty():
		var current: Colony = frontier.pop_front()
		var power := float(strength[current])
		# Neighbours by shared territory border, not by overlapping radii. The radius
		# test could only describe circles and judged contact by geometry nobody can
		# see; a shared cell edge is the border actually painted on screen.
		for other in _territory.neighbours(current):
			if seen.has(other) or other.faction != faction:
				continue
			seen[other] = true
			var carried := power * BLEACH_DECAY
			if carried < Colony.MIN_BIOMASS:
				continue
			strength[other] = carried
			hop[other] = int(hop[current]) + 1
			frontier.append(other)

	# Scheduled by hop rather than applied at once, so the disaster is watched crossing
	# the map instead of having already crossed it.
	for colony: Colony in strength:
		var amount := minf(float(strength[colony]), colony.biomass)
		if amount <= 0.0:
			continue
		destroyed += amount
		_pending.append({
			"colony": colony,
			"amount": float(strength[colony]),
			"at": _disaster_clock + float(hop[colony]) * BLEACH_HOP_DELAY,
		})
	return destroyed

func _nearest_colony(position: Vector2, radius: float) -> Colony:
	var best: Colony = null
	var best_distance := radius
	for colony in _colonies:
		var distance := colony.global_position.distance_to(position)
		if distance <= best_distance:
			best_distance = distance
			best = colony
	return best

## A colony released a fish. It arrives at the colony's edge rather than its centre, so
## a reef visibly seeds the water around it instead of budding fish out of its middle.
func _on_colony_released(colony: Colony, position: Vector2) -> void:
	if colony.faction == null or colony.faction.species == null:
		return
	var offset := Vector2.from_angle(randf_range(-PI, PI)) * colony.radius() * 0.8
	var fish := spawn(colony.faction.species, position + offset, 0.0)
	if fish != null:
		fish.set_faction(colony.faction)

## A colony wants to found a daughter. The tank arbitrates, because only it knows who
## owns the target ground.
##
## Refused onto ground another faction already holds: expansion should have to go around
## a rival or through it, never simply land behind it. Refused inside the tank's own
## edge margin too, or reefs pile up against the glass where half their territory falls
## off the map.
func _on_colony_spreading(parent: Colony, position: Vector2) -> void:
	if _colonies.size() >= MAX_COLONIES or _territory == null:
		return
	var x := _spread_ground(parent, signf(position.x - parent.global_position.x))
	if x < 0.0:
		return
	var stake := parent.pay_to_spread()
	if stake <= 0.0:
		return
	if plant_colony(parent.faction, Vector2(x, 0.0), stake) == null:
		# Nothing was founded, so nothing should have been spent.
		parent.biomass += stake

## Where a daughter of `parent` can go: the nearest legal ground between SPREAD_MIN_GAP and
## SPREAD_MAX_GAP of its extents away, on the side it asked for first and then the other.
## Negative when there is nowhere.
##
## Searched rather than bet on. A daughter used to be aimed at one point, SPREAD_MAX_GAP
## extents out, in one random direction — and a wide faction's extent is wide: a coral
## able to spread aimed ~1,500 units away on a 3,240-unit map. Nearly every attempt landed
## out of bounds, in a basin, or on a rival's ground, and was refused. Measured over one
## seven-minute run: coral 0 of 31 attempts, kelp 0 of 24, the pelagic shoal 0 of 58.
## Only the narrow vent could spread at all.
func _spread_ground(parent: Colony, preferred: float) -> float:
	var reach := parent.extent().x
	var side := preferred if preferred != 0.0 else (1.0 if randf() < 0.5 else -1.0)
	var steps := int((SPREAD_MAX_GAP - SPREAD_MIN_GAP) / 0.1) + 1
	for direction: float in [side, -side]:
		for i in steps:
			var x := parent.global_position.x \
				+ direction * reach * (SPREAD_MIN_GAP + 0.1 * float(i))
			if x < _bounds.position.x + Colony.BASE_RADIUS \
					or x > _bounds.end.x - Colony.BASE_RADIUS:
				break
			# Checked before charging: plant_colony refuses ground the faction cannot
			# occupy, and a parent that had already paid lost the biomass for nothing.
			if not can_found(parent.faction, x):
				continue
			# Only onto water NOBODY holds — a rival's or its own. Spreading is claiming new
			# ground. Allowed onto its own, a daughter was founded inside its faction's
			# territory and the two split it: measured, colonies sat at 18-28% of capacity
			# and the map filled to the colony cap, one shoal alone reaching twenty-two.
			# Pelagic daughters were not checked at all, which is how it got there.
			#
			# Sampled a cell above the floor for a reef — the cell holding the floor is
			# masked as rock, so asking about the floor itself always answered "nobody" —
			# and at the band's own depth for a shoal.
			var probe_y := _seabed.height_at(x) - _territory.cell_size()
			if not parent.is_benthic():
				probe_y = _bounds.position.y + _bounds.size.y * parent.faction.altitude
			if _territory.owner_at(Vector2(x, probe_y)) != null:
				continue
			return x
	return -1.0

## A colony is losing and wants to found its successor on deeper ground.
##
## The tank decides where, because only it knows the terrain and who holds what. The
## nearest legal ground wins rather than the deepest: a lineage should read as working
## its way DOWN the slope in steps, not teleporting to the bottom of the map the first
## time it is squeezed.
func _on_colony_descending(parent: Colony, successor: Faction) -> void:
	if successor == null or _colonies.size() >= MAX_COLONIES or _seabed == null:
		return
	var target := _deeper_ground(parent, successor)
	if target < 0.0:
		return
	var stake := parent.pay_to_descend()
	if stake <= 0.0:
		return
	var colony := plant_colony(successor, Vector2(target, 0.0), stake)
	if colony == null:
		parent.biomass += stake
		return
	# Marked, because a faction appearing out of nowhere on the far side of the map is
	# otherwise the one thing in the simulation that happens with no visible cause.
	# `colony_founded` is not emitted here: plant_colony already owns that signal.
	_mark_disaster(colony.global_position, colony.extent().x * 0.7, successor.color)
	faction_descended.emit(parent.faction, successor)

## A thriving colony releases its successor into the open water above it.
##
## Refused where the successor already holds that stretch of water: a kelp forest that
## has learned to float should seed new rafts, not stack a second one on the first every
## twenty seconds.
func _on_colony_ascending(parent: Colony, successor: Faction) -> void:
	if successor == null or _colonies.size() >= MAX_COLONIES:
		return
	var x := parent.global_position.x
	# Refused anywhere inside an existing raft's claim — out to REACH of its extents, the
	# distance Territory actually evaluates it over. Checking one extent missed claims
	# reaching between 1 and REACH extents, so a second raft could be founded inside the
	# first. Measured against the footprint rather than against who currently owns the
	# cell: above a thriving kelp the kelp's own column usually wins that water, which
	# would have waved a second raft through on top of the first.
	for other in _colonies:
		if other.faction == successor \
				and absf(other.global_position.x - x) < other.extent().x * Territory.REACH:
			return
	var stake := parent.pay_to_ascend()
	if stake <= 0.0:
		return
	var colony := plant_colony(successor, Vector2(x, 0.0), stake)
	if colony == null:
		parent.biomass += stake
		return
	_mark_disaster(colony.global_position, colony.extent().x * 0.5, successor.color)
	faction_ascended.emit(parent.faction, successor)

## The nearest x that `successor` may be founded on and that is meaningfully deeper than
## `parent` stands. Negative when there is nowhere to go.
func _deeper_ground(parent: Colony, successor: Faction) -> float:
	var from := parent.global_position.x
	var floor_here := _seabed.height_at(from)
	var step := 20.0
	var steps := int(DESCENT_SEARCH / step)
	for i in range(1, steps + 1):
		for dir: float in [1.0, -1.0]:
			var x := from + dir * float(i) * step
			if x < _bounds.position.x + Colony.BASE_RADIUS \
					or x > _bounds.end.x - Colony.BASE_RADIUS:
				continue
			if _seabed.height_at(x) < floor_here + DESCENT_DROP:
				continue
			if not can_found(successor, x):
				continue
			# Never onto ground a rival already holds. A lineage has to reach past a
			# neighbour or through it, never simply land behind it.
			var holder := _territory.owner_at(Vector2(x, _seabed.height_at(x) - _territory.cell_size()))
			if holder != null and holder.faction != successor and holder.faction != parent.faction:
				continue
			return x
	return -1.0

func _on_colony_died(colony: Colony) -> void:
	var faction := colony.faction
	if _detach_colony(colony):
		colony_lost.emit(faction)
		for other in _colonies:
			if other.faction == faction:
				return
		faction_extinct.emit(faction)

func _detach_colony(colony: Colony) -> bool:
	var index := _colonies.find(colony)
	if index == -1:
		return false
	_colonies.remove_at(index)
	colony.get_parent().remove_child(colony)
	colony.queue_free()
	_rebuild_territory()
	return true

func colonies() -> Array[Colony]:
	return _colonies.duplicate()

func territory() -> Territory:
	return _territory

## Where the ground is. Shared by fish, decor and colonies so they agree with the
## backdrop about the floor.
func seabed() -> Seabed:
	return _seabed

func clear_colonies() -> void:
	_pending.clear()
	_wounded.clear()
	_survived.clear()
	_disaster_clock = 0.0
	for colony in _colonies:
		colony.get_parent().remove_child(colony)
		colony.queue_free()
	_colonies.clear()
	_rebuild_territory()

## The factions the player may found directly. Anything meant to be earned — the ravine
## dwellers — is reachable only by a lineage descending into it.
func placeable_factions() -> Array[Faction]:
	return available_factions.filter(func(f: Faction) -> bool: return f.placeable)

func select_faction(faction: Faction) -> void:
	selected_faction = faction
	selected_decor = null
	feeding = false
	removing = false
	striking = false
	bleaching = false

## Arms the strike: the next tap calls one down instead of placing anything.
func set_striking(on: bool) -> void:
	striking = on
	if on:
		bleaching = false
		selected_faction = null
		selected_decor = null
		feeding = false
		removing = false

## Arms the bleach: the next tap starts a disaster on the reef under the finger.
func set_bleaching(on: bool) -> void:
	bleaching = on
	if on:
		striking = false
		selected_faction = null
		selected_decor = null
		feeding = false
		removing = false

## Flags every fish that is inside a plant's cover, once per frame.
##
## Done here rather than inside each predator's search: a fish with ten hunters near it
## would otherwise test its surroundings ten times, and the answer is the same each time.
func _mark_sheltered() -> void:
	if _decor.is_empty():
		for fish in _fish:
			fish.sheltered = false
		return
	for fish in _fish:
		fish.sheltered = false
	for item in _decor:
		if not item.shelters():
			continue
		for node: Node2D in _hash.query_radius(item.global_position, item.kind.shelter_radius, null):
			var fish := node as Fish
			if fish != null:
				fish.sheltered = true

## Removes fish that have outlived their species' lifespan.
##
## Iterates a copy: _on_fish_eaten mutates _fish, and the eaten path and this one can
## both fire in a frame.
func _reap() -> void:
	for fish in _fish.duplicate():
		if fish.is_past_lifespan() or fish.is_starved():
			_remove(fish, true)

## Pairs adults of the same species and spawns one offspring per pair.
##
## Both parents go on cooldown, so a crowd cannot spawn a fish per frame, and each
## species stops at its own carrying capacity. Without this the tank only ever loses
## fish: a shark eats and nothing replaces the prey, so every tank trends to zero.
func _breed() -> void:
	var counts: Dictionary = {}
	for fish in _fish:
		counts[fish.species] = int(counts.get(fish.species, 0)) + 1

	var paired: Dictionary = {}
	for fish in _fish:
		if not fish.can_breed() or paired.has(fish):
			continue
		if int(counts.get(fish.species, 0)) >= fish.species.capacity or _fish.size() >= MAX_POPULATION:
			continue
		var mate := _find_mate(fish, paired)
		if mate == null:
			continue
		paired[fish] = true
		paired[mate] = true
		fish.note_bred()
		mate.note_bred()
		var midpoint := (fish.global_position + mate.global_position) * 0.5
		if spawn(fish.species, midpoint, 0.0) != null:
			counts[fish.species] = int(counts.get(fish.species, 0)) + 1
			fish_born.emit(fish.species)

func _find_mate(fish: Fish, paired: Dictionary) -> Fish:
	for other: Node2D in _hash.query_radius(fish.global_position, fish.species.breed_distance, fish):
		var candidate := other as Fish
		if candidate == null or paired.has(candidate):
			continue
		if candidate.species == fish.species and candidate.can_breed():
			return candidate
	return null

## The rect fish are confined to, in world coordinates.
func bounds() -> Rect2:
	return _bounds

## Adds one fish of `species` at `position` (world coordinates). Returns null when
## the tank is full, the species is null, or the tank is not in the scene tree yet.
func spawn(species: FishSpecies, position: Vector2, age: float = -1.0) -> Fish:
	if not is_node_ready():
		push_error("Aquarium.spawn() called before the tank entered the tree.")
		return null
	if species == null or _fish.size() >= MAX_POPULATION:
		return null

	var fish: Fish = FISH_SCENE.instantiate()
	var predators: Array[FishSpecies] = _predator_map.get(species, [] as Array[FishSpecies])
	fish.configure(species, predators, _bounds, age, _seabed)
	# Lifted out of the ground at birth, not merely on its first tick. configure() makes
	# a fish's own movement terrain-aware, but the position written here is the raw
	# request — so a tap on rock, a restored save, or a colony releasing at its own base
	# put a fish inside the seabed until something moved it.
	var at := _bounds.get_center() if not _bounds.has_point(position) else position
	if _seabed != null:
		at = _seabed.lift_out_of_rock(at, species.size * 0.5)
	fish.global_position = at
	fish.eaten.connect(_on_fish_eaten)

	fish_layer.add_child(fish)
	_fish.append(fish)
	population_changed.emit(_fish.size())
	return fish

## Places — or takes out — whatever the picker currently has armed. What a tap calls.
##
## This, and not spawn(), is where undo is recorded: breeding and restoring both go
## through spawn(), and a tank that bred while you were looking away would otherwise
## fill the undo stack with fish you never placed.
##
## `reach` is the tap's grab radius in WORLD units and only matters in remove mode; the
## caller scales REMOVE_REACH by the camera's zoom.
func place_selected(position: Vector2, reach: float = REMOVE_REACH) -> Node2D:
	if removing:
		return remove_at(position, reach)

	# A strike destroys rather than places, so it is neither recorded nor undoable: the
	# reef it took out is gone, the neighbours have already grown into the hole, and
	# putting the biomass back would not put the map back.
	if striking:
		strike(position)
		return null
	if bleaching:
		bleach(position)
		return null

	var placed: Node2D = null
	if feeding:
		placed = drop_food(position)
	elif selected_faction != null:
		placed = plant_colony(selected_faction, position)
	elif selected_decor != null:
		placed = place_decor(selected_decor, position)
	else:
		placed = spawn(selected_species, position)

	if placed != null:
		_history.note_added(placed)
		_note_undo_state()
	return placed

## Takes out the one fish, plant or pellet nearest the tap, if anything is close enough.
## Returns what was removed, or null when the tap landed on open water.
func remove_at(position: Vector2, reach: float = REMOVE_REACH) -> Node2D:
	var target := _nearest_editable(position, maxf(reach, 1.0))
	if target == null:
		return null

	var was_id := target.get_instance_id()
	var record: Dictionary = {}
	var fish := target as Fish
	var item := target as Decor
	if fish != null:
		record = {"what": "fish", "species": fish.species,
			"position": fish.global_position, "age": fish.age}
		_detach(fish)
	elif item != null:
		record = {"what": "decor", "kind": item.kind, "position": item.global_position}
		_detach_decor(item)
	else:
		var pellet := target as Food
		record = {"what": "food", "position": pellet.global_position}
		_detach_food(pellet)

	_history.note_removed(record, was_id)
	_note_undo_state()
	return target

## The closest thing to `position` that the player may remove, or null.
##
## Scored on distance relative to each candidate's own grab radius rather than on
## distance alone, so a shark is not always chosen over the clownfish under the finger
## purely by being bigger. Pellets are checked first so one resting against a fish goes
## before the fish, which is the order they are drawn in.
func _nearest_editable(position: Vector2, reach: float) -> Node2D:
	var best: Node2D = null
	# Ratios above 1 are out of reach, so this both seeds the search and is the cutoff.
	var best_score := 1.0

	for pellet in _food:
		var score := position.distance_to(pellet.global_position) / reach
		if score <= best_score:
			best_score = score
			best = pellet

	for fish in _fish:
		var grab := maxf(reach, fish.half_length())
		var score := position.distance_to(fish.global_position) / grab
		if score <= best_score:
			best_score = score
			best = fish

	for item in _decor:
		# Decor is rooted at its base and stands upward, so the whole plant is the
		# target — measuring to its origin would mean tapping a kelp's foot exactly.
		var rect := _decor_rect(item)
		var score := position.distance_to(position.clamp(rect.position, rect.end)) / reach
		if score <= best_score:
			best_score = score
			best = item

	return best

## The rectangle a decor item occupies, running upward from the point it was planted.
func _decor_rect(item: Decor) -> Rect2:
	var aspect := 1.0
	var texture := item.kind.texture
	if texture != null and texture.get_size().y > 0.0:
		aspect = texture.get_size().x / texture.get_size().y
	var half_width := item.kind.size * aspect * 0.5
	return Rect2(
		item.global_position - Vector2(half_width, item.kind.size),
		Vector2(half_width * 2.0, item.kind.size))

## Takes back the last thing the player placed, or puts back the last thing they
## removed. Returns false when there is nothing left to undo.
##
## An entry naming a fish that has since been eaten is not an error and not a no-op: it
## is dropped and the one before it is used, so the button always undoes the most recent
## thing it still can.
func undo() -> bool:
	var entry := _history.take()
	if entry.is_empty():
		_note_undo_state()
		return false

	if entry.get("action") == TankHistory.Action.ADDED:
		var node: Node2D = entry.get("node")
		var fish := node as Fish
		var item := node as Decor
		var colony := node as Colony
		if fish != null:
			_detach(fish)
		elif item != null:
			_detach_decor(item)
		elif colony != null:
			_detach_colony(colony)
		else:
			_detach_food(node as Food)
		_note_undo_state()
		return true

	var restored: Node2D = null
	match entry.get("what", ""):
		"fish":
			restored = spawn(entry["species"], entry["position"], entry["age"])
		"decor":
			restored = place_decor(entry["kind"], entry["position"])
		"food":
			restored = drop_food(entry["position"])
	# The object is back but it is a new instance, so any older entry that placed the
	# original has to be re-pointed at it or "place, delete, undo, undo" would leave it.
	_history.replace_node(int(entry.get("was_id", 0)), restored)
	_note_undo_state()
	return restored != null

func can_undo() -> bool:
	return _history.can_undo()

func _note_undo_state() -> void:
	var available := _history.can_undo()
	if available == _undo_available:
		return
	_undo_available = available
	undo_changed.emit(available)

## Drops one pellet. It sinks until a hungry fish reaches it or it dissolves.
func drop_food(position: Vector2) -> Food:
	if not is_node_ready() or _food.size() >= MAX_FOOD:
		return null
	var pellet: Food = FOOD_SCENE.instantiate()
	pellet.configure(_bounds)
	pellet.global_position = _bounds.get_center() if not _bounds.has_point(position) else position
	pellet.consumed.connect(_on_food_consumed)
	food_layer.add_child(pellet)
	_food.append(pellet)
	food_changed.emit(_food.size())
	return pellet

func food() -> Array[Food]:
	return _food.duplicate()

func set_feeding(on: bool) -> void:
	feeding = on
	if on:
		selected_decor = null
		selected_faction = null
		striking = false
		bleaching = false
		removing = false

## Arms deletion: the next tap takes something out instead of putting something in.
func set_removing(on: bool) -> void:
	removing = on
	if on:
		selected_decor = null
		selected_faction = null
		striking = false
		bleaching = false
		feeding = false

func _on_food_consumed(pellet: Food) -> void:
	_detach_food(pellet)

## Adds one decor item at `position`.
func place_decor(kind: DecorKind, position: Vector2) -> Decor:
	if not is_node_ready() or kind == null:
		return null
	var item: Decor = DECOR_SCENE.instantiate()
	item.configure(kind)
	var where := _bounds.get_center() if not _bounds.has_point(position) else position
	# Plants are rooted at their base and stand upward, so a plant placed in open water
	# was a plant hanging in open water. Seat it on the ground under the tap.
	item.global_position = Vector2(where.x, _seabed.height_at(where.x)) if _seabed != null else where
	(decor_front if kind.in_front else decor_back).add_child(item)
	_decor.append(item)
	_rebuild_shelter()
	decor_changed.emit(_decor.size())
	return item

func decor() -> Array[Decor]:
	return _decor.duplicate()

func clear_decor() -> void:
	for item in _decor:
		item.get_parent().remove_child(item)
		item.queue_free()
	_decor.clear()
	_rebuild_shelter()
	decor_changed.emit(0)

## Decor does not move, so its grid is rebuilt only when the set changes.
func _rebuild_shelter() -> void:
	_shelter_hash.clear()
	for item in _decor:
		if item.shelters():
			_shelter_hash.insert(item)

func _largest_shelter() -> float:
	var largest := 1.0
	for kind in available_decor:
		largest = maxf(largest, kind.shelter_radius)
	return largest

func select_species(species: FishSpecies) -> void:
	if species == null:
		return
	selected_decor = null
	selected_faction = null
	striking = false
	bleaching = false
	feeding = false
	removing = false
	if selected_species == species:
		return
	selected_species = species
	species_selected.emit(species)

func select_decor(kind: DecorKind) -> void:
	selected_decor = kind
	selected_faction = null
	striking = false
	bleaching = false
	feeding = false
	removing = false

func set_paused(paused: bool) -> void:
	if _paused == paused:
		return
	_paused = paused
	paused_changed.emit(_paused)

func is_paused() -> bool:
	return _paused

func toggle_paused() -> void:
	set_paused(not _paused)

func population() -> int:
	return _fish.size()

## The living fish, in spawn order.
##
## The authoritative list — not `fish_layer.get_children()`. A fish that has been eaten
## or cleared leaves `_fish` at once but stays a child until the end of the frame, so
## reading the node tree can see fish the tank already considers gone. That is how a
## save came to contain dead fish.
func fish() -> Array[Fish]:
	return _fish.duplicate()

func clear_tank() -> void:
	for f in _fish:
		fish_layer.remove_child(f)
		f.queue_free()
	_fish.clear()
	# Every entry named a node that is now gone, and a REMOVED entry would put a fish
	# back into a tank that was deliberately emptied.
	_history.clear()
	_note_undo_state()
	population_changed.emit(0)

func _on_fish_eaten(fish: Fish) -> void:
	_remove(fish, false)

## Takes a fish out of the tank without calling it a death.
##
## `fish_died` means the ecosystem lost a fish — to a predator or to age — and the
## simulation tests count predation from it. A fish the player deleted is neither, so
## removal and dying share the bookkeeping and not the signal.
func _detach(fish: Fish) -> bool:
	var index := _fish.find(fish)
	if index == -1:
		return false
	_fish.remove_at(index)
	fish_layer.remove_child(fish)
	fish.queue_free()
	population_changed.emit(_fish.size())
	return true

func _detach_decor(item: Decor) -> bool:
	var index := _decor.find(item)
	if index == -1:
		return false
	_decor.remove_at(index)
	item.get_parent().remove_child(item)
	item.queue_free()
	_rebuild_shelter()
	decor_changed.emit(_decor.size())
	return true

func _detach_food(pellet: Food) -> bool:
	if pellet == null:
		return false
	var index := _food.find(pellet)
	if index == -1:
		return false
	_food.remove_at(index)
	food_layer.remove_child(pellet)
	pellet.queue_free()
	food_changed.emit(_food.size())
	return true

func _remove(fish: Fish, of_old_age: bool) -> void:
	var species := fish.species
	if _detach(fish):
		fish_died.emit(species, of_old_age)

## Scales the backdrop to cover the tank without distorting it.
func _fit_background() -> void:
	if background.texture == null:
		return
	var texture_size := background.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var cover := maxf(tank_size.x / texture_size.x, tank_size.y / texture_size.y)
	background.scale = Vector2(cover, cover)
	background.position = tank_size * 0.5

## Rebuilds the tank from a save. Returns false when there was nothing usable, so the
## caller can fall back to seeding a fresh tank.
##
## A fish whose species is no longer in the catalogue is skipped rather than failing the
## whole restore: a save outlives the build that wrote it, and losing one species should
## not cost the player the rest of the tank.
func restore(data: Dictionary) -> bool:
	# Earned traits first — before the early return, and before any colony is planted.
	#
	# Before the return, because a tank can hold its factions' progress with nothing
	# alive in it, and skipping it lost what had just been saved. Before the colonies,
	# because a colony reads its traits as it is founded: applied afterwards, Canopy made
	# a restored column taller with no territory pass after it, and a reopened tank drew
	# its old borders until the next one.
	var earned: Variant = data.get("progress", {})
	if typeof(earned) == TYPE_DICTIONARY:
		for f in available_factions:
			progress_for(f).restore_save((earned as Dictionary).get(f.resource_path, {}))

	var entries: Array = data.get("fish", [])
	var decor_entries: Array = data.get("decor", [])
	var colony_entries: Array = data.get("colonies", [])
	if entries.is_empty() and decor_entries.is_empty() and colony_entries.is_empty():
		return false

	# Decor first: plants placed before the fish means a restored tank's shelter is
	# already in effect on the very first frame, rather than one frame late.
	var decor_by_path: Dictionary = {}
	for kind in available_decor:
		decor_by_path[kind.resource_path] = kind
	for entry: Variant in decor_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var kind: DecorKind = decor_by_path.get(entry.get("kind", ""), null)
		if kind != null:
			place_decor(kind, Vector2(float(entry.get("x", 0)), float(entry.get("y", 0))))

	# Colonies before fish, for the same reason decor is: a restored tank's map should
	# be drawn on the first frame rather than a quarter of a second late.
	var faction_by_path: Dictionary = {}
	for f in available_factions:
		faction_by_path[f.resource_path] = f
	for entry: Variant in colony_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var faction: Faction = faction_by_path.get(entry.get("faction", ""), null)
		if faction != null:
			var restored_colony := plant_colony(faction,
				Vector2(float(entry.get("x", 0)), float(entry.get("y", 0))),
				float(entry.get("biomass", -1.0)))
			if restored_colony != null:
				restored_colony.age = float(entry.get("age", 0.0))

	var by_path: Dictionary = {}
	for species in available_species:
		by_path[species.resource_path] = species

	var restored := 0
	var skipped := 0
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var species: FishSpecies = by_path.get(entry.get("species", ""), null)
		if species == null:
			skipped += 1
			continue
		var age := float(entry.get("age", -1))
		if spawn(species, Vector2(float(entry.get("x", 0)), float(entry.get("y", 0))), age) != null:
			restored += 1

	var selected: FishSpecies = by_path.get(data.get("selected", ""), null)
	if selected != null:
		select_species(selected)

	if skipped > 0:
		push_warning("Restored %d fish; skipped %d whose species is no longer present." % [restored, skipped])
	if restored == 0 and (not _decor.is_empty() or not _colonies.is_empty()):
		return true
	if restored > 0:
		_apply_time_away(Offline.elapsed_since(
			int(data.get("saved_at", 0)), int(Time.get_unix_time_from_system())))
	return restored > 0

## Credits the tank for time the app was not running: fish age, the old die, and each
## breeding species grows toward its capacity. See scripts/systems/offline.gd for why
## this is a population model rather than a fast-forwarded simulation.
func _apply_time_away(seconds: float) -> void:
	if seconds <= 0.0:
		return

	# A long absence is a generational turnover, not a mass extinction. The first
	# version grew each species to capacity and then aged every adult past its
	# lifespan, so three hours away returned a tank containing one immortal shark:
	# the survivors had been computed before the deaths were applied, and nothing
	# replaced them.
	#
	# So the target population is computed from who was alive during the absence, the
	# old are then reaped, and the shortfall is made up by their descendants.
	var targets: Dictionary = {}
	for species in available_species:
		targets[species] = 0
	for fish in _fish:
		targets[fish.species] = int(targets.get(fish.species, 0)) + 1
	for species in available_species:
		if species.breed_distance <= 0.0:
			continue
		targets[species] = Offline.project(
			int(targets[species]), species.capacity,
			Offline.growth_rate(species.breed_cooldown), seconds)

	var died := 0
	for fish in _fish.duplicate():
		fish.age += seconds
		if fish.is_past_lifespan():
			_remove(fish, true)
			died += 1

	var alive: Dictionary = {}
	for fish in _fish:
		alive[fish.species] = int(alive.get(fish.species, 0)) + 1

	var born := 0
	for species in available_species:
		var shortfall := int(targets.get(species, 0)) - int(alive.get(species, 0))
		for i in shortfall:
			# Descendants, with ages spread across the run-up to maturity so the tank
			# comes back as a mixed generation rather than a synchronised cohort that
			# would all mature, breed and die on the same frame.
			if spawn(species, _random_point(), randf_range(0.0, species.maturity * 1.5)) != null:
				born += 1

	if born > 0 or died > 0:
		print("Away %d min: %d born, %d died of old age, %d fish now."
			% [int(seconds / 60.0), born, died, _fish.size()])

## A random point in open water. Used to seed a tank and to place the descendants an
## absence produced.
##
## Seabed-aware, like the fish's own wander targets. It was not, so both paths put fish
## inside the rock and relied on the first tick to lift them out — which meant a fish
## saved before it had ever ticked came back somewhere else, and a save/restore round
## trip could not be compared position for position.
func _random_point() -> Vector2:
	if _seabed != null:
		return _seabed.random_water_point(24.0)
	return Vector2(
		randf_range(_bounds.position.x, _bounds.end.x),
		randf_range(_bounds.position.y, _bounds.end.y))

## Writes the tank to disk. Safe to call at any time.
func save() -> Error:
	return TankStore.save(self)

## Stocks the tank with each species' `starting_count`, scattered at random.
##
## Nothing in the app calls this — a new aquarium opens empty. It is how the simulation
## tests and tools/screenshot.gd stand up a representative tank in one line, and the
## counts are the tuned ones, so what they produce is the population the tank settles
## at rather than an arbitrary crowd.
func seed_starting_population() -> void:
	for species in available_species:
		for i in species.starting_count:
			spawn(species, _random_point())

## Inverts every species' `eats` list so each species knows what hunts it.
## The Go original stored both directions by hand and they could disagree.
func _derive_predators(all_species: Array[FishSpecies]) -> Dictionary:
	var map: Dictionary = {}
	for species in all_species:
		map[species] = [] as Array[FishSpecies]
	for predator in all_species:
		for prey in predator.eats:
			if prey == null:
				continue
			if not map.has(prey):
				map[prey] = [] as Array[FishSpecies]
			map[prey].append(predator)
	return map

func _largest_sight() -> float:
	var largest := 1.0
	for species in available_species:
		largest = maxf(largest, species.sight)
	return largest
