extends TestCase
## The settings screen (D-036): language, provider, the player's own API key
## and the models. Driven through its public methods, the way its controls
## drive it. The runner has already sandboxed settings, secrets and the LLM
## client; the first test checks that it really has, because every other test
## here would otherwise be writing over the player's own.

const SETTINGS_SCENE := "res://scenes/ui/settings_screen.tscn"
const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
## Obviously not a key. Real keys never appear in this repository.
const FAKE_KEY := "test-key-not-real-0000-abcd"

var _went_to: Array[String] = []
var _screen: SettingsScreen


func before_each() -> void:
	_went_to = []
	Settings.reset_to_defaults()
	Game.llm.secrets.clear_all()
	Localization.set_locale("en")


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	Settings.reset_to_defaults()
	Game.llm.secrets.clear_all()
	Localization.set_locale("en")


func _spawn(path: String) -> Node:
	var node: Node = (load(path) as PackedScene).instantiate()
	node.set("scene_changer", func(target: String) -> void: _went_to.append(target))
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	return node


func _open() -> SettingsScreen:
	_screen = _spawn(SETTINGS_SCENE)
	return _screen


func _every_text_on(node: Node) -> Array[String]:
	var texts: Array[String] = []
	if node is Label:
		texts.append((node as Label).text)
	elif node is LineEdit:
		texts.append((node as LineEdit).text)
		texts.append((node as LineEdit).placeholder_text)
	elif node is Button:
		texts.append((node as Button).text)
	for child in node.get_children():
		texts.append_array(_every_text_on(child))
	return texts


# --- the sandbox ---------------------------------------------------------------

func test_the_runner_keeps_tests_away_from_the_players_own_settings_and_keys() -> void:
	assert_false(Settings.persist, "tests must never write settings.json")
	assert_ne(Game.llm.secrets.path, SecretStore.SECRET_PATH, "tests must never touch secrets.dat")
	assert_true(Game.llm.sandboxed)
	Settings.set_value("llm_provider", "anthropic")
	assert_eq(Game.llm.provider.id(), "none", "whatever a test configures, no real provider is built")


# --- getting there -------------------------------------------------------------

func test_the_title_screen_opens_the_settings_and_back_returns() -> void:
	var title: TitleScreen = _spawn(TITLE_SCENE)
	title.open_settings()
	assert_eq(_went_to, [TitleScreen.SETTINGS])
	title.free()
	_open().go_back()
	assert_eq(_went_to[-1], SettingsScreen.TITLE)


# --- provider and models -------------------------------------------------------

func test_it_starts_offline_and_says_so() -> void:
	var screen := _open()
	assert_eq(screen.status_text(), Localization.t("ui.settings.status.offline"))


func test_choosing_a_provider_offers_its_models() -> void:
	var screen := _open()
	screen.choose_provider("anthropic")
	assert_eq(Settings.get_value("llm_provider"), "anthropic")
	assert_eq(Settings.get_value("llm_main_model"), "claude-opus-5")
	assert_eq(Settings.get_value("llm_cheap_model"), "claude-haiku-4-5")
	assert_eq(screen.status_text(), Localization.t("ui.settings.status.no_key", {"provider": "Anthropic"}))


func test_switching_provider_does_not_leave_another_providers_model_behind() -> void:
	var screen := _open()
	screen.choose_provider("anthropic")
	screen.choose_provider("openai")
	assert_false(str(Settings.get_value("llm_main_model")).begins_with("claude"), "a Claude model is useless at OpenAI")


func test_a_model_the_player_typed_is_kept() -> void:
	var screen := _open()
	screen.set_model("llm_main_model", "  my-own-model  ")
	screen.choose_provider("anthropic")
	assert_eq(Settings.get_value("llm_main_model"), "my-own-model", "trimmed, and not replaced by a suggestion")


# --- the key ---------------------------------------------------------------------

func test_a_saved_key_goes_to_the_secret_store_and_leaves_the_screen() -> void:
	var screen := _open()
	screen.choose_provider("anthropic")
	assert_ok(screen.save_key("  " + FAKE_KEY + "  "))
	assert_eq(Game.llm.secrets.get_key("anthropic"), FAKE_KEY, "trimmed and stored")
	assert_eq(Settings.all().values().filter(func(v: Variant) -> bool: return str(v).contains(FAKE_KEY)).size(), 0,
		"a key never enters settings.json")
	for text in _every_text_on(screen):
		assert_false(text.contains(FAKE_KEY) or text.contains(FAKE_KEY.right(4)), "the key is never shown again")
	assert_eq(screen.status_text(), Localization.t("ui.settings.status.ready", {"provider": "Anthropic"}))


func test_a_key_needs_a_provider_and_something_to_save() -> void:
	var screen := _open()
	assert_err(screen.save_key(FAKE_KEY), "no_provider")
	assert_true(Game.llm.secrets.configured_providers().is_empty())
	screen.choose_provider("openai")
	assert_err(screen.save_key("   "), "empty_key")
	assert_false(Game.llm.secrets.has_key("openai"))


func test_forgetting_a_key_removes_it() -> void:
	var screen := _open()
	screen.choose_provider("anthropic")
	assert_ok(screen.save_key(FAKE_KEY))
	assert_ok(screen.forget_key())
	assert_false(Game.llm.secrets.has_key("anthropic"))
	assert_err(screen.forget_key(), "no_key")


func test_without_a_model_it_says_so() -> void:
	var screen := _open()
	screen.choose_provider("anthropic")
	assert_ok(screen.save_key(FAKE_KEY))
	screen.set_model("llm_main_model", "")
	screen.set_model("llm_cheap_model", "")
	assert_eq(screen.status_text(), Localization.t("ui.settings.status.no_model"))


func test_the_status_follows_the_clients_conditions() -> void:
	assert_eq(SettingsScreen.status_key("none", true, "m", "m"), "ui.settings.status.offline")
	assert_eq(SettingsScreen.status_key("openai", false, "m", ""), "ui.settings.status.no_key")
	assert_eq(SettingsScreen.status_key("openai", true, "", " "), "ui.settings.status.no_model")
	assert_eq(SettingsScreen.status_key("openai", true, "", "cheap"), "ui.settings.status.ready",
		"one model serves every purpose when it is the only one")


# --- language and routing ----------------------------------------------------------

func test_choosing_finnish_changes_the_screen() -> void:
	var screen := _open()
	screen.choose_language("fi")
	assert_eq(Localization.current_locale(), "fi")
	assert_eq(screen.status_text(), Localization.t("ui.settings.status.offline"))
	assert_true(screen.status_text().contains("kirjoitetuilla"), screen.status_text())


func test_routing_is_a_setting() -> void:
	var screen := _open()
	screen.choose_routing("quality")
	assert_eq(Settings.get_value("llm_routing_mode"), "quality")
