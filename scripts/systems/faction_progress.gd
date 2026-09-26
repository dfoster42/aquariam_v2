class_name FactionProgress
extends RefCounted
## How far one faction has come in one tank: which traits it has earned, and how close
## it is to the next.
##
## Colonies read their stats through this rather than straight off the Faction resource,
## because a Faction is shared by every tank and every save — it is what the faction IS —
## while progress belongs to one faction's history in one tank.

## Hardness never reaches a point where a disaster does nothing: a god whose powers stop
## working has nothing left to do.
const MAX_HARDNESS: float = 0.6

var faction: Faction
var unlocked: Array[FactionTrait] = []
## Trait -> seconds its condition has held without a break.
var _held: Dictionary = {}

var capacity_mul: float = 1.0
var growth_mul: float = 1.0
var reach_mul: float = 1.0
var grip_mul: float = 1.0
var spread_interval_mul: float = 1.0
var band_thickness_mul: float = 1.0
var decay_mul: float = 1.0
var hardness: float = 0.0
## Whether an earned trait lets this faction release its `ascends_to`.
var can_ascend: bool = false

func _init(owner: Faction = null) -> void:
	faction = owner

func has(trait_: FactionTrait) -> bool:
	return unlocked.has(trait_)

## The traits that could be earned next: not yet had, and whose prerequisite is.
func available() -> Array[FactionTrait]:
	var open: Array[FactionTrait] = []
	if faction == null:
		return open
	for t in faction.tech:
		if t == null or has(t):
			continue
		if t.requires != null and not has(t.requires):
			continue
		open.append(t)
	return open

## Advances every available trait by `elapsed` seconds against `facts`, and returns the
## ones earned by it. `facts` is {share, colonies, basins, survived_disaster}.
func tick(elapsed: float, facts: Dictionary) -> Array[FactionTrait]:
	var earned: Array[FactionTrait] = []
	for t in available():
		if _met(t, facts):
			_held[t] = float(_held.get(t, 0.0)) + elapsed
			var instant := t.condition == FactionTrait.Condition.SURVIVE_DISASTER
			if instant or float(_held[t]) >= t.hold_for:
				earned.append(t)
		else:
			_held[t] = 0.0
	for t in earned:
		unlock(t)
	return earned

## How far along its condition's clock `trait_` is, 0..1. For a readout.
func progress_of(trait_: FactionTrait) -> float:
	if has(trait_):
		return 1.0
	if trait_.hold_for <= 0.0:
		return 0.0
	return clampf(float(_held.get(trait_, 0.0)) / trait_.hold_for, 0.0, 1.0)

## Back to no traits and no clocks running.
func reset() -> void:
	unlocked.clear()
	_held.clear()
	_recompute()

func unlock(trait_: FactionTrait) -> void:
	if trait_ == null or has(trait_):
		return
	unlocked.append(trait_)
	_held.erase(trait_)
	_recompute()

func _met(t: FactionTrait, facts: Dictionary) -> bool:
	match t.condition:
		FactionTrait.Condition.HOLD_SHARE:
			return float(facts.get("share", 0.0)) >= t.threshold
		FactionTrait.Condition.COLONIES:
			return float(facts.get("colonies", 0)) >= t.threshold
		FactionTrait.Condition.SURVIVE_DISASTER:
			return bool(facts.get("survived_disaster", false))
		FactionTrait.Condition.HOLD_BASINS:
			return float(facts.get("basins", 0)) >= t.threshold
	return false

func _recompute() -> void:
	capacity_mul = 1.0
	growth_mul = 1.0
	reach_mul = 1.0
	grip_mul = 1.0
	spread_interval_mul = 1.0
	band_thickness_mul = 1.0
	decay_mul = 1.0
	hardness = 0.0
	can_ascend = false
	for t in unlocked:
		capacity_mul *= t.capacity_mul
		growth_mul *= t.growth_mul
		reach_mul *= t.reach_mul
		grip_mul *= t.grip_mul
		spread_interval_mul *= t.spread_interval_mul
		band_thickness_mul *= t.band_thickness_mul
		decay_mul *= t.decay_mul
		hardness += t.hardness
		can_ascend = can_ascend or t.enables_ascent
	hardness = minf(hardness, MAX_HARDNESS)

## What a save keeps: the traits earned, and how long each open trait's condition has
## held so far — both keyed by resource path, so a renamed trait survives.
##
## The clocks are saved as well as the unlocks. Without them a tank reopened halfway to
## Canopy showed 0% where it had shown 40%. Carrying a clock across an absence is honest
## here because the map does not move while the app is closed: the condition that held
## at the moment of saving still holds at the moment of reopening.
func to_save() -> Dictionary:
	var earned: Array = []
	for t in unlocked:
		earned.append(t.resource_path)
	var held: Dictionary = {}
	for t: FactionTrait in _held:
		if float(_held[t]) > 0.0 and not has(t):
			held[t.resource_path] = snappedf(float(_held[t]), 0.01)
	return {"unlocked": earned, "held": held}

func restore_save(data: Variant) -> void:
	if faction == null or typeof(data) != TYPE_DICTIONARY:
		return
	var by_path: Dictionary = {}
	for t in faction.tech:
		if t != null:
			by_path[t.resource_path] = t
	var earned: Variant = (data as Dictionary).get("unlocked", [])
	if typeof(earned) == TYPE_ARRAY:
		for path: Variant in earned:
			if by_path.has(str(path)):
				unlock(by_path[str(path)])
	var held: Variant = (data as Dictionary).get("held", {})
	if typeof(held) == TYPE_DICTIONARY:
		for path: Variant in held:
			if by_path.has(str(path)) and not has(by_path[str(path)]):
				_held[by_path[str(path)]] = maxf(0.0, float(held[path]))

## Whether there is anything worth saving.
func is_empty() -> bool:
	return unlocked.is_empty() and _held.values().all(func(v: Variant) -> bool: return float(v) <= 0.0)
