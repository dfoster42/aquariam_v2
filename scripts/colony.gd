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
## Asks the tank for deeper ground to put a successor faction on. Same division of
## labour: the colony knows it is losing, only the tank knows what ground exists.
signal descending(colony: Colony, successor: Faction)
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
## How far a benthic claim is allowed to reach BELOW its own anchor, in world units.
##
## Not zero: the floor curve is sampled per cell centre and a colony is rooted at one x,
## so on a gradient the cell the colony stands in can have its centre slightly below the
## anchor. Without a little slack the colony fails to claim the ground it is sitting on.
const CRUST_DEPTH: float = 40.0

## Seconds a wound takes to drain out of a colony.
##
## Destruction used to be instantaneous: `damage()` subtracted, the colony fell below
## MIN_BIOMASS in the same call, and the territory pass a quarter-second later simply
## showed a different owner. So there was no moment of destruction to look at — the frame
## captured right after a disaster was indistinguishable from the frame two minutes
## later, and the game's central verb had no visual payoff at all. A wound now drains
## over this long, which makes the colony's claim RETREAT rather than vanish, because
## influence is proportional to biomass and the territory pass runs four times a second
## throughout.
const DRAIN_DURATION: float = 1.4

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

## World y of the ground this colony is rooted to. Benthic colonies extrude their claim
## upward from here; a pelagic colony ignores it.
var anchor_y: float = 0.0

## PELAGIC only: whether a benthic claim currently sits beneath it. Written by the tank
## after each territory pass, for the same reason `pressure` is — the colony cannot see
## the map, and the answer is the same for every cell it occupies.
var supported: bool = true

var _fish_debt: float = 0.0
var _spread_timer: float = 0.0
var _descend_timer: float = 0.0
## Biomass a disaster has taken but that has not yet drained away. Damage is a WOUND,
## not a subtraction — see `damage()`.
var _draining: float = 0.0
var _drain_rate: float = 0.0
var _dead: bool = false

@onready var sprite: Sprite2D = $Sprite2D

func configure(colony_faction: Faction, start_biomass: float = -1.0,
		ground_y: float = 0.0) -> void:
	faction = colony_faction
	biomass = start_biomass if start_biomass > 0.0 else SEED_BIOMASS
	anchor_y = ground_y

func is_benthic() -> bool:
	return faction == null or faction.claim == Faction.Claim.BENTHIC

func _ready() -> void:
	if faction == null:
		push_error("Colony added without a faction; call configure() first.")
		return
	# A shoal has no structure. By definition a pelagic faction "owns a band of open
	# water and nothing permanent", so drawing it as a rooted anemone contradicted the
	# rule it is built on — and it put the floating anemones back in the middle of the
	# ocean, which is the exact thing seating the colonies was meant to fix. Its claim
	# is the band, and the fish it releases are what you actually see.
	sprite.visible = is_benthic()
	if not sprite.visible:
		return
	_apply_tint()
	_apply_size()

## The colony's colour, bleached toward bone while a disaster is draining through it.
##
## Additive-ish tint rather than a flat modulate: the artwork is a dark anemone and a
## straight multiply by a saturated colour turns every faction into the same near-black
## smudge. The bleach is what makes a dying reef legible as dying rather than as merely
## smaller — size alone is not readable over a second and a half.
func _apply_tint() -> void:
	if sprite == null or not sprite.visible or faction == null:
		return
	var base := faction.color.lerp(Color.WHITE, 0.25)
	if _draining <= 0.0:
		sprite.modulate = base
		return
	var severity := clampf(_draining / maxf(biomass + _draining, 1.0), 0.0, 1.0)
	sprite.modulate = base.lerp(Color(0.92, 0.94, 0.9), severity * 0.85)

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

	_tick_drain(delta)
	if _dead:
		return

	var ceiling := faction.capacity * maxf(pressure, MIN_PRESSURE)
	if ceiling > 0.0:
		biomass += faction.growth_rate * biomass * (1.0 - biomass / ceiling) * delta
	# A shoal over open ground has nothing holding it up. Not instant death: it thins
	# visibly, so striking the reef beneath a pelagic faction reads as a cause and the
	# shoal's decline reads as the effect, several seconds apart and on different parts
	# of the screen.
	if not is_benthic() and not supported:
		biomass -= faction.decay_unsupported * delta
	biomass = maxf(biomass, 0.0)
	_apply_size()

	if biomass < MIN_BIOMASS:
		_die()
		return

	_tick_spread(delta)
	_tick_descent(delta)

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
	# Sideways only, and clear of its own claim. Benthic factions walk the seabed and
	# pelagic ones run along their band, so neither has anywhere to go but left or right
	# — the vertical axis is earned by growing, not by budding.
	#
	# The gap must exceed Territory.REACH, or a daughter is founded inside the parent's
	# own claim and the two spend the rest of their lives taking cells off each other.
	# At 1.2 extents they overlapped almost completely: measured, a faction that spread
	# well ended up with eleven colonies averaging 29 biomass against a capacity of 120,
	# every one of them stunted by its own siblings.
	var step := extent().x * (Territory.REACH + 0.6) * (1.0 if randf() < 0.5 else -1.0)
	spreading.emit(self, global_position + Vector2(step, 0.0))

## Looks for deeper ground once this colony is being beaten where it is.
##
## Gated on pressure rather than on biomass alone: a colony holding its ground has no
## reason to go anywhere, and tying the descent to being squeezed means the player's
## attacks cause it. Strike a shelf faction hard enough and its answer is to reach down
## into the ravines.
func _tick_descent(delta: float) -> void:
	if faction.descends_to == null or faction.descend_interval <= 0.0:
		return
	_descend_timer += delta
	if _descend_timer < faction.descend_interval:
		return
	_descend_timer = 0.0
	if pressure > faction.descend_at:
		return
	# It has to be able to afford the journey. A colony already at the floor of its own
	# collapse cannot also found a colony somewhere else.
	if biomass - faction.descend_cost < MIN_BIOMASS:
		return
	descending.emit(self, faction.descends_to)

## Pays for a descent. Returns what the deeper colony should start with, or 0.
func pay_to_descend() -> float:
	var cost := faction.descend_cost
	if _dead or cost <= 0.0 or biomass - cost < MIN_BIOMASS:
		return 0.0
	biomass -= cost
	_apply_size()
	return cost

## The colony's base scale, in world units. Area scales with biomass, so doubling the
## biomass widens it by about 40% rather than doubling it — a colony that grew tenfold
## would otherwise span the map. `extent()` shapes this per claim kind.
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
	return influence_for(offset.x, offset.y, biomass, reach.x, reach.y, is_benthic())

## The claim kernel, as plain floats.
##
## Static and argument-only so Territory's rebuild can call it without an instance lookup
## and without building a Vector2 per cell. Measured before: the rebuild cost ~900 ns for
## every cell it looked at, which is roughly ten times the arithmetic in it — the rest was
## interpreter overhead, and a dynamic method call per cell was most of it.
##
## One definition. `influence_at` is the readable wrapper and delegates here, so the
## formula cannot drift between the two callers.
static func influence_for(dx: float, dy: float, mass: float, ex: float, ey: float,
		benthic: bool) -> float:
	var width := ex
	var vertical := 1.0
	if benthic:
		# Height above the ground this colony is rooted to. Nothing below the floor is
		# claimable — Territory's water mask enforces that too, but a claim that bled
		# into the rock is exactly what read as a view from above.
		var height := -dy
		if height < -CRUST_DEPTH:
			return 0.0
		var t := clampf(height / maxf(ey, 1.0), 0.0, 1.0)
		# The column NARROWS as it rises. Without this a benthic claim is a rectangle:
		# full-width lateral falloff all the way up to a flat lid, which drew as a
		# coloured block standing on the seabed. A reef is widest where it is attached.
		width = ex * lerpf(1.0, 0.42, t * t)
		# Full strength from the floor to the column's cap, then a soft lid — a
		# deliberate flat top rather than the accidental one a clipped circle produced.
		vertical = 1.0 - smoothstep(0.52, 1.0, t)
	else:
		# A pelagic band: strength across its thickness, nothing outside it. The vertical
		# fade runs over most of the half-thickness rather than its outer sliver, because
		# a band that fades over one cell draws as a painted bar.
		vertical = 1.0 - smoothstep(0.35, 1.0, absf(dy) / maxf(ey, 1.0))
	if vertical <= 0.0:
		return 0.0

	# Two colonies meet where their biomasses balance, so a big reef pushes its border
	# into a small neighbour's ground rather than splitting the difference.
	var sx := dx / maxf(width, 1.0)
	var falloff := mass / (1.0 + sx * sx)
	# Tapered to nothing at the edge of the searched box, or the box IS the claim's
	# shape. The fade STARTS early — at about a third of the way out — because where it
	# begins is free while how far the box reaches is not: REACH was cut from 2.4 to 1.7
	# for the rebuild's sake, which narrowed the fade band with it and put the hard-edged
	# rectangles back. Moving the start recovers the soft edge at no cost. Territory only visits cells within REACH extents, and an inverse square has
	# not decayed anywhere near the claim threshold by then: measured at biomass 130 the
	# influence at the box edge was still 19 against a threshold of 3, so every mature
	# territory was a hard-edged rectangle the size of its search box.
	return falloff * vertical * smoothstep(1.0, 0.35, absf(sx) / Territory.REACH)

## The region, relative to this colony, in which its influence can be non-zero.
##
## Territory used to bound its search at `extent * REACH` on both axes, which is right
## laterally — the inverse-square tail lives out there — and badly wrong vertically,
## because a claim is HARD zero above its lid and below the floor. A vent with a
## 1900-unit column was having 4560 units of water scanned for it, the whole height of
## the map, almost all of it cells it could never claim. Measured before this: 40
## colonies cost 93.5 ms a rebuild at a 36-unit cell, which at four passes a second is
## 37% of the machine.
func reach_box() -> Rect2:
	var reach := extent()
	var half_width := reach.x * Territory.REACH
	if is_benthic():
		# Up to the lid, and only a crust's depth below the anchor.
		return Rect2(-half_width, -reach.y, half_width * 2.0, reach.y + CRUST_DEPTH)
	return Rect2(-half_width, -reach.y, half_width * 2.0, reach.y * 2.0)

## How far this colony reaches on each axis, in world units.
##
## Width and height come from different places on purpose. Width is earned by growing and
## is zero-sum — the seabed is 3240 units long and every unit gained is a unit someone
## lost. Height is capped by what the faction IS, so a reef never becomes a kelp forest.
func extent() -> Vector2:
	var r := radius()
	if faction == null:
		return Vector2(r, r)
	if is_benthic():
		return Vector2(r * faction.floor_grip, _column_height())
	return Vector2(r * faction.band_spread, faction.band_thickness * 0.5)

## How high the column of water above this colony's floor currently rises.
##
## Scales with how full the colony is, so a reef given room grows TALLER as well as
## wider — which is the second beat of the clip: the neighbours slide sideways into a
## dead interval, and then their flat tops rise.
func _column_height() -> float:
	if faction == null or faction.capacity <= 0.0:
		return BASE_RADIUS
	var fullness := clampf(biomass / faction.capacity, 0.0, 1.0)
	return faction.reach_up * lerpf(0.28, 1.0, sqrt(fullness))


## Pays for a daughter colony. Returns what the daughter should start with, or 0 when
## the parent cannot afford it after all.
func pay_to_spread() -> float:
	var cost := faction.spread_cost
	if _dead or cost <= 0.0 or biomass - cost < MIN_BIOMASS:
		return 0.0
	biomass -= cost
	_apply_size()
	return cost

## Wounds the colony for `amount`, to drain away over DRAIN_DURATION. Returns how much
## will actually be lost, so a caller can report what a disaster did.
##
## Deliberately not an immediate subtraction. A reef that dies between one frame and the
## next cannot be watched dying, and watching it is the entire point of a god power.
func damage(amount: float) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var takeable := minf(amount, maxf(biomass - _draining, 0.0))
	if takeable <= 0.0:
		return 0.0
	_draining += takeable
	_drain_rate = _draining / DRAIN_DURATION
	return takeable

## Bleeds out whatever a disaster has taken but not yet removed.
func _tick_drain(delta: float) -> void:
	if _draining <= 0.0:
		return
	var step := minf(_draining, _drain_rate * delta)
	_draining -= step
	biomass = maxf(0.0, biomass - step)
	_apply_size()
	_apply_tint()
	if biomass < MIN_BIOMASS:
		_draining = 0.0
		_die()

## Whether a disaster is still working through this colony.
func is_dying() -> bool:
	return _draining > 0.0

func is_dead() -> bool:
	return _dead

func _die() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self)

func _apply_size() -> void:
	if sprite == null or sprite.texture == null or not sprite.visible:
		return
	var texture_size := sprite.texture.get_size()
	if texture_size.y <= 0.0:
		return
	# Drawn at a fraction of the ground it claims: the territory wash is what shows the
	# reach, and a sprite scaled to the full radius would bury the fish under coral.
	var drawn := radius() * 0.85
	var scale_factor := drawn / texture_size.y
	sprite.scale = Vector2(scale_factor, scale_factor)
