class_name SaveMigrations
extends RefCounted
## Forward migration of save data between schema versions.
##
## Written on day one, before there is anything to migrate, because the
## alternative is discovering at version 6 that every early save is garbage.
## Each step upgrades a save by exactly one version; loading applies the chain
## from whatever the file says to CURRENT_VERSION.
##
## Rules for adding a migration:
##   1. Bump CURRENT_VERSION.
##   2. Add a `_v<N>_to_v<N+1>` static function.
##   3. Register it in STEPS.
##   4. Add a test with a fixture of the old shape.
## Never renumber or edit an existing step: someone's save depends on it.

const CURRENT_VERSION := 6

## version -> name of the static function upgrading it to version + 1.
const STEPS := {
	1: "_v1_to_v2",
	2: "_v2_to_v3",
	3: "_v3_to_v4",
	4: "_v4_to_v5",
	5: "_v5_to_v6",
}


## Upgrades `data` in place to CURRENT_VERSION.
## Returns a Result carrying the migrated dictionary, or a failure when the
## save is from a newer build than this one.
static func migrate(data: Dictionary) -> Result:
	var version := int(data.get("schema_version", 0))

	if version > CURRENT_VERSION:
		return Result.failure("save_too_new",
			"Save is version %d; this build understands up to %d." % [version, CURRENT_VERSION])

	if version < 1:
		return Result.failure("save_unversioned", "Save has no schema version.")

	var working := data.duplicate(true)
	while version < CURRENT_VERSION:
		if not STEPS.has(version):
			return Result.failure("no_migration_path",
				"No migration registered from version %d." % version)
		var migrated := _apply_step(version, working)
		if migrated.is_empty():
			return Result.failure("migration_failed",
				"Step for version %d returned no data." % version)
		working = migrated
		version += 1
		working["schema_version"] = version
		Log.info("save", "Save migrated", {"to_version": version})

	return Result.success(working)


## Whether a save at this version can be loaded at all.
static func can_load(version: int) -> bool:
	if version > CURRENT_VERSION or version < 1:
		return false
	var v := version
	while v < CURRENT_VERSION:
		if not STEPS.has(v):
			return false
		v += 1
	return true


## Dispatches one version step. A match rather than a lookup table because
## GDScript cannot hold references to static functions in a const dictionary,
## and an explicit list of versions is easier to audit anyway.
static func _apply_step(version: int, data: Dictionary) -> Dictionary:
	match version:
		1:
			return _v1_to_v2(data)
		2:
			return _v2_to_v3(data)
		3:
			return _v3_to_v4(data)
		4:
			return _v4_to_v5(data)
		5:
			return _v5_to_v6(data)
		_:
			return {}


# --- migration steps --------------------------------------------------------
#
# Example of the shape these take, kept as documentation for the first real one:
#
# static func _v1_to_v2(data: Dictionary) -> Dictionary:
#     # v2 split `player.money` into a wallet with cash and bank.
#     var player: Dictionary = data.get("player", {})
#     if player.has("money"):
#         player["wallet"] = {"cash": int(player["money"]), "bank": 0, "ledger": []}
#         player.erase("money")
#     return data


## v2 adds what people remember of the player (D-038). A v1 save has no
## memories; everyone starts from an empty book, which is exactly the truth.
static func _v1_to_v2(data: Dictionary) -> Dictionary:
	if not data.has("memories"):
		data["memories"] = {"books": {}}
	return data


## v3 adds the shops' shelves and tills (D-039). A v2 save has none; every
## shop opens with its usual stock, as it would the morning after a restock.
static func _v2_to_v3(data: Dictionary) -> Dictionary:
	if not data.has("shops"):
		data["shops"] = {"shops": {}}
	return data


## v4 moves the job out of the player into its own `work` section (D-042).
## A v3 player's `job_id` was an occupation; the one job each such
## occupation had then is written here by hand, not looked up, so this step
## means the same thing whatever the data says later.
const V3_JOBS := {"occ_dockhand": "job_dockhand"}


static func _v3_to_v4(data: Dictionary) -> Dictionary:
	var player: Dictionary = data.get("player", {})
	var occupation := str(player.get("job_id", ""))
	player.erase("job_id")
	if not data.has("work"):
		data["work"] = {"job": str(V3_JOBS.get(occupation, "")), "standing": 1.0}
	return data


## v5 keeps quests (D-044). A v4 save has none under way: its story threads
## did not exist yet, and starting them halfway through a life would be
## stranger than their absence.
static func _v4_to_v5(data: Dictionary) -> Dictionary:
	if not data.has("quests"):
		data["quests"] = {"active": {}, "finished": {}, "errands": {}, "errands_done": {}}
	return data


## v6 keeps the phone (D-045). A v5 save has an empty one: no numbers and no
## messages yet. Contacts are picked up from who already knows the player the
## next time the game looks, so nobody you have met is lost.
static func _v5_to_v6(data: Dictionary) -> Dictionary:
	if not data.has("phone"):
		data["phone"] = {"contacts": {}, "messages": [], "last_started": {}, "next_id": 1}
	return data
