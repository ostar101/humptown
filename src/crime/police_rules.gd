class_name PoliceRules
extends RefCounted
## What the police do about what they know (D-052). Pure: given what an
## officer *believes* — never what actually happened — how serious it seems,
## how sure she is, whether the player has a record, and who she is, the
## proportionate answer: nothing, a warning, a fine or an arrest.
##
## A case is a list of entries {"severity", "strength"}: `strength` is how
## sure she is of it (`strength()`, from how far it has travelled and how
## garbled it is). Someone who saw it herself is sure; someone told is less so;
## a rumour is not enough to act on at all.

## Below this she has heard something, not enough to summon anyone over.
const EVIDENCE_MIN := 0.35
## The weight of a case (see `weight`) at which the answer steps up.
const WEIGHT_WARNING := 0.12
const WEIGHT_FINE := 0.30
const WEIGHT_ARREST := 0.50
## Each earlier offence on the record adds this, up to RECORD_CAP of them.
const RECORD_WEIGHT := 0.10
const RECORD_CAP := 3
## Each further matter in the same case adds a little.
const EXTRA_MATTER_WEIGHT := 0.05
const TRAIT_WEIGHT := {"by_the_book": 0.05}
## Not turning up when told to weighs heavily.
const IGNORED_SUMMONS_WEIGHT := 0.25

const FINE_BASE := 20
const FINE_PER_SEVERITY := 100

## From learning of it to deciding what to do, and how long the player has to
## come in, in minutes. Some officers are unhurried.
const ASSESS_DELAY := 60
const ASSESS_DELAY_TRAIT := {"unhurried": 60}
const SUMMONS_WINDOW := 24 * 60


## How sure she is of what she was told: her confidence, less how garbled the
## account has become.
static func strength(confidence: float, distortion: float) -> float:
	return clampf(confidence * (1.0 - distortion), 0.0, 1.0)


## How much a case weighs: its worst matter as she sees it, a little more for
## each further one, the record, her character, and having ignored a summons.
static func weight(entries: Array, record_count: int, traits: Array, ignored: bool = false,
		adjust: float = 0.0) -> float:
	if entries.is_empty():
		return 0.0
	var worst := 0.0
	for entry: Dictionary in entries:
		worst = maxf(worst, float(entry["severity"]) * float(entry["strength"]))
	var total := worst + EXTRA_MATTER_WEIGHT * float(entries.size() - 1)
	total += RECORD_WEIGHT * float(mini(record_count, RECORD_CAP))
	for t in traits:
		total += float(TRAIT_WEIGHT.get(str(t), 0.0))
	if ignored:
		total += IGNORED_SUMMONS_WEIGHT
	return total + adjust


## "none" | "warning" | "fine" | "arrest".
static func judge_response(entries: Array, record_count: int, traits: Array, ignored: bool = false,
		adjust: float = 0.0) -> String:
	var surest := 0.0
	for entry: Dictionary in entries:
		surest = maxf(surest, float(entry["strength"]))
	if entries.is_empty() or surest < EVIDENCE_MIN:
		return "none"
	var w := weight(entries, record_count, traits, ignored, adjust)
	if w >= WEIGHT_ARREST:
		return "arrest"
	if w >= WEIGHT_FINE:
		return "fine"
	if w >= WEIGHT_WARNING:
		return "warning"
	return "none"


## What a fine comes to, from how serious the worst matter was.
static func fine_for(severity: float) -> int:
	return int(round(FINE_BASE + severity * FINE_PER_SEVERITY))


## A fine the player cannot pay is not waived: it becomes a night in the cells.
static func settle(outcome: String, fine: int, money: int) -> String:
	if outcome == "fine" and money < fine:
		return "arrest"
	return outcome


## Minutes an officer takes over deciding, from who she is.
static func assess_delay(traits: Array) -> int:
	var delay := ASSESS_DELAY
	for t in traits:
		delay += int(ASSESS_DELAY_TRAIT.get(str(t), 0))
	return delay
