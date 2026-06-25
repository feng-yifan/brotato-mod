extends Reference
class_name AT_ItemDecider

# ============================================================================
# AT_ItemDecider — 商店 / 箱子物品决策入口 (P1)
# ----------------------------------------------------------------------------
# 职责:
#   给定一个 item_data (ItemData Resource 或 Dictionary), 在用户配置的 rule
#   与运行时 context (金币 / 玩家槽 / 阈值配置 / 价格上限 ...) 下, 输出唯一
#   终态 DecisionResult, 描述"该物品应被如何处置".
#
# 动作集 (与旧 mod v4 行为契约对齐, 但 STATE_HUMAN 已改名 STATE_MANUAL):
#   shop_action (5 个):
#     - reject              : 直接 SKIPPED
#     - lock_until_cursed   : 非诅咒版本锁定 (LOCKED), 等下一轮翻出诅咒版
#     - cursed_only         : 仅诅咒版本走预算墙, 非诅咒 SKIPPED;
#                             特殊: 不参与阈值反转 (用户配 cursed_only 就是
#                             想等到诅咒版, 不应被阈值闸门拦下)
#     - get                 : 满足预算就 PURCHASED
#     - manual              : 不干预, 交由玩家自行操作 (默认值)
#
#   chest_action (4 个):
#     - reject              : 直接 SKIPPED
#     - cursed_only         : 仅诅咒版本拿取, 非诅咒 SKIPPED;
#                             同样不参与阈值反转
#     - take                : PURCHASED (箱子不扣金币, 复用 PURCHASED 终态)
#     - manual              : 不干预 (默认值)
#
# 终态 (decision_result.gd STATE_*):
#   STATE_PURCHASED / STATE_LOCKED / STATE_MANUAL / STATE_SKIPPED
#
# 8 步决策流程 (与下方私有 helper 顺序一致):
#   1. 取 action: 非法 / 缺字段回落 manual
#   2. manual    -> STATE_MANUAL
#   3. reject    -> STATE_SKIPPED
#   4. is_at_limit (持有已满 Limited) -> STATE_SKIPPED, 优先级最高
#   5. 阈值反转: 仅 get / take / lock_until_cursed 参与;
#                cursed_only 跳过阈值反转
#   6. 诅咒分支: cursed_only 非诅咒 SKIPPED, lock_until_cursed 非诅咒 LOCKED
#   7. 预算墙: price <= item_price_threshold (0 视为不限) 且
#              gold - price >= min_gold_balance;
#              lock_until_cursed 不通过 -> LOCKED, 其余不通过 -> SKIPPED
#   8. dispatch -> STATE_PURCHASED
#
# 与 P0 数据层对接点:
#   - ItemU.get_id / get_base_value / is_cursed / is_at_limit
#   - Gate.should_reject_by_threshold
#   - 价格用 ItemU.get_base_value (P1 不接入 ItemService.get_value 含 wave
#     inflation, 后续 P2 再升级)
#
# 设计约束:
#   - 纯 static func, 决策器不持有任何状态
#   - 不直接读 vanilla autoload (RunData / Keys 走 ItemU / Gate)
#   - 内部不自引用 class_name AT_ItemDecider (Godot 3 cyclic reference)
# ============================================================================


const ItemU  = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/data/item_data_util.gd")
const Gate   = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/threshold_gate.gd")
const Result = preload("res://mods-unpacked/fengyifan-AutoTato/autotato/decisions/decision_result.gd")

const LOG_NAME := "fengyifan-AutoTato:ItemDecider"

# Shop actions (5)
const SHOP_REJECT             := "reject"
const SHOP_LOCK_UNTIL_CURSED  := "lock_until_cursed"
const SHOP_CURSED_ONLY        := "cursed_only"
const SHOP_GET                := "get"
const SHOP_MANUAL             := "manual"  # default

# Chest actions (4)
const CHEST_REJECT      := "reject"
const CHEST_CURSED_ONLY := "cursed_only"
const CHEST_TAKE        := "take"
const CHEST_MANUAL      := "manual"  # default

const VALID_SHOP_ACTIONS := [
	SHOP_REJECT, SHOP_LOCK_UNTIL_CURSED, SHOP_CURSED_ONLY, SHOP_GET, SHOP_MANUAL,
]
const VALID_CHEST_ACTIONS := [
	CHEST_REJECT, CHEST_CURSED_ONLY, CHEST_TAKE, CHEST_MANUAL,
]


# ============================================================================
# 公开 API
# ============================================================================

# 主入口: 对一个 item_data 在给定 rule + context 下做决策.
#
# 输入:
#   item_data : ItemData Resource 或 Dictionary (走 ItemU 抽象双形态)
#   rule      : Dictionary, 字段:
#                 shop_action  : String  非法/缺 -> manual
#                 chest_action : String  非法/缺 -> manual
#   context   : Dictionary, 字段:
#                 gold                 : int     玩家当前金币
#                 player_index         : int     玩家槽 (本地 1P = 0)
#                 is_crate             : bool    true=箱子, false=商店
#                 current_danger       : int     0-5, P1 不用但透传保留
#                 threshold_config     : Dictionary (传给 ThresholdGate)
#                 min_gold_balance     : int     购物后金币安全垫
#                 item_price_threshold : int     单件价格上限 (0 = 不限)
#
# 返回: DecisionResult (terminal_state ∈ STATE_*)
static func decide(item_data, rule: Dictionary, context: Dictionary):
	var item_id: String = ItemU.get_id(item_data)
	var is_crate: bool = bool(context.get("is_crate", false))

	# Step 0: 如果是武器, 解析武器规则的最终 action
	var is_weapon: bool = _is_weapon_item(item_data)
	var weapon_action: String = ""
	if is_weapon:
		weapon_action = _resolve_weapon_action(item_data, context)

	# Step 1: 取并校验 action
	var action: String = _validate_action(rule, is_crate)

	# v6: 如果是武器且有武器规则 (非 follow_set_rule 或类别规则覆盖), 以武器规则为准
	if is_weapon and weapon_action != "":
		action = weapon_action

	# Step 1.5: 武器 min_tier 过滤 (全局设置, 低于此 tier 直接跳过)
	if is_weapon:
		var wt: int = ItemU.get_tier(item_data)
		var w_min: int = int(context.get("weapon_min_tier", 1))
		if w_min > 0 and wt < w_min:
			return Result.make(item_id, Result.STATE_SKIPPED, "武器 tier=%d < 最低=%d, 直接跳过" % [wt, w_min])

	# Step 2: manual -> 不干预; 但武器手动+预算不足→跳过
	if action == SHOP_MANUAL or action == CHEST_MANUAL:
		if is_weapon and not is_crate:
			# 武器手动但预算墙不通过 → 直接跳过
			var price: int = ItemU.get_base_value(item_data)
			var gold: int = int(context.get("gold", 0))
			var mgb: int = int(context.get("min_gold_balance", 0))
			var ipt: int = int(context.get("item_price_threshold", 0))
			var budget: Dictionary = _check_budget_wall(price, gold, mgb, ipt)
			if not bool(budget.get("pass", false)):
				return Result.make(item_id, Result.STATE_SKIPPED, "武器手动但预算不足, 按跳过处理: " + String(budget.get("reason", "")))
		return Result.make(item_id, Result.STATE_MANUAL, "动作配置为 manual, 不干预")

	# Step 3: reject -> 直接 SKIPPED
	if action == SHOP_REJECT or action == CHEST_REJECT:
		return Result.make(item_id, Result.STATE_SKIPPED, "动作配置为 reject")

	# Step 4: is_at_limit (Limited 已满, 优先级最高)
	var player_index: int = int(context.get("player_index", 0))
	if _check_at_limit(item_data, player_index):
		return Result.make(item_id, Result.STATE_SKIPPED, "已满 (Limited)")

	# Step 5: 阈值反转闸门 (cursed_only 跳过)
	var threshold_result: Dictionary = _check_threshold_reject(item_data, action, context)
	if bool(threshold_result.get("should_reject", false)):
		var threshold_reason: String = String(threshold_result.get("reason", "阈值反转"))
		return Result.make(item_id, Result.STATE_SKIPPED, "阈值反转: " + threshold_reason)

	# Step 6: 诅咒分支
	var cursed: bool = ItemU.is_cursed(item_data)
	if action == SHOP_CURSED_ONLY or action == CHEST_CURSED_ONLY:
		if not cursed:
			return Result.make(item_id, Result.STATE_SKIPPED, "非诅咒版本, 等待诅咒版")
		# 诅咒版本 -> 继续走预算墙
	elif action == SHOP_LOCK_UNTIL_CURSED:
		if not cursed:
			return Result.make(item_id, Result.STATE_LOCKED, "非诅咒, 锁定等下一轮")
		# 诅咒版本 -> 继续走预算墙

	# Step 7: 预算墙
	var price: int = ItemU.get_base_value(item_data)
	var gold: int = int(context.get("gold", 0))
	var min_gold_balance: int = int(context.get("min_gold_balance", 0))
	var item_price_threshold: int = int(context.get("item_price_threshold", 0))

	var budget: Dictionary = _check_budget_wall(price, gold, min_gold_balance, item_price_threshold)
	if not bool(budget.get("pass", false)):
		var budget_reason: String = String(budget.get("reason", "预算墙不通过"))
		if action == SHOP_LOCK_UNTIL_CURSED:
			# 诅咒版本但预算不足: 锁定等下一轮 (可能下一轮金币更宽裕)
			return Result.make(item_id, Result.STATE_LOCKED, "预算不足, 锁定: " + budget_reason)
		return Result.make(item_id, Result.STATE_SKIPPED, budget_reason)

	# Step 8: dispatch -> PURCHASED (商店买入 / 箱子拿取)
	return Result.make(item_id, Result.STATE_PURCHASED, "通过预算墙, 买入/拿取")


# ============================================================================
# 私有 helper
# ============================================================================

# 取 rule 中对应 (shop / chest) 的 action 字符串, 校验合法性.
# 非法值 / 缺字段 / 类型异常 一律回落 manual.
static func _validate_action(rule: Dictionary, is_crate: bool) -> String:
	if typeof(rule) != TYPE_DICTIONARY:
		return SHOP_MANUAL
	var field_name: String = "chest_action" if is_crate else "shop_action"
	var raw = rule.get(field_name, null)
	if raw == null:
		return SHOP_MANUAL
	var action: String = String(raw)
	var valid_set: Array = VALID_CHEST_ACTIONS if is_crate else VALID_SHOP_ACTIONS
	if not valid_set.has(action):
		_log("非法 %s=%s, 回落 manual" % [field_name, action])
		return SHOP_MANUAL
	return action


# 委托 ItemU.is_at_limit, 容错 null item_data.
static func _check_at_limit(item_data, player_index: int) -> bool:
	if item_data == null:
		return false
	return ItemU.is_at_limit(item_data, player_index)


# 阈值反转检查.
# 仅当 action ∈ {SHOP_GET, CHEST_TAKE, SHOP_LOCK_UNTIL_CURSED} 时调 Gate.
# cursed_only 跳过 (用户期望等到诅咒版, 不应被阈值闸门拦下).
# reject / manual 已在更早返回, 不会进到这里.
#
# 返回 Dictionary {should_reject: bool, reason: String}
static func _check_threshold_reject(item_data, action: String, context: Dictionary) -> Dictionary:
	var skip_result: Dictionary = {"should_reject": false, "reason": "动作不参与阈值反转"}

	# cursed_only 不参与
	if action == SHOP_CURSED_ONLY or action == CHEST_CURSED_ONLY:
		return skip_result

	# 仅 get / take / lock_until_cursed 进入阈值检查
	if action != SHOP_GET and action != CHEST_TAKE and action != SHOP_LOCK_UNTIL_CURSED:
		return skip_result

	var threshold_config = context.get("threshold_config", {})
	if typeof(threshold_config) != TYPE_DICTIONARY:
		return skip_result
	if threshold_config.size() == 0:
		return skip_result

	var player_index: int = int(context.get("player_index", 0))
	var gate_result: Dictionary = Gate.should_reject_by_threshold(item_data, threshold_config, player_index)
	return {
		"should_reject": bool(gate_result.get("should_reject", false)),
		"reason": String(gate_result.get("reason", "")),
	}


# 预算墙: 两条件同时成立才通过.
#   1. item_price_threshold == 0 (不限) 或 price <= item_price_threshold
#   2. gold - price >= min_gold_balance
#
# 返回 Dictionary {pass: bool, reason: String}
static func _check_budget_wall(
		price: int,
		gold: int,
		min_gold_balance: int,
		item_price_threshold: int
	) -> Dictionary:
	# 价格上限检查
	if item_price_threshold > 0 and price > item_price_threshold:
		return {
			"pass": false,
			"reason": "预算墙: 价格超限 (price=%d > threshold=%d)" % [price, item_price_threshold],
		}
	# 金币安全垫检查
	if gold - price < min_gold_balance:
		return {
			"pass": false,
			"reason": "预算墙: 金币不足 (gold=%d, price=%d, 安全垫=%d)" % [gold, price, min_gold_balance],
		}
	return {"pass": true, "reason": "预算墙通过"}


# ============================================================================
# v6: 武器规则 helpers
# ============================================================================

# 判断 item_data 是否为武器 (有 weapon_id 字段)
static func _is_weapon_item(item_data) -> bool:
	if item_data == null:
		return false
	var wid = ItemU._field(item_data, "weapon_id", null)
	return wid != null and typeof(wid) == TYPE_STRING and wid != ""


# 解析武器最终 action: 自身规则 > 类别规则 > 默认 manual.
# 返回 "manual" / "skip" / "" (空=无规则, 使用物品规则)
static func _resolve_weapon_action(item_data, context: Dictionary) -> String:
	# 使用 weapon_id (升级链 ID) 匹配规则, 与武器 Tab 的去重逻辑一致
	var cid: String = ""
	if item_data is Resource:
		cid = item_data.get("weapon_id")
	elif item_data is Dictionary:
		cid = item_data.get("weapon_id")
	if cid == "" or cid == null:
		return ""
	# 武器自身规则
	var weapon_rules: Dictionary = context.get("weapon_rules", {})
	var sr = weapon_rules.get(cid, "")
	if sr == "manual" or sr == "skip":
		return sr

	# 类别规则: 收集武器所有 set, 全部 skip 才 skip, 否则 manual
	var weapon_cat_rules: Dictionary = context.get("weapon_category_rules", {})
	var sets = ItemU._field(item_data, "sets", [])
	if typeof(sets) != TYPE_ARRAY or sets.size() == 0:
		return ""

	var all_skip := true
	var has_rule := false
	for s in sets:
		var sid: String = ""
		if s is Resource:
			sid = s.get("my_id")
		elif s is Dictionary:
			sid = s.get("my_id")
		if sid == "":
			continue
		var cr = weapon_cat_rules.get(sid, "manual")
		if cr == "manual":
			all_skip = false
			has_rule = true
		elif cr == "skip":
			has_rule = true
	if has_rule and all_skip:
		return "skip"
	return "manual"


# 日志包装
static func _log(msg: String) -> void:
	if typeof(ModLoaderLog) != TYPE_NIL:
		ModLoaderLog.info(msg, LOG_NAME)
