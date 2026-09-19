extends Node
## Headless test entry point.
##
## Run with:
##     godot --headless --path . res://tests/test_runner.tscn
##
## Runs as a scene rather than a --script main loop so that the project's
## autoloads (Log, Events, Settings, Game) exist exactly as they do in the
## real game. A test harness that runs against a different wiring than the
## game is worse than no harness.

const TEST_DIR := "res://tests/"
## Sleeping in your bed saves (D-033); tests sleep, and must never do it over
## the player's own life.
const TEST_SAVE_SLOT := "test_runner_main"
## Nor over the player's API keys, when a test stores one (D-036).
const TEST_SECRETS_PATH := "user://test_runner_secrets.dat"

var total_tests := 0
var total_assertions := 0
var failures: Array[String] = []
var _errors := TestErrorCounter.new()


func _ready() -> void:
	Log.min_level = Log.Level.ERROR    # keep the report readable
	OS.add_logger(_errors)
	Game.save_slot = TEST_SAVE_SLOT
	# A test run starts from the default settings, whatever this machine has
	# saved, and never writes them back (D-036).
	Settings.persist = false
	Settings.reset_to_defaults()
	# It never reaches a real provider either, whatever a test configures: no
	# network, no cost, no key leaving the machine — and its keys are its own.
	Game.llm.sandboxed = true
	Game.llm.secrets = SecretStore.new(TEST_SECRETS_PATH)
	Game.llm.reconfigure()
	# Let the root finish setting up, so tests may add scenes to the tree.
	await get_tree().process_frame
	var started := Time.get_ticks_msec()

	print("")
	print("=== Humptown test suite ===")
	print("")

	for path in _discover():
		await _run_file(path)

	var elapsed := Time.get_ticks_msec() - started
	print("")
	print("---------------------------------------------")
	if failures.is_empty():
		print("PASSED  %d tests, %d assertions in %d ms" % [total_tests, total_assertions, elapsed])
	else:
		print("FAILED  %d of %d tests (%d assertions) in %d ms" % [
			failures.size(), total_tests, total_assertions, elapsed])
		print("")
		for failure in failures:
			print("  x " + failure)
	print("---------------------------------------------")
	print("")

	# Tear the world down and let one frame pass before quitting, so objects
	# created during the run are released rather than reported as leaked.
	Game.unload()
	Game.saves.delete_slot(TEST_SAVE_SLOT)
	Game.llm.secrets.clear_all()
	await get_tree().process_frame
	OS.remove_logger(_errors)
	get_tree().quit(0 if failures.is_empty() else 1)


func _discover() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		push_error("Cannot open test directory")
		return found
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.begins_with("test_") and name.ends_with(".gd") \
				and name != "test_case.gd" and name != "test_runner.gd":
			found.append(TEST_DIR + name)
		name = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found


func _run_file(path: String) -> void:
	var script: GDScript = load(path)
	if script == null:
		failures.append("%s: could not be loaded" % path)
		return

	var suite_name := path.get_file().replace(".gd", "")
	var methods := script.get_script_method_list()
	var test_names: Array[String] = []
	for method in methods:
		var method_name := str(method["name"])
		if method_name.begins_with("test_") and not (method_name in test_names):
			test_names.append(method_name)
	if test_names.is_empty():
		return

	var suite_failures := 0
	for test_name in test_names:
		# A fresh instance per test: shared state between tests is the most
		# common source of a suite that passes only in one order.
		var instance: TestCase = script.new()
		instance.set_current_test("%s.%s" % [suite_name, test_name])
		total_tests += 1
		var errors_before := _errors.count()
		instance.before_each()
		# Awaiting works for plain and coroutine tests alike, so a test that
		# needs real frames (physics, scenes) can simply `await` them.
		await Callable(instance, test_name).call()
		instance.after_each()
		total_assertions += instance.assertions
		if _errors.count() != errors_before:
			instance.failures.append("%s.%s: engine or script error: %s" % [
				suite_name, test_name, _errors.last()])
		for failure in instance.failures:
			failures.append(failure)
			suite_failures += 1

	var mark := "ok  " if suite_failures == 0 else "FAIL"
	print("  %s %-28s %d tests" % [mark, suite_name, test_names.size()])
