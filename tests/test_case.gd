class_name TestCase
extends RefCounted
## Minimal test base class. Zero dependencies on purpose: a test framework is
## not where this project should spend its dependency budget, and a runner
## small enough to read in one sitting is one nobody is afraid to change.
##
## Write a test by extending this and adding methods named test_*. Use
## before_each()/after_each() for fixtures.

var failures: Array[String] = []
var assertions: int = 0
var _current: String = ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func set_current_test(name: String) -> void:
	_current = name


# --- assertions -------------------------------------------------------------

func assert_true(condition: bool, message: String = "") -> void:
	assertions += 1
	if not condition:
		_fail("expected true", message)


func assert_false(condition: bool, message: String = "") -> void:
	assertions += 1
	if condition:
		_fail("expected false", message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertions += 1
	if not _values_equal(actual, expected):
		_fail("expected %s but got %s" % [_show(expected), _show(actual)], message)


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	assertions += 1
	if _values_equal(actual, unexpected):
		_fail("expected something other than %s" % _show(unexpected), message)


func assert_almost(actual: float, expected: float, tolerance: float = 0.0001, message: String = "") -> void:
	assertions += 1
	if absf(actual - expected) > tolerance:
		_fail("expected %f (+/- %f) but got %f" % [expected, tolerance, actual], message)


func assert_gt(actual: float, threshold: float, message: String = "") -> void:
	assertions += 1
	if actual <= threshold:
		_fail("expected > %f but got %f" % [threshold, actual], message)


func assert_lt(actual: float, threshold: float, message: String = "") -> void:
	assertions += 1
	if actual >= threshold:
		_fail("expected < %f but got %f" % [threshold, actual], message)


func assert_null(value: Variant, message: String = "") -> void:
	assertions += 1
	if value != null:
		_fail("expected null but got %s" % _show(value), message)


func assert_not_null(value: Variant, message: String = "") -> void:
	assertions += 1
	if value == null:
		_fail("expected a value but got null", message)


func assert_has(container: Variant, key: Variant, message: String = "") -> void:
	assertions += 1
	var present := false
	if typeof(container) == TYPE_DICTIONARY:
		present = container.has(key)
	else:
		# Covers Array and every Packed*Array, which is what provider header
		# lists are.
		present = key in container
	if not present:
		_fail("expected to find %s in %s" % [_show(key), _show(container)], message)


func assert_ok(result: Result, message: String = "") -> void:
	assertions += 1
	if result == null:
		_fail("expected a Result but got null", message)
	elif result.is_err():
		_fail("expected success but failed with '%s' (%s)" % [result.code, result.message], message)


func assert_err(result: Result, expected_code: String = "", message: String = "") -> void:
	assertions += 1
	if result == null:
		_fail("expected a Result but got null", message)
	elif result.is_ok():
		_fail("expected failure but succeeded", message)
	elif not expected_code.is_empty() and result.code != expected_code:
		_fail("expected failure '%s' but got '%s'" % [expected_code, result.code], message)


func fail(message: String) -> void:
	assertions += 1
	_fail("explicit failure", message)


func _fail(detail: String, message: String) -> void:
	var text := "%s: %s" % [_current, detail]
	if not message.is_empty():
		text += " -- " + message
	failures.append(text)


func _values_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b


func _show(value: Variant) -> String:
	if typeof(value) == TYPE_STRING:
		return "'%s'" % value
	return str(value)
