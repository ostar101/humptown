class_name Skills
extends RefCounted
## Use-based skill progression, RuneScape-flavoured.
##
## You get better at a thing by doing that thing. Generic "character XP" never
## raises a skill; it raises the base attributes in Stats. Levels run 1..99
## and the curve is steep enough that a high level means something, while
## early levels come fast enough to feel responsive in the first hour.
##
## Practising something far below your level yields almost nothing, so
## grinding a trivial task is not a strategy.

const MAX_LEVEL := 99
## Tuning: level 2 at 100 xp, level 50 at ~146k, level 99 at ~580k.
const CURVE_QUADRATIC := 60.0
const CURVE_LINEAR := 40.0

var levels: Dictionary = {}          # skill_id -> int
var xp: Dictionary = {}              # skill_id -> float

var _data: DataRegistry = null


func setup(data: DataRegistry) -> void:
	_data = data
	if data == null:
		return
	for skill_id in data.ids("skills"):
		if not levels.has(skill_id):
			var entry := data.get_entry("skills", skill_id)
			levels[skill_id] = int(entry.get("start_level", 1))
			xp[skill_id] = xp_for_level(int(levels[skill_id]))


## Total XP required to have reached a level.
static func xp_for_level(level: int) -> float:
	var l := float(maxi(1, level) - 1)
	return CURVE_QUADRATIC * l * l + CURVE_LINEAR * l


static func level_for_xp(total_xp: float) -> int:
	var level := 1
	while level < MAX_LEVEL and total_xp >= xp_for_level(level + 1):
		level += 1
	return level


func level_of(skill_id: String) -> int:
	return int(levels.get(skill_id, 1))


func xp_of(skill_id: String) -> float:
	return float(xp.get(skill_id, 0.0))


## Progress toward the next level, in [0,1]. For UI bars.
func progress(skill_id: String) -> float:
	var level := level_of(skill_id)
	if level >= MAX_LEVEL:
		return 1.0
	var floor_xp := xp_for_level(level)
	var next_xp := xp_for_level(level + 1)
	if next_xp <= floor_xp:
		return 1.0
	return clampf((xp_of(skill_id) - floor_xp) / (next_xp - floor_xp), 0.0, 1.0)


## Awards XP for performing a task of a given difficulty.
##
## `difficulty` is the level the task is pitched at. Working well above your
## level teaches a lot; working far below it teaches almost nothing.
func practise(skill_id: String, base_amount: float, difficulty: int = -1) -> float:
	if not levels.has(skill_id):
		levels[skill_id] = 1
		xp[skill_id] = 0.0
	var level := level_of(skill_id)
	var task_level := difficulty if difficulty >= 0 else level
	var gap := float(task_level - level)
	# gap +5 -> 1.5x, gap 0 -> 1.0x, gap -10 -> ~0.1x, gap -20 -> ~0.02x
	var multiplier := clampf(1.0 + gap * 0.1, 0.02, 2.0)
	if gap < -5.0:
		multiplier *= 0.3
	var gained := base_amount * multiplier
	return award(skill_id, gained)


## Awards raw XP with no difficulty scaling (quest rewards, training courses).
func award(skill_id: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	if not levels.has(skill_id):
		levels[skill_id] = 1
		xp[skill_id] = 0.0
	var before := level_of(skill_id)
	xp[skill_id] = xp_of(skill_id) + amount
	var after := level_for_xp(xp_of(skill_id))
	Events.skill_xp_gained.emit(skill_id, amount)
	if after > before:
		levels[skill_id] = after
		Events.skill_level_up.emit(skill_id, after)
		Log.info("skills", "Level up", {"skill": skill_id, "level": after})
	return amount


## Chance of succeeding at a task, from level versus difficulty.
## Never a certainty and never hopeless: there is always a story in the tail.
func success_chance(skill_id: String, difficulty: int, modifier: float = 0.0) -> float:
	var gap := float(level_of(skill_id) - difficulty)
	var chance := 1.0 / (1.0 + exp(-gap * 0.22))
	return clampf(chance + modifier, 0.05, 0.95)


func meets(skill_id: String, required_level: int) -> bool:
	return level_of(skill_id) >= required_level


## Highest levels first. For character sheets and LLM context.
func top_skills(limit: int = 5) -> Array[Dictionary]:
	var entries: Array = []
	for skill_id in levels:
		entries.append({"id": str(skill_id), "level": int(levels[skill_id])})
	entries.sort_custom(func(a, b): return a["level"] > b["level"])
	var out: Array[Dictionary] = []
	for e in entries.slice(0, limit):
		out.append(e)
	return out


func level_map() -> Dictionary:
	return levels.duplicate()


func to_dict() -> Dictionary:
	return {"levels": levels, "xp": xp}


func from_dict(d: Dictionary) -> void:
	levels = d.get("levels", {})
	xp = d.get("xp", {})
