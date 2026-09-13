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

## The rect fish are confined to, in world coordinates.
func bounds() -> Rect2:
	return _bounds

## Adds one fish of `species` at `position` (world coordinates). Returns null when
## the tank is full, the species is null, or the tank is not in the scene tree yet.
func spawn(species: FishSpecies, position: Vector2) -> Fish:
	if not is_node_ready():
		push_error("Aquarium.spawn() called before the tank entered the tree.")
		return null
	if species == null or _fish.size() >= MAX_POPULATION:
		return null

	var fish: Fish = FISH_SCENE.instantiate()
	var predators: Array[FishSpecies] = _predator_map.get(species, [] as Array[FishSpecies])
	fish.configure(species, predators, _bounds)
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
	var index := _fish.find(fish)
	if index == -1:
		return
	_fish.remove_at(index)
	fish_layer.remove_child(fish)
	fish.queue_free()
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
		if spawn(species, Vector2(float(entry.get("x", 0)), float(entry.get("y", 0)))) != null:
			restored += 1

	var selected: FishSpecies = by_path.get(data.get("selected", ""), null)
	if selected != null:
		select_species(selected)

	if skipped > 0:
		push_warning("Restored %d fish; skipped %d whose species is no longer present." % [restored, skipped])
	return restored > 0

## Writes the tank to disk. Safe to call at any time.
func save() -> Error:
	return TankStore.save(self)

func _seed_starting_population() -> void:
	for species in available_species:
		for i in 3:
			spawn(species, Vector2(
				randf_range(0.0, tank_size.x),
				randf_range(0.0, tank_size.y),
			))

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
