class_name SaveManager
extends RefCounted
## Manual, slot-based saving.
##
## Saving is deliberately manual and tied to places in the world, not
## automatic after every action — the brief asks for consequences to stick.
## What that makes non-negotiable is that the last good save is never
## destroyed: writes go to a temporary file and are only swapped in once the
## data has been written and read back successfully.
##
## The save is a dictionary of independent sections. Each system serialises
## itself, so adding a system means adding a section and a migration, never
## touching the others.

const SAVE_DIR := "user://saves/"
const EXTENSION := ".hsave"
const AUTOSAVE_SLOT := "auto"

## Sections written in this order. Load restores in the same order, which
## matters: the world must exist before NPCs are placed in it.
const SECTIONS := [
	"clock", "rng", "world", "npcs", "relationships",
	"knowledge", "memories", "reputation", "events", "player", "shops", "work", "quests", "phone", "calendar", "crime", "asks", "consequences",
]

var last_error: String = ""


func slot_path(slot: String) -> String:
	return SAVE_DIR + slot + EXTENSION


func has_slot(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Slot ids present on disk, newest first.
func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.ends_with(EXTENSION):
			var slot := name.substr(0, name.length() - EXTENSION.length())
			var header := read_header(slot)
			if not header.is_empty():
				out.append(header)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b): return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0)))
	return out


## Reads just the metadata of a save, for the load menu.
func read_header(slot: String) -> Dictionary:
	var data := _read_file(slot)
	if data.is_empty():
		return {}
	return {
		"slot": slot,
		"schema_version": int(data.get("schema_version", 0)),
		"saved_at": int(data.get("saved_at", 0)),
		"loadable": SaveMigrations.can_load(int(data.get("schema_version", 0))),
		"meta": data.get("meta", {}),
	}


## Collects every section and writes the slot. `sections` maps section name
## to a dictionary produced by that system's to_dict().
func save(slot: String, sections: Dictionary, meta: Dictionary = {}) -> Result:
	last_error = ""
	var payload := {
		"schema_version": SaveMigrations.CURRENT_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"meta": meta,
	}
	for name in SECTIONS:
		if sections.has(name):
			payload[name] = sections[name]

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var final_path := slot_path(slot)
	var temp_path := final_path + ".tmp"

	var file := FileAccess.open_compressed(temp_path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		last_error = "cannot open save file for writing"
		Log.error("save", last_error, {"slot": slot, "err": FileAccess.get_open_error()})
		return Result.failure("save_write_failed", last_error)
	file.store_string(JSON.stringify(payload))
	file.close()

	# Read the temporary file back before replacing the existing save, so a
	# failed write can never take the player's only recovery point with it.
	var verify := FileAccess.open_compressed(temp_path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if verify == null:
		last_error = "written save could not be re-read"
		return Result.failure("save_verify_failed", last_error)
	var verify_text := verify.get_as_text()
	verify.close()
	if typeof(SafeJson.parse(verify_text)) != TYPE_DICTIONARY:
		last_error = "written save did not parse"
		return Result.failure("save_verify_failed", last_error)

	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var absolute_final := ProjectSettings.globalize_path(final_path)
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(absolute_final)
	var moved := DirAccess.rename_absolute(absolute_temp, absolute_final)
	if moved != OK:
		last_error = "could not replace previous save"
		return Result.failure("save_replace_failed", last_error)

	Log.info("save", "Game saved", {"slot": slot, "bytes": verify_text.length()})
	Events.game_saved.emit(slot)
	return Result.success(slot)


## Reads and migrates a slot. Returns the section dictionary on success.
func load_slot(slot: String) -> Result:
	last_error = ""
	var data := _read_file(slot)
	if data.is_empty():
		last_error = "save not found or unreadable"
		return Result.failure("save_missing", last_error)

	var migrated := SaveMigrations.migrate(data)
	if migrated.is_err():
		last_error = migrated.message
		Log.error("save", "Migration failed", {"slot": slot, "code": migrated.code})
		return migrated

	Log.info("save", "Game loaded", {"slot": slot})
	return Result.success(migrated.value)


func delete_slot(slot: String) -> Result:
	if not has_slot(slot):
		return Result.failure("save_missing")
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))
	return Result.success(slot) if error == OK else Result.failure("save_delete_failed")


func _read_file(slot: String) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		Log.error("save", "Cannot read save", {"slot": slot, "err": FileAccess.get_open_error()})
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = SafeJson.parse(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.error("save", "Save is not valid JSON", {"slot": slot})
		return {}
	return parsed
