class_name TankUI
extends CanvasLayer
## Tank controls: population readout, pause, and the species picker.
##
## The picker is built from the tank's species list rather than authored, so a new
## .tres dropped into `available_species` appears here with no further work.
##
## Every container in ui.tscn sets `mouse_filter = 2` (IGNORE). A Control defaults to
## STOP, and a full-rect container left at the default silently swallows every tap
## meant for the tank — the fish simply stop spawning and nothing reports an error.
## Only the buttons capture input.

## Fallback padding where a platform reports no safe area (desktop, and the editor).
const BASE_MARGIN: int = 12

@export var aquarium_path: NodePath = ^"../Aquarium"

var _aquarium: Aquarium
var _group := ButtonGroup.new()

@onready var safe: MarginContainer = $Root/Safe
@onready var population_label: Label = $Root/Safe/Stack/TopBar/Population
@onready var pause_button: Button = $Root/Safe/Stack/TopBar/Pause
@onready var picker: HBoxContainer = $Root/Safe/Stack/Picker

func _ready() -> void:
	_aquarium = get_node_or_null(aquarium_path) as Aquarium
	if _aquarium == null:
		push_error("UI could not find an Aquarium at %s" % aquarium_path)
		return

	pause_button.pressed.connect(_aquarium.toggle_paused)
	_aquarium.paused_changed.connect(_on_paused_changed)
	_aquarium.population_changed.connect(_on_population_changed)
	_aquarium.species_selected.connect(_on_species_selected)

	_build_picker()
	_on_population_changed(_aquarium.population())

	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()

func _build_picker() -> void:
	for child in picker.get_children():
		child.queue_free()
	for species in _aquarium.available_species:
		var button := Button.new()
		button.text = species.display_name
		button.toggle_mode = true
		button.button_group = _group
		button.focus_mode = Control.FOCUS_NONE
		button.button_pressed = species == _aquarium.selected_species
		button.pressed.connect(_aquarium.select_species.bind(species))
		picker.add_child(button)

func _on_population_changed(count: int) -> void:
	population_label.text = "%d fish" % count

func _on_paused_changed(paused: bool) -> void:
	pause_button.text = "Resume" if paused else "Pause"

func _on_species_selected(species: FishSpecies) -> void:
	for button: Button in picker.get_children():
		button.set_pressed_no_signal(button.text == species.display_name)

## The inset on each edge (left, top, right, bottom) in screen pixels.
##
## Pure, and separated from the DisplayServer call so it can be tested: headless
## reports a degenerate safe area, so a test that drives this through the platform
## passes whatever the arithmetic does. This is where the arithmetic is checked.
##
## The rectangles are in SCREEN coordinates. Measuring the safe area against the
## WINDOW instead produced a right inset of about -970 on a windowed desktop build,
## which pushed the pause button and the whole species picker off the edges while the
## population label stayed put — it read as a layout that had never been written.
static func safe_insets(safe_area: Rect2i, screen_position: Vector2, screen_size: Vector2) -> Vector4:
	if safe_area.size.x <= 0 or safe_area.size.y <= 0 or screen_size.x <= 0.0 or screen_size.y <= 0.0:
		return Vector4.ZERO
	return Vector4(
		maxf(0.0, safe_area.position.x - screen_position.x),
		maxf(0.0, safe_area.position.y - screen_position.y),
		maxf(0.0, screen_position.x + screen_size.x - safe_area.end.x),
		maxf(0.0, screen_position.y + screen_size.y - safe_area.end.y),
	)

## Insets the controls past a notch or home indicator.
##
## Every margin is floored at BASE_MARGIN: a platform reporting something unexpected
## should cost a little padding, never a control the user cannot reach.
func _apply_safe_area() -> void:
	var window := Vector2(DisplayServer.window_get_size())
	var view := Vector2(get_viewport().get_visible_rect().size)
	if window.x <= 0.0 or window.y <= 0.0:
		return

	var screen := DisplayServer.window_get_current_screen()
	var insets := safe_insets(
		DisplayServer.get_display_safe_area(),
		Vector2(DisplayServer.screen_get_position(screen)),
		Vector2(DisplayServer.screen_get_size(screen)),
	)

	# Insets are in screen pixels; the UI is laid out in viewport units.
	var scale := view / window
	safe.add_theme_constant_override("margin_left", BASE_MARGIN + int(insets.x * scale.x))
	safe.add_theme_constant_override("margin_top", BASE_MARGIN + int(insets.y * scale.y))
	safe.add_theme_constant_override("margin_right", BASE_MARGIN + int(insets.z * scale.x))
	safe.add_theme_constant_override("margin_bottom", BASE_MARGIN + int(insets.w * scale.y))
