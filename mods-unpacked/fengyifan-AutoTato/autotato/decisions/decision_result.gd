extends Reference
class_name AT_DecisionResult

# ============================================================================
# AT_DecisionResult — 决策器的终态结果对象
#
# 本文件位于决策器层的最叶子位置, 无任何依赖, 独立于 schema 层.
#
# 设计要点:
#
# 1. 4 个终态字符串常量代表一次商店/箱子物品的最终处置方式, 与旧 mod v4 的
#    行为契约对齐, 但 STATE_MANUAL 替代了旧名 "human" —— 旧名字语义模糊,
#    容易让人误以为是"玩家身份"或"人形角色", 实际语义是"交由玩家自行操作".
#
# 2. 为什么用 const String 而非 enum:
#    - 持久化兼容: 写入 JSON 配置 / 日志时直接是可读字符串, 不需要 enum->name
#      的反查表, 也不会因 enum 顺序变化而破坏旧档.
#    - 跨 mod 兼容: 其他 mod 若想 hook 决策结果, 字符串比 enum 值更稳定.
#    - 调试友好: 直接 print(result) 就是人类可读, 不需要解码数字.
#
# 3. DecisionResult 是内部类. Godot 3 GDScript 的约束: 内部类不能用外部
#    class_name 自引用 (AT_DecisionResult.STATE_PURCHASED 会导致 cyclic
#    reference 报错), 必须直接写 STATE_PURCHASED.
#
# 4. 工厂 make() 不校验 terminal_state, 由调用方保证传入 STATE_* 之一;
#    is_valid_state() 供单元测试与外部断言使用.
# ============================================================================

# 商店扣金币购入 / 箱子拿取
const STATE_PURCHASED := "purchased"
# 商店 lock_until_cursed 命中, 等下一轮
const STATE_LOCKED    := "locked"
# 不干预, 交由玩家自行操作 (旧 mod 用 "human", 现改名为更明确的 "manual")
const STATE_MANUAL    := "manual"
# 拒绝, 不买不锁不拿
const STATE_SKIPPED   := "skipped"

# 4 个合法终态的列表, 供 is_valid_state() 与外部断言使用
const VALID_TERMINAL_STATES := [STATE_PURCHASED, STATE_LOCKED, STATE_MANUAL, STATE_SKIPPED]


# 决策结果的数据载体. 一次决策必然落在 4 个终态之一,
# 同时附带 item_id (用于追踪是哪个物品) 与 reason (人类可读的决策理由).
class DecisionResult:
	extends Reference

	var terminal_state: String = ""
	var reason: String = ""
	var item_id: String = ""

	func _to_string() -> String:
		return "[%s] %s — %s" % [terminal_state, item_id, reason]


# 创建 DecisionResult 实例. 不校验 terminal_state (调用方保证传 STATE_*).
static func make(item_id: String, terminal_state: String, reason: String) -> DecisionResult:
	var r := DecisionResult.new()
	r.item_id = item_id
	r.terminal_state = terminal_state
	r.reason = reason
	return r


# 判断 terminal_state 是否在 4 个合法值之一
static func is_valid_state(state: String) -> bool:
	return VALID_TERMINAL_STATES.has(state)
