class_name Colony
extends Node2D
## One reef colony: a faction's foothold on the map.
##
## A colony is the tank's first PERSISTENT object. A fish is a transient — it swims,
## breeds, is eaten, and nothing about the tank is different afterwards. A colony
## accumulates: it grows, it claims ground, it holds that ground against neighbours,
## and every second it survives makes it a larger thing to lose. That asymmetry is the
## whole point of the prototype — destruction is only legible when it destroys
## something that took time to build.
##
## Colonies do not drive themselves. Aquarium owns the frame loop and calls tick(), for
## the same reason fish do not: one loop, one rebuild of the shared grids per frame.

signal released(colony: Colony, position: Vector2)
## Asks the tank to found a daughter colony at `position`. The tank decides — it is the
## only thing that knows whether that ground is already owned.
signal spreading(colony: Colony, position: Vector2)
signal died(colony: Colony)

## Below this a colony is rubble and is cleared. Not zero: a colony asymptotically
## approaching zero would linger forever as an invisible claim on the map.
const MIN_BIOMASS: float = 3.0
## Radius in world units of a colony holding `REFERENCE_BIOMASS`. Everything else
## scales from here.
const BASE_RADIUS: float = 140.0
const REFERENCE_BIOMASS: float = 12.0
## Biomass a colony is founded with.
const SEED_BIOMASS: float = 12.0
## How hard being hemmed in bites. A colony that owns none of the ground it reaches
## for still grows at this fraction of its rate, so a besieged colony stalls rather
## than dying of geometry alone.
const MIN_PRESSURE: float = 0.12

var faction: Faction
## The accumulating quantity. Drives radius, territory, and how much there is to lose.
var biomass: float = SEED_BIOMASS
## Fraction of the ground within reach that this colony actually owns, 0..1. Written
## by Aquarium after each territory pass; competition is expressed through this rather
## than through a separate combat step, so what throttles a colony is exactly what the
## player can see on the map.
var pressure: float = 1.0
## Seconds lived. Not used for death — colonies die by damage, not age — but it is what
## makes "a colony you have had for six minutes" a different thing from a fresh one.
var age: float = 0.0

var _fish_debt: float = 0.0
var _spread_timer: float = 0.0
var _dead: bool = false

@onready var sprite: Sprite2D = $Sprite2D

func configure(colony_faction: Faction, start_biomass: float = -1.0) -> void:
	faction = colony_faction
	biomass = start_biomass if start_biomass > 0.0 else SEED_BIOMASS

func _ready() -> void:
	if faction == null:
		push_error("Colony added without a faction; call configure() first.")
		return
	# Additive-ish tint rather than a flat modulate: the artwork is a dark anemone and
	# a straight multiply by a saturated colour turns every faction into the same
	# near-black smudge.
	sprite.modulate = faction.color.lerp(Color.WHITE, 0.25)
	_apply_size()

## Advances the colony. `delta` is already clamped by the caller.
##
## Growth is logistic against a capacity scaled by how much ground the colony actually
## holds. A colony with room runs to its faction's capacity; one boxed in by neighbours
## stalls at a fraction of it. Kill the neighbour and both halves of the payoff land at
## once: the territory floods into the vacuum, and the survivor starts growing again.
func tick(delta: float) -> void:
	if _dead or faction == null:
		return
	age += delta

	var ceiling := faction.capacity * maxf(pressure, MIN_PRESSURE)
	if ceiling > 0.0:
		biomass += faction.growth_rate * biomass * (1.0 - biomass / ceiling) * delta
	biomass = maxf(biomass, 0.0)
	_apply_size()

	if biomass < MIN_BIOMASS:
		_die()
		return

	_tick_spread(delta)

	if faction.species == null or faction.biomass_per_fish <= 0.0:
		return
	# Release is paid for out of growth, not out of standing biomass: a colony that has
	# stalled stops restocking the water, which is what makes a besieged reef read as
	# besieged rather than merely smaller.
	_fish_debt += faction.growth_rate * biomass * maxf(pressure, MIN_PRESSURE) * delta
	if _fish_debt >= faction.biomass_per_fish:
		_fish_debt -= faction.biomass_per_fish
		released.emit(self, global_position)

## Tries to push a daughter colony outward once the parent is established and has room.
##
## Gated on pressure as well as biomass: a colony hemmed in by neighbours has nowhere to
## put one, and a reef that keeps flinging daughters into ground it has already lost
## bleeds mass it needs to hold the ground it has.
func _tick_spread(delta: float) -> void:
	if faction.spread_interval <= 0.0 or faction.spread_cost <= 0.0:
		return
	_spread_timer += delta
	if _spread_timer < faction.spread_interval:
		return
	_spread_timer = 0.0
	if biomass < faction.capacity * faction.spread_at or pressure < 0.5:
		return
	# Just beyond its own edge: close enough that the daughter's territory joins the
	# parent's rather than stranding an island, far enough that it is new ground.
	var offset := Vector2.from_angle(randf_range(-PI, PI)) * radius() * 1.35
	spreading.emit(self, global_position + offset)

## How far this colony reaches, in world units. Area scales with biomass, so doubling
## the biomass widens the reach by about 40% rather than doubling it — a colony that
## grew tenfold would otherwise span the map.
func radius() -> float:
	return BASE_RADIUS * sqrt(maxf(biomass, 1.0) / REFERENCE_BIOMASS)

## What this colony projects at `offset` — a vector FROM the colony TO the point.
##
## Takes the whole offset rather than a scalar distance, which is the one change that
## lets a claim be any shape but a circle. Territory already computed the vector and
## threw the direction away on the next line; an isotropic claim is a top-down idiom and
## in a side view it reads as a disc of colour floating in open water, so the direction
## is exactly the information that was missing.
##
## Still falls off as an inverse square, now in units of the colony's per-axis extent, so
## two colonies meet where their biomasses balance rather than at a fixed midpoint — a
## big reef pushes its border into a small neighbour's ground.
func influence_at(offset: Vector2) -> float:
	var reach := extent()
	var sx := offset.x / maxf(reach.x, 1.0)
	var sy := offset.y / maxf(reach.y, 1.0)
	var influence := biomass / (1.0 + sx * sx + sy * sy)

	# Taper to nothing at the edge of the searched box, or the box IS the claim's shape.
	#
	# Territory only visits cells within REACH extents, and an inverse square has not
	# decayed anywhere near the claim threshold by then: measured at biomass 130, the
	# influence at the box edge was still 19 against a MIN_CLAIM of 3, so every mature
	# colony's territory was a hard-edged RECTANGLE the size of its search box. It read
	# as blocks of colour stacked on the seabed. Fading over the outer quarter puts the
	# claim's boundary back where the falloff says it should be.
	var q := sqrt(sx * sx + sy * sy) / Territory.REACH
	return influence * smoothstep(1.0, 0.72, q)

## How far this colony reaches on each axis, in world units.
##
## `radius()` scaled by the faction's `shape`. A faction with shape (1, 1) claims the
## disc it always did; anything else claims an ellipse, which is what a reef hugging the
## floor or a plume rising off a vent actually looks like.
func extent() -> Vector2:
	var r := radius()
	var shape := faction.shape if faction != null else Vector2.ONE
	return Vector2(r * maxf(shape.x, 0.01), r * maxf(shape.y, 0.01))

## Pays for a daughter colony. Returns what the daughter should start with, or 0 when
## the parent cannot afford it after all.
func pay_to_spread() -> float:
	var cost := faction.spread_cost
	if _dead or cost <= 0.0 or biomass - cost < MIN_BIOMASS:
		return 0.0
	biomass -= cost
	_apply_size()
	return cost

## Takes `amount` off the colony. Returns how much was actually removed, so a caller
## can report what a strike did.
func damage(amount: float) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var before := biomass
	biomass = maxf(0.0, biomass - amount)
	_apply_size()
	if biomass < MIN_BIOMASS:
		_die()
	return before - biomass

func is_dead() -> bool:
	return _dead

func _die() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self)

func _apply_size() -> void:
	if sprite == null or sprite.texture == null:
		return
	var texture_size := sprite.texture.get_size()
	if texture_size.y <= 0.0:
		return
	# Drawn at a fraction of the ground it claims: the territory wash is what shows the
	# reach, and a sprite scaled to the full radius would bury the fish under coral.
	var drawn := radius() * 0.85
	var scale_factor := drawn / texture_size.y
	sprite.scale = Vector2(scale_factor, scale_factor)
