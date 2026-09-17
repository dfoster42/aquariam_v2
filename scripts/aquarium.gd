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
## Fires when the undo button should enable or disable.
signal undo_changed(available: bool)

const FISH_SCENE: PackedScene = preload("res://scenes/fish.tscn")
const DECOR_SCENE: PackedScene = preload("res://scenes/decor.tscn")
const FOOD_SCENE: PackedScene = preload("res://scenes/food.tscn")
const COLONY_SCENE: PackedScene = preload("res://scenes/colony.tscn")
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
## Biomass a strike takes out at its centre, falling to nothing at its edge. Tuned so a
## single hit kills a young colony outright and badly wounds a mature one — a power
## that only chips at a reef gives the player nothing to watch.
const STRIKE_POWER: float = 90.0
## How far a bleach carries past the colony it started on, as a multiple of the two
## colonies' radii. Above 1.0 it can cross a small gap between neighbours; much above
## and it jumps to reefs that do not look connected.
const BLEACH_CONTACT: float = 1.15
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
	_territory = Territory.new(_bounds)

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
	if _colonies.is_empty():
		return
	for colony: Colony in _colonies.duplicate():
		colony.tick(delta)

	_since_territory += delta
	if _since_territory < TERRITORY_INTERVAL:
		return
	_since_territory = 0.0
	_rebuild_territory()

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
	territory_layer.texture = _territory.texture()
	_fit_territory()
	territory_changed.emit(_colonies.size())

## Stretches the coarse ownership grid over the whole map. Linear filtering on the
## sprite is what turns 90x60 cells into soft regions instead of a chequerboard.
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
	var colony: Colony = COLONY_SCENE.instantiate()
	colony.configure(faction, start_biomass)
	colony.global_position = _bounds.get_center() if not _bounds.has_point(position) else position
	colony.released.connect(_on_colony_released)
	colony.spreading.connect(_on_colony_spreading)
	colony.died.connect(_on_colony_died)
	colony_layer.add_child(colony)
	_colonies.append(colony)
	_rebuild_territory()
	colony_founded.emit(faction)
	return colony

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
		destroyed += colony.damage(power * (1.0 - distance / radius))
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
		return 0.0

	var faction := origin.faction
	var frontier: Array[Colony] = [origin]
	var strength: Dictionary = {origin: origin.biomass * BLEACH_POWER}
	var seen: Dictionary = {origin: true}
	var destroyed := 0.0

	# Breadth-first across touching colonies of the same faction, losing strength at
	# each hop, so a bleach burns out somewhere inside a large faction rather than
	# always taking all of it.
	while not frontier.is_empty():
		var current: Colony = frontier.pop_front()
		var power := float(strength[current])
		var reach := current.radius()
		for other in _colonies:
			if seen.has(other) or other.faction != faction:
				continue
			var gap := current.global_position.distance_to(other.global_position)
			if gap > (reach + other.radius()) * BLEACH_CONTACT:
				continue
			seen[other] = true
			var carried := power * BLEACH_DECAY
			if carried < Colony.MIN_BIOMASS:
				continue
			strength[other] = carried
			frontier.append(other)

	for colony: Colony in strength:
		destroyed += colony.damage(float(strength[colony]))
	if destroyed > 0.0:
		_rebuild_territory()
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
	var margin := Colony.BASE_RADIUS
	var inner := Rect2(_bounds.position + Vector2(margin, margin),
		_bounds.size - Vector2(margin, margin) * 2.0)
	if not inner.has_point(position):
		return
	var holder := _territory.owner_at(position)
	if holder != null and holder.faction != parent.faction:
		return
	var stake := parent.pay_to_spread()
	if stake <= 0.0:
		return
	plant_colony(parent.faction, position, stake)

func _on_colony_died(colony: Colony) -> void:
	var faction := colony.faction
	if _detach_colony(colony):
		colony_lost.emit(faction)

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

func clear_colonies() -> void:
	for colony in _colonies:
		colony.get_parent().remove_child(colony)
		colony.queue_free()
	_colonies.clear()
	_rebuild_territory()

func select_faction(faction: Faction) -> void:
	selected_faction = faction
	selected_decor = null
	feeding = false
	removing = false
	striking = false

## Arms the strike: the next tap calls one down instead of placing anything.
func set_striking(on: bool) -> void:
	striking = on
	if on:
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
	fish.configure(species, predators, _bounds, age)
	fish.global_position = _bounds.get_center() if not _bounds.has_point(position) else position
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
		removing = false

## Arms deletion: the next tap takes something out instead of putting something in.
func set_removing(on: bool) -> void:
	removing = on
	if on:
		selected_decor = null
		selected_faction = null
		striking = false
		feeding = false

func _on_food_consumed(pellet: Food) -> void:
	_detach_food(pellet)

## Adds one decor item at `position`.
func place_decor(kind: DecorKind, position: Vector2) -> Decor:
	if not is_node_ready() or kind == null:
		return null
	var item: Decor = DECOR_SCENE.instantiate()
	item.configure(kind)
	item.global_position = _bounds.get_center() if not _bounds.has_point(position) else position
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
			plant_colony(faction,
				Vector2(float(entry.get("x", 0)), float(entry.get("y", 0))),
				float(entry.get("biomass", -1.0)))

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

func _random_point() -> Vector2:
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
