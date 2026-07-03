extends Reference

# ============================================================================
# AutoTato — IntentResult
# ----------------------------------------------------------------------------
# 表达单个商店物品的决策意图(纯 intent)。
# decider 只输出意图,不输出最终状态、不输出 is_affordable。
# is_affordable(currency >= price)由 shop_automation 在循环里重读自算,
# 与决策正交,用于 reroll 停止条件。
# ============================================================================

const DECISION_PURCHASE := "purchase"
const DECISION_LOCK := "lock"
const DECISION_MANUAL := "manual"
const DECISION_SKIP := "skip"

# 返回纯意图结果。extra 用于添加未来扩展字段。
static func make(intent: String) -> Dictionary:
	return {"intent": intent}

static func purchase() -> Dictionary:
	return make(DECISION_PURCHASE)

static func lock() -> Dictionary:
	return make(DECISION_LOCK)

static func manual() -> Dictionary:
	return make(DECISION_MANUAL)

static func skip() -> Dictionary:
	return make(DECISION_SKIP)
