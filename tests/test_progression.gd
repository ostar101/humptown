extends TestCase
## Skill and character progression.

var data: DataRegistry
var skills: Skills
var stats: Stats


func before_each() -> void:
	data = DataRegistry.new()
	data.load_all()
	skills = Skills.new()
	skills.setup(data)
	stats = Stats.new()


# --- skills -----------------------------------------------------------------

func test_curve_is_monotonic_and_starts_at_zero() -> void:
	assert_almost(Skills.xp_for_level(1), 0.0)
	var previous := -1.0
	for level in range(1, Skills.MAX_LEVEL + 1):
		var required := Skills.xp_for_level(level)
		assert_gt(required, previous)
		previous = required


func test_level_for_xp_inverts_the_curve() -> void:
	for level in [1, 5, 20, 50, 99]:
		assert_eq(Skills.level_for_xp(Skills.xp_for_level(level)), level)


func test_level_is_capped() -> void:
	assert_eq(Skills.level_for_xp(999_999_999.0), Skills.MAX_LEVEL)


func test_awarding_xp_levels_up() -> void:
	skills.award("brawling", Skills.xp_for_level(5))
	assert_eq(skills.level_of("brawling"), 5)


func test_level_up_emits_once_per_level() -> void:
	var levels: Array[int] = []
	var handler := func(skill: String, level: int) -> void:
		if skill == "brawling":
			levels.append(level)
	Events.skill_level_up.connect(handler)
	skills.award("brawling", Skills.xp_for_level(3))
	Events.skill_level_up.disconnect(handler)
	assert_eq(levels.size(), 1, "one signal per award, carrying the new level")
	assert_eq(levels[0], 3)


func test_progress_bar_is_zero_at_a_fresh_level() -> void:
	skills.award("brawling", Skills.xp_for_level(10))
	assert_almost(skills.progress("brawling"), 0.0)


func test_progress_bar_advances_within_a_level() -> void:
	skills.award("brawling", Skills.xp_for_level(10))
	var to_next := Skills.xp_for_level(11) - Skills.xp_for_level(10)
	skills.award("brawling", to_next * 0.5)
	assert_almost(skills.progress("brawling"), 0.5, 0.01)


func test_practising_above_your_level_teaches_more() -> void:
	skills.levels["brawling"] = 10
	skills.xp["brawling"] = Skills.xp_for_level(10)
	var hard := skills.practise("brawling", 100.0, 15)

	skills.levels["stealth"] = 10
	skills.xp["stealth"] = Skills.xp_for_level(10)
	var level := skills.practise("stealth", 100.0, 10)

	assert_gt(hard, level)


func test_practising_far_below_your_level_is_nearly_worthless() -> void:
	# The anti-grind rule: repeating a trivial task must not be a strategy.
	skills.levels["brawling"] = 30
	skills.xp["brawling"] = Skills.xp_for_level(30)
	var gained := skills.practise("brawling", 100.0, 5)
	assert_lt(gained, 10.0)


func test_zero_or_negative_awards_are_ignored() -> void:
	assert_almost(skills.award("brawling", 0.0), 0.0)
	assert_almost(skills.award("brawling", -50.0), 0.0)
	assert_eq(skills.level_of("brawling"), 1)


func test_success_chance_responds_to_the_gap_and_never_certain() -> void:
	skills.levels["persuasion"] = 20
	var easy := skills.success_chance("persuasion", 5)
	var even := skills.success_chance("persuasion", 20)
	var hard := skills.success_chance("persuasion", 40)
	assert_gt(easy, even)
	assert_gt(even, hard)
	assert_almost(even, 0.5, 0.01)
	assert_lt(easy, 0.96)
	assert_gt(hard, 0.04)


func test_content_skills_are_registered_at_setup() -> void:
	assert_gt(float(skills.levels.size()), 10.0)
	assert_has(skills.levels, "persuasion")


func test_top_skills_are_ordered() -> void:
	skills.levels["persuasion"] = 30
	skills.levels["stealth"] = 10
	var top := skills.top_skills(2)
	assert_eq(top[0]["id"], "persuasion")


func test_skills_round_trip() -> void:
	skills.award("brawling", 5000.0)
	var restored := Skills.new()
	restored.from_dict(skills.to_dict())
	assert_eq(restored.level_of("brawling"), skills.level_of("brawling"))


# --- stats ------------------------------------------------------------------

func test_character_levels_award_attribute_points() -> void:
	stats.award_character_xp(Stats.XP_PER_CHARACTER_LEVEL * 3.0)
	assert_eq(stats.character_level, 4)
	assert_eq(stats.attribute_points, 3)


func test_spending_attribute_points() -> void:
	stats.award_character_xp(Stats.XP_PER_CHARACTER_LEVEL)
	assert_ok(stats.spend_attribute_point("strength"))
	assert_eq(stats.attribute("strength"), 6)
	assert_err(stats.spend_attribute_point("strength"), "no_points")


func test_unknown_attributes_are_refused() -> void:
	stats.attribute_points = 1
	assert_err(stats.spend_attribute_point("luck"), "unknown_attribute")
	assert_eq(stats.attribute_points, 1)


func test_meters_clamp() -> void:
	stats.modify("health", -5.0)
	assert_almost(stats.health, 0.0)
	assert_true(stats.is_incapacitated())
	stats.modify("health", 5.0)
	assert_almost(stats.health, 1.0)


func test_sleeping_restores_and_waking_drains() -> void:
	stats.sleep = 0.2
	stats.drift(480, "sleep")
	assert_gt(stats.sleep, 0.9)

	stats.hunger = 0.0
	stats.drift(360, "idle")
	assert_gt(stats.hunger, 0.5)


func test_injuries_persist_and_penalise_the_right_part() -> void:
	stats.add_injury("broken_arm", "arm", 0.6, 5000)
	assert_true(stats.has_injury_to("arm"))
	assert_lt(stats.injury_penalty("arm"), 1.0)
	assert_almost(stats.injury_penalty("leg"), 1.0)


func test_injuries_heal_on_schedule_not_before() -> void:
	stats.add_injury("broken_arm", "arm", 0.6, 5000)
	assert_eq(stats.heal_expired_injuries(4000), 0)
	assert_true(stats.has_injury_to("arm"))
	assert_eq(stats.heal_expired_injuries(5001), 1)
	assert_false(stats.has_injury_to("arm"))


func test_condition_reduces_effectiveness() -> void:
	var healthy := stats.effectiveness()
	stats.health = 0.3
	stats.sleep = 0.2
	stats.hunger = 0.9
	assert_lt(stats.effectiveness(), healthy)


func test_stats_round_trip() -> void:
	stats.award_character_xp(4000.0)
	stats.add_injury("cut", "arm", 0.3, 900)
	stats.modify("stress", 0.5)
	var restored := Stats.new()
	restored.from_dict(stats.to_dict())
	assert_eq(restored.character_level, stats.character_level)
	assert_eq(restored.injuries.size(), 1)
	assert_almost(restored.stress, stats.stress)
