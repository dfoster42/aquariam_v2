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

## BENTHIC: whether this faction belongs in a basin or out on the open floor.
##
## A two-way gate, and the thing that makes the terrain the board rather than the
## wallpaper. The three basins already drawn into the backdrop become the only ground a
## vent faction can take, and ground no shelf faction can take — so a lineage that works
## its way down into one has somewhere that is genuinely its own.
##
## It weights the CLAIM as well as gating the founding. Gating founding alone left a
## shelf colony beside a basin projecting across it at full strength, and a descended
## beachhead arrived under a rival's full weight and never established.
##
## Weights the claim, not just where it may be founded. Substrate used to gate founding
## only, so a shelf faction rooted beside a basin still projected at full strength across
## it — ground it is forbidden to occupy — and a lineage that had worked its way down
## into that basin arrived as a beachhead under a rival's full weight and never
## established.
##
## Keyed on CARVING rather than on depth, because the two are not the same thing here:
## the basin at x=1847 sits at 0.71 of map height while the uncarved floor at x=0 is at
## 0.87. A depth rule hands a shelf faction two of the three basins.
@export var likes_ravines: bool = false



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

@export_group("Tech")
## The faction's tech tree. Each trait may name another it `requires`; the roots are the
## ones that do not. Order only matters for display.
@export var tech: Array[FactionTrait] = []

@export_group("Descent")
## Whether the player may found this faction directly.
##
## False for anything meant to be EARNED. The deepest ground on the map — the three
## ravines — was a picker tile like any other, which made the most restricted real estate
## in the game the cheapest thing to acquire. A faction that can only be reached by a
## lineage working its way down to it is a destination; one you can tap onto is scenery.
@export var placeable: bool = true

## What this faction becomes when it goes deeper. Null means it is the end of its line.
@export var descends_to: Faction

## Pressure below which a colony starts looking for deeper ground.
##
## Descent is driven by LOSING. A faction holding its own has no reason to leave, and
## making the player's attacks the cause of the descent is worth more than a timer: you
## strike a shelf faction and it answers by colonising the deep you were keeping empty.
@export_range(0.0, 1.0, 0.05) var descend_at: float = 0.3

## Seconds between attempts, once a colony is losing.
@export_range(0.0, 300.0, 1.0) var descend_interval: float = 18.0

## Biomass the parent spends founding the deeper colony, which starts with it. The parent
## survives — a lineage reaches down, it does not migrate.
@export_range(1.0, 200.0, 1.0) var descend_cost: float = 22.0

@export_group("Ascent")
## What this faction releases into open water when it rises. Null means it does not.
##
## The mirror of `descends_to`, and deliberately its opposite in cause: a lineage reaches
## DOWN because it is losing, and rises because it is thriving. Gated by the tech tree —
## nothing ascends until it has earned a trait that `enables_ascent`.
@export var ascends_to: Faction

## Pressure at or above which a colony may rise: only a colony holding its ground does.
@export_range(0.0, 1.0, 0.05) var ascend_at: float = 0.7

## Seconds between a colony's attempts to rise.
@export_range(0.0, 300.0, 1.0) var ascend_interval: float = 20.0

## Biomass the parent spends on it; the risen colony starts with it.
@export_range(1.0, 200.0, 1.0) var ascend_cost: float = 18.0

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
