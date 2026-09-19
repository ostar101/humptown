class_name SettingsScreen
extends Node
## The language, and — if the player wants it — the model that speaks for
## the people of the town (D-036).
##
## The API key is the player's own. The player pastes it here; SecretStore
## keeps it encrypted (D-006); the field is emptied the moment it is saved,
## and from then on the screen only ever says *whether* a key is stored.
## Every change applies at once: there is no "apply" to forget, and Back is
## always safe.

const TITLE := "res://scenes/ui/title_screen.tscn"
const ROUTING_MODES: Array[String] = ["cheap_first", "balanced", "quality"]

## Where the key goes. Defaults to the game's own store; the test runner
## gives the game a store of its own, so tests never touch the player's keys.
var secrets: SecretStore

## Where this screen goes next. Tests set `scene_changer` to see where it would
## go without replacing the test runner's own scene.
var scene_changer: Callable = Callable()

var _locales: Array[String] = []
var _providers: Array[String] = []

@onready var _language: OptionButton = %Language
@onready var _provider: OptionButton = %Provider
@onready var _key_edit: LineEdit = %KeyEdit
@onready var _save_key: Button = %SaveKey
@onready var _forget_key: Button = %ForgetKey
@onready var _main_model: LineEdit = %MainModel
@onready var _cheap_model: LineEdit = %CheapModel
@onready var _routing: OptionButton = %Routing
@onready var _status: Label = %Status
@onready var _privacy: Label = %Privacy
@onready var _notice: Label = %Notice
@onready var _back: Button = %Back


func _ready() -> void:
	if secrets == null:
		secrets = Game.llm.secrets
	_locales = Localization.available_locales()
	_locales.sort()
	_providers = LlmClient.available_provider_ids()
	_fill_options()
	refresh()

	_language.item_selected.connect(func(index: int) -> void: choose_language(_locales[index]))
	_provider.item_selected.connect(func(index: int) -> void: choose_provider(_providers[index]))
	_routing.item_selected.connect(func(index: int) -> void: choose_routing(ROUTING_MODES[index]))
	_save_key.pressed.connect(func() -> void: save_key(_key_edit.text))
	_key_edit.text_submitted.connect(func(text: String) -> void: save_key(text))
	_forget_key.pressed.connect(forget_key)
	_main_model.text_submitted.connect(func(text: String) -> void: set_model("llm_main_model", text))
	_main_model.focus_exited.connect(func() -> void: set_model("llm_main_model", _main_model.text))
	_cheap_model.text_submitted.connect(func(text: String) -> void: set_model("llm_cheap_model", text))
	_cheap_model.focus_exited.connect(func() -> void: set_model("llm_cheap_model", _cheap_model.text))
	_back.pressed.connect(go_back)
	Events.locale_changed.connect(_on_locale_changed)
	_language.grab_focus()
	DevCapture.maybe_capture(self)


# --- what the player can do ----------------------------------------------------

func choose_language(locale: String) -> void:
	Localization.set_locale(locale)


## Choosing a provider also offers its models, unless the player has typed
## their own: a model name from another provider is never left behind.
func choose_provider(provider_id: String) -> void:
	Settings.set_value("llm_provider", provider_id)
	var suggested := LlmClient.make_provider(provider_id).suggested_models()
	for pair in [["llm_main_model", "main"], ["llm_cheap_model", "cheap"]]:
		var current := str(Settings.get_value(pair[0], ""))
		if current == "" or _is_suggested_elsewhere(current, provider_id):
			var offers: Array = suggested.get(pair[1], [])
			Settings.set_value(pair[0], str(offers[0]) if not offers.is_empty() else "")
	_notice.text = ""
	refresh()


func save_key(text: String) -> Result:
	var key := text.strip_edges()
	var provider_id := _provider_id()
	var saved: Result
	if provider_id == "none":
		saved = Result.failure("no_provider")
	elif key.is_empty():
		saved = Result.failure("empty_key")
	else:
		saved = secrets.set_key(provider_id, key)
	# Saved or not, the key does not stay on screen.
	_key_edit.text = ""
	_notice.text = Localization.t("ui.settings.key_saved") if saved.is_ok() \
		else Localization.t("ui.settings.refusal." + saved.code)
	refresh()
	return saved


func forget_key() -> Result:
	var provider_id := _provider_id()
	if provider_id == "none" or not secrets.has_key(provider_id):
		return Result.failure("no_key")
	var forgotten := secrets.set_key(provider_id, "")
	if forgotten.is_ok():
		_notice.text = Localization.t("ui.settings.key_forgotten")
	refresh()
	return forgotten


func set_model(setting: String, text: String) -> void:
	Settings.set_value(setting, text.strip_edges())
	refresh()


func choose_routing(mode: String) -> void:
	Settings.set_value("llm_routing_mode", mode)
	refresh()


func go_back() -> void:
	_go(TITLE)


# --- what the screen says ------------------------------------------------------

## Whether people will answer in their own words, and if not, why not — the
## same conditions `LlmClient.is_available` checks, read from the settings.
static func status_key(provider_id: String, has_key: bool, main_model: String, cheap_model: String) -> String:
	if provider_id == "none":
		return "ui.settings.status.offline"
	if not has_key:
		return "ui.settings.status.no_key"
	if main_model.strip_edges() == "" and cheap_model.strip_edges() == "":
		return "ui.settings.status.no_model"
	return "ui.settings.status.ready"


func status_text() -> String:
	return _status.text


func refresh() -> void:
	var provider_id := _provider_id()
	var provider := LlmClient.make_provider(provider_id)
	var named := {"provider": provider.display_name()}
	var has_key := provider_id != "none" and secrets.has_key(provider_id)

	_language.select(maxi(_locales.find(Localization.current_locale()), 0))
	_provider.select(maxi(_providers.find(provider_id), 0))
	_routing.select(maxi(ROUTING_MODES.find(str(Settings.get_value("llm_routing_mode", "balanced"))), 0))

	var online := provider_id != "none"
	_key_edit.editable = online
	_save_key.disabled = not online
	_forget_key.disabled = not has_key
	if not online:
		_key_edit.placeholder_text = Localization.t("ui.settings.key_needs_provider")
	elif has_key:
		_key_edit.placeholder_text = Localization.t("ui.settings.key_stored")
	else:
		_key_edit.placeholder_text = Localization.t("ui.settings.key_placeholder", named)

	var suggested := provider.suggested_models()
	for pair in [[_main_model, "llm_main_model", "main"], [_cheap_model, "llm_cheap_model", "cheap"]]:
		var edit: LineEdit = pair[0]
		edit.editable = online
		if not edit.has_focus():
			edit.text = str(Settings.get_value(pair[1], ""))
		var offers: Array = suggested.get(pair[2], [])
		edit.placeholder_text = Localization.t("ui.settings.model_placeholder", {"model": offers[0]}) \
			if not offers.is_empty() else ""
	_routing.disabled = not online

	_status.text = Localization.t(status_key(provider_id, has_key,
		str(Settings.get_value("llm_main_model", "")), str(Settings.get_value("llm_cheap_model", ""))), named)
	_privacy.text = Localization.t("ui.settings.privacy", named) if online else ""


# --- internals -------------------------------------------------------------------

func _provider_id() -> String:
	var provider_id := str(Settings.get_value("llm_provider", "none"))
	return provider_id if provider_id in _providers else "none"


func _is_suggested_elsewhere(model: String, provider_id: String) -> bool:
	for other in _providers:
		if other == provider_id:
			continue
		var suggested := LlmClient.make_provider(other).suggested_models()
		if model in suggested.get("main", []) or model in suggested.get("cheap", []):
			return true
	return false


## Option texts come from the locale in code, not from the scene, so they can
## be rebuilt when the language changes under them.
func _fill_options() -> void:
	_language.clear()
	for locale in _locales:
		_language.add_item(Localization.t("ui.settings.locale." + locale))
	_provider.clear()
	for provider_id in _providers:
		_provider.add_item(Localization.t("ui.settings.provider.none") if provider_id == "none"
			else LlmClient.make_provider(provider_id).display_name())
	_routing.clear()
	for mode in ROUTING_MODES:
		_routing.add_item(Localization.t("ui.settings.routing." + mode))


func _on_locale_changed(_locale: String) -> void:
	_fill_options()
	_notice.text = ""
	refresh()


func _go(path: String) -> void:
	if scene_changer.is_valid():
		scene_changer.call(path)
	else:
		get_tree().change_scene_to_file(path)
