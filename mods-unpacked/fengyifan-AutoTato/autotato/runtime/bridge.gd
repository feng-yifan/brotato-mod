extends Reference
class_name AT_Bridge

# ============================================================================
# AT_Bridge — P2 引入的薄适配层 (decision 层 ↔ hook 层胶水)
# v6: 武器规则 + 升级黑名单/优先级 + 阈值 limit 字段 + 阈值 min_tier
# ----------------------------------------------------------------------------
# Config schema (v6):
#   - version                    : int, SCHEMA_VERSION (6)
#   - shop_automation_enabled    : bool
#   - upgrade_automation_enabled : bool
#   - item_rules                 : Dictionary<item_id, {shop_action, chest_action}>
#   - weapon_rules               : Dictionary<weapon_id, "manual"|"skip"|"follow_set_rule">
#   - weapon_category_rules      : Dictionary<set_id, "manual"|"skip">
#   - weapon                     : {min_tier: int}
#   - thresholds                 : Dictionary<stat_key, {mode, value, min_tier, limit_upgrade, limit_shop, limit_chest}>
#   - general                    : {min_gold_balance, item_price_threshold, auto_start_wave, keep_running}
#   - upgrade                    : {min_tier, quality_first, ignore_blacklist_on_stuck, stat_blacklist, stat_priority}
#
# 默认阈值 (5 项):
#   speed=20, armor=10, dodge=60, hp_regen=10, crit_chance=100, 全部 upper.
#   limit_upgrade=true, limit_shop=true, limit_chest=false, min_tier=-1.
# ============================================================================


const ItemDecider    = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/item_decider.gd")
const UpgradeDecider = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/upgrade_decider.gd")
const Result         = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/decision_result.gd")
const Danger         = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/danger_modifier.gd")
const ItemU          = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/item_data_util.gd")

const LOG_NAME       := "fengyifan-AutoTato:Bridge"
const META_KEY       := "fengyifan-AutoTato:Bridge"
const SCHEMA_VERSION := 6

# 5 个用户共识预设阈值 — limit_upgrade/limit_shop 默认 true, limit_chest 默认 false
const DEFAULT_THRESHOLDS := {
	"stat_speed":           {"mode": "upper", "value": 20, "min_tier": -1, "limit_upgrade": true, "limit_shop": true, "limit_chest": false},
	"stat_armor":           {"mode": "upper", "value": 10, "min_tier": -1, "limit_upgrade": true, "limit_shop": true, "limit_chest": false},
	"stat_dodge":           {"mode": "upper", "value": 60, "min_tier": -1, "limit_upgrade": true, "limit_shop": true, "limit_chest": false},
	"stat_hp_regeneration": {"mode": "upper", "value": 10, "min_tier": -1, "limit_upgrade": true, "limit_shop": true, "limit_chest": false},
	"stat_crit_chance":     {"mode": "upper", "value": 100, "min_tier": -1, "limit_upgrade": true, "limit_shop": true, "limit_chest": false},
}

# 默认阈值条目的完整字段 (用于 schema 迁移补缺)
const DEFAULT_THRESHOLD_ENTRY := {
	"mode": "unlimited",
	"value": 0,
	"min_tier": -1,
	"limit_upgrade": true,
	"limit_shop": true,
	"limit_chest": false,
}

# 白名单
const VALID_GENERAL_KEYS := ["min_gold_balance", "item_price_threshold", "auto_start_wave", "keep_running"]
const VALID_UPGRADE_CONFIG_KEYS := ["min_tier", "quality_first", "ignore_blacklist_on_stuck"]
const VALID_WEAPON_CONFIG_KEYS := ["min_tier"]
const VALID_THRESHOLD_FIELDS := ["mode", "value", "min_tier", "limit_upgrade", "limit_shop", "limit_chest"]


# ============================================================================
# 成员
# ============================================================================

var _config: Dictionary = {}
var _skip_persistence: bool = false


# ============================================================================
# 静态工厂
# ============================================================================

static func new_pristine() -> Reference:
	var b = load("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/bridge.gd").new()
	b._skip_persistence = true
	b._config = b._load_defaults()
	return b


# ============================================================================
# 生命周期
# ============================================================================

func _init() -> void:
	var defaults: Dictionary = _load_defaults()
	var loaded = AT_ConfigManager.load_config(defaults)
	if loaded == null:
		_config = defaults
		_log("Bridge 使用默认 config (load 失败或文件不存在)")
	else:
		_config = loaded
		_log("Bridge 已加载 config (顶层 keys=%d)" % _config.size())
	_log("Bridge 已初始化, version=%d, %d 个预设阈值" % [SCHEMA_VERSION, _config["thresholds"].size()])


func _load_defaults() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"shop_automation_enabled": true,
		"upgrade_automation_enabled": false,
		"item_rules": {},
		"weapon_rules": {},
		"weapon_category_rules": {},
		"weapon": {
			"min_tier": 1,
		},
		"thresholds": DEFAULT_THRESHOLDS.duplicate(true),
		"general": {
			"min_gold_balance": 0,
			"item_price_threshold": 0,
			"auto_start_wave": false,
			"keep_running": false,
		},
		"upgrade": {
			"min_tier": -1,
			"quality_first": false,
			"ignore_blacklist_on_stuck": false,
			"stat_blacklist": [],
			"stat_priority": [],
		},
	}


func _persist() -> void:
	if _skip_persistence:
		return
	if not AT_ConfigManager.save_config(_config):
		_log_warn("Bridge 持久化失败, 本次修改仅在内存")


# ============================================================================
# 全局注册
# ============================================================================

static func get_global() -> Reference:
	if not Engine.has_meta(META_KEY):
		return null
	return Engine.get_meta(META_KEY)


static func register_global(instance: Reference) -> void:
	Engine.set_meta(META_KEY, instance)


# ============================================================================
# 公开读取 API (全部返回深拷贝)
# ============================================================================

func get_config() -> Dictionary:
	return _config.duplicate(true)


func get_thresholds() -> Dictionary:
	return (_config.get("thresholds", {}) as Dictionary).duplicate(true)


func get_item_rules() -> Dictionary:
	return (_config.get("item_rules", {}) as Dictionary).duplicate(true)


func get_weapon_rules() -> Dictionary:
	return (_config.get("weapon_rules", {}) as Dictionary).duplicate(true)


func get_weapon_category_rules() -> Dictionary:
	return (_config.get("weapon_category_rules", {}) as Dictionary).duplicate(true)


func get_weapon_config() -> Dictionary:
	return (_config.get("weapon", {}) as Dictionary).duplicate(true)


func get_general() -> Dictionary:
	return (_config.get("general", {}) as Dictionary).duplicate(true)


func get_upgrade_config() -> Dictionary:
	return (_config.get("upgrade", {}) as Dictionary).duplicate(true)


func get_item_rule(item_id: String) -> Dictionary:
	var rules: Dictionary = _config.get("item_rules", {})
	var rule = rules.get(item_id, null)
	if rule == null or typeof(rule) != TYPE_DICTIONARY:
		return {}
	return (rule as Dictionary).duplicate()


func get_weapon_rule(weapon_id: String) -> String:
	var rules: Dictionary = _config.get("weapon_rules", {})
	var r = rules.get(weapon_id, null)
	if typeof(r) == TYPE_STRING and r != "":
		return r
	return "follow_set_rule"


func get_weapon_category_rule(set_id: String) -> String:
	var rules: Dictionary = _config.get("weapon_category_rules", {})
	var r = rules.get(set_id, null)
	if typeof(r) == TYPE_STRING and r != "":
		return r
	return "manual"


func get_weapon_min_tier() -> int:
	var w: Dictionary = _config.get("weapon", {})
	return int(w.get("min_tier", 1))


func get_threshold(stat_key: String) -> Dictionary:
	var ths: Dictionary = _config.get("thresholds", {})
	var t = ths.get(stat_key, null)
	if t == null or typeof(t) != TYPE_DICTIONARY:
		return {}
	return (t as Dictionary).duplicate()


func is_shop_automation_enabled() -> bool:
	return bool(_config.get("shop_automation_enabled", false))


func is_upgrade_automation_enabled() -> bool:
	return bool(_config.get("upgrade_automation_enabled", false))


# ============================================================================
# 公开写入 API
# ============================================================================

func set_item_rule(item_id: String, rule: Dictionary) -> void:
	if item_id == null or item_id == "":
		_log_warn("set_item_rule 跳过: item_id 为空")
		return
	if typeof(rule) != TYPE_DICTIONARY:
		_log_warn("set_item_rule 跳过: rule 非 dict")
		return
	if not _config.has("item_rules"):
		_config["item_rules"] = {}
	_config["item_rules"][item_id] = rule.duplicate()
	_persist()


func remove_item_rule(item_id: String) -> void:
	if _config.has("item_rules"):
		_config["item_rules"].erase(item_id)
	_persist()


func set_weapon_rule(weapon_id: String, action: String) -> void:
	if weapon_id == null or weapon_id == "":
		return
	if not _config.has("weapon_rules"):
		_config["weapon_rules"] = {}
	_config["weapon_rules"][weapon_id] = action
	_persist()


func remove_weapon_rule(weapon_id: String) -> void:
	if _config.has("weapon_rules"):
		_config["weapon_rules"].erase(weapon_id)
	_persist()


func set_weapon_category_rule(set_id: String, action: String) -> void:
	if set_id == null or set_id == "":
		return
	if not _config.has("weapon_category_rules"):
		_config["weapon_category_rules"] = {}
	_config["weapon_category_rules"][set_id] = action
	_persist()


func set_weapon_config(key: String, value) -> void:
	if not VALID_WEAPON_CONFIG_KEYS.has(key):
		_log_warn("set_weapon_config 跳过: 未知 key '%s'" % key)
		return
	if not _config.has("weapon"):
		_config["weapon"] = {}
	_config["weapon"][key] = value
	_persist()


# 设置阈值 mode + value, 同时保留已有 limit_* / min_tier 字段
func set_threshold(stat_key: String, mode: String, value: int) -> void:
	if stat_key == null or stat_key == "":
		_log_warn("set_threshold 跳过: stat_key 为空")
		return
	if not _config.has("thresholds"):
		_config["thresholds"] = {}
	var existing := (_config["thresholds"].get(stat_key, {}) as Dictionary).duplicate()
	existing["mode"] = mode
	existing["value"] = value
	for f in ["min_tier", "limit_upgrade", "limit_shop", "limit_chest"]:
		if not existing.has(f):
			existing[f] = DEFAULT_THRESHOLD_ENTRY[f]
	_config["thresholds"][stat_key] = existing
	_persist()


# 设置阈值条目的单个字段 (limit_upgrade / limit_shop / limit_chest / min_tier 等)
func set_threshold_field(stat_key: String, field: String, value) -> void:
	if stat_key == null or stat_key == "":
		return
	if not VALID_THRESHOLD_FIELDS.has(field):
		_log_warn("set_threshold_field 跳过: 未知字段 '%s'" % field)
		return
	if not _config.has("thresholds"):
		_config["thresholds"] = {}
	var existing := (_config["thresholds"].get(stat_key, {}) as Dictionary).duplicate()
	existing[field] = value
	# 补齐缺失的默认字段
	for f in VALID_THRESHOLD_FIELDS:
		if not existing.has(f):
			existing[f] = DEFAULT_THRESHOLD_ENTRY[f]
	_config["thresholds"][stat_key] = existing
	_persist()


func remove_threshold(stat_key: String) -> void:
	if _config.has("thresholds"):
		_config["thresholds"].erase(stat_key)
	_persist()


func set_general(key: String, value) -> void:
	if not VALID_GENERAL_KEYS.has(key):
		_log_warn("set_general 跳过: 未知 key '%s'" % key)
		return
	if not _config.has("general"):
		_config["general"] = {}
	_config["general"][key] = value
	_persist()


func set_upgrade_config(key: String, value) -> void:
	if not VALID_UPGRADE_CONFIG_KEYS.has(key):
		_log_warn("set_upgrade_config 跳过: 未知 key '%s'" % key)
		return
	if not _config.has("upgrade"):
		_config["upgrade"] = {}
	_config["upgrade"][key] = value
	_persist()


# 批量设置 upgrade 数组字段 (stat_blacklist / stat_priority)
func set_upgrade_array(key: String, value: Array) -> void:
	if key != "stat_blacklist" and key != "stat_priority":
		_log_warn("set_upgrade_array 跳过: 未知 key '%s'" % key)
		return
	if not _config.has("upgrade"):
		_config["upgrade"] = {}
	_config["upgrade"][key] = value.duplicate()
	_persist()


func set_shop_automation_enabled(val: bool) -> void:
	_config["shop_automation_enabled"] = val
	_persist()


func set_upgrade_automation_enabled(val: bool) -> void:
	_config["upgrade_automation_enabled"] = val
	_persist()


# ============================================================================
# 决策入口
# ============================================================================

func decide_shop_item(item_data, gold: int, player_index: int = 0):
	var item_id := _safe_item_id(item_data)
	if not is_shop_automation_enabled():
		return Result.make(item_id, Result.STATE_MANUAL, "shop automation disabled (商店自动化已关闭)")
	var rule := get_item_rule(item_id)
	var ctx := _build_item_context(gold, false, player_index)
	return ItemDecider.decide(item_data, rule, ctx)


func decide_chest_item(item_data, player_index: int = 0):
	var item_id := _safe_item_id(item_data)
	if not is_shop_automation_enabled():
		return Result.make(item_id, Result.STATE_MANUAL, "shop automation disabled")
	var rule := get_item_rule(item_id)
	var ctx := _build_item_context(0, true, player_index)
	return ItemDecider.decide(item_data, rule, ctx)


func process_shop(base_shop, player_index: int = 0) -> Array:
	var results: Array = []
	if base_shop == null:
		return results

	var slots = base_shop.get("_shop_items")
	if typeof(slots) != TYPE_ARRAY:
		return results
	if player_index < 0 or player_index >= slots.size():
		return results

	var player_slots = slots[player_index]
	if typeof(player_slots) != TYPE_ARRAY:
		return results

	var gold: int = _read_player_gold(player_index)

	for slot_index in player_slots.size():
		var pair = player_slots[slot_index]
		var entry: Dictionary
		if typeof(pair) != TYPE_ARRAY or pair.size() < 2:
			entry = {
				"slot_index": slot_index,
				"terminal_state": Result.STATE_SKIPPED,
				"reason": "malformed slot",
				"item_id": "",
			}
			results.append(entry)
			continue

		var item_data = pair[0]
		var wave_value: int = int(pair[1])

		var dr = decide_shop_item(item_data, gold, player_index)

		entry = {
			"slot_index": slot_index,
			"terminal_state": dr.terminal_state,
			"reason": dr.reason,
			"item_id": dr.item_id,
		}
		results.append(entry)

		if dr.terminal_state == Result.STATE_PURCHASED:
			gold -= wave_value

	return results


func _read_player_gold(player_index: int) -> int:
	if typeof(RunData) != TYPE_OBJECT:
		return 0
	var gold_arr = RunData.get("gold")
	if typeof(gold_arr) != TYPE_ARRAY:
		return 0
	if player_index < 0 or player_index >= gold_arr.size():
		return 0
	var val = gold_arr[player_index]
	if typeof(val) != TYPE_INT and typeof(val) != TYPE_REAL:
		return 0
	return int(val)


func decide_upgrade(option_list: Array, player_index: int = 0) -> int:
	if not is_upgrade_automation_enabled():
		return UpgradeDecider.NO_PICK
	var upg_cfg: Dictionary = get_upgrade_config()
	upg_cfg["enabled"] = true
	var ctx := _build_upgrade_context(player_index)
	return UpgradeDecider.decide(option_list, upg_cfg, ctx)


# ============================================================================
# 私有 helpers
# ============================================================================

func _build_item_context(gold: int, is_crate: bool, player_index: int) -> Dictionary:
	var general: Dictionary = _config.get("general", {})
	return {
		"gold": gold,
		"player_index": player_index,
		"is_crate": is_crate,
		"current_danger": Danger.get_danger_level(),
		"threshold_config": (_config.get("thresholds", {}) as Dictionary).duplicate(true),
		"min_gold_balance": int(general.get("min_gold_balance", 0)),
		"item_price_threshold": int(general.get("item_price_threshold", 0)),
		"weapon_min_tier": get_weapon_min_tier(),
		"weapon_rules": get_weapon_rules(),
		"weapon_category_rules": get_weapon_category_rules(),
	}


func _build_upgrade_context(player_index: int) -> Dictionary:
	var upg: Dictionary = _config.get("upgrade", {})
	return {
		"player_index": player_index,
		"current_danger": Danger.get_danger_level(),
		"threshold_config": (_config.get("thresholds", {}) as Dictionary).duplicate(true),
		"stat_blacklist": (upg.get("stat_blacklist", []) as Array).duplicate(),
		"stat_priority": (upg.get("stat_priority", []) as Array).duplicate(),
	}


func _safe_item_id(item_data) -> String:
	if item_data == null:
		return ""
	var id := ItemU.get_id(item_data)
	return id if typeof(id) == TYPE_STRING else ""


func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)


func _log_warn(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.warning(msg, LOG_NAME)
