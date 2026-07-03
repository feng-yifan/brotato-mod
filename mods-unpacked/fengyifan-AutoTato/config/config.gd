extends Reference

# ============================================================================
# AutoTato — Config Repository (新配置层 v1)
# ----------------------------------------------------------------------------
# 这是配置服务的运行时入口。不要依赖全局脚本名注册；Godot 3 +
# Workshop ZIP 环境下全局类名注册时机不稳定，未来调用方应通过脚本资源访问：
#   const _Config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")
#   var cfg = _Config.get_instance()
# ============================================================================

const _ConfigManager = preload("res://mods-unpacked/fengyifan-AutoTato/config/config_manager.gd")
const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")

const _LOG_NAME := "Config"
const _CONFIG_META_KEY := "fengyifan-autotato-config"
const _CONFIG_SCRIPT_PATH := "res://mods-unpacked/fengyifan-AutoTato/config/config.gd"

const SCHEMA_VERSION := 1

const DEFAULT_THRESHOLDS := {
	"stat_speed": {"mode": "upper", "value": 20},
	"stat_armor": {"mode": "upper", "value": 10},
	"stat_dodge": {"mode": "upper", "value": 60},
	"stat_hp_regeneration": {"mode": "upper", "value": 10},
	"stat_crit_chance": {"mode": "upper", "value": 100},
}

const VALID_GENERAL_KEYS := ["min_gold_balance", "item_price_threshold", "reroll_budget",
	"auto_start_wave", "keep_running", "shop_respect_thresholds", "chest_respect_thresholds",
	"turbo_mode", "decision_step_delay"]
const VALID_UPGRADE_CONFIG_KEYS := ["min_tier", "quality_first", "ignore_forbid_on_stuck", "respect_thresholds"]
const VALID_WEAPON_CONFIG_KEYS := ["min_tier"]
const VALID_THRESHOLD_MODES := ["upper", "lower", "unlimited"]
const VALID_SHOP_ACTIONS := ["manual", "reject", "lock_until_cursed", "cursed_only", "get"]
const VALID_CHEST_ACTIONS := ["manual", "take", "skip"]
# item 规则缺失/字段非法时返回的默认 rule。
# chest_action 当前无外层消费者,作为未来 chest 重构块的对称预留。
const DEFAULT_ITEM_RULE := {
	"shop_action": "manual",
	"chest_action": "manual",
}
# 某 stat 未配置阈值时返回的默认阈值。
# mode=unlimited 表示无限制(threshold_gate 读到 → 不拒绝),
# 与"未配置该 stat"行为等价,消费者无需判存在性。
const DEFAULT_THRESHOLD := {
	"mode": "unlimited",
	"value": 0,
}
const VALID_WEAPON_RULE_ACTIONS := ["manual", "skip", "follow_set_rule"]
const VALID_WEAPON_CATEGORY_ACTIONS := ["manual", "skip"]

var _config: Dictionary = {}
var _skip_persistence: bool = false
var _loaded: bool = false
var _last_error: String = ""

# ============================================================================
# 全局单例
# ============================================================================

static func initialize() -> Reference:
	if Engine.has_meta(_CONFIG_META_KEY):
		return Engine.get_meta(_CONFIG_META_KEY)

	var instance = ResourceLoader.load(_CONFIG_SCRIPT_PATH).new()
	Engine.set_meta(_CONFIG_META_KEY, instance)
	instance.load()
	return instance

static func get_instance() -> Reference:
	if not Engine.has_meta(_CONFIG_META_KEY):
		return initialize()
	return Engine.get_meta(_CONFIG_META_KEY)

static func has_instance() -> bool:
	return Engine.has_meta(_CONFIG_META_KEY)

static func register_instance(instance: Reference) -> void:
	if instance == null:
		return
	Engine.set_meta(_CONFIG_META_KEY, instance)

static func new_pristine() -> Reference:
	var instance = ResourceLoader.load(_CONFIG_SCRIPT_PATH).new()
	instance._skip_persistence = true
	instance._config = instance._load_defaults()
	instance._loaded = true
	return instance

# ============================================================================
# 生命周期与持久化入口
# ============================================================================

func _init() -> void:
	_config = _load_defaults()
	_loaded = false

func load() -> void:
	_config = _ConfigManager.load_config(_load_defaults())
	_loaded = true
	_log("配置已加载 version=%d keys=%d" % [int(_config.get("version", 0)), _config.size()])

func save() -> bool:
	if _skip_persistence:
		return true
	return _ConfigManager.save_config(_config.duplicate(true))

func is_loaded() -> bool:
	return _loaded

func get_last_error() -> String:
	return _last_error

# ============================================================================
# 默认 schema
# ============================================================================

func _load_defaults() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"shop_automation_enabled": true,
		"upgrade_automation_enabled": false,
		"item_rules": {},
		"weapon_rules": {},
		"weapon_category_rules": {},
		"weapon": {
			"min_tier": 0,
		},
		"thresholds": DEFAULT_THRESHOLDS.duplicate(true),
		"general": {
			"min_gold_balance": 0,
			"item_price_threshold": 0,
			"reroll_budget": 0,
			"auto_start_wave": false,
			"keep_running": false,
			"shop_respect_thresholds": true,
			"chest_respect_thresholds": false,
			"turbo_mode": false,
			"decision_step_delay": 0.3,
		},
		"upgrade": {
			"respect_thresholds": true,
			"min_tier": - 1,
			"quality_first": false,
			"ignore_forbid_on_stuck": true,
			"forbid_stats": [],
			"stat_priority": [],
		},
	}

# ============================================================================
# 读取 API
# ============================================================================

func get_config() -> Dictionary:
	return _config.duplicate(true)

func get_item_rules() -> Dictionary:
	return _duplicate_dict(_config.get("item_rules", {}))

func get_weapon_rules() -> Dictionary:
	return _duplicate_dict(_config.get("weapon_rules", {}))

func get_weapon_category_rules() -> Dictionary:
	return _duplicate_dict(_config.get("weapon_category_rules", {}))

func get_weapon_config() -> Dictionary:
	return _duplicate_dict(_config.get("weapon", {}))

func get_general() -> Dictionary:
	var raw: Dictionary = _section_or_empty("general")
	return {
		"min_gold_balance": int(raw.get("min_gold_balance", 0)),
		"item_price_threshold": int(raw.get("item_price_threshold", 0)),
		"reroll_budget": int(raw.get("reroll_budget", 0)),
		"auto_start_wave": bool(raw.get("auto_start_wave", false)),
		"keep_running": bool(raw.get("keep_running", false)),
		"shop_respect_thresholds": bool(raw.get("shop_respect_thresholds", true)),
		"chest_respect_thresholds": bool(raw.get("chest_respect_thresholds", false)),
		"turbo_mode": bool(raw.get("turbo_mode", false)),
		"decision_step_delay": float(raw.get("decision_step_delay", 0.3)),
	}

func get_upgrade_config() -> Dictionary:
	return _duplicate_dict(_config.get("upgrade", {}))

func get_item_rule(item_id: String) -> Dictionary:
	var rules: Dictionary = _section_or_empty("item_rules")
	var raw = rules.get(item_id, null)
	var result: Dictionary = DEFAULT_ITEM_RULE.duplicate(true)
	if typeof(raw) == TYPE_DICTIONARY:
		var sa = raw.get("shop_action", "")
		if typeof(sa) == TYPE_STRING and VALID_SHOP_ACTIONS.has(sa):
			result["shop_action"] = sa
		var ca = raw.get("chest_action", "")
		if typeof(ca) == TYPE_STRING and VALID_CHEST_ACTIONS.has(ca):
			result["chest_action"] = ca
	return result

func get_weapon_rule(weapon_id: String) -> String:
	var rules: Dictionary = _section_or_empty("weapon_rules")
	var action = rules.get(weapon_id, null)
	if typeof(action) == TYPE_STRING and action != "":
		return action
	return "follow_set_rule"

func get_weapon_category_rule(set_id: String) -> String:
	var rules: Dictionary = _section_or_empty("weapon_category_rules")
	var action = rules.get(set_id, null)
	if typeof(action) == TYPE_STRING and action != "":
		return action
	return "manual"

func get_weapon_min_tier() -> int:
	var weapon: Dictionary = _section_or_empty("weapon")
	return int(weapon.get("min_tier", 0))

func get_threshold(stat_key: String) -> Dictionary:
	var thresholds: Dictionary = _section_or_empty("thresholds")
	var raw = thresholds.get(stat_key, null)
	var result: Dictionary = DEFAULT_THRESHOLD.duplicate(true)
	if typeof(raw) == TYPE_DICTIONARY:
		var mode = raw.get("mode", "")
		if typeof(mode) == TYPE_STRING and VALID_THRESHOLD_MODES.has(mode):
			result["mode"] = mode
		var v = raw.get("value", null)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_REAL:
			result["value"] = v
	return result

func is_shop_automation_enabled() -> bool:
	return bool(_config["shop_automation_enabled"])

func is_upgrade_automation_enabled() -> bool:
	return bool(_config["upgrade_automation_enabled"])

func is_turbo_mode() -> bool:
	return bool(_section_or_empty("general")["turbo_mode"])

func get_upgrade_forbid_stats() -> Array:
	var upgrade: Dictionary = _section_or_empty("upgrade")
	return _duplicate_array(upgrade.get("forbid_stats", []))

func get_upgrade_priority() -> Array:
	var upgrade: Dictionary = _section_or_empty("upgrade")
	return _duplicate_array(upgrade.get("stat_priority", []))

# ============================================================================
# 写入 API
# ============================================================================

func set_item_rule(item_id: String, rule: Dictionary) -> void:
	if item_id == "":
		_log_warn("set_item_rule 跳过: item_id 为空")
		return
	if typeof(rule) != TYPE_DICTIONARY:
		_log_warn("set_item_rule 跳过: rule 非 Dictionary")
		return
	_ensure_dict_section("item_rules")[item_id] = rule.duplicate(true)
	_persist()

func remove_item_rule(item_id: String) -> void:
	if item_id == "":
		return
	_ensure_dict_section("item_rules").erase(item_id)
	_persist()

func set_weapon_rule(weapon_id: String, action: String) -> void:
	if weapon_id == "":
		_log_warn("set_weapon_rule 跳过: weapon_id 为空")
		return
	if not VALID_WEAPON_RULE_ACTIONS.has(action):
		_log_warn("set_weapon_rule 跳过: 非法 action '%s'" % action)
		return
	_ensure_dict_section("weapon_rules")[weapon_id] = action
	_persist()

func remove_weapon_rule(weapon_id: String) -> void:
	if weapon_id == "":
		return
	_ensure_dict_section("weapon_rules").erase(weapon_id)
	_persist()

func set_weapon_category_rule(set_id: String, action: String) -> void:
	if set_id == "":
		_log_warn("set_weapon_category_rule 跳过: set_id 为空")
		return
	if not VALID_WEAPON_CATEGORY_ACTIONS.has(action):
		_log_warn("set_weapon_category_rule 跳过: 非法 action '%s'" % action)
		return
	_ensure_dict_section("weapon_category_rules")[set_id] = action
	_persist()

func remove_weapon_category_rule(set_id: String) -> void:
	if set_id == "":
		return
	_ensure_dict_section("weapon_category_rules").erase(set_id)
	_persist()

func set_weapon_config(key: String, value) -> void:
	if not VALID_WEAPON_CONFIG_KEYS.has(key):
		_log_warn("set_weapon_config 跳过: 未知 key '%s'" % key)
		return
	_ensure_dict_section("weapon")[key] = value
	_persist()

func set_threshold(stat_key: String, mode: String, value: int) -> void:
	if stat_key == "":
		_log_warn("set_threshold 跳过: stat_key 为空")
		return
	if not VALID_THRESHOLD_MODES.has(mode):
		_log_warn("set_threshold 跳过: 非法 mode '%s'" % mode)
		return
	_ensure_dict_section("thresholds")[stat_key] = {"mode": mode, "value": value}
	_persist()

func remove_threshold(stat_key: String) -> void:
	if stat_key == "":
		return
	_ensure_dict_section("thresholds").erase(stat_key)
	_persist()

func set_general(key: String, value) -> void:
	if not VALID_GENERAL_KEYS.has(key):
		_log_warn("set_general 跳过: 未知 key '%s'" % key)
		return
	_ensure_dict_section("general")[key] = value
	_persist()

func set_upgrade_config(key: String, value) -> void:
	if not VALID_UPGRADE_CONFIG_KEYS.has(key):
		_log_warn("set_upgrade_config 跳过: 未知 key '%s'" % key)
		return
	_ensure_dict_section("upgrade")[key] = value
	_persist()

func set_upgrade_forbid_stats(value: Array) -> void:
	_ensure_dict_section("upgrade")["forbid_stats"] = value.duplicate(true)
	_persist()

func set_upgrade_priority(value: Array) -> void:
	_ensure_dict_section("upgrade")["stat_priority"] = value.duplicate(true)
	_persist()

func set_upgrade_respect_thresholds(val: bool) -> void:
	_ensure_dict_section("upgrade")["respect_thresholds"] = val
	_persist()

func set_shop_automation_enabled(val: bool) -> void:
	_config["shop_automation_enabled"] = val
	_persist()

func set_upgrade_automation_enabled(val: bool) -> void:
	_config["upgrade_automation_enabled"] = val
	_persist()

func reset_to_defaults() -> void:
	_config = _load_defaults()
	_persist()
	_log("配置已重置为 v%d 默认值" % SCHEMA_VERSION)

# ============================================================================
# 私有 helpers
# ============================================================================

func _persist() -> void:
	if not save():
		_set_last_error("配置保存失败, 本次修改仅保留在内存")
		_log_warn(_last_error)

func _ensure_dict_section(key: String) -> Dictionary:
	if not _config.has(key) or typeof(_config[key]) != TYPE_DICTIONARY:
		_config[key] = {}
	return _config[key]

func _section_or_empty(key: String) -> Dictionary:
	var value = _config.get(key, {})
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}

func _duplicate_dict(value) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).duplicate(true)
	return {}

func _duplicate_array(value) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).duplicate(true)
	return []

func _set_last_error(msg: String) -> void:
	_last_error = msg

func _log(msg: String) -> void:
	_Logger.info(msg, _LOG_NAME)

func _log_warn(msg: String) -> void:
	_Logger.warning(msg, _LOG_NAME)

func _log_error(msg: String) -> void:
	_Logger.error(msg, _LOG_NAME)
