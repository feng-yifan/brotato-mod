extends Reference

# ============================================================================
# AutoTato — ExecuteResult
# ----------------------------------------------------------------------------
# 单个商店物品的执行结果常量。由 base_shop.at_execute_action 返回,
# 被 shop_automation 消费做最终状态统计。
# 与 decision_result.gd 的 DECISION_* (意图,动词原形) 相对:
#   RESULT_* 是执行事实(过去分词),二者词形不同,不可混用。
# ============================================================================

const RESULT_PURCHASED := "purchased"
const RESULT_LOCKED := "locked"
const RESULT_MANUAL := "manual"
const RESULT_SKIPPED := "skipped"
