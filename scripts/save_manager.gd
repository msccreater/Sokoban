class_name  SaveManager

const SAVE_PATH := "user://save.cfg"
static var _config: ConfigFile = null

static func _get_config() -> ConfigFile:
	if _config == null:
		_config = ConfigFile.new()
		_config.load(SAVE_PATH)
	return _config

static func _save() -> void:
	_get_config().save(SAVE_PATH)

static func set_int(key: String, value: int) -> void:
	_get_config().set_value("game", key, value)
	_save()

static func get_int(key: String, default_value: int = 0) -> int:
	return _get_config().get_value("game", key, default_value)

static func set_string(key: String, value: String) -> void:
	_get_config().set_value("game", key, value)
	_save()

static func get_string(key: String, default_value: String = "") -> String:
	return _get_config().get_value("game", key, default_value)

static func set_bool(key: String, value: bool) -> void:
	_get_config().set_value("game", key, value)
	_save()

static func get_bool(key: String, default_value: bool = false) -> bool:
	return _get_config().get_value("game", key, default_value)

static func remove(key: String) -> void:
	_get_config().erase_section_key("game", key)
	_save()

static func clear() -> void:
	_get_config().erase_section("game")
	_save()
