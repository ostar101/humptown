class_name DealRules
extends RefCounted
## Whether a grey or illicit deal may go ahead (M8 step 7, D-083). Pure: the
## caller gathers the facts, this answers with a Result, and nothing changes
## on a refusal. Not called by anything yet — `ask_deal` (M8 step 9) is the
## first caller; the exchange itself then runs through `ShopWindow` exactly
## as an ordinary shop does, priced by the `factor` this returns.
##
## Facts: has_deal (this keeper's Npc.deals names the shop), legality
## ("legal"|"grey"|"illicit", the shop's own), lawfulness/greed/risk/
## discretion (the keeper's Npc.nature), requires_met (the shop's authored
## `requires`, already checked by the caller), familiarity/trust
## (Relationship, keeper -> player), vouched (a "vouched_for" fact this
## person knows, M8 step 11), standing (the player's criminal-scope
## Reputation), heat (how hot the player currently runs, [0, 1]), watched
## (someone else is about who would notice).
##
## The order is the design: a lawful person is asked before anyone checks
## whether they know you; someone who already distrusts you never gets to
## the question of whether tonight is a bad night to be seen.
##
## Refused: not_a_dealer, wont_deal, requires_unmet, dont_know_you,
## dont_trust_you, bad_standing, too_hot, not_now.
## Success: {"factor": price multiplier from greed and closeness,
## "visibility": how loudly this deal writes into KnowledgeNetwork, from
## discretion}. Neither is a yes/no gate — they come out as price and risk.

## Below this, a scope's opinion of the player is bad enough that nobody who
## deals wants the exposure, whatever their own nature.
const STANDING_FLOOR := -0.2
## A dealer who tolerates less risk than this waits for the street to clear.
const RISK_FOR_WATCHERS := 0.7


static func judge(facts: Dictionary) -> Result:
	if not bool(facts.get("has_deal", false)):
		return Result.failure("not_a_dealer")

	var lawfulness := clampf(float(facts.get("lawfulness", 0.8)), 0.0, 1.0)
	var greed := clampf(float(facts.get("greed", 0.3)), 0.0, 1.0)
	var risk := clampf(float(facts.get("risk", 0.2)), 0.0, 1.0)
	var discretion := clampf(float(facts.get("discretion", 0.5)), 0.0, 1.0)
	var familiarity := clampf(float(facts.get("familiarity", 0.0)), 0.0, 1.0)
	var trust := clampf(float(facts.get("trust", 0.0)), -1.0, 1.0)
	var vouched := bool(facts.get("vouched", false))

	if str(facts.get("legality", "legal")) == "illicit" and lawfulness > 0.6:
		return Result.failure("wont_deal")
	if not bool(facts.get("requires_met", true)):
		return Result.failure("requires_unmet")
	if not vouched and familiarity < familiarity_floor(greed, lawfulness):
		return Result.failure("dont_know_you")
	if not vouched and trust < trust_floor(greed, risk):
		return Result.failure("dont_trust_you")
	if float(facts.get("standing", 0.0)) < STANDING_FLOOR:
		return Result.failure("bad_standing")
	if float(facts.get("heat", 0.0)) > risk:
		return Result.failure("too_hot")
	if bool(facts.get("watched", false)) and risk < RISK_FOR_WATCHERS:
		return Result.failure("not_now")

	return Result.success({
		"factor": price_factor(greed, familiarity, trust),
		"visibility": visibility_for(discretion),
	})


## Greed lowers how well a dealer needs to know you before they will deal;
## lawfulness raises it back, since even a greedy but law-abiding person
## wants more assurance first.
static func familiarity_floor(greed: float, lawfulness: float) -> float:
	return clampf(0.6 - greed * 0.4 + lawfulness * 0.3, 0.0, 1.0)


## Greed and a dealer's own risk tolerance both lower how much they need to
## trust you — a greedy or reckless dealer takes the chance a cautious one
## would not.
static func trust_floor(greed: float, risk: float) -> float:
	return clampf(0.6 - greed * 0.3 - risk * 0.3, -1.0, 1.0)


## Greed raises the price; being known and trusted brings it back down.
## Never free, never more than two and a half times over.
static func price_factor(greed: float, familiarity: float, trust: float) -> float:
	var closeness := clampf((familiarity + maxf(trust, 0.0)) * 0.5, 0.0, 1.0)
	return clampf(1.0 + greed * 0.6 - closeness * 0.3, 0.5, 2.5)


## Discretion IS the inverse of visibility — the one axis that never gates,
## only costs. A chatty dealer (low discretion) makes the fact loud even on
## a deal that goes through clean.
static func visibility_for(discretion: float) -> float:
	return clampf(1.0 - discretion, 0.05, 1.0)
