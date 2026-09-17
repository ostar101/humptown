class_name Result
extends RefCounted
## A success/failure value used wherever an operation can legitimately be
## refused rather than crash.
##
## This is the backbone of the "LLM proposes, Godot disposes" rule: every
## validator in the execution layer returns a Result, so a rejected action
## carries a machine-readable reason code that debug mode can display and
## that dialogue can turn into an in-world explanation.

var ok: bool
## Reason code on failure, e.g. "not_present", "locked", "insufficient_funds".
var code: String
## Human-facing message key for localisation, or a plain debug string.
var message: String
## Arbitrary payload on success.
var value: Variant


func _init(p_ok: bool, p_value: Variant = null, p_code: String = "", p_message: String = "") -> void:
	ok = p_ok
	value = p_value
	code = p_code
	message = p_message


static func success(value: Variant = null) -> Result:
	return Result.new(true, value)


static func failure(code: String, message: String = "") -> Result:
	return Result.new(false, null, code, message)


func is_ok() -> bool:
	return ok


func is_err() -> bool:
	return not ok


## Returns value on success, fallback on failure. Never throws.
func unwrap_or(fallback: Variant) -> Variant:
	return value if ok else fallback


func to_dict() -> Dictionary:
	return {"ok": ok, "code": code, "message": message, "value": value}


func _to_string() -> String:
	if ok:
		return "Result(ok, %s)" % [value]
	return "Result(err, %s: %s)" % [code, message]
