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
	var line := Localization.t("ui.status.line", {
		"day": Localization.t(Game.clock.weekday_key()),
		"time": Game.clock.format_time(),
		"place": InteractionText.place_name(Game.player.location),
		"cash": Game.player.wallet.cash,
	})
	var unread := PhoneText.unread_line()
	return line + " · " + unread if unread != "" else line


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


## "Dockhand at the Harbour · Mon–Fri 06:00–16:30", or "" without a job.
static func job() -> String:
	if not Game.is_running() or not Game.work.has_job():
		return ""
	var job_data := Game.data.get_entry("jobs", Game.work.job_id)
	var occupation := Game.data.get_entry("occupations", str(job_data.get("occupation", "")))
	return Localization.t("ui.status.job", {
		"job": Localization.t(str(occupation.get("name_key", ""))),
		"place": InteractionText.place_name(str(job_data.get("workplace", ""))),
		"days": days_text(job_data.get("days", "all")),
		"from": "%02d:%02d" % [int(job_data.get("shift_start", 0)) / 60, int(job_data.get("shift_start", 0)) % 60],
		"until": "%02d:%02d" % [int(job_data.get("shift_end", 0)) / 60, int(job_data.get("shift_end", 0)) % 60],
	})


static func days_text(days: Variant) -> String:
	if typeof(days) == TYPE_ARRAY:
		var keys: Array[String] = []
		for d in days:
			keys.append(Localization.t(GameClock.WEEKDAY_KEYS[int(d) % 7]))
		return ", ".join(keys)
	match str(days):
		"weekday":
			return Localization.t("ui.status.weekdays")
		"weekend":
			return Localization.t("ui.status.weekends")
	return Localization.t("ui.status.every_day")


## "Hungry · Tired", or "" when you are fine.
static func condition() -> String:
	if not Game.is_running():
		return ""
	return " · ".join(condition_keys(Game.player.stats).map(func(k: String) -> String: return Localization.t(k)))
