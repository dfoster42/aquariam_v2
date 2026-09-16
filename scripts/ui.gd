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
@onready var sound_button: Button = $Root/Safe/Stack/TopBar/Sound
@onready var tanks_button: Button = $Root/Safe/Stack/TopBar/Tanks
@onready var pause_button: Button = $Root/Safe/Stack/TopBar/Pause
@onready var tank_panel: PanelContainer = $Root/Safe/Stack/TankPanel
@onready var tank_list: VBoxContainer = $Root/Safe/Stack/TankPanel/TankList
@onready var picker: HBoxContainer = $Root/Safe/Stack/Picker

func _ready() -> void:
	_aquarium = get_node_or_null(aquarium_path) as Aquarium
	if _aquarium == null:
		push_error("UI could not find an Aquarium at %s" % aquarium_path)
		return

	pause_button.pressed.connect(_aquarium.toggle_paused)
	tanks_button.pressed.connect(_toggle_tank_panel)
	sound_button.pressed.connect(_toggle_sound)
	_refresh_sound_button()
	_aquarium.paused_changed.connect(_on_paused_changed)
	_aquarium.population_changed.connect(_on_population_changed)
	_aquarium.species_selected.connect(_on_species_selected)

	_build_picker()
	_on_population_changed(_aquarium.population())

	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()

func _toggle_sound() -> void:
	var main := get_parent()
	main.set_muted(not main.is_muted())
	_refresh_sound_button()

func _refresh_sound_button() -> void:
	sound_button.text = "Sound off" if get_parent().is_muted() else "Sound on"

func _toggle_tank_panel() -> void:
	tank_panel.visible = not tank_panel.visible
	if tank_panel.visible:
		_build_tank_list()

## One row per saved tank, plus a row to make a new one.
##
## Rebuilt on open rather than kept in sync: the list is short, opening it is rare, and
## a rebuild cannot drift from what is actually on disk.
func _build_tank_list() -> void:
	for child in tank_list.get_children():
		child.queue_free()

	var active := TankStore.active_slot()
	for slot: Variant in TankStore.slots():
		var id: String = str(slot.get("id", ""))
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var open := Button.new()
		open.text = "%s%s  (%d fish)" % [
			"> " if id == active else "", slot.get("name", id), _fish_in(id)]
		open.focus_mode = Control.FOCUS_NONE
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.disabled = id == active
		open.pressed.connect(_switch_to.bind(id))
		row.add_child(open)

		var rename := Button.new()
		rename.text = "Rename"
		rename.focus_mode = Control.FOCUS_NONE
		rename.pressed.connect(_begin_rename.bind(id))
		row.add_child(rename)

		var remove := Button.new()
		remove.text = "Delete"
		remove.focus_mode = Control.FOCUS_NONE
		# Never offer to delete the only tank: it would leave the app with nowhere to
		# save and the next launch would silently make a fresh one.
		remove.disabled = TankStore.slots().size() <= 1
		remove.pressed.connect(_confirm_delete.bind(id, slot.get("name", id)))
		row.add_child(remove)

		tank_list.add_child(row)

	var new_tank := Button.new()
	new_tank.text = "New aquarium"
	new_tank.focus_mode = Control.FOCUS_NONE
	new_tank.disabled = TankStore.slots().size() >= TankStore.MAX_SLOTS
	new_tank.pressed.connect(_create)
	tank_list.add_child(new_tank)

func _fish_in(slot_id: String) -> int:
	return TankStore.read(slot_id).get("fish", []).size()

## Saving the current tank before leaving it is the whole contract of switching.
func _switch_to(slot_id: String) -> void:
	_aquarium.save()
	TankStore.set_active(slot_id)
	_reload()

func _create() -> void:
	_aquarium.save()
	var id := TankStore.create_slot("Aquarium %d" % (TankStore.slots().size() + 1))
	if id == "":
		return
	_reload()

## Deleting a tank destroys years of a player's fish in one tap, so it asks first.
func _confirm_delete(slot_id: String, name: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete aquarium"
	dialog.dialog_text = "Delete \"%s\" and every fish in it?\n\nThis cannot be undone." % name
	dialog.ok_button_text = "Delete"
	dialog.confirmed.connect(_delete.bind(slot_id))
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func _begin_rename(slot_id: String) -> void:
	var current := slot_id
	for slot: Variant in TankStore.slots():
		if slot.get("id", "") == slot_id:
			current = str(slot.get("name", slot_id))

	var dialog := AcceptDialog.new()
	dialog.title = "Rename aquarium"
	var field := LineEdit.new()
	field.text = current
	field.custom_minimum_size = Vector2(260, 0)
	field.select_all()
	dialog.add_child(field)
	dialog.ok_button_text = "Rename"
	dialog.confirmed.connect(func() -> void:
		var name := field.text.strip_edges()
		if name != "":
			TankStore.rename_slot(slot_id, name)
			_build_tank_list())
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
	field.grab_focus()

func _delete(slot_id: String) -> void:
	var was_active := slot_id == TankStore.active_slot()
	TankStore.delete_slot(slot_id)
	if was_active:
		_reload()
	else:
		_build_tank_list()

## Reloading the scene is how a tank is swapped: the Aquarium builds itself from the
## active slot in _ready, so there is no second code path for "load a different tank"
## that could drift from the one used at launch.
func _reload() -> void:
	get_tree().reload_current_scene()

func _build_picker() -> void:
	for child in picker.get_children():
		child.queue_free()
	for species in _aquarium.available_species:
		var button := _picker_button(species.display_name)
		button.button_pressed = species == _aquarium.selected_species
		button.pressed.connect(_aquarium.select_species.bind(species))
		picker.add_child(button)

	if not _aquarium.available_decor.is_empty():
		var divider := VSeparator.new()
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picker.add_child(divider)
	for kind in _aquarium.available_decor:
		var button := _picker_button(kind.display_name)
		button.pressed.connect(_aquarium.select_decor.bind(kind))
		picker.add_child(button)

	var feed := _picker_button("Feed")
	feed.pressed.connect(_aquarium.set_feeding.bind(true))
	picker.add_child(feed)

## One group across fish and decor, so arming a plant disarms the fish and a tap can
## only ever place one kind of thing.
func _picker_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.button_group = _group
	button.focus_mode = Control.FOCUS_NONE
	return button

func _on_population_changed(count: int) -> void:
	population_label.text = "%d fish" % count

func _on_paused_changed(paused: bool) -> void:
	pause_button.text = "Resume" if paused else "Pause"

func _on_species_selected(species: FishSpecies) -> void:
	for child in picker.get_children():
		var button := child as Button
		if button != null:
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
