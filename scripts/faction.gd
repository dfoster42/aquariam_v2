class_name Faction
extends Resource
## A reef faction: a colour on the map, and the fish that belong to it.
##
## Same contract as FishSpecies and DecorKind — one .tres per faction, dropped into an
## exported array, no code per faction.
##
## This is the thing the tank was missing. Fish are transient: one spawns, breeds, is
## eaten, and the tank afterwards is indistinguishable from the tank before. A faction
## holds ground, and ground is state that accumulates — which is what makes destroying
## it mean anything.

@export var display_name: String = "Reef"
## Paints this faction's territory on the map, and tints the fish that belong to it.
## Wants to be saturated: it is read as a region of colour at a distance, not as a
## surface under good light.
@export var color: Color = Color(0.95, 0.45, 0.2)
## What this faction's colonies release into the water. Null means the faction holds
## ground but never spawns anything.
@export var species: FishSpecies

## How a faction holds water.
##
## The rule the whole scheme turns on: **water is only claimable above ground you hold.**
## A benthic faction owns an interval of the seabed and extrudes a column of water upward
## from it. Everything above the tallest column is a commons, and only a pelagic faction
## lives there — but a pelagic faction with no benthic claim beneath it bleeds out. So the
## open ocean is genuinely open, genuinely valuable, and genuinely indefensible.
enum Claim {
	## Rooted on the floor. Owns a stretch of seabed and the water above it.
	BENTHIC,
	## Owns a band of open water and nothing permanent. Needs a benthic neighbour below.
	PELAGIC,
}

@export_group("Claim")
@export var claim: Claim = Claim.BENTHIC

## BENTHIC: how wide a stretch of seabed the colony grips, as a multiple of its radius.
##
## Width and height are earned by different actions and are both legible without any UI:
## a faction's strength is a rectangle — how much floor it holds by how high it reaches.
@export_range(0.2, 8.0, 0.1) var floor_grip: float = 2.6

## BENTHIC: how far the column of water above the held floor rises, in world units, once
## the colony is at capacity. A young reef's column is short and grows with it, so a
## faction that has just been given room visibly gets TALLER as well as wider.
##
## The shipped water column is 1380-1871 units deep depending on x, so 450 is a reef and
## 1300 is a vent chimney that reaches the surface from the bottom of a ravine.
@export_range(60.0, 2200.0, 10.0) var reach_up: float = 450.0

## BENTHIC: the stretch of floor this faction can be founded on, as a fraction of map
## height — so (0.0, 1.0) is anywhere and (0.0, 0.82) is the shelf but not the deeps.
@export var floor_depth_range: Vector2 = Vector2(0.0, 1.0)

## BENTHIC: world units of ravine carving the ground must have for this faction to take
## it. Above 0, the faction can only be founded inside a basin.
##
## This is what makes the terrain the board rather than the wallpaper: the three ravines
## already drawn into the backdrop become the only ground a vent faction can hold — a few
## hundred units of a 3240-unit seabed — and because they are the deepest ground on the
## map, a column rising out of one reaches higher than anything else in the game.
##
## Checked against carving rather than against depth, because depth cannot tell a basin
## from the landform's own low ground: the floor at x=0 is deeper than two of the three
## ravines and is not a ravine at all.
@export_range(0.0, 200.0, 5.0) var requires_ravine: float = 0.0

## PELAGIC: the depth its band sits at, as a fraction of map height.
@export_range(0.0, 1.0, 0.01) var altitude: float = 0.24

## PELAGIC: how thick that band is, in world units.
@export_range(60.0, 1200.0, 10.0) var band_thickness: float = 280.0

## PELAGIC: how wide the band runs, as a multiple of the colony's radius.
@export_range(0.5, 10.0, 0.1) var band_spread: float = 3.2

## PELAGIC: biomass lost per second while no benthic claim sits beneath it.
##
## Not instant death — a drifting shoal should have time to be somewhere else by the time
## the player notices, and a pelagic faction whose supporting reef is struck should visibly
## thin rather than blink out.
@export_range(0.0, 20.0, 0.1) var decay_unsupported: float = 2.2

@export_group("Growth")
## Biomass a colony of this faction tends toward when nothing is pressing on it.
@export_range(10.0, 1000.0, 5.0) var capacity: float = 130.0
## Per-second logistic growth rate. 0.05 roughly doubles a young colony in 15 seconds,
## which is slow enough to watch happen and fast enough to be worth watching.
@export_range(0.001, 1.0, 0.001) var growth_rate: float = 0.05
## Biomass gained per colony before it releases one fish.
@export_range(5.0, 500.0, 5.0) var biomass_per_fish: float = 26.0

@export_group("Spread")
## Seconds between attempts to found a daughter colony.
##
## Colonies that only grow in place never fill the map, and a map that is mostly open
## water has no borders — so a strike deletes a reef and leaves a hole nobody wants.
## Measured: three reefs left to grow held 12.8% each with 61.8% open water between
## them, and striking one moved the survivors by 0.2 points. Spreading is what turns a
## set of separate objects into a map worth fighting over.
@export_range(0.0, 300.0, 1.0) var spread_interval: float = 14.0
## Fraction of capacity a colony must hold before it can spread at all.
@export_range(0.1, 1.0, 0.05) var spread_at: float = 0.55
## Biomass the parent spends founding a daughter. The daughter starts with it, so
## spreading moves mass rather than creating it.
@export_range(1.0, 200.0, 1.0) var spread_cost: float = 14.0
