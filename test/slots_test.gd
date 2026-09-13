extends SceneTree
## Multiple saved aquariums: slots, switching, migration.
## Run: godot --headless --script res://test/slots_test.gd

var _started: bool = false
var _failures: Array[String] = []

func _initialize() -> void:
	TankStore.clear()

func _process(_d: float) -> bool:
	if _started:
		return true
	_started = true
	_run()
	return true

func _run() -> void:
	_check_empty_state()
	_check_create_and_switch()
	_check_isolation()
	_check_delete()
	_check_legacy_migration()

	TankStore.clear()
	if _failures.is_empty():
		print("RESULT: PASS")
		return
	for f in _failures:
		printerr("FAIL: " + f)
	print("RESULT: FAIL (%d)" % _failures.size())
	quit(1)

## A fresh install has no tanks, and asking for one must not crash or invent a file.
func _check_empty_state() -> void:
	_check(TankStore.slots().is_empty(), "a fresh install should have no slots")
	_check(TankStore.active_slot() == "", "a fresh install should have no active slot")
	_check(TankStore.read().is_empty(), "reading with no slots should give nothing")
	_check(not TankStore.has_save(), "a fresh install should report no save")

func _check_create_and_switch() -> void:
	var reef := TankStore.create_slot("Reef")
	var deep := TankStore.create_slot("Deep")
	_check(reef != "" and deep != "" and reef != deep, "create_slot must return distinct ids")
	_check(TankStore.slots().size() == 2, "expected 2 slots, got %d" % TankStore.slots().size())
	_check(TankStore.active_slot() == deep, "creating a slot should make it active")

	TankStore.set_active(reef)
	_check(TankStore.active_slot() == reef, "set_active did not stick")

	TankStore.rename_slot(reef, "Home Reef")
	var named := ""
	for slot: Variant in TankStore.slots():
		if slot.get("id", "") == reef:
			named = slot.get("name", "")
	_check(named == "Home Reef", "rename_slot did not take (got %s)" % named)

## Two tanks must not see each other's fish. This is the whole point of the feature.
func _check_isolation() -> void:
	var slot_a := TankStore.active_slot()
	var tank_a := _new_tank()
	var count_a := tank_a.population()
	TankStore.save(tank_a, slot_a)

	var slot_b := TankStore.create_slot("Second")
	var tank_b := _new_tank()
	tank_b.clear_tank()
	tank_b.spawn(tank_b.available_species[0], Vector2(500, 500))
	TankStore.save(tank_b, slot_b)

	var read_a := TankStore.read(slot_a)
	var read_b := TankStore.read(slot_b)
	_check(read_a.get("fish", []).size() == count_a,
		"slot A should hold %d fish, holds %d" % [count_a, read_a.get("fish", []).size()])
	_check(read_b.get("fish", []).size() == 1,
		"slot B should hold 1 fish, holds %d" % read_b.get("fish", []).size())
	_check(count_a != 1, "test is meaningless if both tanks have the same population")

	# saved_at is recorded per slot, so each tank ages on its own clock.
	for slot: Variant in TankStore.slots():
		if slot.get("id", "") in [slot_a, slot_b]:
			_check(int(slot.get("saved_at", 0)) > 0, "slot %s has no saved_at" % slot.get("id"))

	tank_a.queue_free()
	tank_b.queue_free()

func _check_delete() -> void:
	var before := TankStore.slots().size()
	var doomed := TankStore.create_slot("Doomed")
	var tank := _new_tank()
	TankStore.save(tank, doomed)
	_check(TankStore.has_save(doomed), "the new slot should have a save")

	TankStore.delete_slot(doomed)
	_check(TankStore.slots().size() == before, "delete_slot did not remove the slot")
	_check(not TankStore.has_save(doomed), "delete_slot left the tank file behind")
	_check(TankStore.active_slot() != doomed, "active slot still points at a deleted tank")
	tank.queue_free()

## A save written before slots existed must become a slot, not be stranded.
func _check_legacy_migration() -> void:
	TankStore.clear()
	var legacy := {
		"version": TankStore.FORMAT_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"selected": "",
		"fish": [{"species": "res://resources/species/clownfish.tres", "x": 10, "y": 20, "age": 5}],
	}
	var file := FileAccess.open(TankStore.LEGACY_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()

	var slots := TankStore.slots()
	_check(slots.size() == 1, "the legacy save should have become exactly 1 slot, got %d" % slots.size())
	_check(TankStore.read().get("fish", []).size() == 1, "the migrated tank lost its fish")
	_check(not FileAccess.file_exists(TankStore.LEGACY_PATH), "the legacy file should be removed after migration")

func _new_tank() -> Aquarium:
	var tank: Aquarium = load("res://scenes/aquarium.tscn").instantiate()
	tank.autosave_interval = 0.0
	root.add_child(tank)
	return tank

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
