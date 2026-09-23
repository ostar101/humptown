extends TestCase
## Save persistence and forward migration.

const SLOT := "test_slot"

var saves: SaveManager


func before_each() -> void:
	saves = SaveManager.new()
	saves.delete_slot(SLOT)


func after_each() -> void:
	saves.delete_slot(SLOT)


func test_round_trip_preserves_sections() -> void:
	var sections := {
		"player": {"display_name": "Test", "wallet": {"cash": 55}},
		"world": {"current_region": "harbourside", "flags": {"grew_up_here": true}},
		"clock": {"total_minutes": 1234},
	}
	assert_ok(saves.save(SLOT, sections, {"player_name": "Test"}))
	var loaded := saves.load_slot(SLOT)
	assert_ok(loaded)
	var data: Dictionary = loaded.value
	assert_eq(data["player"]["wallet"]["cash"], 55)
	assert_eq(data["world"]["flags"]["grew_up_here"], true)
	assert_eq(data["clock"]["total_minutes"], 1234)


func test_saves_carry_a_schema_version() -> void:
	saves.save(SLOT, {})
	var data: Dictionary = saves.load_slot(SLOT).value
	assert_eq(data["schema_version"], SaveMigrations.CURRENT_VERSION)


func test_header_reads_without_a_full_load() -> void:
	saves.save(SLOT, {"clock": {"total_minutes": 60}},
		{"player_name": "Ida", "region": "harbourside"})
	var header := saves.read_header(SLOT)
	assert_eq(header["meta"]["player_name"], "Ida")
	assert_true(header["loadable"])
	assert_gt(float(header["saved_at"]), 0.0)


## Played on past the save, then went back to it: the periodic retier must
## carry on from the loaded minute, not wait for the clock to catch up with
## where the abandoned life had got to.
func test_loading_an_earlier_save_keeps_the_retier_going() -> void:
	assert_ok(Game.new_game("", 3))
	assert_ok(Game.save_game(Game.save_slot))
	Game._last_retier = Game.clock.total_minutes + 5000   # the life that was not saved
	assert_ok(Game.load_game(Game.save_slot))
	var minute := Game.clock.total_minutes + Game.RETIER_INTERVAL
	Game._on_minute(minute)
	assert_eq(Game._last_retier, minute, "tiers were reassigned on schedule")
	saves.delete_slot(Game.save_slot)


func test_saving_over_a_save_leaves_nothing_half_done_behind() -> void:
	assert_ok(saves.save(SLOT, {"clock": {"total_minutes": 1}}))
	assert_ok(saves.save(SLOT, {"clock": {"total_minutes": 2}}))
	assert_eq(saves.load_slot(SLOT).value["clock"]["total_minutes"], 2)
	assert_false(FileAccess.file_exists(saves.slot_path(SLOT) + ".tmp"))
	assert_false(FileAccess.file_exists(saves.slot_path(SLOT) + ".bak"))


## Stopped between setting the old save aside and putting the new one in its
## place: the old one is still what loads.
func test_a_save_interrupted_mid_swap_still_loads_the_last_good_one() -> void:
	assert_ok(saves.save(SLOT, {"clock": {"total_minutes": 5}}))
	var path := ProjectSettings.globalize_path(saves.slot_path(SLOT))
	assert_eq(DirAccess.rename_absolute(path, path + ".bak"), OK)
	assert_true(saves.has_slot(SLOT))
	assert_eq(saves.load_slot(SLOT).value["clock"]["total_minutes"], 5)
	assert_ok(saves.delete_slot(SLOT))
	assert_false(saves.has_slot(SLOT), "the backup goes with the slot")


func test_missing_slots_fail_gracefully() -> void:
	assert_err(saves.load_slot("does_not_exist"), "save_missing")
	assert_false(saves.has_slot("does_not_exist"))


func test_deleting_a_slot() -> void:
	saves.save(SLOT, {})
	assert_true(saves.has_slot(SLOT))
	assert_ok(saves.delete_slot(SLOT))
	assert_false(saves.has_slot(SLOT))
	assert_err(saves.delete_slot(SLOT), "save_missing")


func test_overwriting_keeps_the_slot_readable() -> void:
	# The rule that matters most: a save must never destroy the previous one
	# without a verified replacement in hand.
	saves.save(SLOT, {"clock": {"total_minutes": 1}})
	saves.save(SLOT, {"clock": {"total_minutes": 2}})
	var data: Dictionary = saves.load_slot(SLOT).value
	assert_eq(data["clock"]["total_minutes"], 2)


func test_slot_listing_includes_saved_slots() -> void:
	saves.save(SLOT, {}, {"player_name": "Test"})
	var found := false
	for entry in saves.list_slots():
		if entry["slot"] == SLOT:
			found = true
	assert_true(found)


# --- migration --------------------------------------------------------------

func test_current_version_saves_need_no_migration() -> void:
	var data := {"schema_version": SaveMigrations.CURRENT_VERSION, "player": {"x": 1}}
	var migrated := SaveMigrations.migrate(data)
	assert_ok(migrated)
	assert_eq(migrated.value["player"]["x"], 1)


func test_saves_from_the_future_are_refused_clearly() -> void:
	var migrated := SaveMigrations.migrate({"schema_version": 999})
	assert_err(migrated, "save_too_new")
	assert_true(migrated.message.contains("999"),
		"the player is told which version they need")


func test_unversioned_data_is_refused() -> void:
	assert_err(SaveMigrations.migrate({"player": {}}), "save_unversioned")


func test_can_load_reports_reachable_versions() -> void:
	assert_true(SaveMigrations.can_load(SaveMigrations.CURRENT_VERSION))
	assert_false(SaveMigrations.can_load(SaveMigrations.CURRENT_VERSION + 1))
	assert_false(SaveMigrations.can_load(0))


func test_migration_does_not_mutate_the_input() -> void:
	var original := {"schema_version": SaveMigrations.CURRENT_VERSION, "player": {"cash": 10}}
	SaveMigrations.migrate(original)
	assert_eq(original["player"]["cash"], 10)


func test_every_registered_step_is_reachable() -> void:
	# Guards the most likely migration bug: bumping CURRENT_VERSION and
	# forgetting to register the step that bridges the gap.
	for version in range(1, SaveMigrations.CURRENT_VERSION):
		assert_has(SaveMigrations.STEPS, version,
			"no migration registered from version %d" % version)
