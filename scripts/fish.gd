class_name Fish
extends Node2D
## A single fish. All stats come from its FishSpecies resource.
##
## Fish do not drive themselves: Aquarium owns the frame loop and calls tick()
## so the shared SpatialHash is built exactly once per frame.

signal eaten(fish: Fish)

enum Behaviour { WANDER, HUNT, FLEE }

const ARRIVE_DISTANCE: float = 24.0
const BITE_DISTANCE: float = 14.0
## Degrees per second the sprite rotates toward its heading.
const TURN_RATE: float = 360.0
## How far from level a fish is allowed to look, in degrees. Headings are drawn from
## anywhere in the tank, so an unclamped sprite pitches to 80 degrees nose-down on a
## routine wander and reads as a dying fish rather than a swimming one. The fish still
## travels along its true heading; only how far it tips to show it is limited.
const PITCH_LIMIT: float = 22.0

var species: FishSpecies
var behaviour: Behaviour = Behaviour.WANDER
## Seconds lived. Drives size, breeding eligibility and death of old age.
var age: float = 0.0

var _breed_timer: float = 0.0

var _predators: Array[FishSpecies] = []
var _target: Vector2 = Vector2.ZERO
var _bounds: Rect2 = Rect2()
var _is_eaten: bool = false

@onready var sprite: Sprite2D = $Sprite2D

## Called by Aquarium immediately after instantiation, before the node enters
## the tree. `predators` is the derived reverse of every species' `eats` list.
func configure(fish_species: FishSpecies, predators: Array[FishSpecies], bounds: Rect2,
		start_age: float = -1.0) -> void:
	species = fish_species
	_predators = predators
	_bounds = bounds
	_target = _random_point()
	# Seeded and restored fish arrive as adults of assorted ages; only a fish born in
	# the tank starts at zero, so a fresh tank is not a shoal of identical juveniles
	# that all mature and breed on the same frame.
	age = start_age if start_age >= 0.0 else randf_range(species.maturity, species.maturity * 2.0)
	_breed_timer = species.breed_cooldown

func _ready() -> void:
	if species == null:
		push_error("Fish added without a species; call configure() first.")
		return
	sprite.texture = species.texture
	_apply_size()

func set_bounds(bounds: Rect2) -> void:
	_bounds = bounds

## Advances this fish by `delta` seconds. `hash` must already contain every
## other fish in the tank for this frame.
func tick(delta: float, hash: SpatialHash) -> void:
	if _is_eaten:
		return

	age += delta
	_breed_timer = maxf(0.0, _breed_timer - delta)
	_apply_size()

	var heading := _decide_heading(hash)
	if heading != Vector2.ZERO:
		global_position += heading * species.speed * delta
		_face(heading, delta)

	global_position = _clamp_to_bounds(global_position)

func _decide_heading(hash: SpatialHash) -> Vector2:
	var neighbours := hash.query_radius(global_position, species.sight, self)

	var nearest_threat: Fish = _nearest_of(neighbours, _predators)
	if nearest_threat != null:
		behaviour = Behaviour.FLEE
		return nearest_threat.global_position.direction_to(global_position)

	var nearest_prey: Fish = _nearest_of(neighbours, species.eats)
	if nearest_prey != null:
		var gap := global_position.distance_to(nearest_prey.global_position)
		if gap <= BITE_DISTANCE:
			nearest_prey.be_eaten()
			behaviour = Behaviour.WANDER
			_target = _random_point()
			return Vector2.ZERO
		behaviour = Behaviour.HUNT
		return global_position.direction_to(nearest_prey.global_position)

	behaviour = Behaviour.WANDER
	if global_position.distance_to(_target) < ARRIVE_DISTANCE:
		_target = _random_point()
	return global_position.direction_to(_target)

## Returns the closest neighbour whose species appears in `wanted`, or null.
func _nearest_of(neighbours: Array[Node2D], wanted: Array[FishSpecies]) -> Fish:
	if wanted.is_empty():
		return null

	var best: Fish = null
	var best_distance_sq := INF
	for node: Node2D in neighbours:
		var other := node as Fish
		if other == null or other._is_eaten or not wanted.has(other.species):
			continue
		var d := global_position.distance_squared_to(other.global_position)
		if d < best_distance_sq:
			best_distance_sq = d
			best = other
	return best

## A fish is grown at `maturity` and no smaller than a third of adult size at birth.
func growth() -> float:
	if species.maturity <= 0.0:
		return 1.0
	return clampf(0.34 + 0.66 * (age / species.maturity), 0.34, 1.0)

func is_mature() -> bool:
	return age >= species.maturity

## Whether this fish could pair right now, ignoring whether a partner is nearby.
func can_breed() -> bool:
	return (not _is_eaten) and species.breed_distance > 0.0 and is_mature() and _breed_timer <= 0.0

func note_bred() -> void:
	_breed_timer = species.breed_cooldown

func is_past_lifespan() -> bool:
	return species.lifespan > 0.0 and age > species.lifespan

func be_eaten() -> void:
	if _is_eaten:
		return
	_is_eaten = true
	eaten.emit(self)

func is_eaten() -> bool:
	return _is_eaten

## Rotates toward `heading` and mirrors the sprite so the fish never swims
## upside down when travelling right-to-left.
##
## Every sprite in assets/textures/ is drawn facing LEFT — tools/art/prompts/style.txt
## fixes that for the whole catalogue — so it is a fish swimming RIGHT that needs
## mirroring, not one swimming left.
func _face(heading: Vector2, delta: float) -> void:
	var desired := heading.angle()
	var facing_left := absf(wrapf(desired, -PI, PI)) > PI / 2.0
	if facing_left:
		desired = wrapf(desired + PI, -PI, PI)
	sprite.flip_h = not facing_left
	var limit := deg_to_rad(PITCH_LIMIT)
	desired = clampf(desired, -limit, limit)
	sprite.rotation = rotate_toward(sprite.rotation, desired, deg_to_rad(TURN_RATE) * delta)

func _apply_size() -> void:
	if sprite.texture == null:
		return
	var texture_size := sprite.texture.get_size()
	if texture_size.y <= 0.0:
		return
	var scale_factor := species.size * growth() / texture_size.y
	sprite.scale = Vector2(scale_factor, scale_factor)

func _clamp_to_bounds(point: Vector2) -> Vector2:
	var margin := species.size * 0.5
	return Vector2(
		clampf(point.x, _bounds.position.x + margin, _bounds.end.x - margin),
		clampf(point.y, _bounds.position.y + margin, _bounds.end.y - margin),
	)

func _random_point() -> Vector2:
	var margin := species.size * 0.5 if species != null else 0.0
	return Vector2(
		randf_range(_bounds.position.x + margin, _bounds.end.x - margin),
		randf_range(_bounds.position.y + margin, _bounds.end.y - margin),
	)
