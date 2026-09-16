class_name Food
extends Node2D
## A pellet of food, sinking until something eats it or it reaches the floor.
##
## Deliberately a plain Node2D like Fish rather than anything physics-backed: the tank
## runs its own loop in _process and adding a physics body per pellet would put the
## simulation back on the fixed clock it was moved off.

signal consumed(food: Food)

## Pixels per second it sinks. Slow enough that fish have time to reach it.
const SINK_SPEED: float = 26.0
## How long a pellet lasts once it settles on the floor before dissolving, in seconds.
const SETTLED_LIFETIME: float = 25.0
const RADIUS: float = 7.0

var _floor_y: float = 0.0
var _settled_for: float = 0.0
var _eaten: bool = false

func configure(bounds: Rect2) -> void:
	# Settles a little above the very bottom, where fish can still reach it.
	_floor_y = bounds.end.y - 40.0

func tick(delta: float) -> void:
	if _eaten:
		return
	if global_position.y < _floor_y:
		global_position.y = minf(_floor_y, global_position.y + SINK_SPEED * delta)
	else:
		_settled_for += delta
		if _settled_for >= SETTLED_LIFETIME:
			be_eaten()

func be_eaten() -> void:
	if _eaten:
		return
	_eaten = true
	consumed.emit(self)

func is_eaten() -> bool:
	return _eaten

func _draw() -> void:
	# Drawn rather than textured: a pellet is a dot, and a dot does not need an asset,
	# an import step or a place in the atlas.
	draw_circle(Vector2.ZERO, RADIUS, Color(0.85, 0.72, 0.42))
	draw_circle(Vector2(-RADIUS * 0.28, -RADIUS * 0.28), RADIUS * 0.34, Color(0.96, 0.88, 0.62))
