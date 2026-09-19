class_name ConversationRules
extends RefCounted
## What something the player said is allowed to change (D-037).
##
## An interpreter — `OfflineTopics` from words, or the cheap model — says
## what the player *meant*: an intent. This judges it against the world as
## it stands and answers with a `Result`: the effects Godot will apply and a
## plain sentence of what actually happened, for the person's reply; or a
## refusal code, after which nothing changes. It is pure — the caller gathers
## the state and applies the effects — so every rule can be tested alone.
##
## Intent (from an interpreter):
##   kind       "greet", "give_money", … or any snake_case word a model chose
##   subject    npc id or location id the line is about, resolved by Godot
##   amount     int, for money
##   name       the name the player gave for themselves, as said
##
## State (from the world):
##   npc_id, player_name, player_cash, relationship {dimension: value}
##   (how the person feels about the player), warmth (how much this
##   conversation has already warmed them), hiring ({"job", "name",
##   "problem"} — the job this person hires for, if any, and why the player
##   could not have it), works_for_them (the player's job is theirs to give),
##   player_bank (what is in the account: by phone money goes through it),
##   channel ("in_person", "call" or "text": nothing said down a phone carries cash),
##   errand ({"id", "what", "reward"} — something they could ask of the
##   player today, D-044), errand_running (they are already waiting on one)
##
## A kind with no rule here — a model may say "persuade", "negotiate", "lie"
## — is talk: accepted, and it changes nothing until a system exists that it
## could change. The player is never restricted to this list; only its
## effects are.

## Kinds that have rules. Offered to the model as the vocabulary to prefer.
const KINDS: Array[String] = [
	"greet", "farewell", "thanks", "about_self", "about_work", "about_person", "about_place",
	"introduce_self", "compliment", "flirt", "apologize", "insult", "threaten", "give_money",
	"ask_for_work", "quit_job", "offer_help",
]
## Kinds a model may use that are understood but change nothing yet.
const TALK_KINDS: Array[String] = ["persuade", "negotiate", "ask_favor", "lie", "small_talk"]

## The most cash a single gesture may hand over. Past this it is not a gift,
## it is a transaction, and transactions are M4.
const MAX_GIFT := 1000
## One conversation can warm someone only so far: flattery past this changes
## nothing more. Coldness has no such cap — every insult lands.
const WARMTH_CAP := 0.15

const COMPLIMENT_AFFECTION := 0.04
const APOLOGY_MENDS := 0.06
const FLIRT_DELTA := 0.03
## Flirting is welcome only from someone they know and like this much.
const FLIRT_FAMILIARITY := 0.3
const FLIRT_AFFECTION := 0.2
const INSULT := {"affection": -0.08, "respect": -0.03}
const THREAT := {"fear": 0.15, "affection": -0.12, "trust": -0.1}
## A gift warms by its size, up to this, at this many units of cash per point.
const GIFT_WARMTH_MAX := 0.08
const GIFT_CASH_PER_POINT := 250.0


## Ok: {"kind", "topic", "effects": Array[Dictionary], "happened": String,
## "ends": bool}. Refused: `invalid_amount`, `not_enough_cash`, `not_enough_bank` (by text) — with what
## happened in the message, so the person can react to it.
##
## Effects: {"do": "feel", "dimension", "delta"} (their feeling toward the
## player) · {"do": "pay", "amount"} · {"do": "remember", "predicate",
## "visibility", "severity"} (a fact about the player they witnessed) ·
## {"do": "introduce_them"} · {"do": "introduce_player"} · {"do": "transfer",
## "amount"} (from the account, by text) · {"do": "tell_place", "place"}.
static func judge(intent: Dictionary, state: Dictionary) -> Result:
	var kind := str(intent.get("kind", "unknown"))
	var feeling: Dictionary = state.get("relationship", {})
	var warmth_left := maxf(WARMTH_CAP - float(state.get("warmth", 0.0)), 0.0)
	var effects: Array[Dictionary] = []
	var topic := kind if kind in KINDS else "unknown"
	var happened := ""
	var ends := false

	match kind:
		"farewell":
			ends = true
		"about_self":
			effects.append({"do": "introduce_them"})
		"about_place":
			# They tell you where it is: it goes on your map (D-049).
			if str(intent.get("subject", "")).begins_with("loc_"):
				effects.append({"do": "tell_place", "place": str(intent["subject"])})
		"introduce_self":
			var said_name := str(intent.get("name", "")).strip_edges()
			if said_name == "" or _same_name(said_name, str(state.get("player_name", ""))):
				effects.append({"do": "introduce_player"})
				happened = "They told you their name: %s." % str(state.get("player_name", ""))
			else:
				# A false name is theirs to give; it is simply not learned.
				happened = "They told you their name is %s." % said_name
		"compliment":
			_warm(effects, "affection", COMPLIMENT_AFFECTION, warmth_left)
		"apologize":
			var affection := float(feeling.get("affection", 0.0))
			if affection < 0.0:
				effects.append({"do": "feel", "dimension": "affection", "delta": minf(APOLOGY_MENDS, -affection)})
		"flirt":
			if float(feeling.get("familiarity", 0.0)) >= FLIRT_FAMILIARITY \
					and float(feeling.get("affection", 0.0)) >= FLIRT_AFFECTION:
				_warm(effects, "affection", FLIRT_DELTA, warmth_left)
				topic = "flirt_welcome"
			else:
				effects.append({"do": "feel", "dimension": "affection", "delta": -FLIRT_DELTA})
				topic = "flirt_unwelcome"
		"insult":
			for dimension in INSULT:
				effects.append({"do": "feel", "dimension": dimension, "delta": INSULT[dimension]})
			effects.append({"do": "remember", "predicate": "insulted", "visibility": "social", "severity": 0.3})
		"threaten":
			for dimension in THREAT:
				effects.append({"do": "feel", "dimension": dimension, "delta": THREAT[dimension]})
			effects.append({"do": "remember", "predicate": "threatened", "visibility": "social", "severity": 0.6})
			happened = "They threatened you. You want this conversation over."
			ends = true
		"give_money":
			var amount := int(intent.get("amount", 0))
			if amount <= 0 or amount > MAX_GIFT:
				return Result.failure("invalid_amount", "They talked about giving you money, but offered nothing you could take.")
			if str(state.get("channel", "in_person")) != "in_person":
				# By phone there are no hands: it goes through the account (D-048).
				if int(state.get("player_bank", 0)) < amount:
					return Result.failure("not_enough_bank",
						"They offered to send you %d, but there is not that much in their account. Nothing was sent." % amount)
				effects.append({"do": "transfer", "amount": amount})
				happened = "They sent you %d from their account, and it arrived." % amount
			else:
				if int(state.get("player_cash", 0)) < amount:
					return Result.failure("not_enough_cash",
						"They offered you %d in cash, but they do not have that much on them. Nothing changed hands." % amount)
				effects.append({"do": "pay", "amount": amount})
				happened = "They handed you %d in cash, and you took it." % amount
			_warm(effects, "affection", minf(amount / GIFT_CASH_PER_POINT, GIFT_WARMTH_MAX), warmth_left)
			effects.append({"do": "remember", "predicate": "gave_money_to", "visibility": "private", "severity": 0.2})
			topic = "gift_accepted"
		"ask_for_work":
			var hiring: Dictionary = state.get("hiring", {})
			if hiring.is_empty():
				return Result.failure("not_hiring", "They asked you for work. You have none to give.")
			if bool(state.get("works_for_them", false)):
				happened = "They asked you for work, but they already work for you."
				topic = "already_hired"
			elif str(hiring.get("problem", "")) != "":
				return Result.failure(str(hiring["problem"]),
					"They asked you for work as a %s, but you cannot take them on: %s." % [
						hiring.get("name", "worker"), str(hiring["problem"]).replace("_", " ")])
			else:
				effects.append({"do": "hire", "job": str(hiring["job"])})
				happened = "They asked you for work, and you took them on as a %s, from the next shift." % hiring.get("name", "worker")
				topic = "hired"
		"offer_help":
			var errand: Dictionary = state.get("errand", {})
			if bool(state.get("errand_running", false)):
				happened = "They offered to help, but they have not yet brought what you asked for."
				topic = "errand_waiting"
			elif not errand.is_empty():
				effects.append({"do": "take_errand", "errand": str(errand["id"])})
				happened = "They offered to help. You asked them to bring you %s, and you will pay them %d." % [
					errand.get("what", "something"), int(errand.get("reward", 0))]
				topic = "errand_asked"
			else:
				happened = "They offered to help. You do not need anything from them."
				topic = "no_errand"
		"quit_job":
			if bool(state.get("works_for_them", false)):
				effects.append({"do": "quit"})
				happened = "They told you they quit. They no longer work for you."
				topic = "quit"

	return Result.success({"kind": kind, "topic": topic, "effects": effects, "happened": happened, "ends": ends})


## What a judged line leaves in the person's memory: {"text", "weight"},
## a phrase that follows "they", or {} for nothing worth keeping. Written from
## the verdict, never from anything a model said (D-038). `subject_name` is
## the person or place asked about, as a name.
static func memory_of(intent: Dictionary, judged: Result, subject_name: String = "") -> Dictionary:
	var kind := str(intent.get("kind", ""))
	if judged.is_err():
		if judged.code == "not_enough_cash":
			return {"text": "offered you %d in cash they did not have" % int(intent.get("amount", 0)), "weight": 0.3}
		if kind == "ask_for_work":
			return {"text": "asked you for work", "weight": 0.2}
		return {}
	var verdict: Dictionary = judged.value
	match kind:
		"about_self":
			return {"text": "asked who you are", "weight": 0.1}
		"about_work":
			return {"text": "asked about your work", "weight": 0.1}
		"about_person", "about_place":
			return {"text": "asked you about %s" % subject_name, "weight": 0.2} if subject_name != "" else {}
		"introduce_self":
			var said_name := str(intent.get("name", "")).strip_edges()
			var honest := false
			for effect: Dictionary in verdict["effects"]:
				honest = honest or effect["do"] == "introduce_player"
			return {"text": "told you their name" if honest else "said their name was %s" % said_name, "weight": 0.3}
		"compliment":
			return {"text": "complimented you", "weight": 0.2}
		"flirt":
			return {"text": "flirted with you" if verdict["topic"] == "flirt_welcome" else "flirted with you, uninvited", "weight": 0.3}
		"apologize":
			return {"text": "apologised", "weight": 0.3 if not (verdict["effects"] as Array).is_empty() else 0.1}
		"insult":
			return {"text": "insulted you", "weight": 0.6}
		"threaten":
			return {"text": "threatened you", "weight": 0.9}
		"give_money":
			return {"text": "gave you %d in cash" % int(intent.get("amount", 0)), "weight": 0.5}
		"ask_for_work":
			return {"text": "asked you for work, and you took them on" if verdict["topic"] == "hired"
				else "asked you for work", "weight": 0.4 if verdict["topic"] == "hired" else 0.2}
		"quit_job":
			return {"text": "quit working for you", "weight": 0.5} if verdict["topic"] == "quit" else {}
		"offer_help":
			return {"text": "offered to help you", "weight": 0.2}
	return {}


## The authored topic that answers a refusal.
static func topic_for_refusal(code: String) -> String:
	match code:
		"not_enough_cash":
			return "gift_no_cash"
		"not_hiring", "not_qualified", "do_not_know_you":
			return code
		"not_enough_bank":
			return "transfer_no_funds"
	return "unknown"


## How much a set of effects warms someone, for the conversation's cap.
static func warmth_of(effects: Array) -> float:
	var total := 0.0
	for effect: Dictionary in effects:
		if effect.get("do") == "feel" and float(effect["delta"]) > 0.0 \
				and str(effect["dimension"]) in ["affection", "trust", "respect"]:
			total += float(effect["delta"])
	return total


static func _warm(effects: Array[Dictionary], dimension: String, delta: float, warmth_left: float) -> void:
	var allowed := minf(delta, warmth_left)
	if allowed > 0.0:
		effects.append({"do": "feel", "dimension": dimension, "delta": allowed})


static func _same_name(said: String, real: String) -> bool:
	var said_first := said.to_lower().split(" ", false)
	var real_first := real.to_lower().split(" ", false)
	return not said_first.is_empty() and not real_first.is_empty() and said_first[0] == real_first[0]
