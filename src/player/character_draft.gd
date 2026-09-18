class_name CharacterDraft
extends RefCounted
## Everything the player chooses before the world starts (D-033): a
## background, a name, pronouns, a look, and a small reshuffle of the
## background's attributes.
##
## A proposal, not a character. The creation screens fill one in however they
## like; `Game.new_game_from()` validates it and only then builds a world from
## it — the same rule every other input obeys (the layering rule in CLAUDE.md).
## Nothing here is saved: once applied, the choices live on `PlayerState`.

const NAME_MAX := 24
const PRONOUNS: Array[String] = ["they", "she", "he"]

## A background is a starting life, so it is only *adjusted*: up to this many
## points moved from one attribute to another, and none taken outside
## [ATTRIBUTE_MIN, ATTRIBUTE_MAX]. Enough to make a dockhand a clever one; not
## enough to stop them being a dockhand.
const ATTRIBUTE_POINTS := 2
const ATTRIBUTE_MIN := 3
const ATTRIBUTE_MAX := 8

## Keys a look may carry. Colours are hex strings, as `look` is in
## data/npcs.json; styles name a LimeZu generator style ("01".."32") and are
## ignored where the art is not installed.
const APPEARANCE_COLOURS: Array[String] = ["skin", "hair", "shirt", "trousers", "shoes"]
const APPEARANCE_STYLES: Array[String] = ["hair_style", "outfit_style"]

var background_id: String = ""
var display_name: String = ""
var pronouns: String = "they"
var appearance: Dictionary = {}
## attribute -> signed change from the background's value.
var attribute_shifts: Dictionary = {}


## Ok, or the first reason this draft cannot become a character. Reason codes
## are what the creation screen shows (through `ui.create.refusal.<code>`).
func validate(data: DataRegistry) -> Result:
	var trimmed := display_name.strip_edges()
	if trimmed.is_empty():
		return Result.failure("name_empty")
	if trimmed.length() > NAME_MAX:
		return Result.failure("name_too_long")
	if not PRONOUNS.has(pronouns):
		return Result.failure("unknown_pronouns")
	var backgrounds := data.table("backgrounds")
	if not backgrounds.has(background_id):
		return Result.failure("unknown_background")
	var shifted := _check_shifts(backgrounds[background_id])
	if shifted.is_err():
		return shifted
	return _check_appearance()


## The attributes this draft ends up with: the background's, plus the shifts.
func attributes(background: Dictionary) -> Dictionary:
	var out := {}
	var base: Dictionary = background.get("attributes", {})
	for attribute in base:
		out[attribute] = int(base[attribute]) + int(attribute_shifts.get(attribute, 0))
	return out


## Points already moved, counted once (what one attribute gained).
func points_used() -> int:
	var used := 0
	for attribute in attribute_shifts:
		used += maxi(int(attribute_shifts[attribute]), 0)
	return used


## Moves one point from `from` to `to` if that stays within the rules, and
## says whether it did. The creation screen's arrows go through this, so the
## screen can never show a draft that `validate()` would refuse.
func move_point(background: Dictionary, from: String, to: String) -> bool:
	if from == to:
		return false
	var trial := attribute_shifts.duplicate()
	trial[from] = int(trial.get(from, 0)) - 1
	trial[to] = int(trial.get(to, 0)) + 1
	for key in [from, to]:
		if int(trial[key]) == 0:
			trial.erase(key)
	var saved := attribute_shifts
	attribute_shifts = trial
	if _check_shifts(background).is_err():
		attribute_shifts = saved
		return false
	return true


func _check_shifts(background: Dictionary) -> Result:
	var base: Dictionary = background.get("attributes", {})
	var net := 0
	for attribute in attribute_shifts:
		if not base.has(attribute):
			return Result.failure("unknown_attribute", str(attribute))
		var shift := int(attribute_shifts[attribute])
		var value := int(base[attribute]) + shift
		if value < ATTRIBUTE_MIN or value > ATTRIBUTE_MAX:
			return Result.failure("attribute_out_of_range", str(attribute))
		net += shift
	if net != 0:
		return Result.failure("attributes_unbalanced")
	if points_used() > ATTRIBUTE_POINTS:
		return Result.failure("too_many_points")
	return Result.success()


func _check_appearance() -> Result:
	for key in appearance:
		var value := str(appearance[key])
		if APPEARANCE_COLOURS.has(key):
			if not Color.html_is_valid(value):
				return Result.failure("bad_appearance", str(key))
		elif APPEARANCE_STYLES.has(key):
			if value.length() > 4 or not value.is_valid_int():
				return Result.failure("bad_appearance", str(key))
		else:
			return Result.failure("bad_appearance", str(key))
	return Result.success()
