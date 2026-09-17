class_name Localization
extends RefCounted
## Runtime localisation from JSON files in res://locale/.
##
## JSON rather than Godot's CSV pipeline so that translations need no editor
## import step: headless tests and CI see exactly what the game sees, and
## adding a language is dropping in one file. English is the base and the
## fallback; a missing key renders as the key itself, which makes gaps loud
## in testing rather than silently blank on screen.

const LOCALE_DIR := "res://locale/"
const FALLBACK := "en"

static var _loaded: Array[String] = []


## Loads every locale file and applies the saved language preference.
static func setup() -> void:
	_loaded.clear()
	var dir := DirAccess.open(LOCALE_DIR)
	if dir == null:
		Log.warn("loc", "No locale directory found")
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.ends_with(".json"):
			_load_locale(name.substr(0, name.length() - 5))
		name = dir.get_next()
	dir.list_dir_end()

	set_locale(str(Settings.get_value("locale", FALLBACK)))
	Log.info("loc", "Localisation ready", {"locales": _loaded})


static func available_locales() -> Array[String]:
	return _loaded.duplicate()


static func set_locale(locale: String) -> void:
	if not (locale in _loaded) and locale != FALLBACK:
		Log.warn("loc", "Unknown locale requested", {"locale": locale})
		locale = FALLBACK
	TranslationServer.set_locale(locale)
	Settings.set_value("locale", locale)
	Events.locale_changed.emit(locale)


static func current_locale() -> String:
	return TranslationServer.get_locale()


## Translates with named placeholders: t("greeting", {"name": "Ida"})
## where the entry is "Hello, {name}."
static func t(key: String, args: Dictionary = {}) -> String:
	var text := String(TranslationServer.translate(key))
	for placeholder in args:
		text = text.replace("{%s}" % placeholder, str(args[placeholder]))
	return text


## Keys present in the base locale but missing from another. Used by a test
## so a half-finished translation cannot ship unnoticed.
static func missing_keys(locale: String) -> Array[String]:
	var base := _read_locale(FALLBACK)
	var other := _read_locale(locale)
	var out: Array[String] = []
	for key in base:
		if not other.has(key):
			out.append(str(key))
	return out


## Keys a translation defines that the base locale does not. These can never
## be reached through the fallback, so they are dead weight or a typo.
static func missing_keys_in_base(locale: String) -> Array[String]:
	var base := _read_locale(FALLBACK)
	var other := _read_locale(locale)
	var out: Array[String] = []
	for key in other:
		if not base.has(key):
			out.append(str(key))
	return out


static func _load_locale(locale: String) -> void:
	var entries := _read_locale(locale)
	if entries.is_empty():
		return
	var translation := Translation.new()
	translation.locale = locale
	for key in entries:
		translation.add_message(StringName(key), str(entries[key]))
	TranslationServer.add_translation(translation)
	_loaded.append(locale)


static func _read_locale(locale: String) -> Dictionary:
	var path := LOCALE_DIR + locale + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = SafeJson.parse(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.error("loc", "Locale file is not a JSON object", {"locale": locale})
		return {}
	return parsed
