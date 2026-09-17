class_name Relationship
extends RefCounted
## A directed feeling from one person toward another.
##
## Directed on purpose: he may trust her far more than she trusts him, and
## that asymmetry is most of what makes a social world interesting.

## Structural tie, independent of how they currently feel about each other.
enum Kind { STRANGER, ACQUAINTANCE, FRIEND, FAMILY, PARTNER, COLLEAGUE, RIVAL, ENEMY, DEPENDENT }

const KIND_NAMES := [
	"stranger", "acquaintance", "friend", "family",
	"partner", "colleague", "rival", "enemy", "dependent",
]

## All in [-1, 1] except familiarity, which is [0, 1] and never decreases
## quickly: you do not un-know someone.
var trust: float = 0.0
var affection: float = 0.0
var respect: float = 0.0
var fear: float = 0.0
var familiarity: float = 0.0
var kind: Kind = Kind.STRANGER
## World minute of the last meaningful interaction.
var last_interaction: int = -1

const DIMENSIONS := ["trust", "affection", "respect", "fear", "familiarity"]


func adjust(dimension: String, delta: float) -> void:
	match dimension:
		"trust": trust = clampf(trust + delta, -1.0, 1.0)
		"affection": affection = clampf(affection + delta, -1.0, 1.0)
		"respect": respect = clampf(respect + delta, -1.0, 1.0)
		"fear": fear = clampf(fear + delta, -1.0, 1.0)
		"familiarity": familiarity = clampf(familiarity + delta, 0.0, 1.0)
		_: Log.warn("social", "Unknown relationship dimension", {"dimension": dimension})


func get_dimension(dimension: String) -> float:
	match dimension:
		"trust": return trust
		"affection": return affection
		"respect": return respect
		"fear": return fear
		"familiarity": return familiarity
	return 0.0


## Single number for quick gating ("will she do me this favour?").
## Fear counts for something, but coercion is worth less than goodwill.
func disposition() -> float:
	return clampf(trust * 0.4 + affection * 0.4 + respect * 0.2 + fear * 0.1, -1.0, 1.0)


## Short phrase for LLM context. Keeps prompts small and human-readable.
func describe() -> String:
	if familiarity < 0.1:
		return "a stranger"
	var d := disposition()
	var base: String = KIND_NAMES[kind]
	if d > 0.5: return "a trusted " + base
	if d > 0.15: return "a friendly " + base
	if d < -0.5: return "a hated " + base
	if d < -0.15: return "a disliked " + base
	return base


func to_dict() -> Dictionary:
	return {
		"trust": trust, "affection": affection, "respect": respect,
		"fear": fear, "familiarity": familiarity,
		"kind": int(kind), "last": last_interaction,
	}


static func from_dict(d: Dictionary) -> Relationship:
	var r := Relationship.new()
	r.trust = float(d.get("trust", 0.0))
	r.affection = float(d.get("affection", 0.0))
	r.respect = float(d.get("respect", 0.0))
	r.fear = float(d.get("fear", 0.0))
	r.familiarity = float(d.get("familiarity", 0.0))
	r.kind = d.get("kind", Kind.STRANGER) as Kind
	r.last_interaction = int(d.get("last", -1))
	return r
