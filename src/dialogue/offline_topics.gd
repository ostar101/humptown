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
## Topics, checked in this order so that "thanks, bye" is a goodbye, "hi,
## who are you?" is a question and "bye, idiot" is an insult: threaten,
## insult, ask_follow, ask_wait, ask_action (asking them to come along, to
## wait, or to fetch or go — D-057), negotiate, farewell, give_money, introduce_self, apologize, about_person,
## about_place, about_self, about_work, compliment, thanks, greet — else
## unknown. A topic is also an intent kind (D-037): what the words are
## taken to mean, which `ConversationRules` then judges.

const PHRASES := {
	"farewell": ["bye", "goodbye", "good bye", "see you", "see ya", "farewell", "later",
		"näkemiin", "moikka", "heippa", "hei hei", "moi moi", "nähdään"],
	"ask_follow": ["follow me", "come with me", "come along", "walk with me", "join me", "come with us",
		"seuraa minua", "seuraa mua", "seuraa meitä", "tule mukaan", "tule mukaani", "tule mun mukaan",
		"tule kanssani", "tule mun kanssa", "lähde mukaan", "lähde mukaani", "tule perässäni"],
	"ask_wait": ["wait here", "stay here", "stay put", "stop following", "don't follow", "do not follow",
		"you can go now", "wait for me", "odota tässä", "odota täällä", "odota minua", "odota mua", "pysy täällä",
		"pysy tässä", "jää tähän", "jää tänne", "lopeta seuraaminen", "älä seuraa", "voit mennä"],
	"ask_action": ["bring me", "bring us", "fetch me", "get me", "go and get", "go fetch", "carry this",
		"tuo minulle", "tuo mulle", "tuo tänne", "hae minulle", "hae mulle", "vie tämä", "vie tää", "mene hakemaan",
		"mene sinne", "tule tänne", "come here"],
	"about_self": ["who are you", "your name", "what's your name", "whats your name", "about yourself",
		"introduce yourself", "kuka olet", "kuka sinä olet", "kuka sä oot", "nimesi", "sinun nimesi",
		"mikä on nimesi", "kerro itsestäsi"],
	"about_work": ["work", "job", "working", "do you do", "for a living", "your shop", "occupation",
		"työ", "työsi", "töissä", "työksesi", "mitä teet", "ammatti", "ammattisi"],
	"thanks": ["thanks", "thank you", "cheers", "kiitos", "kiitti", "kiitoksia"],
	"threaten": ["or else", "i'll hurt you", "i will hurt you", "i'll kill you", "i will kill you",
		"watch your back", "you'll regret", "you will regret", "i know where you live",
		"tapan sinut", "tapan sut", "satutan sinua", "kadut vielä", "varo selustaasi", "tiedän missä asut"],
	"insult": ["idiot", "stupid", "shut up", "moron", "loser", "fool", "i hate you", "you're useless",
		"you are useless", "idiootti", "tyhmä", "turpa kiinni", "ääliö", "vihaan sinua", "luuseri", "hölmö"],
	"apologize": ["sorry", "i apologise", "i apologize", "my apologies", "forgive me",
		"anteeksi", "pahoittelen", "sori"],
	"introduce_self": ["my name is", "my name's", "i'm called", "i am called", "call me",
		"nimeni on", "mun nimi on", "minun nimeni on", "minun nimi on"],
	"ask_for_work": ["any work", "need work", "need a job", "looking for work", "looking for a job",
		"are you hiring", "you hiring", "give me a job", "can i work", "work for you", "take me on",
		"töitä", "työpaikkaa", "palkkaatteko", "tarvitsetteko apua", "etsin töitä", "saisinko töitä"],
	"quit_job": ["i quit", "i'm quitting", "i am quitting", "i resign", "i'm done working",
		"irtisanoudun", "lopetan tämän työn", "otan lopputilin", "lopetan täällä"],
	"attack": ["i hit you", "i punch you", "i'm going to hit you", "i am going to hit you", "punch you", "let's fight",
		"lets fight", "fight me", "come at me", "square up", "put up your fists", "i'll hit you", "take a swing",
		"lyön sinua", "lyön sut", "tapellaan", "nyrkit esiin", "tule tappelemaan"],
	"negotiate": ["more time", "an extension", "give me time", "some time to pay", "pay you later", "pay later",
		"pay it back later", "go easy", "go easy on me", "cut me some slack", "let me off", "let it go this time",
		"be lenient", "give me a break", "give me a chance", "lisää aikaa", "anna minulle aikaa", "maksan myöhemmin",
		"voinko maksaa myöhemmin", "armoa", "ole lempeä", "anna mulle vielä mahdollisuus", "päästä minut"],
	"offer_help": ["can i help", "need any help", "need help", "anything i can do", "do you need anything",
		"can i do something for you", "voinko auttaa", "tarvitsetko apua", "voinko tehdä jotain",
		"tarvitsetko jotain"],
	"compliment": ["you look great", "you look nice", "you're nice", "you are nice", "you're kind",
		"you are kind", "i like you", "well done", "good job", "nice shop", "you're great", "you are great",
		"olet mukava", "olet ihana", "näytät hyvältä", "hyvää työtä", "hieno kauppa", "olet kiva"],
	"greet": ["hello", "hi", "hey", "good morning", "good evening", "good day", "morning", "evening",
		"moi", "hei", "terve", "huomenta", "iltaa", "päivää", "moro"],
}

const ORDER: Array[String] = [
	"attack", "threaten", "insult", "ask_follow", "ask_wait", "ask_action", "negotiate", "farewell", "give_money", "introduce_self", "apologize",
	"quit_job", "ask_for_work", "offer_help",
	"about_person", "about_place", "about_self", "about_work", "compliment", "thanks", "greet",
]
## Handing over money needs all three: a giving phrase, a number, and money.
const GIVE_PHRASES: Array[String] = [
	"give you", "here's", "here is", "take this", "for you", "have this",
	"annan sinulle", "annan sulle", "tässä", "ota", "saat",
]
const MONEY_WORDS: Array[String] = ["euro", "euros", "eur", "money", "cash", "bucks", "euroa", "rahaa", "egeä", "e"]

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
static var _amount := RegEx.create_from_string("(\\d+)\\s*(€)?")


## {"topic", "subject", "amount", "name"}. `subject` is the npc id or
## location id a person or place topic is about, else "". `amount` is the
## cash offered, for give_money; `name` the name the player gave, for
## introduce_self. `npc_id` is who is being spoken to — their own name is not
## a question about somebody else.
static func topic_of(text: String, npc_id: String, people: Dictionary, places: Dictionary) -> Dictionary:
	var tokens := tokens_of(text)
	var padded := " " + " ".join(tokens) + " "
	for topic in ORDER:
		match topic:
			"give_money":
				var amount := _money_offered(text, tokens, padded)
				if amount > 0:
					return {"topic": topic, "subject": "", "amount": amount, "name": ""}
			"introduce_self":
				for phrase: String in PHRASES[topic]:
					var at := padded.find(" " + phrase + " ")
					if at >= 0:
						var after := padded.substr(at + phrase.length() + 2).split(" ", false)
						return {"topic": topic, "subject": "", "amount": 0,
							"name": after[0].capitalize() if not after.is_empty() else ""}
			"about_person":
				var who := _mentioned(tokens, people, npc_id)
				if who != "":
					return {"topic": topic, "subject": who, "amount": 0, "name": ""}
			"about_place":
				var where := _mentioned(tokens, places, "")
				if where != "":
					return {"topic": topic, "subject": where, "amount": 0, "name": ""}
			_:
				for phrase: String in PHRASES[topic]:
					if padded.contains(" " + phrase + " "):
						return {"topic": topic, "subject": "", "amount": 0, "name": ""}
	return {"topic": "unknown", "subject": "", "amount": 0, "name": ""}


## The cash a line offers, or 0: "here's 20 euros", "annan sulle 5 €".
## Words are not understanding — "I won't give you 20 euros" reads as an
## offer — which is one reason a model interprets when there is one, and
## why the rules check the wallet whoever interpreted.
static func _money_offered(text: String, tokens: Array[String], padded: String) -> int:
	var found := _amount.search(text)
	if found == null:
		return 0
	var giving := false
	for phrase in GIVE_PHRASES:
		if padded.contains(" " + phrase + " "):
			giving = true
			break
	var money := found.get_string(2) != ""
	for word in MONEY_WORDS:
		if tokens.has(word):
			money = true
	return int(found.get_string(1)) if giving and money else 0


## The person or place a name as someone said it picks out, or "". How a
## model's "person": "Tuomas" becomes an id — or nothing, if there is no
## such person (D-037).
static func resolve(name: String, words_by_id: Dictionary, except_id: String) -> String:
	return _mentioned(tokens_of(name), words_by_id, except_id) if name.strip_edges() != "" else ""


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
