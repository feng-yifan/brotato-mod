extends Reference
class_name AT_Bridge

# ============================================================================
# AT_Bridge — P2 引入的薄适配层 (decision 层 ↔ hook 层胶水)
# v7: 阈值纯化 (mode+value), per-context action 移到各自上下文
# ----------------------------------------------------------------------------
# Config schema (v7):
#   - version                    : int, SCHEMA_VERSION (7)
#   - shop_automation_enabled    : bool
#   - upgrade_automation_enabled : bool
#   - item_rules                 : Dictionary<item_id, {shop_action, chest_action}>
#   - weapon_rules               : Dictionary<weapon_id, "manual"|"skip"|"follow_set_rule">
#   - weapon_category_rules      : Dictionary<set_id, "manual"|"skip">
#   - weapon                     : {min_tier: int}
#   - thresholds                 : Dictionary<stat_key, {mode, value}>
#   - general                    : {min_gold_balance, item_price_threshold, reroll_budget,
#                                   auto_start_wave, keep_running,
#                                   shop_respect_thresholds, chest_respect_thresholds}
#   - upgrade                    : {respect_thresholds, min_tier, quality_first,
#                                   ignore_forbid_on_stuck, forbid_stats, stat_priority}
#
# 默认阈值 (5 项):
#   speed=20, armor=10, dodge=60, hp_regen=10, crit_chance=100, 全部 upper.
# ============================================================================


const ItemDecider    = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/item_decider.gd")
const UpgradeDecider = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/upgrade_decider.gd")
const Result         = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/decision_result.gd")
const Danger         = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/danger_modifier.gd")
const ItemU          = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/item_data_util.gd")
# 强制 preload config_manager.gd, 确保 class_name AT_ConfigManager 在 bridge.gd 编译前注册.
# Godot 3 热重载时编译顺序不保证 class_name 先就绪, 没有这行 preload 会报
# "Parse Error: The identifier AT_ConfigManager isn't declared in the current scope".
const _ConfigManager = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/runtime/config_manager.gd")

const LOG_NAME       := "fengyifan-AutoTato:Bridge"
const META_KEY       := "fengyifan-AutoTato:Bridge"
const SCHEMA_VERSION := 7

# v7: 阈值纯化 — 只保留 mode+value, per-context action 移到各上下文
const DEFAULT_THRESHOLDS := {
	"stat_speed":           {"mode": "upper", "value": 20},
	"stat_armor":           {"mode": "upper", "value": 10},
	"stat_dodge":           {"mode": "upper", "value": 60},
	"stat_hp_regeneration": {"mode": "upper", "value": 10},
	"stat_crit_chance":     {"mode": "upper", "value": 100},
}

# 白名单
const VALID_GENERAL_KEYS := ["min_gold_balance", "item_price_threshold", "reroll_budget",
	"auto_start_wave", "keep_running", "shop_respect_thresholds", "chest_respect_thresholds",
	"turbo_mode"]
const VALID_UPGRADE_CONFIG_KEYS := ["min_tier", "quality_first", "ignore_forbid_on_stuck", "respect_thresholds"]
const VALID_WEAPON_CONFIG_KEYS := ["min_tier"]
const VALID_THRESHOLD_FIELDS := ["mode", "value"]


# ============================================================================
# 成员
# ============================================================================

var _config: Dictionary = {}
var _skip_persistence: bool = false

# 决策序号 (每波次从 1 计数, 用于日志 "决策 M")
var _decision_count: int = 0
var _decision_wave: int = -1


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
		},
		"upgrade": {
			"respect_thresholds": true,
			"min_tier": -1,
			"quality_first": false,
			"ignore_forbid_on_stuck": true,
			"forbid_stats": [],
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
	return int(w.get("min_tier", 0))


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


# 急速模式: 开 = 推进动作 call_deferred 瞬间执行 + 全屏 Overlay 计时;
# 关 = 推进动作 0.3s Timer 延迟, 让界面渲染可见. hook 层推进点读此值决定分支.
func is_turbo_mode() -> bool:
	return bool(_config.get("general", {}).get("turbo_mode", false))


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


# 设置阈值 mode + value, 同时保留已有 *_action / min_tier 字段
func set_threshold(stat_key: String, mode: String, value: int) -> void:
	if stat_key == null or stat_key == "":
		_log_warn("set_threshold 跳过: stat_key 为空")
		return
	if not _config.has("thresholds"):
		_config["thresholds"] = {}
	_config["thresholds"][stat_key] = {"mode": mode, "value": value}
	_persist()


# 批量设置 upgrade forbid_stats 数组
func set_upgrade_forbid_stats(value: Array) -> void:
	if not _config.has("upgrade"):
		_config["upgrade"] = {}
	_config["upgrade"]["forbid_stats"] = value.duplicate()
	_persist()


func get_upgrade_forbid_stats() -> Array:
	var upg = _config.get("upgrade", {})
	var arr = upg.get("forbid_stats", [])
	if typeof(arr) == TYPE_ARRAY:
		return arr.duplicate()
	return []


func set_upgrade_respect_thresholds(val: bool) -> void:
	if not _config.has("upgrade"):
		_config["upgrade"] = {}
	_config["upgrade"]["respect_thresholds"] = val
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


# 批量设置 upgrade stat_priority 数组
func set_upgrade_priority(value: Array) -> void:
	if not _config.has("upgrade"):
		_config["upgrade"] = {}
	_config["upgrade"]["stat_priority"] = value.duplicate()
	_persist()


func set_shop_automation_enabled(val: bool) -> void:
	_config["shop_automation_enabled"] = val
	_persist()


func set_upgrade_automation_enabled(val: bool) -> void:
	_config["upgrade_automation_enabled"] = val
	_persist()


# 将配置重置为默认值并持久化. 由 ConfigPanel 的 Reset 按钮调用.
func reset_to_defaults() -> void:
	_config = _load_defaults()
	_persist()
	_log("配置已重置为默认值 (version=%d)" % SCHEMA_VERSION)


# ============================================================================
# 决策入口
# ============================================================================

func decide_shop_item(item_data, gold: int, player_index: int = 0, force: bool = false):
	var item_id := _safe_item_id(item_data)
	# force=true 时绕过自动化开关 (商店"继续决策"按钮手动触发用)
	if not force and not is_shop_automation_enabled():
		return Result.make(item_id, Result.STATE_MANUAL, "商店自动化已关闭")
	var rule := get_item_rule(item_id)
	var ctx := _build_item_context(gold, false, player_index)
	# 传入含通胀的真实售价 (与容器 shop_item.value 一致), 让决策器预算墙用同样的价格判断
	ctx["item_price"] = _real_shop_price(item_data, player_index)
	return ItemDecider.decide(item_data, rule, ctx)


func decide_chest_item(item_data, player_index: int = 0, force: bool = false):
	var item_id := _safe_item_id(item_data)
	# force=true 时绕过自动化开关 (箱子卡片上的 AutoTato 按钮手动触发用)
	if not force and not is_shop_automation_enabled():
		return Result.make(item_id, Result.STATE_MANUAL, "商店自动化已关闭")
	var rule := get_item_rule(item_id)
	var ctx := _build_item_context(0, true, player_index)
	return ItemDecider.decide(item_data, rule, ctx)


# 决策会话 — 内部循环 + 停止条件 + executor 回调
# ============================================================================

func _decide_shop_round(executor, player_index: int, force: bool) -> Array:
	var wave: int = _current_wave()
	var seq: int = _next_decision_seq()
	_log("")
	_log("┌─ AutoTato 商店决策 波次=%d 决策=%d ──────────────────" % [wave, seq])
	_log("│ 玩家=%d 金币=%d" % [player_index, _read_player_gold(player_index)])

	var results: Array = []
	var slots = executor._at_get_shop_slots(player_index)
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
		var price: int = _real_shop_price(item_data, player_index)

		var dr = decide_shop_item(item_data, gold, player_index, force)

		entry = {
			"slot_index": slot_index,
			"terminal_state": dr.terminal_state,
			"reason": dr.reason,
			"item_id": dr.item_id,
		}
		results.append(entry)

		if dr.terminal_state == Result.STATE_PURCHASED:
			gold -= price

	# 汇总
	var purchased := 0
	var locked := 0
	var skipped := 0
	var manual_count := 0
	for r in results:
		match r.get("terminal_state", Result.STATE_SKIPPED):
			Result.STATE_PURCHASED: purchased += 1
			Result.STATE_LOCKED:    locked += 1
			Result.STATE_SKIPPED:   skipped += 1
			Result.STATE_MANUAL:    manual_count += 1

	_log("──────────────────────────────────────────────────────")
	_log("  商店汇总: 购买=%d 锁定=%d 跳过=%d 手动=%d" % [purchased, locked, skipped, manual_count])
	_log("══════════════════════════════════════════════════════")

	return results


# 完整商店决策会话: 决策 + 执行 + 刷新循环 (无限循环, 仅靠停止条件终止).
# executor 是 hook 节点 (base_shop), 需暴露 _at_* executor 方法.
func run_shop_session(executor, player_index: int, force: bool = false) -> Dictionary:
	var auto_enabled: bool = is_shop_automation_enabled()
	var round_num: int = 0
	var total_purchases := 0
	var total_locks := 0
	var total_skips := 0
	var total_manuals := 0
	var session_has_manual := false

	while true:
		round_num += 1
		var round_has_skip := false
		var round_has_manual := false

		# 1. 决策本轮
		var results: Array = _decide_shop_round(executor, player_index, force)

		# 2. 统计本轮 break 条件 (在实际执行前, 因为 manual 在 decision 阶段就已确定)
		for r in results:
			var st: String = String(r.get("terminal_state", ""))
			if st == Result.STATE_SKIPPED:
				round_has_skip = true
			elif st == Result.STATE_MANUAL:
				round_has_manual = true
				session_has_manual = true

		# 3. 通过 executor 执行
		var applied: Dictionary = executor._at_execute_shop_round(results, player_index)
		total_purchases += int(applied.get("purchases", 0))
		total_locks += int(applied.get("locks", 0))
		total_skips += int(applied.get("skips", 0))
		total_manuals += int(applied.get("manuals", 0))

		# 4. 停止条件
		if not round_has_skip:
			_log("商店会话: 本轮无跳过项, 停止 轮数=%d" % round_num)
			break
		if round_has_manual:
			_log("商店会话: 本轮有手动项, 停止 轮数=%d" % round_num)
			break
		if not (auto_enabled or force):
			_log("商店会话: 自动化关闭且非强制, 停止 轮数=%d" % round_num)
			break
		if not _can_shop_reroll(executor, player_index):
			break
		_log("商店会话: %d 项跳过, 自动刷新 (第 %d 轮)" % [total_skips, round_num])
		executor._at_reroll_shop(player_index)

	var summary := {
		"purchases": total_purchases,
		"locks": total_locks,
		"skips": total_skips,
		"manuals": total_manuals,
		"rounds": round_num,
		"should_auto_start": auto_enabled and not session_has_manual and not force,
	}
	_log("商店会话结束: 购买=%d 锁定=%d 跳过=%d 手动=%d 轮数=%d" % [total_purchases, total_locks, total_skips, total_manuals, round_num])
	return summary


# 判断商店是否可以刷新: 金币够、未全锁、价格未超上限.
func _can_shop_reroll(executor, player_index: int) -> bool:
	var price: int = executor._at_get_reroll_price(player_index)
	var gold: int = _read_player_gold(player_index)
	if gold < price:
		return false
	var locked = RunData.get_player_locked_shop_items(player_index)
	if typeof(locked) == TYPE_ARRAY and locked.size() >= ItemService.NB_SHOP_ITEMS:
		return false
	var general: Dictionary = _config.get("general", {})
	var budget: int = int(general.get("reroll_budget", 0))
	if budget > 0 and price > budget:
		return false
	return true


# 完整升级决策会话: 决策 + reroll 循环 (无限循环, 仅靠停止条件).
func run_upgrade_session(executor, player_index: int, force: bool = false) -> Dictionary:
	var round_num: int = 0
	while true:
		round_num += 1
		var candidates: Dictionary = executor._at_get_upgrade_candidates(player_index)
		var options: Array = candidates.get("options", [])
		if options.empty():
			_log("升级会话: 无候选, 停止 轮数=%d" % round_num)
			break

		var idx: int = int(decide_upgrade(options, player_index, force))
		if idx >= 0:
			executor._at_choose_upgrade(idx, player_index)
			_log("升级会话: 选中 idx=%d 轮数=%d" % [idx, round_num])
			return {"chosen": true, "rounds": round_num}

		# 无合格候选, 检查是否可以 reroll
		var price: int = executor._at_get_upgrade_reroll_price(player_index)
		var gold: int = _read_player_gold(player_index)
		if gold < price:
			_log("升级会话: 金币不足 (gold=%d < price=%d), 停止 轮数=%d" % [gold, price, round_num])
			break
		var general: Dictionary = _config.get("general", {})
		var budget: int = int(general.get("reroll_budget", 0))
		if budget > 0 and price > budget:
			_log("升级会话: 刷新价 %d > 上限 %d, 停止 轮数=%d" % [price, budget, round_num])
			break
		if not executor._at_reroll_upgrade(player_index):
			_log("升级会话: 刷新失败, 停止 轮数=%d" % round_num)
			break

	# 循环耗尽: fallback
	var chosen: bool = executor._at_fallback_upgrade(player_index)
	return {"chosen": chosen, "rounds": round_num}


func _read_player_gold(player_index: int) -> int:
	# gold 存在 player_data.gold 上 (run_data.gd:287 等), RunData 本身没有 gold 属性,
	# 早期用 RunData.get("gold") 当数组读会返回 null → 金币=0. 改用 vanilla 的 getter.
	if typeof(RunData) != TYPE_OBJECT:
		return 0
	if not RunData.has_method("get_player_gold"):
		return 0
	return int(RunData.get_player_gold(player_index))


func decide_upgrade(option_list: Array, player_index: int = 0, force: bool = false) -> int:
	if not force and not is_upgrade_automation_enabled():
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
		"current_wave": _current_wave(),
		"current_danger": Danger.get_danger_level(),
		"decision_seq": _next_decision_seq(),
		"threshold_config": (_config.get("thresholds", {}) as Dictionary).duplicate(true),
		"min_gold_balance": int(general.get("min_gold_balance", 0)),
		"item_price_threshold": int(general.get("item_price_threshold", 0)),
		"reroll_budget": int(general.get("reroll_budget", 0)),
		"weapon_min_tier": get_weapon_min_tier(),
		"weapon_rules": get_weapon_rules(),
		"weapon_category_rules": get_weapon_category_rules(),
		"shop_respect_thresholds": bool(general.get("shop_respect_thresholds", true)),
		"chest_respect_thresholds": bool(general.get("chest_respect_thresholds", false)),
	}


func _build_upgrade_context(player_index: int) -> Dictionary:
	var upg: Dictionary = _config.get("upgrade", {})
	return {
		"player_index": player_index,
		"current_wave": _current_wave(),
		"current_danger": Danger.get_danger_level(),
		"threshold_config": (_config.get("thresholds", {}) as Dictionary).duplicate(true),
		"stat_priority": (upg.get("stat_priority", []) as Array).duplicate(),
		"decision_seq": _next_decision_seq(),
		"forbid_stats": (upg.get("forbid_stats", []) as Array).duplicate(),
		"respect_thresholds": bool(upg.get("respect_thresholds", true)),
	}


func _safe_item_id(item_data) -> String:
	if item_data == null:
		return ""
	var id := ItemU.get_id(item_data)
	return id if typeof(id) == TYPE_STRING else ""


func _current_wave() -> int:
	if typeof(RunData) == TYPE_OBJECT:
		var w = RunData.get("current_wave")
		return int(w) if w != null else 0
	return 0


# 每波次从 1 递增的决策序号 (跨 shop/chest/upgrade 共享, 波次切换自动重置)
func _next_decision_seq() -> int:
	var wave = _current_wave()
	if wave != _decision_wave:
		_decision_count = 0
		_decision_wave = wave
	_decision_count += 1
	return _decision_count


# 商店物品真实售价 (含波次通胀等, 与 vanilla shop_item.value = ItemService.get_value 一致).
# 让决策器预算墙用和容器同样的价格判断, 避免基础价可负担但通胀价被容器拒绝.
func _real_shop_price(item_data, player_index: int) -> int:
	var base: int = ItemU.get_base_value(item_data)
	if typeof(ItemService) != TYPE_OBJECT or not ItemService.has_method("get_value"):
		return base
	if typeof(RunData) != TYPE_OBJECT:
		return base
	var is_weapon: bool = false
	var id_hash: int = 0
	if item_data is Resource:
		var wid = item_data.get("weapon_id")
		is_weapon = (wid != null and str(wid) != "")
		id_hash = int(item_data.get("my_id_hash"))
	return int(ItemService.get_value(RunData.current_wave, base, player_index, true, is_weapon, id_hash))


func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)


func _log_warn(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.warning(msg, LOG_NAME)
