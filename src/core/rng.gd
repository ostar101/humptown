class_name RngStreams
extends RefCounted
## Named deterministic random streams.
##
## A single global RNG makes saves unreproducible and makes one system's
## extra roll silently shift another system's results. Instead every
## subsystem draws from its own named stream seeded from the world seed,
## so adding a roll to combat cannot perturb NPC scheduling.

var world_seed: int = 0
var _streams: Dictionary = {}


func _init(p_seed: int = 0) -> void:
	world_seed = p_seed


## Returns (creating if needed) the RandomNumberGenerator for a stream.
func stream(name: String) -> RandomNumberGenerator:
	if _streams.has(name):
		return _streams[name]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s" % [world_seed, name])
	_streams[name] = rng
	return rng


func reseed(p_seed: int) -> void:
	world_seed = p_seed
	_streams.clear()


## Stable per-entity value in [0,1) that does not consume stream state.
## Use for "does this NPC prefer coffee" style stable traits.
static func stable_unit(entity_id: String, salt: String) -> float:
	var h := hash("%s|%s" % [entity_id, salt])
	return float(absi(h) % 1000000) / 1000000.0


func to_dict() -> Dictionary:
	var states := {}
	for key in _streams:
		var rng: RandomNumberGenerator = _streams[key]
		states[key] = {"seed": rng.seed, "state": rng.state}
	return {"world_seed": world_seed, "streams": states}


func from_dict(d: Dictionary) -> void:
	world_seed = int(d.get("world_seed", 0))
	_streams.clear()
	var states: Dictionary = d.get("streams", {})
	for key in states:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(states[key].get("seed", 0))
		rng.state = int(states[key].get("state", 0))
		_streams[key] = rng
