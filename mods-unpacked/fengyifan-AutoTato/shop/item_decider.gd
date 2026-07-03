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
static func decide_shop_entry(entry: Dictionary, player_index: int) -> Dictionary:
	var shop_item = entry.get("shop_item")
	var item_data = entry.get("item_data")
	var item_id: String = String(entry.get("item_id", ""))

	if shop_item == null or item_data == null or item_id == "":
		return _DecisionResult.skip()

	if not _Data.is_shop_item_active(shop_item):
		return _DecisionResult.skip()

	var cfg = _Config.get_instance()
	if cfg == null:
		return _DecisionResult.manual()

	# 读取规则(已含默认值与合法性校验,见 config.get_item_rule)
	var shop_action: String = cfg.get_item_rule(item_id)["shop_action"]

	var price: int = _Data.get_item_price(shop_item)
	var currency: int = _Data.get_player_currency(player_index)
	var general: Dictionary = cfg.get_general()

	# decider 只为预算墙读 currency/price,is_affordable(currency >= price)
	# 不属于决策层 —— 由 shop_automation 在循环里重读自算,与决策正交。

	# — manual —
	if shop_action == "manual":
		return _DecisionResult.manual()

	# — reject —
	if shop_action == "reject":
		return _DecisionResult.skip()

	# — lock_until_cursed —
	if shop_action == "lock_until_cursed":
		var cursed: bool = _Data.is_item_cursed(item_data)
		if not cursed:
			if _Data.is_shop_item_lockable(shop_item):
				return _DecisionResult.lock()
			return _DecisionResult.manual()
		# cursed: 继续预算判断

	# — cursed_only —
	if shop_action == "cursed_only":
		var cursed: bool = _Data.is_item_cursed(item_data)
		if not cursed:
			return _DecisionResult.skip()
		# cursed: 继续预算判断

	# — get (和上述规则的 cursed 分支都走到这里) —

	# 限购
	if _Data.is_at_limit(item_data, player_index):
		return _DecisionResult.skip()

	# 阈值 gate
	if general["shop_respect_thresholds"]:
		var gate: Dictionary = _ThresholdGate.should_reject_item(item_data, player_index)
		if bool(gate.get("reject", false)):
			_Logger.info("跳过 %s: 阈值触达 %s" % [item_id, str(gate.get("stats", []))], _LOG_NAME)
			return _DecisionResult.skip()

	# 预算墙(策略性不买:min_gold_balance + item_price_threshold)
	if _hits_budget_wall(currency, price, general):
		_Logger.info("跳过 %s: 预算墙 currency=%d price=%d" % [item_id, currency, price], _LOG_NAME)
		return _DecisionResult.skip()

	# 购买
	_Logger.info("购买 %s: currency=%d price=%d" % [item_id, currency, price], _LOG_NAME)
	return _DecisionResult.purchase()

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
