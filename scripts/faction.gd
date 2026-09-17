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

@export_group("Claim")
## Per-axis multiplier on a colony's reach: (lateral, vertical).
##
## (1, 1) is the circular claim the prototype shipped with, which is a top-down idiom —
## measured, a mature colony's claim was a 922-unit disc inside a 1384-unit water column,
## so it was geometrically incapable of reading as anything but a view from above.
## Anisotropy is what lets a claim be a crust along the floor (say (3.4, 0.3)) or a plume
## rising off a vent ((0.55, 2.6)).
@export var shape: Vector2 = Vector2.ONE

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
