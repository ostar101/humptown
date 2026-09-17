extends Node
## User settings, persisted to user://settings.json. Autoload: Settings
##
## API keys are deliberately NOT stored here. They live in the encrypted
## SecretStore (see src/llm/secret_store.gd and DECISIONS.md D-006) so that
## settings.json stays safe to share when someone reports a bug.

const SETTINGS_PATH := "user://settings.json"

const DEFAULTS := {
	"locale": "en",
	"master_volume": 0.8,
	"music_volume": 0.6,
	"sfx_volume": 0.8,
	"text_speed": 45.0,            # characters per second in dialogue
	"window_mode": 0,              # 0 windowed, 1 fullscreen
	"developer_mode": false,
	"log_level": 2,                # Log.Level.INFO
	"minutes_per_real_second": 1.0,
	# --- LLM -------------------------------------------------------------
	"llm_provider": "none",        # none | openai | anthropic | google | openrouter
	"llm_main_model": "",
	"llm_cheap_model": "",
	"llm_routing_mode": "balanced",# cheap_first | balanced | quality
	"llm_temperature": 0.8,
	"llm_max_output_tokens": 400,
	"llm_timeout_seconds": 20.0,
	"llm_max_retries": 2,
	"llm_daily_request_cap": 600,
	"llm_debug_capture": false,
}

var _values: Dictionary = {}


func _ready() -> void:
	load_settings()


func get_value(key: String, fallback: Variant = null) -> Variant:
	if _values.has(key):
		return _values[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return fallback


func set_value(key: String, value: Variant, save_now: bool = true) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	Events.settings_changed.emit(key)
	if save_now:
		save_settings()


func all() -> Dictionary:
	var merged := DEFAULTS.duplicate(true)
	merged.merge(_values, true)
	return merged


func reset_to_defaults() -> void:
	_values.clear()
	save_settings()
	Events.settings_changed.emit("*")


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		_values = {}
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		Log.warn("settings", "Could not open settings file", {"err": FileAccess.get_open_error()})
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = SafeJson.parse(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		Log.warn("settings", "Settings file is not valid JSON; using defaults")
		_values = {}
		return
	# Drop unknown keys so a downgrade cannot resurrect stale options.
	_values = {}
	for key in parsed:
		if DEFAULTS.has(key):
			_values[key] = parsed[key]
	Log.info("settings", "Settings loaded", {"count": _values.size()})


func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		Log.error("settings", "Could not write settings", {"err": FileAccess.get_open_error()})
		return
	file.store_string(JSON.stringify(all(), "\t", false))
	file.close()
