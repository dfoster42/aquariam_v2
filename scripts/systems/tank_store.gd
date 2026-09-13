class_name TankStore
extends RefCounted
## Reads and writes the tank to disk.
##
## JSON in user://, not a .tres. A saved Resource is a script-bearing file that Godot
## will happily instantiate on load, so a save file becomes a code path; JSON is inert
## data that has to be validated before it means anything, which is the right shape for
## something a player's device owns and an update has to keep reading.
##
## Species are stored by `resource_path`, so reordering the species list or renaming a
## display name does not orphan a saved tank. A fish whose species no longer exists is
## dropped on load rather than failing the whole restore.

const SAVE_PATH: String = "user://tank.json"
const FORMAT_VERSION: int = 1

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
	return {
		"version": FORMAT_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"selected": tank.selected_species.resource_path if tank.selected_species else "",
		"fish": fish,
	}

static func save(tank: Aquarium) -> Error:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s: %s" % [SAVE_PATH, error_string(FileAccess.get_open_error())])
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(capture(tank)))
	file.close()
	return OK

static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## Returns the parsed save, or an empty Dictionary when there is nothing usable.
##
## Every failure here is silent and recoverable by design: a corrupt or future-versioned
## save should cost the player their tank's layout, not the ability to open the app.
static func read() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
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

static func clear() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
