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

## Multiplied into the backdrop. The shipped backdrop is a photograph and the
## fish are flat vector art; dimming and cooling it is what lets a bright fish
## read against it. A stopgap until the backdrop is redrawn to match the fish.
@export var backdrop_tint: Color = Color(0.48, 0.58, 0.68)

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
	_seed_starting_population()

func _physics_process(delta: float) -> void:
	if _paused:
		return
	_hash.clear()
	for fish in _fish:
		_hash.insert(fish)
	for fish in _fish:
		fish.tick(delta, _hash)

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

func clear_tank() -> void:
	for fish in _fish:
		fish.queue_free()
	_fish.clear()
	population_changed.emit(0)

func _on_fish_eaten(fish: Fish) -> void:
	var index := _fish.find(fish)
	if index == -1:
		return
	_fish.remove_at(index)
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
