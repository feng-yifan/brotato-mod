extends Reference

# ============================================================================
# AutoTato — ItemDecider
# ----------------------------------------------------------------------------
# 单个商店物品的业务决策。不执行 UI,只返回纯决策意图(intent)。
# 余额是否充足(is_affordable)不属于决策层,由 shop_automation 在循环里
# 重读 currency/price 自算,与决策正交。
# 被 shop_automation.gd 调用。
# ============================================================================

const _Config = preload("res://mods-unpacked/fengyifan-AutoTato/config/config.gd")
const _Data = preload("res://mods-unpacked/fengyifan-AutoTato/shop/shop_data_reader.gd")
const _DecisionResult = preload("res://mods-unpacked/fengyifan-AutoTato/shop/decision_result.gd")
const _ThresholdGate = preload("res://mods-unpacked/fengyifan-AutoTato/shop/threshold_gate.gd")
const _Logger = preload("res://mods-unpacked/fengyifan-AutoTato/utils/logger.gd")

const _LOG_NAME := "ItemDecider"

# ============================================================================
# 公开 API
# ============================================================================

# 对单个商店 entry 做决策,返回纯决策意图(intent)。
# entry: {shop_item, item_data, item_id} 来自 shop_data_reader
#
# 两阶段判断结构:
#   阶段 1 — 类型特定规则(差异大,分武器/物品):
#     武器 → _resolve_weapon_action(min_tier → weapon_rules → weapon_category_rules)
#     物品 → item_rules.shop_action(manual/reject/lock_until_cursed/cursed_only/get)
#     否定意图(skip/manual)直接返回,不进阶段 2。
#   阶段 2 — 商店通用规则(对所有物品/武器生效):
#     限购 → 阈值 gate → 预算墙 → purchase。
#     仅对阶段 1 的"肯定意图"(get / cursed 走 get / 武器通过 min_tier)执行。
static func decide_shop_entry(entry: Dictionary, player_index: int) -> Dictionary:
	var shop_item = entry.get("shop_item")
	var item_data = entry.get("item_data")
	var item_id: String = String(entry.get("item_id", ""))

	if shop_item == null or item_data == null or item_id == "":
		_Logger.info("决策 [无id]: skip (entry 数据不完整)", _LOG_NAME)
		return _DecisionResult.skip()

	if not _Data.is_shop_item_active(shop_item):
		_Logger.info("决策 %s: skip (商品不 active)" % item_id, _LOG_NAME)
		return _DecisionResult.skip()

	var cfg = _Config.get_instance()
	if cfg == null:
		_Logger.info("决策 %s: manual (config 未初始化)" % item_id, _LOG_NAME)
		return _DecisionResult.manual()

	var price: int = _Data.get_item_price(shop_item)
	var currency: int = _Data.get_player_currency(player_index)
	var general: Dictionary = cfg.get_general()

	# decider 只为预算墙读 currency/price,is_affordable(currency >= price)
	# 不属于决策层 —— 由 shop_automation 在循环里重读自算,与决策正交。

	# ─── 阶段 1: 类型特定规则 ───
	# 武器走 weapon_rules / weapon_category_rules / min_tier(用 weapon_id,不是 my_id)。
	# 物品走 item_rules(用 my_id)。
	var is_weapon: bool = item_data is WeaponData
	# Godot 3 不支持元组解包,用数组中转。[action, reason]
	var phase1: Array
	if is_weapon:
		var wr = _resolve_weapon_action(item_data, cfg)
		phase1 = [wr["action"], wr["reason"]]
	else:
		# 未配置的物品返回 DEFAULT_ITEM_RULE.shop_action = "manual" — manual 的主要来源。
		var shop_action: String = cfg.get_item_rule(item_id)["shop_action"]
		phase1 = _resolve_item_action(shop_action, item_data, shop_item, item_id)
	var phase1_action: String = phase1[0]
	var phase1_reason: String = phase1[1]

	# 阶段 1 否定/终止意图直接返回,不进阶段 2。
	# lock 也是终止意图(lock_until_cursed 可锁时),不走阶段 2。
	match phase1_action:
		"skip":
			_Logger.info("决策 %s: skip (%s)" % [item_id, phase1_reason], _LOG_NAME)
			return _DecisionResult.skip()
		"manual":
			_Logger.info("决策 %s: manual (%s)" % [item_id, phase1_reason], _LOG_NAME)
			return _DecisionResult.manual()
		"lock":
			_Logger.info("决策 %s: lock (%s)" % [item_id, phase1_reason], _LOG_NAME)
			return _DecisionResult.lock()
		"get":
			# 继续进阶段 2
			pass
		_:
			_Logger.info("决策 %s: manual (未知 phase1_action=%s)" % [item_id, phase1_action], _LOG_NAME)
			return _DecisionResult.manual()

	# ─── 阶段 2: 商店通用规则(对所有肯定意图生效) ───

	# 限购
	if _Data.is_at_limit(item_data, player_index):
		_Logger.info("决策 %s: skip (限购触顶)" % item_id, _LOG_NAME)
		return _DecisionResult.skip()

	# 阈值 gate
	if general["shop_respect_thresholds"]:
		var gate: Dictionary = _ThresholdGate.should_reject_item(item_data, player_index)
		if bool(gate.get("reject", false)):
			_Logger.info("决策 %s: skip (阈值触达 %s)" % [item_id, str(gate.get("stats", []))], _LOG_NAME)
			return _DecisionResult.skip()

	# 预算墙(策略性不买:min_gold_balance + item_price_threshold)
	if _hits_budget_wall(currency, price, general):
		_Logger.info("决策 %s: skip (预算墙 currency=%d price=%d min_balance=%d price_threshold=%d)" % [
			item_id, currency, price, general["min_gold_balance"], general["item_price_threshold"]
		], _LOG_NAME)
		return _DecisionResult.skip()

	# 购买
	_Logger.info("决策 %s: purchase (%s currency=%d price=%d)" % [
		item_id, phase1_reason, currency, price
	], _LOG_NAME)
	return _DecisionResult.purchase()


# ─── 阶段 1 helpers ───

# 物品规则解析:把 shop_action 翻译为 [action, reason]。
# action ∈ {"skip", "manual", "lock", "get"}:
#   skip/manual/lock — 阶段 1 终止意图,decide_shop_entry 直接返回,不进阶段 2。
#   get             — 肯定意图,进阶段 2 接受通用规则过滤。
# lock_until_cursed + 非 cursed + 可锁 → "lock"(锁定动作,也是终止意图)。
static func _resolve_item_action(shop_action: String, item_data, shop_item, item_id: String) -> Array:
	# 返回 [action, reason]
	match shop_action:
		"manual":
			return ["manual", "shop_action=manual, 含未配置的默认规则"]
		"reject":
			return ["skip", "shop_action=reject"]
		"get":
			return ["get", "shop_action=get"]
		"lock_until_cursed":
			var cursed: bool = _Data.is_item_cursed(item_data)
			if not cursed:
				if _Data.is_shop_item_lockable(shop_item):
					return ["lock", "lock_until_cursed, 非 cursed, 可锁"]
				return ["manual", "lock_until_cursed, 非 cursed, 但 is_lockable=false → 降级 manual"]
			return ["get", "lock_until_cursed, 是 cursed, 走 get"]
		"cursed_only":
			var cursed_co: bool = _Data.is_item_cursed(item_data)
			if not cursed_co:
				return ["skip", "cursed_only, 非 cursed"]
			return ["get", "cursed_only, 是 cursed, 走 get"]
		_:
			return ["manual", "未知 shop_action=%s" % shop_action]


# 武器规则解析:三道闸,任一否定即终止。
#   1. min_tier 先判(硬门槛,优先于 weapon_rules)
#   2. weapon_rules[weapon_id] → manual/skip/follow_set_rule
#   3. weapon_category_rules[sets[i].my_id] → 任一 skip 则 skip(保守)
# 默认 → get(进阶段 2)
#
# 注意:武器用 weapon_id(WeaponData.weapon_id),不是 my_id(entry.item_id)。
# 这与写入侧 set_weapon_rule(wid) 一致(见 shop_item.gd _at_popup_save)。
static func _resolve_weapon_action(item_data, cfg) -> Dictionary:
	var weapon_id: String = String(item_data.get("weapon_id"))
	var tier: int = int(item_data.get("tier"))
	var min_tier: int = cfg.get_weapon_min_tier()

	# 1. min_tier 硬门槛
	if min_tier > 0 and tier < min_tier:
		return {"action": "skip", "reason": "武器 tier=%d < min_tier=%d" % [tier, min_tier]}

	# 2. weapon_rules[weapon_id]
	var rule_action: String = cfg.get_weapon_rule(weapon_id)
	match rule_action:
		"manual":
			return {"action": "manual", "reason": "weapon_rules[%s]=manual" % weapon_id}
		"skip":
			return {"action": "skip", "reason": "weapon_rules[%s]=skip" % weapon_id}
		"follow_set_rule":
			pass  # 走 set 规则
		_:
			_Logger.warning("未知 weapon_rule action=%s weapon_id=%s, 走 set 规则" % [rule_action, weapon_id], _LOG_NAME)

	# 3. weapon_category_rules[set.my_id] — 任一 skip 则 skip
	var sets = item_data.get("sets")
	if typeof(sets) == TYPE_ARRAY and not (sets as Array).empty():
		var hit_skip_set := ""
		for s in sets:
			if s == null:
				continue
			var set_id: String = String(s.get("my_id"))
			if set_id == "":
				continue
			var set_action: String = cfg.get_weapon_category_rule(set_id)
			if set_action == "skip":
				hit_skip_set = set_id
				break
		if hit_skip_set != "":
			return {"action": "skip", "reason": "weapon_category_rules[%s]=skip (武器 %s 命中)" % [hit_skip_set, weapon_id]}

	return {"action": "get", "reason": "武器默认 get (weapon_id=%s tier=%d)" % [weapon_id, tier]}

# ============================================================================
# 私有 helpers
# ============================================================================

# 判断是否触达预算墙(策略性预算墙,非余额不足)
static func _hits_budget_wall(currency: int, price: int, general: Dictionary) -> bool:
	var min_balance: int = general["min_gold_balance"]
	if min_balance > 0 and currency - price < min_balance:
		return true
	var price_threshold: int = general["item_price_threshold"]
	if price_threshold > 0 and price > price_threshold:
		return true
	return false
