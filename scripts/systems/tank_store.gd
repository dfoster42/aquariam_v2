class_name TankStore
extends RefCounted
## Reads and writes tanks to disk, one file per tank.
##
## JSON in user://, not a .tres. A saved Resource is a script-bearing file that Godot
## will happily instantiate on load, so a save file becomes a code path; JSON is inert
## data that has to be validated before it means anything, which is the right shape for
## something a player's device owns and an update has to keep reading.
##
## Species are stored by `resource_path`, so reordering the species list or renaming a
## display name does not orphan a saved tank. A fish whose species no longer exists is
## dropped on load rather than failing the whole restore.
##
## Layout:
##   user://tanks/index.json   the slot list and which one is active
##   user://tanks/<id>.json    one tank

const DIR: String = "user://tanks"
const INDEX_PATH: String = "user://tanks/index.json"
## Where single-tank saves lived before slots existed. Migrated, not abandoned.
const LEGACY_PATH: String = "user://tank.json"
const FORMAT_VERSION: int = 1
const INDEX_VERSION: int = 1
const MAX_SLOTS: int = 12

# ---------------------------------------------------------------- slot management

static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))

static func slot_path(slot_id: String) -> String:
	return "%s/%s.json" % [DIR, slot_id]

## The whole index: `{version, active, slots: [{id, name, saved_at}]}`.
##
## Always returns something usable. A missing or unreadable index is not an error the
## player should meet as a crash — it means "no tanks yet", and the caller makes one.
static func index() -> Dictionary:
	_migrate_legacy()
	var blank := {"version": INDEX_VERSION, "active": "", "slots": []}
	if not FileAccess.file_exists(INDEX_PATH):
		return blank
	var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if file == null:
		return blank
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY or int((parsed as Dictionary).get("version", 0)) != INDEX_VERSION:
		push_warning("Tank index unreadable or from a future version; starting fresh.")
		return blank
	var data: Dictionary = parsed
	if typeof(data.get("slots")) != TYPE_ARRAY:
		data["slots"] = []
	return data

static func _write_index(data: Dictionary) -> Error:
	_ensure_dir()
	var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.close()
	return OK

## Moves a pre-slots `user://tank.json` into a slot rather than stranding it.
static func _migrate_legacy() -> void:
	if not FileAccess.file_exists(LEGACY_PATH) or FileAccess.file_exists(INDEX_PATH):
		return
	_ensure_dir()
	var source := FileAccess.open(LEGACY_PATH, FileAccess.READ)
	if source == null:
		return
	var contents := source.get_as_text()
	source.close()

	var id := "tank_1"
	var target := FileAccess.open(slot_path(id), FileAccess.WRITE)
	if target == null:
		return
	target.store_string(contents)
	target.close()
	_write_index({
		"version": INDEX_VERSION,
		"active": id,
		"slots": [{"id": id, "name": "My Aquarium", "saved_at": int(Time.get_unix_time_from_system())}],
	})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_PATH))
	print("Migrated the existing tank into slot '%s'." % id)

static func slots() -> Array:
	return index().get("slots", [])

static func active_slot() -> String:
	var data := index()
	var id: String = data.get("active", "")
	for slot: Variant in data.get("slots", []):
		if typeof(slot) == TYPE_DICTIONARY and slot.get("id", "") == id:
			return id
	# Active points at nothing: fall back to the first real slot rather than writing to
	# a file no slot claims.
	var list: Array = data.get("slots", [])
	return list[0].get("id", "") if not list.is_empty() else ""

static func set_active(slot_id: String) -> void:
	var data := index()
	data["active"] = slot_id
	_write_index(data)

## Creates an empty slot and returns its id, or "" when full.
static func create_slot(name: String) -> String:
	var data := index()
	var list: Array = data.get("slots", [])
	if list.size() >= MAX_SLOTS:
		push_warning("Refusing to create a %dth tank." % (MAX_SLOTS + 1))
		return ""

	var highest := 0
	for slot: Variant in list:
		var id: String = str(slot.get("id", ""))
		if id.begins_with("tank_"):
			highest = maxi(highest, int(id.trim_prefix("tank_")))
	var new_id := "tank_%d" % (highest + 1)

	list.append({"id": new_id, "name": name, "saved_at": 0})
	data["slots"] = list
	data["active"] = new_id
	_write_index(data)
	return new_id

static func rename_slot(slot_id: String, name: String) -> void:
	var data := index()
	for slot: Variant in data.get("slots", []):
		if typeof(slot) == TYPE_DICTIONARY and slot.get("id", "") == slot_id:
			slot["name"] = name
	_write_index(data)

static func delete_slot(slot_id: String) -> void:
	var data := index()
	var kept: Array = []
	for slot: Variant in data.get("slots", []):
		if typeof(slot) == TYPE_DICTIONARY and slot.get("id", "") != slot_id:
			kept.append(slot)
	data["slots"] = kept
	if data.get("active", "") == slot_id:
		data["active"] = kept[0].get("id", "") if not kept.is_empty() else ""
	_write_index(data)
	var path := ProjectSettings.globalize_path(slot_path(slot_id))
	if FileAccess.file_exists(slot_path(slot_id)):
		DirAccess.remove_absolute(path)

# ---------------------------------------------------------------- tank contents

## Serialises the live tank. Positions are rounded to whole pixels — a fish's exact
## subpixel offset is not worth the file size or the diff noise.
static func capture(tank: Aquarium) -> Dictionary:
	var fish: Array = []
	for f in tank.fish():
		if f == null or f.is_eaten() or f.species == null:
			continue
		fish.append({
			"species": f.species.resource_path,
			"x": roundi(f.global_position.x),
			"y": roundi(f.global_position.y),
			"age": roundi(f.age),
		})
	var decor: Array = []
	for item in tank.decor():
		if item == null or item.kind == null:
			continue
		decor.append({
			"kind": item.kind.resource_path,
			"x": roundi(item.global_position.x),
			"y": roundi(item.global_position.y),
		})

	# Colonies are the one thing in the tank that is worth more the longer it has
	# existed, so biomass is saved with them: restoring a mature reef as a seed would
	# quietly undo however long the player spent growing it.
	var colonies: Array = []
	for colony in tank.colonies():
		if colony == null or colony.faction == null or colony.is_dead():
			continue
		colonies.append({
			"faction": colony.faction.resource_path,
			"x": roundi(colony.global_position.x),
			"y": roundi(colony.global_position.y),
			"biomass": snappedf(colony.biomass, 0.01),
		})

	return {
		"version": FORMAT_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"selected": tank.selected_species.resource_path if tank.selected_species else "",
		"fish": fish,
		"decor": decor,
		"colonies": colonies,
	}

static func save(tank: Aquarium, slot_id: String = "") -> Error:
	var id := slot_id if slot_id != "" else active_slot()
	if id == "":
		id = create_slot("My Aquarium")
	_ensure_dir()
	var file := FileAccess.open(slot_path(id), FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s: %s" % [slot_path(id), error_string(FileAccess.get_open_error())])
		return FileAccess.get_open_error()
	var data := capture(tank)
	file.store_string(JSON.stringify(data))
	file.close()

	var meta := index()
	for slot: Variant in meta.get("slots", []):
		if typeof(slot) == TYPE_DICTIONARY and slot.get("id", "") == id:
			slot["saved_at"] = data["saved_at"]
	_write_index(meta)
	return OK

static func has_save(slot_id: String = "") -> bool:
	var id := slot_id if slot_id != "" else active_slot()
	return id != "" and FileAccess.file_exists(slot_path(id))

## Returns the parsed tank, or an empty Dictionary when there is nothing usable.
##
## Every failure here is silent and recoverable by design: a corrupt or future-versioned
## save should cost the player their tank's layout, not the ability to open the app.
static func read(slot_id: String = "") -> Dictionary:
	var id := slot_id if slot_id != "" else active_slot()
	if id == "" or not FileAccess.file_exists(slot_path(id)):
		return {}
	var file := FileAccess.open(slot_path(id), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Tank save is not a JSON object; ignoring it.")
		return {}
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != FORMAT_VERSION:
		push_warning("Tank save is version %s, expected %d; ignoring it." % [
			data.get("version", "?"), FORMAT_VERSION])
		return {}
	return data

## Removes every tank and the index. Used by tests.
static func clear() -> void:
	for slot: Variant in slots():
		var id: String = str(slot.get("id", ""))
		if id != "" and FileAccess.file_exists(slot_path(id)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(id)))
	for path in [INDEX_PATH, LEGACY_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
