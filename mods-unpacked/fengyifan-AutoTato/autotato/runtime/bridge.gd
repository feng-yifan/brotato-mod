extends Reference
class_name AT_Bridge

# ============================================================================
# AT_Bridge — P2 引入的薄适配层 (decision 层 ↔ hook 层胶水)
# P3 扩展: 加 process_shop / _read_player_gold, 让商店 hook 一行调用即可拿到全部 slot 的决策结果
# ----------------------------------------------------------------------------
# 定位:
#   Bridge 居于"无状态纯函数决策器 (P1)" 与"vanilla hook 注入 (P3 任务)"之间.
#   决策器是 static, 不持有任何状态; hook 是 ModLoader extension 脚本, 在
#   vanilla 信号 / 函数被触发时调度. Bridge 把两者粘起来:
#     - 持有内存版 config schema (单一可信源)
#     - 装填决策器需要的 context dict (gold / danger / threshold_config ...)
#     - 暴露 decide_shop_item / decide_chest_item / decide_upgrade 三个入口
#
# 全局可达:
#   实例化后通过 Engine.set_meta(META_KEY, self) 注册. mod_main._init() 末尾
#   调 AT_Bridge.register_global(bridge). Hook 端拿实例只需要一行:
#     var bridge = AT_Bridge.get_global()
#     if bridge: bridge.decide_shop_item(item, gold)
#
# Config schema (P2 内存版, P4 才接 ConfigManager 持久化):
#   - version                    : int, SCHEMA_VERSION
#   - shop_automation_enabled    : bool
#   - upgrade_automation_enabled : bool
#   - item_rules                 : Dictionary<item_id, {shop_action, chest_action}>
#   - thresholds                 : Dictionary<stat_key, {mode, value}>
#   - general                    : {min_gold_balance, item_price_threshold}
#   - upgrade                    : {min_tier, quality_first, ignore_blacklist_on_stuck}
#
# 默认阈值 (5 项, P2 用户共识):
#   speed=20, armor=10, dodge=60, hp_regen=10, crit_chance=100, 全部 upper.
#
# 与 P0 / P1 的对接点:
#   - Danger.get_danger_level()         : 装填 context.current_danger
#   - ItemU.get_id(item_data)           : 容错 null 拿 item_id 写日志/结果
#   - ItemDecider.decide(item, rule, ctx)
#   - UpgradeDecider.decide(opts, cfg, ctx)
#   - Result.STATE_MANUAL / make()      : 自动化关闭时短路返回
#
# 约束:
#   - 不读 vanilla autoload (RunData / ItemService 等), 那是 P3 hook 的事;
#     danger 间接通过 P0 DangerModifier 取 (后者已封装 RunData 访问)
#   - 不写任何持久化逻辑 (P4 ConfigManager 才负责)
#   - 公开读取 API 全部返回深拷贝, 防止上层意外篡改 _config
# ============================================================================


const ItemDecider    = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/item_decider.gd")
const UpgradeDecider = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/upgrade_decider.gd")
const Result         = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/decision_result.gd")
const Danger         = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/danger_modifier.gd")
const ItemU          = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/item_data_util.gd")

const LOG_NAME       := "fengyifan-AutoTato:Bridge"
const META_KEY       := "fengyifan-AutoTato:Bridge"   # Engine.set_meta 的 key, 含 mod namespace 防冲突
const SCHEMA_VERSION := 5                              # 与旧 mod v4 区分

# 5 个用户共识预设阈值
const DEFAULT_THRESHOLDS := {
	"stat_speed":           {"mode": "upper", "value": 20},
	"stat_armor":           {"mode": "upper", "value": 10},
	"stat_dodge":           {"mode": "upper", "value": 60},
	"stat_hp_regeneration": {"mode": "upper", "value": 10},
	"stat_crit_chance":     {"mode": "upper", "value": 100},
}

# 白名单, 防止误写未知字段静默成功
const VALID_GENERAL_KEYS := ["min_gold_balance", "item_price_threshold"]
const VALID_UPGRADE_CONFIG_KEYS := ["min_tier", "quality_first", "ignore_blacklist_on_stuck"]


# ============================================================================
# 成员
# ============================================================================

var _config: Dictionary = {}


# ============================================================================
# 生命周期
# ============================================================================

func _init() -> void:
	_config = _load_defaults()
	_log("Bridge 已初始化, version=%d, %d 个预设阈值" % [SCHEMA_VERSION, _config["thresholds"].size()])


# 返回完整 config dict.
# 注意: DEFAULT_THRESHOLDS 是类级 const, 直接 assign 会让所有实例共享同一引用;
# 这里 .duplicate(true) 出一份深拷贝, 保证每个 Bridge 实例隔离.
func _load_defaults() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"shop_automation_enabled": true,
		"upgrade_automation_enabled": true,
		"item_rules": {},
		"thresholds": DEFAULT_THRESHOLDS.duplicate(true),
		"general": {
			"min_gold_balance": 0,
			"item_price_threshold": 0,
		},
		"upgrade": {
			"min_tier": -1,
			"quality_first": false,
			"ignore_blacklist_on_stuck": false,
		},
	}


# ============================================================================
# 全局注册 (静态 helper)
# ----------------------------------------------------------------------------
# Hook 端入口: 一行拿到全局 Bridge 实例
#   var bridge = AT_Bridge.get_global()
#   if bridge: bridge.decide_shop_item(item, gold)
#
# 返回类型用 Reference: Godot 3 GDScript 解析期不允许类内自引用 class_name
# (cyclic reference). 调用方按需 cast 或鸭式访问 (调 decide_* 方法均可).
# ============================================================================

static func get_global() -> Reference:
	if not Engine.has_meta(META_KEY):
		return null
	return Engine.get_meta(META_KEY)


# mod_main._init 末尾调用, 注册到 Engine 元数据.
# 允许 mod 重新加载时覆盖旧实例 (Engine.set_meta 本身就是覆盖语义).
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


func get_general() -> Dictionary:
	return (_config.get("general", {}) as Dictionary).duplicate(true)


func get_upgrade_config() -> Dictionary:
	return (_config.get("upgrade", {}) as Dictionary).duplicate(true)


# 单条 item rule 查询. 不存在 / 类型异常返回 {}.
# 与 get_threshold 保持一致, 不返 null 以减少调用方判空成本.
func get_item_rule(item_id: String) -> Dictionary:
	var rules: Dictionary = _config.get("item_rules", {})
	var rule = rules.get(item_id, null)
	if rule == null or typeof(rule) != TYPE_DICTIONARY:
		return {}
	return (rule as Dictionary).duplicate()


# 单条 threshold 查询. 不存在 / 类型异常返回 {}.
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
# ----------------------------------------------------------------------------
# 写入时浅拷贝入参 dict, 避免外部继续持有引用后误改 _config.
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


func remove_item_rule(item_id: String) -> void:
	if _config.has("item_rules"):
		_config["item_rules"].erase(item_id)


func set_threshold(stat_key: String, mode: String, value: int) -> void:
	if stat_key == null or stat_key == "":
		_log_warn("set_threshold 跳过: stat_key 为空")
		return
	if not _config.has("thresholds"):
		_config["thresholds"] = {}
	_config["thresholds"][stat_key] = {"mode": mode, "value": value}


func remove_threshold(stat_key: String) -> void:
	if _config.has("thresholds"):
		_config["thresholds"].erase(stat_key)


func set_general(key: String, value) -> void:
	if not VALID_GENERAL_KEYS.has(key):
		_log_warn("set_general 跳过: 未知 key '%s'" % key)
		return
	if not _config.has("general"):
		_config["general"] = {}
	_config["general"][key] = value


func set_upgrade_config(key: String, value) -> void:
	if not VALID_UPGRADE_CONFIG_KEYS.has(key):
		_log_warn("set_upgrade_config 跳过: 未知 key '%s'" % key)
		return
	if not _config.has("upgrade"):
		_config["upgrade"] = {}
	_config["upgrade"][key] = value


func set_shop_automation_enabled(val: bool) -> void:
	_config["shop_automation_enabled"] = val


func set_upgrade_automation_enabled(val: bool) -> void:
	_config["upgrade_automation_enabled"] = val


# ============================================================================
# 决策入口
# ----------------------------------------------------------------------------
# Hook 端的核心调用面. 三个入口都做"总开关短路 + context 装填 + 调决策器".
# ============================================================================

# 商店物品决策. gold 是玩家当前金币 (P3 hook 传).
# 自动化关闭 → 短路 STATE_MANUAL.
func decide_shop_item(item_data, gold: int, player_index: int = 0):
	var item_id := _safe_item_id(item_data)
	if not is_shop_automation_enabled():
		return Result.make(item_id, Result.STATE_MANUAL, "shop automation disabled (商店自动化已关闭)")
	var rule := get_item_rule(item_id)
	var ctx := _build_item_context(gold, false, player_index)
	return ItemDecider.decide(item_data, rule, ctx)


# 箱子物品决策. is_crate=true. 箱子不扣金币, gold 传 0 占位.
func decide_chest_item(item_data, player_index: int = 0):
	var item_id := _safe_item_id(item_data)
	if not is_shop_automation_enabled():
		return Result.make(item_id, Result.STATE_MANUAL, "shop automation disabled")
	var rule := get_item_rule(item_id)
	var ctx := _build_item_context(0, true, player_index)
	return ItemDecider.decide(item_data, rule, ctx)


# ----------------------------------------------------------------------------
# 整商店决策入口 (P3 新增)
# ----------------------------------------------------------------------------

# 对整个商店做决策. 内部 snapshot _shop_items[player_index], 累计 gold 计算预算墙,
# 对每个 slot 调 decide_shop_item, 返回所有 slot 的决策结果数组.
#
# 输入:
#   base_shop    : BaseShop 节点 (vanilla, 子类 self 同样可传)
#   player_index : 玩家槽 (默认 0)
#
# 返回 Array of Dictionary, 长度 = 该玩家 _shop_items 大小:
#   [
#     {"slot_index": 0, "terminal_state": "purchased", "reason": "...", "item_id": "..."},
#     {"slot_index": 1, "terminal_state": "skipped",   "reason": "...", "item_id": "..."},
#     ...
#   ]
#
# 容错矩阵:
#   - base_shop == null            → 返回 []
#   - base_shop 无 _shop_items     → 返回 []
#   - shop_automation_enabled=false → 每个 slot 全返 manual (不短路, 让烟雾能验)
#   - slot 二元组结构异常 / item null → 该 slot 标 skipped + reason="malformed slot"
#   - RunData 不可用 (烟雾 mock)     → gold 取 0
#
# Godot 3 注意:
#   - 用 Object.get("_shop_items") 而非 base_shop._shop_items, 防止字段缺失崩
#   - decide_shop_item 返回 DecisionResult 对象, 这里转 Dictionary 输出
#   - 决策时 gold 累计减 (用 slot[1] = wave_value, 已含 vanilla 折扣)

func process_shop(base_shop, player_index: int = 0) -> Array:
	var results: Array = []
	if base_shop == null:
		return results

	# 取 _shop_items 字典/数组, 防御性访问
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

		# decide_shop_item 内部会处理:
		#   - shop_automation_enabled 总开关 (短路 manual)
		#   - rule 取值 (没配落 manual)
		#   - 阈值闸门 / 预算墙 / 诅咒逻辑
		var dr = decide_shop_item(item_data, gold, player_index)

		entry = {
			"slot_index": slot_index,
			"terminal_state": dr.terminal_state,
			"reason": dr.reason,
			"item_id": dr.item_id,
		}
		results.append(entry)

		# 阶段 1 内即时累减 gold (用 wave_value, vanilla 已计算折扣)
		if dr.terminal_state == Result.STATE_PURCHASED:
			gold -= wave_value

	return results


# 读 RunData.gold[player_index] 的容错 helper. 任何异常返 0.
# vanilla RunData.gold 是 Array<int>, 每个玩家一项.
# 烟雾环境 RunData 可能不存在或 gold 字段缺失, 此时安全降级到 0.
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


# 升级 4 选 1 决策. 返回 0-based 索引或 -1 (NO_PICK).
# Bridge 层用 upgrade_automation_enabled 做总开关, 桥接到 decider 期望的
# config.enabled (decider 自身只看 config.enabled, 不读 Bridge 配置).
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

# 装填 item_decider 期望的 context dict.
# 字段对照 item_decider.gd 顶部注释的 context schema.
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
	}


# 装填 upgrade_decider 期望的 context dict.
# 字段对照 upgrade_decider.gd 的 context 注释.
func _build_upgrade_context(player_index: int) -> Dictionary:
	return {
		"player_index": player_index,
		"current_danger": Danger.get_danger_level(),
		"threshold_config": (_config.get("thresholds", {}) as Dictionary).duplicate(true),
	}


# 容错从 item_data 取 id, null / 非 String 一律返回空串.
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
