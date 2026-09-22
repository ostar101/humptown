extends TestCase
## Localisation wiring and translation coverage.

func test_english_is_available() -> void:
	assert_has(Localization.available_locales(), "en")


func test_finnish_is_available() -> void:
	assert_has(Localization.available_locales(), "fi")


func test_keys_resolve_in_english() -> void:
	Localization.set_locale("en")
	assert_eq(tr("region.harbourside"), "Harbourside")
	assert_eq(tr("ui.inventory"), "Inventory")


func test_switching_locale_changes_output() -> void:
	Localization.set_locale("fi")
	assert_eq(tr("ui.inventory"), "Tavarat")
	Localization.set_locale("en")
	assert_eq(tr("ui.inventory"), "Inventory")


func test_unknown_locales_fall_back_to_english() -> void:
	Localization.set_locale("xx")
	assert_eq(Localization.current_locale(), "en")


func test_unknown_keys_render_as_the_key() -> void:
	# Loud rather than blank: a missing string should be obvious in testing.
	Localization.set_locale("en")
	assert_eq(tr("this.key.does.not.exist"), "this.key.does.not.exist")


func test_placeholder_substitution() -> void:
	Localization.set_locale("en")
	assert_eq(Localization.t("ui.cash", {}), "Cash")
	assert_eq(Localization.t("{name} is here", {"name": "Ida"}), "Ida is here")


func test_english_covers_every_key_any_locale_defines() -> void:
	# English is the base. A key that exists only in a translation can never
	# be reached through the fallback, so it is a content bug.
	for locale in Localization.available_locales():
		if locale == "en":
			continue
		var orphans := Localization.missing_keys_in_base(locale)
		assert_eq(orphans.size(), 0,
			"%s defines keys English does not: %s" % [locale, ", ".join(orphans)])


func test_translation_gaps_are_reported_not_fatal() -> void:
	# Finnish is deliberately incomplete; the point is that we can measure it
	# and that the gaps fall back to English rather than rendering blank.
	var missing := Localization.missing_keys("fi")
	Localization.set_locale("fi")
	for key in missing.slice(0, 5):
		assert_ne(tr(key), "", "missing translations must fall back, not blank")
	Localization.set_locale("en")


## Checks every content table's `name_key`, never an item's `.desc` (M8 step
## 5, D-081): that sentence is deliberately optional, authored for ~30 of
## 115 items where the generated facts cannot speak for it, and its absence
## is not a content bug — `ItemFacts.description_of` treats "" as normal.
func test_content_name_keys_all_have_english_strings() -> void:
	Localization.set_locale("en")
	var data := DataRegistry.new()
	data.load_all()
	for table_name in ["regions", "locations", "occupations", "skills", "items", "backgrounds"]:
		for id in data.ids(table_name):
			var key := str(data.get_entry(table_name, id).get("name_key", ""))
			if key.is_empty():
				continue
			assert_ne(tr(key), key, "%s.%s has no English string (%s)" % [table_name, id, key])
