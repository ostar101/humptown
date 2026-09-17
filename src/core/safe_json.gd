class_name SafeJson
extends RefCounted
## JSON parsing for input we do not control.
##
## JSON.parse_string() pushes an engine error on malformed input. That is
## right for a programming mistake and wrong for a model returning prose, a
## provider returning an HTML error page, or a player hand-editing a data
## file — all of which are handled outcomes, not bugs. Using this keeps the
## error log meaningful instead of full of expected noise.

## Returns the parsed value, or null when the text is not valid JSON.
static func parse(text: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data


## Returns the parsed dictionary, or an empty one.
static func parse_dict(text: String) -> Dictionary:
	var parsed: Variant = parse(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Returns the parsed array, or an empty one.
static func parse_array(text: String) -> Array:
	var parsed: Variant = parse(text)
	return parsed if typeof(parsed) == TYPE_ARRAY else []
