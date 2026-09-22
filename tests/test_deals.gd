extends TestCase
## DealRules (M8 D-083): pure gating for a grey or illicit deal, unused by
## the game yet. Every refusal code and the shape of a successful judgement.


## An easy pass: dealer, legal-enough nature, well known, well trusted,
## clean standing, no heat, nobody about.
func _facts(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"has_deal": true,
		"legality": "illicit",
		"lawfulness": 0.2,
		"greed": 0.3,
		"risk": 0.6,
		"discretion": 0.5,
		"requires_met": true,
		"familiarity": 0.9,
		"trust": 0.9,
		"vouched": false,
		"standing": 0.0,
		"heat": 0.0,
		"watched": false,
	}
	for key in overrides:
		base[key] = overrides[key]
	return base


func test_a_good_case_succeeds() -> void:
	var result := DealRules.judge(_facts())
	assert_ok(result)
	assert_true(result.value.has("factor"))
	assert_true(result.value.has("visibility"))


func test_not_a_dealer() -> void:
	assert_err(DealRules.judge(_facts({"has_deal": false})), "not_a_dealer")


func test_wont_deal_when_illicit_and_lawful() -> void:
	assert_err(DealRules.judge(_facts({"legality": "illicit", "lawfulness": 0.9})), "wont_deal")


func test_a_lawful_person_still_deals_when_the_shop_is_only_grey() -> void:
	assert_ok(DealRules.judge(_facts({"legality": "grey", "lawfulness": 0.9})))


func test_requires_unmet() -> void:
	assert_err(DealRules.judge(_facts({"requires_met": false})), "requires_unmet")


func test_dont_know_you_when_unfamiliar_and_not_vouched() -> void:
	assert_err(DealRules.judge(_facts({"familiarity": 0.0, "trust": 0.9})), "dont_know_you")


func test_being_vouched_for_skips_the_familiarity_floor() -> void:
	assert_ok(DealRules.judge(_facts({"familiarity": 0.0, "trust": 0.9, "vouched": true})))


func test_dont_trust_you_when_untrusted_and_not_vouched() -> void:
	assert_err(DealRules.judge(_facts({"familiarity": 0.9, "trust": -1.0})), "dont_trust_you")


func test_being_vouched_for_skips_the_trust_floor() -> void:
	assert_ok(DealRules.judge(_facts({"familiarity": 0.9, "trust": -1.0, "vouched": true})))


func test_bad_standing() -> void:
	assert_err(DealRules.judge(_facts({"standing": -0.5})), "bad_standing")


func test_too_hot_when_heat_exceeds_risk_tolerance() -> void:
	assert_err(DealRules.judge(_facts({"risk": 0.2, "heat": 0.5})), "too_hot")


func test_not_now_when_watched_and_risk_averse() -> void:
	assert_err(DealRules.judge(_facts({"watched": true, "risk": 0.1})), "not_now")


func test_a_bold_dealer_does_not_mind_being_watched() -> void:
	assert_ok(DealRules.judge(_facts({"watched": true, "risk": 0.9})))


func test_checks_run_in_order_not_a_dealer_first() -> void:
	# Everything else about this fact set is also wrong, but not_a_dealer wins.
	assert_err(DealRules.judge(_facts({
		"has_deal": false, "legality": "illicit", "lawfulness": 1.0,
		"familiarity": 0.0, "trust": -1.0, "standing": -1.0, "heat": 1.0,
	})), "not_a_dealer")


# --- the numbers behind price and visibility --------------------------------

func test_greed_raises_price_and_closeness_lowers_it() -> void:
	var greedy := DealRules.price_factor(0.9, 0.0, 0.0)
	var generous := DealRules.price_factor(0.0, 0.0, 0.0)
	assert_gt(greedy, generous)
	var close := DealRules.price_factor(0.5, 1.0, 1.0)
	var distant := DealRules.price_factor(0.5, 0.0, 0.0)
	assert_lt(close, distant)


func test_price_factor_stays_within_its_clamped_range() -> void:
	for greed in [0.0, 0.5, 1.0]:
		for familiarity in [0.0, 0.5, 1.0]:
			for trust in [-1.0, 0.0, 1.0]:
				var factor := DealRules.price_factor(greed, familiarity, trust)
				assert_true(factor >= 0.5 and factor <= 2.5,
					"factor %s out of range for greed=%s familiarity=%s trust=%s" % [factor, greed, familiarity, trust])


func test_discretion_and_visibility_are_inverse() -> void:
	assert_lt(DealRules.visibility_for(0.9), DealRules.visibility_for(0.1))
	assert_gt(DealRules.visibility_for(1.0), 0.0)   # never perfectly silent
