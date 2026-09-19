class_name SecretStore
extends RefCounted
## Encrypted local storage for API keys.
##
## Threat model, stated plainly: the player owns the machine and the key is
## theirs. What this protects against is accidental disclosure — a key ending
## up in a git commit, a save file swapped with a friend, a settings.json
## pasted into a bug report, or a screenshot of a log. It is not, and cannot
## be, protection against someone with access to the machine, because the
## game must be able to decrypt the key unattended.
##
## Keys live in user://secrets.dat, encrypted with a passphrase derived from
## the machine id. They never enter settings.json, a save, the repository, or
## any log line. See DECISIONS.md (D-006).

const SECRET_PATH := "user://secrets.dat"
const MACHINE_SALT_PATH := "user://.machine"
const OBFUSCATION_SALT := "humptown/secret/v1"

## Where the keys live. Only the test runner points it elsewhere, so that no
## test can read, overwrite or delete the player's own keys (D-036).
var path: String = SECRET_PATH
var _cache: Dictionary = {}
var _loaded: bool = false



func _init(p_path: String = SECRET_PATH) -> void:
	path = p_path


## Stores a key for a provider. Pass "" to clear it.
func set_key(provider: String, key: String) -> Result:
	_ensure_loaded()
	if key.is_empty():
		_cache.erase(provider)
	else:
		_cache[provider] = key
	var saved := _save()
	if saved.is_ok():
		Log.info("llm", "API key stored", {"provider": provider, "key": Log.redact(key)})
	return saved


func get_key(provider: String) -> String:
	_ensure_loaded()
	return str(_cache.get(provider, ""))


func has_key(provider: String) -> bool:
	return not get_key(provider).is_empty()


## Provider ids that currently have a key, for the settings screen.
func configured_providers() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for provider in _cache:
		out.append(str(provider))
	return out


func clear_all() -> Result:
	_cache.clear()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_loaded = true
	return Result.success()


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_cache = {}
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open_encrypted_with_pass(path, FileAccess.READ, _passphrase())
	if file == null:
		# Wrong machine, or a corrupted file. Do not crash: the player can
		# simply re-enter the key.
		Log.warn("llm", "Could not decrypt secret store; keys must be re-entered")
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = SafeJson.parse(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		_cache = parsed


func _save() -> Result:
	var file := FileAccess.open_encrypted_with_pass(path, FileAccess.WRITE, _passphrase())
	if file == null:
		Log.error("llm", "Could not write secret store")
		return Result.failure("secret_write_failed")
	file.store_string(JSON.stringify(_cache))
	file.close()
	return Result.success()


## Machine-derived passphrase. Falls back to a locally generated random salt
## when the platform reports no unique id (some Linux and sandboxed setups).
func _passphrase() -> String:
	var machine_id := OS.get_unique_id()
	if machine_id.is_empty():
		machine_id = _local_salt()
	return (machine_id + OBFUSCATION_SALT).sha256_text()


func _local_salt() -> String:
	if FileAccess.file_exists(MACHINE_SALT_PATH):
		var read := FileAccess.open(MACHINE_SALT_PATH, FileAccess.READ)
		if read != null:
			var existing := read.get_as_text().strip_edges()
			read.close()
			if not existing.is_empty():
				return existing
	var generated := ("%d-%d" % [Time.get_unix_time_from_system(), randi()]).sha256_text()
	var write := FileAccess.open(MACHINE_SALT_PATH, FileAccess.WRITE)
	if write != null:
		write.store_string(generated)
		write.close()
	return generated
