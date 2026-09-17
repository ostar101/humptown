extends Node
## Leveled logger. Autoload singleton: Log
##
## Every subsystem logs through here so that verbosity is controllable from
## settings and so that debug overlays can mirror recent output without
## scraping stdout. Never log secrets: use redact() for anything that might
## contain an API key.

enum Level { TRACE, DEBUG, INFO, WARN, ERROR }

const LEVEL_NAMES := ["TRACE", "DEBUG", "INFO", "WARN", "ERROR"]
const RING_SIZE := 400

## Messages at or above this level are printed.
var min_level: Level = Level.INFO
## Per-channel overrides, e.g. {"llm": Level.DEBUG}
var channel_levels: Dictionary = {}

var _ring: Array[Dictionary] = []

signal logged(entry: Dictionary)


func trace(channel: String, message: String, data: Dictionary = {}) -> void:
	_emit(Level.TRACE, channel, message, data)


func debug(channel: String, message: String, data: Dictionary = {}) -> void:
	_emit(Level.DEBUG, channel, message, data)


func info(channel: String, message: String, data: Dictionary = {}) -> void:
	_emit(Level.INFO, channel, message, data)


func warn(channel: String, message: String, data: Dictionary = {}) -> void:
	_emit(Level.WARN, channel, message, data)


func error(channel: String, message: String, data: Dictionary = {}) -> void:
	_emit(Level.ERROR, channel, message, data)


## Returns the recent log ring buffer, oldest first.
func recent(count: int = 50) -> Array[Dictionary]:
	var start := maxi(0, _ring.size() - count)
	return _ring.slice(start)


func clear_ring() -> void:
	_ring.clear()


## Replaces all but the last 4 characters of a sensitive string.
## Use this before logging anything that could be a credential.
static func redact(secret: String) -> String:
	if secret.is_empty():
		return "<empty>"
	if secret.length() <= 4:
		return "****"
	return "****" + secret.substr(secret.length() - 4)


func _threshold_for(channel: String) -> Level:
	if channel_levels.has(channel):
		return channel_levels[channel]
	return min_level


func _emit(level: Level, channel: String, message: String, data: Dictionary) -> void:
	if level < _threshold_for(channel):
		return
	var entry := {
		"level": level,
		"channel": channel,
		"message": message,
		"data": data,
		"at": Time.get_ticks_msec(),
	}
	_ring.append(entry)
	if _ring.size() > RING_SIZE:
		_ring.remove_at(0)

	var line := "[%s][%s] %s" % [LEVEL_NAMES[level], channel, message]
	if not data.is_empty():
		line += " " + JSON.stringify(data)
	if level >= Level.ERROR:
		printerr(line)
	else:
		print(line)
	logged.emit(entry)
