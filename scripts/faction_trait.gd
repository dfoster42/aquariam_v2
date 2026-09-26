class_name FactionTrait
extends Resource
## One node of a faction's tech tree: what earns it, and what it changes.
##
## Same contract as everything else here — one .tres per trait, no code per trait. A
## faction lists its traits in `Faction.tech`; `requires` links them into a tree.
##
## Everything a trait is earned by is something the simulation already measures, and
## everything it does is a multiplier on a stat the simulation already has. That is on
## purpose: an unlock the player cannot SEE is a number changing in a menu, and the point
## of these is a column visibly climbing, or a reef shrugging off a bleach that would have
## killed it an hour earlier.

enum Condition {
	## The faction holds at least `threshold` of the sea, continuously for `hold_for`.
	HOLD_SHARE,
	## The faction has at least `threshold` living colonies, continuously for `hold_for`.
	COLONIES,
	## A colony of the faction was hit by a disaster and lived. An event: `hold_for` is
	## ignored. The one condition that rewards being attacked rather than winning.
	SURVIVE_DISASTER,
	## The faction has colonies in at least `threshold` distinct basins, for `hold_for`.
	HOLD_BASINS,
}

@export var display_name: String = "Trait"
## One line shown when it is earned. Say what the player will see change.
@export var description: String = ""
## Must already be earned before this one can be. Null for a root of the tree.
@export var requires: FactionTrait

@export_group("Earned by")
@export var condition: Condition = Condition.HOLD_SHARE
@export var threshold: float = 0.1
## Seconds the condition must hold without a break.
@export_range(0.0, 600.0, 1.0) var hold_for: float = 20.0

@export_group("Effect")
@export var capacity_mul: float = 1.0
@export var growth_mul: float = 1.0
@export var reach_mul: float = 1.0
@export var grip_mul: float = 1.0
## Below 1 is faster budding.
@export var spread_interval_mul: float = 1.0
@export var band_thickness_mul: float = 1.0
## Below 1 bleeds out more slowly over open ground.
@export var decay_mul: float = 1.0
## Fraction of any disaster's damage that is ignored. Adds across traits, capped.
@export_range(0.0, 0.9, 0.05) var hardness: float = 0.0
## Earning this lets the faction rise: a thriving colony releases the faction's
## `ascends_to` into open water. The tech tree deciding when a new faction can appear.
@export var enables_ascent: bool = false
