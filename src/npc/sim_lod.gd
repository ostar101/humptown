class_name SimLod
extends RefCounted
## Simulation detail tiers for NPCs.
##
## The cost of a living town is controlled here and nowhere else. An NPC's
## tier decides how often it thinks and how much context it carries; the
## NpcDirector assigns tiers from proximity and narrative importance.

enum Tier {
	DORMANT,     ## Not ticked at all. Location computed from schedule on demand.
	BACKGROUND,  ## Coarse ticks (15 game minutes). Schedule + needs drift only.
	ACTIVE,      ## In the player's region. Per-minute schedule, needs, reactions.
	FOCUS,       ## In conversation or combat with the player. Full detail + LLM.
}

const TIER_NAMES := ["DORMANT", "BACKGROUND", "ACTIVE", "FOCUS"]

## Game minutes between ticks for each tier. DORMANT never ticks.
const TICK_INTERVAL := {
	Tier.DORMANT: 0,
	Tier.BACKGROUND: 15,
	Tier.ACTIVE: 1,
	Tier.FOCUS: 1,
}

## Hard ceilings so a crowded district cannot stall a weak CPU.
const MAX_ACTIVE := 60
const MAX_FOCUS := 8
## NPCs promoted or demoted per director pass, to spread cost over frames.
const RETIER_BUDGET_PER_PASS := 12


static func tier_name(tier: Tier) -> String:
	return TIER_NAMES[tier]


static func ticks_this_minute(tier: Tier, total_minutes: int) -> bool:
	var interval: int = TICK_INTERVAL.get(tier, 0)
	if interval <= 0:
		return false
	return total_minutes % interval == 0
