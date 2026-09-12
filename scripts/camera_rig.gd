class_name CameraRig
extends Camera2D
## Pan and zoom over the tank, and decide whether a touch was a tap or a drag.
##
## Tap-to-spawn and drag-to-pan share one finger, so they cannot both be handled
## eagerly: a press is provisional until it either moves far enough to be a drag
## or is released still enough to be a tap. Only the release emits `tapped`.

signal tapped(world_position: Vector2)

## Movement in screen pixels beyond which a press stops being a candidate tap.
## Generous because a finger on glass is never still.
const DRAG_SLOP: float = 12.0
## A press held longer than this is not a tap even if it never moved, so that
## tap-and-hold does not spray fish on release.
const TAP_TIME: float = 0.4
const WHEEL_STEP: float = 1.12
const ZOOM_SMOOTHING: float = 12.0

## Zoom bounds. The lower bound is recomputed from the tank so the view can never
## zoom out past the tank's edges, whatever is set here.
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0

var _tank: Rect2 = Rect2()
var _target_zoom: float = 1.0
var _floor_zoom: float = 0.5

# A press is provisional until it resolves to a tap or a drag.
var _press_index: int = -1
var _press_screen: Vector2 = Vector2.ZERO
var _press_time: float = 0.0
var _dragging: bool = false

# Active touches, by index, for the two-finger pinch.
var _touches: Dictionary = {}
var _pinch_distance: float = 0.0

func setup(tank: Rect2) -> void:
	_tank = tank
	limit_left = int(tank.position.x)
	limit_top = int(tank.position.y)
	limit_right = int(tank.end.x)
	limit_bottom = int(tank.end.y)
	position = tank.get_center()
	_recompute_zoom_floor()
	_target_zoom = _floor_zoom
	zoom = Vector2(_target_zoom, _target_zoom)

func _ready() -> void:
	get_viewport().size_changed.connect(_recompute_zoom_floor)

func _process(delta: float) -> void:
	var current := zoom.x
	if absf(current - _target_zoom) > 0.0005:
		var eased := lerpf(current, _target_zoom, minf(1.0, ZOOM_SMOOTHING * delta))
		zoom = Vector2(eased, eased)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		_on_wheel(event as InputEventMouseButton)

func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_press_index = event.index
			_press_screen = event.position
			_press_time = 0.0
			_dragging = false
		else:
			# A second finger cancels the candidate tap and starts a pinch.
			_press_index = -1
			_pinch_distance = _touch_spread()
		return

	_touches.erase(event.index)
	if event.index == _press_index:
		var still := event.position.distance_to(_press_screen) <= DRAG_SLOP
		var quick := _press_time <= TAP_TIME
		if still and quick and not _dragging:
			tapped.emit(to_world(event.position))
		_press_index = -1
	if _touches.size() < 2:
		_pinch_distance = 0.0

func _on_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position

	if _touches.size() >= 2:
		var spread := _touch_spread()
		if _pinch_distance > 0.0 and spread > 0.0:
			_apply_zoom(_target_zoom * (spread / _pinch_distance))
		_pinch_distance = spread
		return

	if event.index == _press_index:
		_press_time += get_process_delta_time()
		if event.position.distance_to(_press_screen) > DRAG_SLOP:
			_dragging = true
	if _dragging:
		# Screen delta is in screen pixels; world movement is that over the zoom.
		position -= event.relative / zoom.x
		_clamp_position()

func _on_wheel(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_apply_zoom(_target_zoom * WHEEL_STEP)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_apply_zoom(_target_zoom / WHEEL_STEP)

func to_world(screen_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_position

func _apply_zoom(value: float) -> void:
	_target_zoom = clampf(value, maxf(min_zoom, _floor_zoom), max_zoom)
	_clamp_position()

## The zoom at which the tank exactly fills the viewport. Below it the view would
## show past the tank's edge, which Camera2D's limits cannot prevent on their own.
func _recompute_zoom_floor() -> void:
	if _tank.size.x <= 0.0 or _tank.size.y <= 0.0:
		return
	var view := Vector2(get_viewport_rect().size)
	_floor_zoom = maxf(view.x / _tank.size.x, view.y / _tank.size.y)
	if _target_zoom < _floor_zoom:
		_apply_zoom(_floor_zoom)

func _clamp_position() -> void:
	var half := Vector2(get_viewport_rect().size) * 0.5 / maxf(zoom.x, 0.001)
	position = Vector2(
		clampf(position.x, _tank.position.x + half.x, _tank.end.x - half.x),
		clampf(position.y, _tank.position.y + half.y, _tank.end.y - half.y),
	)

func _touch_spread() -> float:
	var points := _touches.values()
	if points.size() < 2:
		return 0.0
	return (points[0] as Vector2).distance_to(points[1] as Vector2)
