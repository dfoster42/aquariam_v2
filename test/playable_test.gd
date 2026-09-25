extends SceneTree
## Can a player actually do the things the prototype was measured doing?
##
## Every colony test drives the tank directly — `tank.bleach(...)`, `tank.plant_colony(...)`
## — so they prove the simulation works and say nothing about whether a finger can reach
## it. That gap was real: the picker only offered Strike, the travelling bleach that every
## measurement and screenshot was about could only be triggered from code, and no test
## noticed because no test went through the picker.
##
## So this one does nothing a player could not. It presses picker tiles by their label and
## taps through `main._on_tapped`, which is exactly where the camera delivers a tap.
##
## Run: godot --headless --script res://test/playable_test.gd

var _main: Node2D
var _tank: Aquarium
var _ui: CanvasLayer
var _failures: Array[String] = []

func _initialize() -> void:
	TankStore.clear()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)

## First frame, not _initialize(): nodes added there are not ready yet.
func _process(_delta: float) -> bool:
	_tank = _main.get_node("Aquarium")
	_tank.autosave_interval = 0.0
	_ui = _main.get_node("UI")

	_check_every_placeable_faction_has_a_tile()
	_check_unplaceable_factions_have_no_tile()
	_check_tap_founds_a_colony()
	_check_standings()
	_check_bleach_is_reachable()
	_check_standings_on_reopen()

	if _failures.is_empty():
		print("RESULT: PASS")
	else:
		for failure in _failures:
			printerr("FAIL: %s" % failure)
		print("RESULT: FAIL")
	quit(0 if _failures.is_empty() else 1)
	return true

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _tile(label: String) -> Button:
	var picker: HBoxContainer = _ui.get_node("%Picker")
	for child in picker.get_children():
		var button := child as Button
		if button != null and button.text == label:
			return button
	return null

func _press(label: String) -> bool:
	var tile := _tile(label)
	if tile == null:
		_failures.append("the picker has no %s tile" % label)
		return false
	tile.button_pressed = true
	tile.pressed.emit()
	return true

## A tap, delivered where the camera delivers one.
func _tap(world: Vector2) -> void:
	_main._on_tapped(world)

func _check_every_placeable_faction_has_a_tile() -> void:
	for faction in _tank.placeable_factions():
		_check(_tile(faction.display_name) != null,
			"placeable faction %s has no picker tile" % faction.display_name)
	_check(_tile("Strike") != null, "the picker has no Strike tile")
	_check(_tile("Bleach") != null, "the picker has no Bleach tile")

func _check_unplaceable_factions_have_no_tile() -> void:
	for faction in _tank.available_factions:
		if not faction.placeable:
			_check(_tile(faction.display_name) == null,
				"%s is meant to be earned but has a picker tile" % faction.display_name)

func _check_tap_founds_a_colony() -> void:
	_tank.clear_colonies()
	if not _press("Coral"):
		return
	var x := _shelf_x()
	_tap(Vector2(x, 300.0))
	_check(_tank.colonies().size() == 1,
		"arming Coral and tapping the water founded %d colonies" % _tank.colonies().size())

func _check_standings() -> void:
	var standings: Control = _ui.get_node("%Standings")
	_tank.clear_colonies()
	_tank._rebuild_territory()
	_check(not standings.visible, "the standings show with no colonies on the map")

	_press("Coral")
	_tap(Vector2(_shelf_x(), 300.0))
	_tank._rebuild_territory()
	_check(standings.visible, "the standings stay hidden with a colony on the map")
	var text := ""
	for child in standings.get_children():
		var label := child as Label
		if label != null and label.visible:
			text += label.text + " "
	_check(text.contains("Coral"), "the standings do not name the faction holding ground: '%s'" % text)
	_check(text.contains("%"), "the standings show no share: '%s'" % text)

func _check_bleach_is_reachable() -> void:
	_tank.clear_colonies()
	_press("Coral")
	var x := _shelf_x()
	_tap(Vector2(x, 300.0))
	var reef: Colony = _tank.colonies()[0] if not _tank.colonies().is_empty() else null
	if reef == null:
		_failures.append("could not found the reef to bleach")
		return

	if not _press("Bleach"):
		return
	_check(_tank.bleaching, "pressing Bleach did not arm the bleach")
	_check(not _tank.striking, "pressing Bleach left Strike armed as well")

	_tap(reef.global_position + Vector2(0, -40))
	# A bleach lands on the tank's disaster clock, so let it run.
	for i in 30:
		_tank._tick_colonies(0.1)
	_check(not is_instance_valid(reef) or reef.is_dying() or reef.is_dead(),
		"arming Bleach and tapping a reef did not bleach it")

	# Arming something else must disarm it, or the next tap on the water bleaches.
	_press("Coral")
	_check(not _tank.bleaching, "arming a faction left Bleach armed")

## An x on open shelf that Coral may be founded on.
func _shelf_x() -> float:
	var coral: Faction = null
	for f in _tank.available_factions:
		if f.display_name == "Coral":
			coral = f
	for i in 200:
		var x := 1440.0 + float(i) * 12.0 * (1.0 if i % 2 == 0 else -1.0)
		if coral != null and _tank.can_found(coral, x):
			return x
	return 1440.0

## A reopened tank shows its standings immediately, with no territory pass having run.
##
## The Aquarium restores its save in its own _ready, before the UI's, so the signal those
## restored colonies emit has already gone past by the time the UI connects to it. Checked
## with no frame processed at all, which is exactly a tank reopened while paused.
func _check_standings_on_reopen() -> void:
	_tank.clear_colonies()
	_press("Coral")
	_tap(Vector2(_shelf_x(), 300.0))
	_check(TankStore.save(_tank) == OK, "could not save the tank to reopen it")

	var reopened: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(reopened)
	var tank: Aquarium = reopened.get_node("Aquarium")
	tank.autosave_interval = 0.0
	_check(not tank.colonies().is_empty(), "the reopened tank did not restore its colony")
	var standings: Control = reopened.get_node("UI").get_node("%Standings")
	_check(standings.visible,
		"a reopened tank with colonies shows no standings until a territory pass runs")
	root.remove_child(reopened)
	reopened.free()
	TankStore.clear()
