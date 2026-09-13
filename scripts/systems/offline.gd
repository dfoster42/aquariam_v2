class_name Offline
extends RefCounted
## Advances the tank for time the app was not running.
##
## Deliberately a population model, not a fast-forwarded simulation. Replaying the real
## sim would mean stepping every fish for every frame of an overnight absence, and doing
## it in coarse steps is worse than not doing it: at half-second steps a fish crosses
## 40px per tick, so it jumps straight past the distances that decide eating and
## breeding, and the result is neither fast nor faithful.
##
## So the rules are stated directly: fish age, fish past their lifespan are gone, and
## each breeding species grows logistically toward its carrying capacity. That is
## reproducible, instant, and honest about being an approximation.

## Longest absence that is credited. A week away should not return a tank that behaved
## as though someone were watching it for a week.
const MAX_CATCHUP: float = 8.0 * 3600.0

## Per-capita growth rate from a species' breeding cooldown.
##
## A pair yields one offspring per cooldown, so each individual contributes about half
## an offspring per cooldown period.
static func growth_rate(breed_cooldown: float) -> float:
	if breed_cooldown <= 0.0:
		return 0.0
	return 0.5 / breed_cooldown

## Logistic growth: how many there are after `seconds`, starting from `count`.
##
## Returns `count` unchanged when the species cannot breed, is already at capacity, or
## has died out — a population of zero has nothing to grow from, and no amount of time
## away should conjure a fish from an empty tank.
static func project(count: int, capacity: int, rate: float, seconds: float) -> int:
	if count <= 0 or capacity <= 0 or rate <= 0.0 or seconds <= 0.0:
		return count
	if count >= capacity:
		return capacity
	var n := float(count)
	var k := float(capacity)
	var grown := k / (1.0 + ((k - n) / n) * exp(-rate * seconds))
	return clampi(int(round(grown)), count, capacity)

## Seconds to credit for an absence, clamped and guarded against a clock that moved
## backwards (a timezone change, or a device whose clock was corrected while away).
static func elapsed_since(saved_at: int, now: int) -> float:
	if saved_at <= 0 or now <= saved_at:
		return 0.0
	return minf(float(now - saved_at), MAX_CATCHUP)
