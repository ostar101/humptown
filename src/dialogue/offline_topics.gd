class_name OfflineTopics
extends RefCounted
## What a line the player typed is about, well enough to answer it without a
## model (D-035).
##
## This is the floor the conversation stands on when there is no provider,
## no key or no network: a handful of topics, recognised from words in English
## and Finnish, each answered from authored lines. It is deliberately modest —
## it does not pretend to understand, it notices a greeting, a name, a place.
## When a model is available it does the interpreting instead; this never
## decides anything a model would be better at.
##
## Topics, checked in this order so that "thanks, bye" is a goodbye and
## "hi, who are you?" is a question: farewell, about_person, about_place,
## about_self, about_work, thanks, greet — else unknown.

const PHRASES := {
	"farewell": ["bye", "goodbye", "good bye", "see you", "see ya", "farewell", "later",
		"näkemiin", "moikka", "heippa", "hei hei", "moi moi", "nähdään"],
	"about_self": ["who are you", "your name", "what's your name", "whats your name", "about yourself",
		"introduce yourself", "kuka olet", "kuka sinä olet", "kuka sä oot", "nimesi", "sinun nimesi",
		"mikä on nimesi", "kerro itsestäsi"],
	"about_work": ["work", "job", "working", "do you do", "for a living", "your shop", "occupation",
		"työ", "työsi", "töissä", "työksesi", "mitä teet", "ammatti", "ammattisi"],
	"thanks": ["thanks", "thank you", "cheers", "kiitos", "kiitti", "kiitoksia"],
	"greet": ["hello", "hi", "hey", "good morning", "good evening", "good day", "morning", "evening",
		"moi", "hei", "terve", "huomenta", "iltaa", "päivää", "moro"],
}

const ORDER: Array[String] = ["farewell", "about_person", "about_place", "about_self", "about_work", "thanks", "greet"]

## Words in place names too common to say which place is meant.
const PLACE_STOPWORDS: Array[String] = [
	"the", "street", "house", "your", "flat", "room", "rented", "shop", "stop",
	"katu", "talo", "asunto", "huone", "kauppa",
]
## A place word this long also matches its inflected forms by its first five
## letters — "satamassa" is still the harbour. Finnish needs it; English
## barely notices it.
const STEM_MIN := 6
const STEM_LENGTH := 5

static var _words := RegEx.create_from_string("[\\p{L}']+")


## {"topic": String, "subject": String}. `subject` is the npc id or location
## id a person or place topic is about, else "". `npc_id` is who is being
## spoken to — their own name is not a question about somebody else.
static func topic_of(text: String, npc_id: String, people: Dictionary, places: Dictionary) -> Dictionary:
	var tokens := tokens_of(text)
	var padded := " " + " ".join(tokens) + " "
	for topic in ORDER:
		match topic:
			"about_person":
				var who := _mentioned(tokens, people, npc_id)
				if who != "":
					return {"topic": topic, "subject": who}
			"about_place":
				var where := _mentioned(tokens, places, "")
				if where != "":
					return {"topic": topic, "subject": where}
			_:
				for phrase: String in PHRASES[topic]:
					if padded.contains(" " + phrase + " "):
						return {"topic": topic, "subject": ""}
	return {"topic": "unknown", "subject": ""}


static func tokens_of(text: String) -> Array[String]:
	var out: Array[String] = []
	for found in _words.search_all(text.to_lower()):
		out.append(found.get_string())
	return out


## The words that pick out a person or place: an id -> display names map in,
## an id -> lowercase words map out. People are recognised by first name,
## places by every distinctive word of their name in every language shown.
## `exclude` keeps people's names out of place names — "Veikko's Flat" must
## not make "Veikko, what do you do?" a question about a flat.
static func name_words(names: Dictionary, first_only: bool, exclude: Array[String] = []) -> Dictionary:
	var out := {}
	for id in names:
		var words: Array[String] = []
		for display_name: String in names[id]:
			var tokens := tokens_of(display_name.replace("'s", ""))
			if first_only:
				tokens = tokens.slice(0, 1)
			for word in tokens:
				if word.length() >= 3 and not PLACE_STOPWORDS.has(word) and not exclude.has(word) \
						and not words.has(word):
					words.append(word)
		out[id] = words
	return out


static func _mentioned(tokens: Array[String], words_by_id: Dictionary, except_id: String) -> String:
	for id in words_by_id:
		if id == except_id:
			continue
		for word: String in words_by_id[id]:
			for token in tokens:
				if token == word:
					return id
				if word.length() >= STEM_MIN and token.length() >= STEM_LENGTH \
						and token.begins_with(word.substr(0, STEM_LENGTH)):
					return id
	return ""
