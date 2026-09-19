class_name StatusText
extends RefCounted
## The words for the HUD's status corner (D-041): when and where you are,
## your cash, and how you are — only when it is worth saying.

## (meter, above-or-below, threshold, key), most serious first per meter.
const CONDITION_WORDS := [
	["hunger", ">=", Stats.STARVING, "ui.condition.starving"],
	["hunger", ">=", 0.6, "ui.condition.hungry"],
	["sleep", "<=", 0.1, "ui.condition.exhausted"],
	["sleep", "<=", 0.3, "ui.condition.tired"],
	["health", "<=", 0.25, "ui.condition.badly_hurt"],
	["health", "<=", 0.6, "ui.condition.hurt"],
	["intoxication", ">=", 0.5, "ui.condition.drunk"],
	["intoxication", ">=", 0.2, "ui.condition.tipsy"],
	["stress", ">=", 0.7, "ui.condition.on_edge"],
]


## "Tue 07:30 · Dock Street · €23"
static func line() -> String:
	if not Game.is_running():
		return ""
	return Localization.t("ui.status.line", {
		"day": Localization.t(Game.clock.weekday_key()),
		"time": Game.clock.format_time(),
		"place": InteractionText.place_name(Game.player.location),
		"cash": Game.player.wallet.cash,
	})


## The condition keys that apply, one per meter, most serious first.
static func condition_keys(stats: Stats) -> Array[String]:
	var out: Array[String] = []
	var said: Array[String] = []
	for rule: Array in CONDITION_WORDS:
		var meter := str(rule[0])
		if said.has(meter):
			continue
		var value := stats.get_meter(meter)
		var applies := value >= float(rule[2]) if rule[1] == ">=" else value <= float(rule[2])
		if applies:
			out.append(str(rule[3]))
			said.append(meter)
	return out


## "Hungry · Tired", or "" when you are fine.
static func condition() -> String:
	if not Game.is_running():
		return ""
	return " · ".join(condition_keys(Game.player.stats).map(func(k: String) -> String: return Localization.t(k)))
