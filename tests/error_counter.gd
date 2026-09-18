class_name TestErrorCounter
extends Logger
## Counts engine and script errors while the suite runs.
##
## GDScript cannot catch a runtime error: the failing test function simply
## stops, and without this the runner would report it as passed. The runner
## compares the count before and after each test and fails any test during
## which an error was logged. Warnings are not counted.

var _mutex := Mutex.new()
var _count := 0
var _last := ""


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	_mutex.lock()
	_count += 1
	var what := rationale if not rationale.is_empty() else code
	_last = "%s (%s:%d in %s)" % [what, file.get_file(), line, function]
	_mutex.unlock()


func count() -> int:
	_mutex.lock()
	var c := _count
	_mutex.unlock()
	return c


func last() -> String:
	_mutex.lock()
	var l := _last
	_mutex.unlock()
	return l
