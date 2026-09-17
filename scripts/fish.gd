class_name Fish
extends Node2D
## A single fish. All stats come from its FishSpecies resource.
##
## Fish do not drive themselves: Aquarium owns the frame loop and calls tick()
## so the shared SpatialHash is built exactly once per frame.

signal eaten(fish: Fish)

enum Behaviour { WANDER, HUNT, FLEE, HIDE, FEED }

const ARRIVE_DISTANCE: float = 24.0
## How close a predator's MOUTH must come to prey to eat it — not its centre.
##
## Measured centre to centre, a shark only registered a catch once the prey had reached
## the middle of its body: the sprite is around 213px long at its shipped size, so its
## mouth is ~106px ahead of the point the distance was being taken from, and prey
## visibly swam into the shark before anything happened.
const BITE_DISTANCE: float = 16.0
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

## The direction the fish is actually pointing, turned smoothly toward its heading.
##
## Kept separately from the sprite because the sprite's own state is discontinuous:
## flip_h snaps the instant a heading crosses vertical while rotation eases, so a mouth
## derived from the sprite teleported a full body length across the fish. A shark could
## then "bite" prey that was behind its tail.
var _facing: Vector2 = Vector2.LEFT

## How full the fish is, 0..1. Drains over `hunger_time`; eating refills it.
var fullness: float = 1.0
var _starving_for: float = 0.0

## Whether this fish is currently inside a plant's cover. Set once per frame by the
## Aquarium rather than worked out per predator, so a fish with ten hunters near it
## still only tests its own surroundings once.
var sheltered: bool = false

## The colony that released this fish, if any. Cosmetic for now — it tints the sprite
## so a shoal reads as belonging to a reef — but it is the hook a territorial fish
## would hang off later.
var faction: Faction

var _predators: Array[FishSpecies] = []
var _target: Vector2 = Vector2.ZERO
var _bounds: Rect2 = Rect2()
## Where the ground is. Fish used to swim through it: `_random_point` sampled the whole
## rectangle and `_clamp_to_bounds` only knew about the rectangle, so between 13% and 36%
## of every column — the part the backdrop paints as solid rock — was open water as far
## as the simulation was concerned. Nobody noticed while nothing else knew about the floor
## either. Optional, so a fish built without one behaves exactly as it always did.
var _seabed: Seabed
var _is_eaten: bool = false

@onready var sprite: Sprite2D = $Sprite2D

## Called by Aquarium immediately after instantiation, before the node enters
## the tree. `predators` is the derived reverse of every species' `eats` list.
func configure(fish_species: FishSpecies, predators: Array[FishSpecies], bounds: Rect2,
		start_age: float = -1.0, seabed: Seabed = null) -> void:
	species = fish_species
	_predators = predators
	_bounds = bounds
	_seabed = seabed
	_target = _random_point()
	# Seeded and restored fish arrive as adults of assorted ages; only a fish born in
	# the tank starts at zero, so a fresh tank is not a shoal of identical juveniles
	# that all mature and breed on the same frame.
	age = start_age if start_age >= 0.0 else randf_range(species.maturity, species.maturity * 2.0)
	_breed_timer = species.breed_cooldown
	_facing = Vector2.from_angle(randf_range(-PI, PI))

func _ready() -> void:
	if species == null:
		push_error("Fish added without a species; call configure() first.")
		return
	sprite.texture = species.texture
	_apply_size()
	_apply_faction_tint()

## Marks this fish as belonging to a faction, tinting it to match.
##
## A partial lerp toward the faction colour, not a modulate by it: the sprites are
## already coloured, and multiplying a clownfish by a saturated green leaves a dark
## smear that reads as neither clownfish nor green.
func set_faction(new_faction: Faction) -> void:
	faction = new_faction
	_apply_faction_tint()

func _apply_faction_tint() -> void:
	if sprite == null:
		return
	if faction == null:
		sprite.modulate = Color.WHITE
		return
	sprite.modulate = Color.WHITE.lerp(faction.color, 0.45)

func set_bounds(bounds: Rect2) -> void:
	_bounds = bounds

func set_seabed(seabed: Seabed) -> void:
	_seabed = seabed

## Advances this fish by `delta` seconds. `hash` must already contain every
## other fish in the tank for this frame.
func tick(delta: float, hash: SpatialHash, shelter: SpatialHash = null,
		food: SpatialHash = null) -> void:
	if _is_eaten:
		return

	age += delta
	_breed_timer = maxf(0.0, _breed_timer - delta)
	_tick_hunger(delta)
	_apply_size()

	var heading := _decide_heading(hash, shelter, food)
	if heading != Vector2.ZERO:
		global_position += heading * species.speed * delta
		_face(heading, delta)

	global_position = _clamp_to_bounds(global_position)

func _decide_heading(hash: SpatialHash, shelter: SpatialHash, food: SpatialHash = null) -> Vector2:
	var neighbours := hash.query_radius(global_position, species.sight, self)

	var nearest_threat: Fish = _nearest_of(neighbours, _predators)
	if nearest_threat != null:
		behaviour = Behaviour.FLEE
		# Already hidden: hold still rather than run.
		#
		# Fleeing while sheltered swam the fish straight out of its own cover and into
		# the open, where the predator could see it again — so a plant protected a fish
		# only until something threatened it, which is exactly when it was supposed to
		# work. A fish holding in the weeds is also what one actually does.
		if sheltered:
			behaviour = Behaviour.HIDE
			return Vector2.ZERO

		# Otherwise break for cover if any is in sight. Without this, plants would
		# shelter only the prey that happened to drift into one, and the player would
		# have no way to see that cover was doing anything.
		var refuge := _nearest_shelter(shelter)
		if refuge != null:
			return global_position.direction_to(refuge.global_position)
		return nearest_threat.global_position.direction_to(global_position)

	# Hungry and nothing chasing it: go for the nearest pellet. Checked after fleeing,
	# because a fish should not swim into a shark's mouth for a snack.
	if is_hungry():
		var pellet := _nearest_food(food)
		if pellet != null:
			behaviour = Behaviour.FEED
			if mouth_position().distance_to(pellet.global_position) <= BITE_DISTANCE + Food.RADIUS:
				pellet.be_eaten()
				feed()
				return Vector2.ZERO
			var aim := pellet.global_position - facing() * half_length()
			return global_position.direction_to(aim)

	var nearest_prey: Fish = _nearest_of(neighbours, species.eats)
	if nearest_prey != null:
		# Mouth to the prey's body, so a catch happens where it looks like one.
		var reach := BITE_DISTANCE + nearest_prey.half_length()
		if mouth_position().distance_to(nearest_prey.global_position) <= reach:
			nearest_prey.be_eaten()
			feed(1.0)
			behaviour = Behaviour.WANDER
			_target = _random_point()
			return Vector2.ZERO
		behaviour = Behaviour.HUNT
		# Steer so the MOUTH converges on the prey, not the centre. Aiming the centre
		# at prey means the mouth — half a body length ahead — sweeps past it on a
		# tangent and never closes: a lone chase then hung on a 0.2px margin, and in a
		# crowded tank, where the nearest target changes frame to frame, sharks stopped
		# catching anything at all.
		var aim := nearest_prey.global_position - facing() * half_length()
		return global_position.direction_to(aim)

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
		# Prey inside cover is invisible to whatever hunts it. Checked here rather than
		# at the bite, so a shark does not swim to a plant and wait beside it.
		if other.sheltered and wanted == species.eats:
			continue
		var d := global_position.distance_squared_to(other.global_position)
		if d < best_distance_sq:
			best_distance_sq = d
			best = other
	return best

## Half the fish's drawn length, in world units. Accounts for growth, since a juvenile
## is drawn smaller and should have a correspondingly shorter reach.
func half_length() -> float:
	if sprite == null or sprite.texture == null:
		return 0.0
	return sprite.texture.get_size().x * absf(sprite.scale.x) * 0.5

## The direction the fish is pointing, in world space. Continuous by construction.
func facing() -> Vector2:
	return _facing

## World position of the fish's mouth: the front of the drawn sprite.
func mouth_position() -> Vector2:
	return global_position + facing() * half_length()

func _tick_hunger(delta: float) -> void:
	if species.hunger_time <= 0.0:
		return
	fullness = maxf(0.0, fullness - delta / species.hunger_time)
	if fullness > 0.0:
		_starving_for = 0.0
		return
	_starving_for += delta

func is_hungry() -> bool:
	return species.hunger_time > 0.0 and fullness < species.hungry_below

## Whether the fish has been empty long enough to die of it.
func is_starved() -> bool:
	return species.starve_time > 0.0 and _starving_for > species.starve_time

func feed(amount: float = 0.5) -> void:
	fullness = minf(1.0, fullness + amount)
	_starving_for = 0.0

func _nearest_food(food: SpatialHash) -> Food:
	if food == null:
		return null
	var best: Food = null
	var best_distance_sq := INF
	for node: Node2D in food.query_radius(global_position, species.sight, null):
		var pellet := node as Food
		if pellet == null or pellet.is_eaten():
			continue
		var d := global_position.distance_squared_to(pellet.global_position)
		if d < best_distance_sq:
			best_distance_sq = d
			best = pellet
	return best

## A fish is grown at `maturity` and no smaller than a third of adult size at birth.
func growth() -> float:
	if species.maturity <= 0.0:
		return 1.0
	return clampf(0.34 + 0.66 * (age / species.maturity), 0.34, 1.0)

## Seconds until this fish could breed again.
func breed_wait() -> float:
	return _breed_timer

func is_mature() -> bool:
	return age >= species.maturity

## Whether this fish could pair right now, ignoring whether a partner is nearby.
func can_breed() -> bool:
	return (not _is_eaten) and species.breed_distance > 0.0 and is_mature() and _breed_timer <= 0.0

## Hunger does not kill; it slows breeding.
##
## Starvation would punish an ambient app for the thing ambient apps are for — being
## left alone — and a tank that dies out while nobody is watching is a tank nobody comes
## back to. A hungry fish still breeds, just half as often, so feeding is a reward for
## attention rather than a tax on absence.
func note_bred() -> void:
	_breed_timer = species.breed_cooldown * (2.0 if is_hungry() else 1.0)

func is_past_lifespan() -> bool:
	return species.lifespan > 0.0 and age > species.lifespan

## The nearest sheltering plant within sight, or null.
func _nearest_shelter(shelter: SpatialHash) -> Decor:
	if shelter == null:
		return null
	var best: Decor = null
	var best_distance_sq := INF
	for node: Node2D in shelter.query_radius(global_position, species.sight, null):
		var item := node as Decor
		if item == null:
			continue
		var d := global_position.distance_squared_to(item.global_position)
		if d < best_distance_sq:
			best_distance_sq = d
			best = item
	return best

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
	# Turn the true facing first, at a bounded rate, then derive the sprite from it.
	var max_turn := deg_to_rad(TURN_RATE) * delta
	_facing = _facing.rotated(clampf(_facing.angle_to(heading), -max_turn, max_turn)).normalized()

	var angle := _facing.angle()
	var facing_left := absf(wrapf(angle, -PI, PI)) > PI / 2.0
	sprite.flip_h = not facing_left
	var desired := wrapf(angle + PI, -PI, PI) if facing_left else angle
	var limit := deg_to_rad(PITCH_LIMIT)
	sprite.rotation = clampf(desired, -limit, limit)

func _apply_size() -> void:
	if sprite.texture == null:
		return
	var texture_size := sprite.texture.get_size()
	if texture_size.y <= 0.0:
		return
	var scale_factor := species.size * growth() / texture_size.y
	sprite.scale = Vector2(scale_factor, scale_factor)

## Keeps a fish inside the tank AND out of the ground.
##
## The rectangle first, then the floor: the floor is sampled at the clamped x, so a fish
## pushed sideways at the map's edge is seated against the ground that is actually there
## rather than against the ground under where it used to be.
func _clamp_to_bounds(point: Vector2) -> Vector2:
	var margin := species.size * 0.5
	var inside := Vector2(
		clampf(point.x, _bounds.position.x + margin, _bounds.end.x - margin),
		clampf(point.y, _bounds.position.y + margin, _bounds.end.y - margin),
	)
	if _seabed == null:
		return inside
	return _seabed.lift_out_of_rock(inside, margin)

func _random_point() -> Vector2:
	var margin := species.size * 0.5 if species != null else 0.0
	if _seabed != null:
		return _seabed.random_water_point(margin)
	return Vector2(
		randf_range(_bounds.position.x + margin, _bounds.end.x - margin),
		randf_range(_bounds.position.y + margin, _bounds.end.y - margin),
	)
