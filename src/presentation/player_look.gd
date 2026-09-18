class_name PlayerLook
extends RefCounted
## How the player looks, from the choices kept on `PlayerState.appearance`
## (D-033), and what there is to choose from.
##
## An appearance is a handful of hex colours and two style ids — the same
## vocabulary an NPC's authored `look` uses — rather than a list of sprite
## files. That keeps a save meaningful whether or not the LimeZu art is
## installed (the code-painted figure wears the colours) and survives the art
## being re-imported under different file names.

## The colour families on offer. Skin and hair are the same ranges the town's
## own people are drawn from (NpcLook), so the player never stands out as a
## different kind of person; clothes get a wider choice.
const HAIR_COLOURS: Array[String] = ["1a1a1a", "3b2a20", "6b4a2e", "a0703a", "d0b070", "9a9a9a", "b04a2e", "5a6a8a"]
const SHIRT_COLOURS: Array[String] = ["3f6e8c", "6b8c3f", "8c3f4a", "c9a23a", "5a4a7a", "d0d0c8", "2f5f5a", "a0603a", "1f1f24"]
const TROUSER_COLOURS: Array[String] = ["2f3440", "2e4a6b", "4a3f30", "3a3a3a", "5a5a50"]


static func palette(appearance: Dictionary) -> Dictionary:
	var out: Dictionary = CharacterFigure.DEFAULTS.duplicate()
	for key in CharacterDraft.APPEARANCE_COLOURS:
		var value := str(appearance.get(key, ""))
		if Color.html_is_valid(value):
			out[key] = Color(value)
	return out


static func chosen_styles(appearance: Dictionary) -> Dictionary:
	var out := {}
	if appearance.has("hair_style"):
		out["hairstyles"] = str(appearance["hair_style"])
	if appearance.has("outfit_style"):
		out["outfits"] = str(appearance["outfit_style"])
	return out


## The sprite layers the player wears; empty without the art.
static func look(appearance: Dictionary) -> Dictionary:
	return CharacterSprites.look_for(PlayerState.ID, palette(appearance), chosen_styles(appearance))


# --- what the creation screen offers -----------------------------------------

## Skin tones: the art's own bodies where it is installed, so every choice is a
## visibly different person, else the town's range.
static func skin_options() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in CharacterSprites.manifest().get("bodies", []):
		out.append(str(entry.get("colour", "")).trim_prefix("#"))
	if out.is_empty():
		out.assign(NpcLook.SKINS)
	return out


## What a choice can be, given the rest of the look. Where the art is
## installed, a hair or outfit colour is one the *chosen style* is actually
## drawn in — a swatch the sprite cannot wear would be a promise the preview
## breaks. Trousers are only offered without the art: LimeZu's outfits are
## whole outfits, legs included, so a separate trouser colour would change
## nothing on screen.
static func options(key: String, appearance: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	var art := CharacterSprites.available()
	match key:
		"skin":
			return skin_options()
		"hair":
			if art:
				return _style_colours("hairstyles", str(appearance.get("hair_style", "")))
			out.assign(HAIR_COLOURS)
		"shirt":
			if art:
				return _style_colours("outfits", str(appearance.get("outfit_style", "")))
			out.assign(SHIRT_COLOURS)
		"trousers":
			if not art:
				out.assign(TROUSER_COLOURS)
		"hair_style":
			return CharacterSprites.styles("hairstyles")
		"outfit_style":
			return CharacterSprites.styles("outfits")
	return out


## Where the creation screen starts: the first of every list, which is a plain
## and unremarkable person — the player makes them someone.
static func default_appearance() -> Dictionary:
	var out := {}
	for key in ["hair_style", "outfit_style"]:
		var choices := options(key)
		if not choices.is_empty():
			out[key] = choices[0]
	for key in ["skin", "hair", "shirt", "trousers"]:
		var choices := options(key, out)
		if not choices.is_empty():
			out[key] = "#" + choices[0]
	return out


## Steps one choice forwards or backwards through its options, wrapping.
## Changing a style keeps the colour as close as the new style allows, so a
## red jacket becomes the reddest version of the next cut, not its first.
static func cycle(appearance: Dictionary, key: String, step: int) -> Dictionary:
	var choices := options(key, appearance)
	var out := appearance.duplicate()
	if choices.is_empty():
		return out
	var colour := CharacterDraft.APPEARANCE_COLOURS.has(key)
	var current := str(appearance.get(key, "")).trim_prefix("#")
	var index := choices.find(current)
	index = posmod((index if index >= 0 else 0) + step, choices.size())
	out[key] = ("#" + choices[index]) if colour else choices[index]
	var follows: String = {"hair_style": "hair", "outfit_style": "shirt"}.get(key, "")
	if follows != "":
		out[follows] = "#" + _closest(options(follows, out), str(appearance.get(follows, "")))
	return out


## The colours a layer's style is drawn in, without the '#', in sheet order.
static func _style_colours(layer: String, style: String) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in CharacterSprites.manifest().get(layer, []):
		if str(entry.get("style", "")) == style:
			out.append(str(entry.get("colour", "")).trim_prefix("#"))
	return out


static func _closest(choices: Array[String], wanted: String) -> String:
	if choices.is_empty():
		return wanted.trim_prefix("#")
	if not Color.html_is_valid(wanted):
		return choices[0]
	var target := Color(wanted)
	var best := choices[0]
	var best_distance := INF
	for choice in choices:
		var c := Color(choice)
		var distance := Vector3(c.r - target.r, c.g - target.g, c.b - target.b).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = choice
	return best
