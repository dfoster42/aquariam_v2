class_name Shockwave
extends Node2D
## A ring that expands and fades where a disaster lands.
##
## The game's central verb had no visual payoff: a bleach removed a faction between one
## territory pass and the next, so the frame captured immediately after a disaster was
## indistinguishable from the frame two minutes later. A viewer could see that something
## had changed and never what had happened.
##
## Drawn rather than authored, for the reason the UI glyphs are: a ring is geometry, and
## geometry is arithmetic rather than adjectives. It costs no generation quota and no
## texture, and it cannot come back at a different weight on a re-roll.

## Seconds from strike to gone.
const LIFETIME: float = 0.85
## How far the ring travels past the radius it is given.
const OVERSHOOT: float = 1.9
## Width of the ring at birth, in world units. It thins as it expands.
const LINE_WIDTH: float = 26.0

var _radius: float = 120.0
var _tint: Color = Color.WHITE
var _age: float = 0.0

func configure(radius: float, tint: Color) -> void:
	_radius = maxf(radius, 8.0)
	_tint = tint

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	# Redrawn every frame because both the radius and the alpha are functions of age.
	queue_redraw()

func _draw() -> void:
	var t := clampf(_age / LIFETIME, 0.0, 1.0)
	# Fast out, slow to a stop: a linear ring reads as a scripted animation, an eased one
	# reads as something that happened.
	var eased := 1.0 - pow(1.0 - t, 3.0)
	var radius := _radius * lerpf(0.15, OVERSHOOT, eased)
	var colour := _tint
	colour.a = (1.0 - t) * 0.85
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, colour,
		LINE_WIDTH * (1.0 - t * 0.7), true)
