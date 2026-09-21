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
##   ask ({"id", …} — something they could be asked for, D-053) and ask_cooldown
##   (they were asked too recently),
##   channel ("in_person", "call" or "text": nothing said down a phone carries cash),
##   errand ({"id", "what", "reward"} — something they could ask of the
##   player today, D-044), errand_running (they are already waiting on one),
##   follow ({"following", "free_minutes"} — are they walking with the player,
##   and how long their own day leaves them free to, D-057),
##   gift ({"count", "value", "name", "keep"} — about the item the intent's
##   subject names: how many the player has, what it is worth, its name, and
##   whether it is something they will not part with, D-062),
##   go ({"problem", "free_minutes", "busy", "here"} — about the place the
##   intent's subject names: `problem` is "" or why they could not go there
##   (`unknown`, `far`, `closed`), `busy` an errand or meeting already has
##   them, `here` they are there already, D-061)
##
## A kind with no rule here — a model may say "persuade", "negotiate", "lie"
## — is talk: accepted, and it changes nothing until a system exists that it
## could change. The player is never restricted to this list; only its
## effects are.

## Kinds that have rules. Offered to the model as the vocabulary to prefer.
const KINDS: Array[String] = [
	"greet", "farewell", "thanks", "about_self", "about_work", "about_person", "about_place",
	"introduce_self", "compliment", "flirt", "apologize", "insult", "threaten", "give_money", "give_item",
	"ask_for_work", "quit_job", "offer_help", "negotiate", "attack",
	"ask_follow", "ask_wait", "ask_go", "ask_action",
]
## Kinds that put an ask, when there is something to ask (D-053).
const ASK_KINDS: Array[String] = ["negotiate", "persuade", "ask_favor"]
## Kinds a model may use that are understood but change nothing yet.
const TALK_KINDS: Array[String] = ["persuade", "ask_favor", "lie", "small_talk"]

## Someone who trusts the player less than this, or likes them less, will not
## go anywhere with them. A stranger is not held against them: nobody has done
## anything yet.
const FOLLOW_MIN_TRUST := -0.2
const FOLLOW_MIN_AFFECTION := -0.3

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
## Even a cheap thing handed over is a kindness.
const GIFT_MIN_ITEM_WARMTH := 0.01


## Ok: {"kind", "topic", "effects": Array[Dictionary], "happened": String,
## "ends": bool}. Refused: `invalid_amount`, `not_enough_cash`, `not_enough_bank` (by text) — with what
## happened in the message, so the person can react to it.
##
## Effects: {"do": "feel", "dimension", "delta"} (their feeling toward the
## player) · {"do": "pay", "amount"} · {"do": "remember", "predicate",
## "visibility", "severity"} (a fact about the player they witnessed) ·
## {"do": "introduce_them"} · {"do": "introduce_player"} · {"do": "transfer",
## "amount"} (from the account, by text) · {"do": "tell_place", "place"} · {"do": "fight"} · {"do": "ask", "ask"} (put an ask: what
## comes of it is rolled and applied by `AskDirector`) · {"do": "follow",
## "minutes"} and {"do": "stop_following"} (D-057) · {"do": "go", "place",
## "minutes"} (D-061) · {"do": "give_item", "item", "count"} (D-062).
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
		"give_item":
			# The player hands over something from the bag (D-062). People have no
			# belongings of their own yet, so it is theirs and goes no further.
			var item := str(intent.get("subject", ""))
			var gift: Dictionary = state.get("gift", {})
			var item_name := str(gift.get("name", "something"))
			if not item.begins_with("item_") or gift.is_empty():
				return Result.failure("invalid_item", "They talked about giving you something, but offered nothing you could take.")
			if str(state.get("channel", "in_person")) != "in_person":
				return Result.failure("not_here", "They offered you something over the phone. There are no hands to take it.")
			if int(gift.get("count", 0)) < 1:
				return Result.failure("no_item", "They offered you %s, but they do not have one on them. Nothing changed hands." % item_name)
			if bool(gift.get("keep", false)):
				return Result.failure("keep_it", "They offered you %s, but it is something they need. You told them to keep it." % item_name)
			effects.append({"do": "give_item", "item": item, "count": 1})
			_warm(effects, "affection", clampf(float(gift.get("value", 0)) / GIFT_CASH_PER_POINT, GIFT_MIN_ITEM_WARMTH, GIFT_WARMTH_MAX), warmth_left)
			effects.append({"do": "remember", "predicate": "gave_item_to", "visibility": "private", "severity": 0.2})
			happened = "They handed you %s, and you took it." % item_name
			topic = "gift_item_accepted"
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
		"negotiate", "persuade", "ask_favor":
			var ask: Dictionary = state.get("ask", {})
			if ask.is_empty():
				happened = "They tried to bargain with you, but there is nothing between you to bargain over."
				topic = "no_ask"
			elif bool(state.get("ask_cooldown", false)):
				happened = "They asked you for the same thing again, too soon after the last time."
				topic = "ask_again"
			else:
				effects.append({"do": "ask", "ask": str(ask["id"])})
				happened = "They asked you for something."
				topic = "ask_made"
		"attack":
			# Blows are thrown face to face; nothing is thrown down a phone (D-054).
			if str(state.get("channel", "in_person")) != "in_person":
				return Result.failure("not_here", "They swung at you over the phone. There is no one to hit.")
			effects.append({"do": "fight"})
			happened = "They attacked you."
			topic = "attacked"
			ends = true
		"ask_follow":
			var follow: Dictionary = state.get("follow", {})
			if str(state.get("channel", "in_person")) != "in_person":
				return Result.failure("follow_remote", "They asked you to come along, over the phone. You cannot walk with someone you cannot see.")
			if bool(follow.get("following", false)):
				happened = "They asked you to come along. You are already walking with them."
				topic = "follow_already"
			elif float(feeling.get("trust", 0.0)) < FOLLOW_MIN_TRUST or float(feeling.get("affection", 0.0)) < FOLLOW_MIN_AFFECTION:
				return Result.failure("follow_distrust", "They asked you to come along. You do not trust them enough to go anywhere with them, and you said no.")
			elif int(follow.get("free_minutes", 0)) < FollowRules.MIN_MINUTES:
				return Result.failure("follow_busy", "They asked you to come along, but you have to be somewhere and cannot go with them now.")
			else:
				effects.append({"do": "follow", "minutes": int(follow["free_minutes"])})
				happened = "They asked you to come along. You agreed, and you are now walking with them until you have to be elsewhere."
				topic = "follow_yes"
		"ask_wait":
			if bool((state.get("follow", {}) as Dictionary).get("following", false)):
				effects.append({"do": "stop_following"})
				happened = "They asked you to wait here. You stopped following them and will get on with your day."
				topic = "wait_ok"
			else:
				happened = "They asked you to wait here, but you were not going anywhere with them."
				topic = "wait_nothing"
		"ask_go":
			# Going somewhere alone is a one-off change to their day (D-061).
			var place := str(intent.get("subject", ""))
			var go: Dictionary = state.get("go", {})
			if not place.begins_with("loc_"):
				return Result.failure("cannot_do", "They asked you to go somewhere, but not anywhere you know of. You cannot, and you did not promise anything.")
			if str(state.get("channel", "in_person")) != "in_person":
				return Result.failure("go_remote", "They asked you to go somewhere, over the phone. You cannot promise that: you would have to be seen going.")
			if float(feeling.get("trust", 0.0)) < FOLLOW_MIN_TRUST or float(feeling.get("affection", 0.0)) < FOLLOW_MIN_AFFECTION:
				return Result.failure("go_distrust", "They asked you to go somewhere for them. You do not trust them enough to do their errands, and you said no.")
			if bool(go.get("here", false)):
				happened = "They asked you to go somewhere. You are already there."
				topic = "go_here"
			elif str(go.get("problem", "")) != "":
				return Result.failure("go_closed", "They asked you to go somewhere you cannot get to now: it is shut, private or too far. You said so, and did not promise anything.")
			elif bool(go.get("busy", false)) or int(go.get("free_minutes", 0)) < FollowRules.MIN_MINUTES:
				return Result.failure("go_busy", "They asked you to go somewhere, but you have to be elsewhere and cannot go now.")
			else:
				if bool((state.get("follow", {}) as Dictionary).get("following", false)):
					effects.append({"do": "stop_following"})
				effects.append({"do": "go", "place": place,
					"minutes": mini(int(go["free_minutes"]), FollowRules.GO_MINUTES)})
				happened = "They asked you to go somewhere. You agreed, and you are on your way there now."
				topic = "go_yes"
		"ask_action":
			# Fetching and carrying for someone are not built yet (D-057): say
			# so, instead of a promise nothing will keep.
			return Result.failure("cannot_do", "They asked you to do something for them, like fetch or carry something. You cannot, and you did not promise anything.")
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
		"give_item":
			return {"text": "gave you %s" % subject_name, "weight": 0.4} if subject_name != "" else {}
		"ask_go":
			if verdict["topic"] == "go_yes" and subject_name != "":
				return {"text": "asked you to go to %s, and you went" % subject_name, "weight": 0.3}
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
		"not_here":
			return "not_here"
		"follow_remote", "follow_busy", "cannot_do":
			return code
		"follow_distrust", "go_distrust":
			return "follow_no"
		"go_busy":
			return "follow_busy"
		"no_item":
			return "gift_no_item"
		"keep_it":
			return "gift_keep_it"
		"go_closed", "go_remote":
			return code
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
