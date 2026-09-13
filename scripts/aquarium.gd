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

const FISH_SCENE: PackedScene = preload("res://scenes/fish.tscn")
## Refuse to spawn beyond this; keeps a stray tap-and-hold from hanging the app.
const MAX_POPULATION: int = 1500

## Every species the tank can spawn. Populated in the inspector — drop a new
## .tres in here and it appears in the picker with no code change. An exported
## array rather than a directory scan, because exported builds rewrite
## res://...tres to .tres.remap and a filename scan would come back empty.
@export var available_species: Array[FishSpecies] = []

## The tank's size in world units, deliberately larger than a phone viewport so
## that panning has somewhere to go.
@export var tank_size: Vector2 = Vector2(1080, 1920)

## Multiplied into the backdrop. White now that the backdrop is drawn to sit under
## the fish rather than compete with them — it was a stopgap that dimmed the
## photograph this replaced, and applying it to the drawn backdrop would crush it.
@export var backdrop_tint: Color = Color.WHITE

var selected_species: FishSpecies

var _fish: Array[Fish] = []
var _predator_map: Dictionary = {}
var _hash: SpatialHash
var _bounds: Rect2 = Rect2()
var _paused: bool = false

@onready var background: Sprite2D = $Background
@onready var fish_layer: Node2D = $FishLayer

func _ready() -> void:
	available_species = available_species.filter(func(s: FishSpecies) -> bool: return s != null)
	if available_species.is_empty():
		push_error("Aquarium has no species assigned; set available_species in the inspector.")
		return
	available_species.sort_custom(func(a: FishSpecies, b: FishSpecies) -> bool:
		return a.display_name < b.display_name)

	_bounds = Rect2(Vector2.ZERO, tank_size)
	_predator_map = _derive_predators(available_species)
	_hash = SpatialHash.new(_largest_sight())
	selected_species = available_species[0]

	background.modulate = backdrop_tint
	_fit_background()

	if not restore(TankStore.read()):
		_seed_starting_population()

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
	for fish in _fish:
		fish.tick(step, _hash)
	_reap()
	_breed()

## Removes fish that have outlived their species' lifespan.
##
## Iterates a copy: _on_fish_eaten mutates _fish, and the eaten path and this one can
## both fire in a frame.
func _reap() -> void:
	for fish in _fish.duplicate():
		if fish.is_past_lifespan():
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

## Spawns the currently selected species. What a tap on the tank calls.
func spawn_selected(position: Vector2) -> Fish:
	return spawn(selected_species, position)

func select_species(species: FishSpecies) -> void:
	if species == null or selected_species == species:
		return
	selected_species = species
	species_selected.emit(species)

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
	population_changed.emit(0)

func _on_fish_eaten(fish: Fish) -> void:
	_remove(fish, false)

func _remove(fish: Fish, of_old_age: bool) -> void:
	var index := _fish.find(fish)
	if index == -1:
		return
	var species := fish.species
	_fish.remove_at(index)
	fish_layer.remove_child(fish)
	fish.queue_free()
	fish_died.emit(species, of_old_age)
	population_changed.emit(_fish.size())

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
	if entries.is_empty():
		return false

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

	# Breeding is applied BEFORE ageing, from the population that was actually alive
	# during the absence. Done the other way round, a long absence kills every adult of
	# old age first and then grows a species from zero — which returns zero, because
	# nothing breeds from an empty tank. A species would go permanently extinct purely
	# by the order of two loops.
	var counts: Dictionary = {}
	for fish in _fish:
		counts[fish.species] = int(counts.get(fish.species, 0)) + 1

	var born := 0
	for species in available_species:
		# breed_distance is what disables breeding in the live tank, so it has to mean
		# the same thing here. Without this check sharks, which never pair in the tank,
		# multiplied to their capacity every time the app was reopened.
		if species.breed_distance <= 0.0:
			continue
		var before := int(counts.get(species, 0))
		var after := Offline.project(
			before, species.capacity, Offline.growth_rate(species.breed_cooldown), seconds)
		for i in (after - before):
			# Newborns, not adults: an absence leaves juveniles growing, and being born
			# at age zero is also what keeps them from being reaped by the ageing below.
			if spawn(species, _random_point(), 0.0) != null:
				born += 1

	var died := 0
	for fish in _fish.duplicate():
		if fish.age == 0.0:
			continue  # born during the absence
		fish.age += seconds
		if fish.is_past_lifespan():
			_remove(fish, true)
			died += 1

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

func _seed_starting_population() -> void:
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
